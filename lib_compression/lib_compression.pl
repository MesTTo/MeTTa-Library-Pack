% Purpose: compress bytes and files, inspect archives and publish extracted data.
% Assumes: input archive files remain unchanged during an operation.
% Guarantees: gzip/zlib decoding checks complete members; file outputs publish
% after successful decoding and close. Extraction refuses escaping names and
% unsupported entry kinds before publishing its complete tree.
% [tested: lib_compression; commit=7b42d5ee5cecb82709617b7ed08dfa2c1441f268].
% Owns resources: memory files, input/decoder/entry streams, intermediate files
% and staging trees close or disappear on success, failure and exception.
% File's metta_staged_publish/2 owns final publication and staging cleanup.
% with_utf8/1 restores its call-local native character locale after archive close.
% Guarded by: resources belong to their call; no shared mutable library state.
% Decides: formats are gzip and zlib; levels are 0..9; complete concatenated
% members are accepted. Extraction restores regular file data and directories,
% using portable relative names and refusing links and special files.
% [tested: lib_compression; commit=7b42d5ee5cecb82709617b7ed08dfa2c1441f268].

:- module(lib_compression,
          ['compression-formats'/1,'compress-bytes'/4,'decompress-bytes'/3,
           'compress-file!'/5,'decompress-file!'/4,
           'archive-entries!'/2,'archive-read!'/3,'archive-extract!'/3]).
:- set_module(base(metta_engine)).
:- metta_requires('compressed-sources').
:- metta_requires('memory-files').
:- metta_requires(archive).
:- use_module(library(zlib), [zopen/3]).
:- use_module(library(memfile),
              [new_memory_file/1,free_memory_file/1,open_memory_file/4,memory_file_to_codes/3]).
:- use_module(library(archive), []).
:- use_module(library(predicate_options), [current_predicate_options/3]).
:- use_module(library(error), [must_be/2,domain_error/2,permission_error/3,existence_error/2]).
:- use_module(library(lists), [member/2,memberchk/2,reverse/2,last/2]).
:- use_module(library(apply), [maplist/2,maplist/3,exclude/3]).
:- use_module(library(readutil), [read_stream_to_codes/2]).
:- use_module(library(filesex),
              [directory_file_path/3,make_directory_path/1,delete_directory_and_contents/1]).
:- use_module('../lib_string/lib_string', [metta_text/2]).
:- use_module('../lib_file/lib_file', [metta_staged_publish/2,'temp-dir!'/2]).
% Workaround: swi-relative-compound-source - keep the relative pathname an atom
% so another library's directory cannot reuse its cached compound specification.
:- use_module('support/native',
              [with_utf8/1,with_archive/4,archive_property/2,archive_next_header/2,
               archive_header_property/2,archive_open_entry/2]).
:- meta_predicate archive_file(+,4,+,-), archive_file_utf8(+,4,+,-),
                  fold_file(+,4,+,-), fold_entries(+,4,+,+,-).

%! 'compression-formats'(-Formats:list) is det.
%
% Return the byte/file envelope names gzip and zlib. These use native zlib;
% archive operations separately detect formats supported by linked libarchive.
'compression-formats'([gzip,zlib]).

%! 'compress-bytes'(+Format:'Symbol', +Level:integer, +Bytes:list, -Compressed:list) is det.
%
% Compress integers 0..255 using gzip or zlib and level 0..9. Level 0 stores data;
% higher levels trade encoding work for size. Empty input produces a complete
% empty member. The result is bytes, independent of locale and text encoding.
'compress-bytes'(Format,Level,Bytes,Compressed) :-
    compression_arguments(Format,Level,Envelope),byte_list(Bytes),
    setup_call_cleanup(new_memory_file(Memory),
        ( setup_call_cleanup(open_memory_file(Memory,write,Output,[encoding(octet)]),
              setup_call_cleanup(zopen(Output,Encoded,[format(Envelope),level(Level),close_parent(false)]),
                                 maplist(put_byte(Encoded),Bytes),close(Encoded)),close(Output)),
          memory_file_to_codes(Memory,Compressed,octet) ),free_memory_file(Memory)).

%! 'decompress-bytes'(+Format:'Symbol', +Compressed:list, -Bytes:list) is det.
%
% Decode complete gzip or zlib members, concatenating their bytes. Empty input,
% a different envelope, truncation, checksum errors and trailing junk raise.
% A compressed empty member returns (). Results require memory proportional to
% the input and decoded bytes; use the file operation for streaming output.
'decompress-bytes'(Format,Compressed,Bytes) :-
    envelope(Format,Envelope),byte_list(Compressed),string_codes(Text,Compressed),
    setup_call_cleanup(open_string(Text,Input),
        setup_call_cleanup(zopen(Input,Decoded,[format(Envelope),multi_part(true),close_parent(false)]),
                           read_stream_to_codes(Decoded,Bytes),close(Decoded)),close(Input)).

%! 'compress-file!'(+Format:'Symbol', +Level:integer, +Source:any, +Destination:any, -Done:boolean) is det.
%
% Stream a file into gzip or zlib and replace Destination after all streams
% close successfully. Its parent must exist. Source and Destination may be
% the same path. A failure before publication preserves the old destination.
'compress-file!'(Format,Level,Source,Destination,true) :-
    compression_arguments(Format,Level,Envelope),file_path(Source,From),file_path(Destination,To),
    metta_staged_publish(To,compressed_copy(Envelope,Level,From)).

%! 'decompress-file!'(+Format:'Symbol', +Source:any, +Destination:any, -Done:boolean) is det.
%
% Stream complete gzip/zlib members into one file, replacing Destination after
% checksum validation and close. The input may name Destination. Its parent
% must exist; malformed input preserves an existing destination. Memory use
% is bounded by decoder/stream buffers instead of the decoded file's length.
'decompress-file!'(Format,Source,Destination,true) :-
    envelope(Format,Envelope),file_path(Source,From),file_path(Destination,To),
    metta_staged_publish(To,decoded_copy(Envelope,From)).

%! 'archive-entries!'(+Path:any, -Entries:list) is det.
%
% Inspect every entry as (archive-entry Index NameString PropertyPairs), with
% zero-based ordinals and archive order, retaining duplicate names. Properties
% are native filetype, mtime, size, optional link_target, format and permissions.
% Textual link targets and format descriptions are Strings; a native unknown
% filetype remains its integer code. Inspection creates no extracted paths.
% Native name conversion uses a call-local UTF8 character locale, preserving
% the process locale. Unflagged ZIP names use CP437; UTF8 flags and Unicode extra
% fields retain native precedence. Unconvertible pathnames raise before returning.
% All entry data is consumed to surface native read errors. Gzip layers are
% checked through zlib, including gzip inside other compression filters.
'archive-entries!'(Path,Entries) :-
    file_path(Path,File),archive_file(File,collect_entry,[],Reverse),reverse(Reverse,Entries).

%! 'archive-read!'(+Path:any, +Index:integer, -Bytes:list) is det.
%
% Read one regular entry by its zero-based ordinal. Ordinals distinguish equal
% names. An absent ordinal or a nonregular entry raises. Other entries are
% consumed as well, so a later archive read error is not hidden by selection.
'archive-read!'(Path,Index,Bytes) :-
    file_path(Path,File),must_be(nonneg,Index),
    archive_file(File,select_entry(Index),missing,Result),
    ( Result=found(Bytes) -> true ; existence_error(archive_entry(Index),File) ).

%! 'archive-extract!'(+Path:any, +Destination:any, -Done:boolean) is det.
%
% Publish regular files and directories into a missing or empty destination
% directory. Its parent must exist. Build a separate tree first; errors leave
% the destination unchanged. Links, unknown kinds, devices and pipes raise.
% Modes, ownership and times are not restored. File duplicates and file/tree
% collisions raise; repeated directories and ./ directory entries are valid.
% Names must be portable relative paths: no .. components, absolute paths,
% backslashes, controls, Windows device names, reserved punctuation or trailing
% dots/spaces. Empty and . components are normalized. Inspection retains names
% that extraction refuses. Input files must remain unchanged during the call.
% Archives containing gzip use temporary seekable files for validation; only
% adjacent decoded layers coexist. Other archives use the linked reader directly.
'archive-extract!'(Path,Destination,true) :-
    file_path(Path,File),file_path(Destination,To),
    metta_staged_publish(To,extract_tree(File)).

compression_arguments(Format,Level,Envelope) :-
    envelope(Format,Envelope),must_be(between(0,9),Level).
envelope(Format,Envelope) :-
    must_be(atom,Format),
    ( Format==gzip -> Envelope=gzip ; Format==zlib -> Envelope=deflate
    ; domain_error(compression_format,Format) ).
byte_list(Bytes) :- must_be(list(between(0,255)),Bytes).
file_path(Value,Path) :-
    metta_text(Value,Path),string_codes(Path,Codes),
    ( Codes\==[],\+memberchk(0,Codes) -> true ; domain_error(nonempty_file_path,Value) ).

compressed_copy(Envelope,Level,Source,Destination) :-
    setup_call_cleanup(open(Source,read,Input,[type(binary)]),
        setup_call_cleanup(open(Destination,write,Output,[type(binary)]),
            setup_call_cleanup(zopen(Output,Encoded,[format(Envelope),level(Level),close_parent(false)]),
                               copy_stream_data(Input,Encoded),close(Encoded)),close(Output)),close(Input)).
decoded_copy(Envelope,Source,Destination) :-
    setup_call_cleanup(open(Source,read,Input,[type(binary)]),
        setup_call_cleanup(zopen(Input,Decoded,[format(Envelope),multi_part(true),close_parent(false)]),
                           copy_to_file(Decoded,Destination),close(Decoded)),close(Input)).
copy_to_file(Input,Path) :-
    setup_call_cleanup(open(Path,write,Output,[type(binary)]),copy_stream_data(Input,Output),close(Output)).
discard_stream(Input) :-
    setup_call_cleanup(open_null_stream(Null),copy_stream_data(Input,Null),close(Null)).

archive_file(Path,Visitor,Initial,Final) :-
    with_utf8(archive_file_utf8(Path,Visitor,Initial,Final)).
archive_file_utf8(Path,Visitor,Initial,Final) :-
    with_archive(Path,[],Probe,archive_property(Probe,filter(Filters))),
    ( memberchk(gzip,Filters)
    -> setup_call_cleanup('temp-dir!'("archive-decode",Scratch),
           ( native_filters_without_gzip(Native),decode_layers(Path,Native,Scratch,0,Decoded),
             fold_file(Decoded,Visitor,Initial,Final) ),delete_directory_and_contents(Scratch))
    ; fold_file(Path,Visitor,Initial,Final) ).

% Workaround: swi-archive-input-exception - close each decoder before an archive
% reader can observe its failure through a native stream callback.
% Only the current and next intermediate file coexist; final input is seekable.
decode_layers(Path,Filters,Directory,Index,Final) :-
    number_string(Index,Name),directory_file_path(Directory,Name,Next),
    setup_call_cleanup(open(Path,read,Input,[type(binary)]),
                       decode_layer(Input,Filters,Next,Changed),close(Input)),
    ( Changed==false -> Final=Path
    ; ( Index>0 -> delete_file(Path) ; true ),
      After is Index+1,decode_layers(Next,Filters,Directory,After,Final) ).

% Workaround: libarchive-gzip-trailer - zlib verifies the header, CRC and length
% that libarchive's gzip filter omits, at every layer in the declared filter chain.
% https://github.com/libarchive/libarchive/blob/c719b9b1f56621d92063a85361cc8d114f5575a9/libarchive/archive_read_support_filter_gzip.c#L401
decode_layer(Input,Filters,Path,Changed) :-
    peek_string(Input,2,Prefix),string_codes(Prefix,Codes),
    ( Codes==[] -> Changed=false
    ; Codes==[31,139]
    -> setup_call_cleanup(zopen(Input,Decoded,[format(gzip),multi_part(true),close_parent(false)]),
                          copy_to_file(Decoded,Path),close(Decoded)),Changed=true
    ; with_archive(stream(Input),[formats([raw]),filters(Filters)],Raw,
          ( archive_property(Raw,filter(Used)),
            ( Used==[] -> Changed=false
            ; archive_next_header(Raw,data),
              setup_call_cleanup(archive_open_entry(Raw,Decoded),copy_to_file(Decoded,Path),close(Decoded)),
              ( archive_next_header(Raw,_) -> domain_error(single_raw_archive,Raw) ; true ),
              Changed=true ) )) ).
native_filters_without_gzip(Filters) :-
    current_predicate_options(archive:archive_open/4,4,Options),
    memberchk(filters(list(oneof(Names))),Options),exclude(gzip_or_all,Names,Filters).
gzip_or_all(gzip).
gzip_or_all(all).

% The host archive_foldl/4 establishes this entry-at-a-time fold. This version
% carries ordinals and owns each stream before invoking the native visitor.
% https://github.com/SWI-Prolog/packages-archive/blob/13a3f4af8f8219e10faf4895ce9fb189bc6aaefd/archive.pl#L665
fold_file(Path,Visitor,Initial,Final) :-
    with_archive(Path,[],Archive,fold_entries(Archive,Visitor,0,Initial,Final)).
fold_entries(Archive,Visitor,Index,Initial,Final) :-
    ( archive_next_header(Archive,Name)
    -> atom_string(Name,Text),
       findall(Property,archive_header_property(Archive,Property),Properties),
       maplist(property_pair,Properties,Pairs),Entry=['archive-entry',Index,Text,Pairs],
       setup_call_cleanup(archive_open_entry(Archive,Input),
                          call(Visitor,Entry,Input,Initial,Next),close(Input)),
       After is Index+1,fold_entries(Archive,Visitor,After,Next,Final)
    ; Final=Initial ).
property_pair(Property,[Key,Value]) :-
    compound_name_arguments(Property,Key,[Native]),
    ( memberchk(Key,[link_target,format]) -> atom_string(Native,Value) ; Value=Native ).
collect_entry(Entry,Input,Before,[Entry|Before]) :- discard_stream(Input).
select_entry(Index,Entry,Input,Before,After) :-
    ( Entry=['archive-entry',Index,Name,Properties]
    -> regular_entry(Name,Properties),read_stream_to_codes(Input,Bytes),After=found(Bytes)
    ; discard_stream(Input),After=Before ).
regular_entry(Name,Properties) :-
    memberchk([filetype,Type],Properties),
    ( Type==file -> true ; domain_error(regular_archive_entry,Name-Type) ).
extract_tree(File,Directory) :-
    make_directory(Directory),archive_file(File,extract_entry(Directory),[],_).
extract_entry(Directory,['archive-entry',_,Name,Properties],Input,State,State) :-
    memberchk([filetype,Type],Properties),
    ( memberchk(Type,[file,directory]) -> true ; domain_error(extractable_archive_entry,Name-Type) ),
    extraction_path(Name,Type,Directory,Target),
    ( Type==directory -> make_directory_path(Target),discard_stream(Input)
    ; ( exists_file(Target);exists_directory(Target) )
    -> permission_error(create,duplicate_archive_path,Name)
    ; file_directory_name(Target,Parent),make_directory_path(Parent),copy_to_file(Input,Target) ).

extraction_path(Name,Type,Directory,Target) :-
    string_codes(Name,Codes),
    ( Codes\==[],Codes\=[47|_],\+ (member(Code,Codes),forbidden_path_code(Code))
    -> true ; domain_error(portable_relative_archive_path,Name) ),
    split_string(Name,"/","",Parts0),exclude(dot_component,Parts0,Parts),
    maplist(portable_component,Parts),
    ( Parts==[] -> (Type==directory -> Target=Directory;domain_error(archive_file_name,Name))
    ; atomics_to_string(Parts,"/",Relative),directory_file_path(Directory,Relative,Target) ).
dot_component("").
dot_component(".").
forbidden_path_code(Code) :- Code<32;memberchk(Code,[34,42,58,60,62,63,92,124]).

% Portable components cannot designate an OS device or a differently normalized
% path. Windows reserves device stems even when followed by an extension.
% https://github.com/MicrosoftDocs/win32/blob/63e70903d18b0637e62ffab6656c4a388ef0f2ce/desktop-src/FileIO/naming-a-file.md#naming-conventions
portable_component(Part) :-
    string_codes(Part,Codes),last(Codes,Last),
    ( Part\=="..",Codes\=[32|_],\+memberchk(Last,[32,46]),\+reserved_device(Part)
    -> true ; domain_error(portable_archive_component,Part) ).
reserved_device(Part) :-
    split_string(Part,".","",[Stem|_]),normalize_space(string(Trimmed),Stem),string_upper(Trimmed,Upper),
    ( memberchk(Upper,["CON","PRN","AUX","NUL","CONIN$","CONOUT$","CLOCK$"])
    ; sub_string(Upper,0,3,1,Prefix),memberchk(Prefix,["COM","LPT"]),
      sub_string(Upper,3,1,0,Digit),memberchk(Digit,["1","2","3","4","5","6","7","8","9","¹","²","³"]) ).

:- det('compression-formats'/1).
:- det('compress-bytes'/4).
:- det('decompress-bytes'/3).
:- det('compress-file!'/5).
:- det('decompress-file!'/4).
:- det('archive-entries!'/2).
:- det('archive-read!'/3).
:- det('archive-extract!'/3).
