% Purpose: file input and output, MeTTa HE's handle surface, whole-file text and
%   byte operations, staged publication, renaming, tree copy and removal,
%   traversal and globbing, lexical and resolved paths, entry kinds, links,
%   scoped resources, temporary files and directories, standard streams and
%   process exit.
%
%   The handle names, argument order and option letters are HE's, because HE
%   already specified this and the fallback rule says an unexplored area takes
%   HE's answer [source 2026-08-15: MeTTa HE stdlib, File Input/Output]. The
%   letter b is the one addition to that alphabet, the binary mode C and Python
%   spell the same way.
% Assumes:
%   - a MeTTa string is an SWI string, so paths and contents cross as strings
%     [verified 2026-08-15, see lib_string.pl]
%   - bytes are an expression of integers 0 to 255; the host's binary streams
%     write a string of such codes as exactly those bytes
%     [tested: lib_file_surface:bytes_round_trip_every_value; commit=WORKTREE]
% Guarantees:
%   - a handle is a small integer, so it prints, compares and crosses the [tested: lib_file:the_handle_surface_reads_and_seeks]
%     Python boundary as an ordinary MeTTa value rather than as a blob
%   - every operation on an unknown or closed handle raises an existence error
%     naming the handle, rather than failing silently [tested: lib_file:using_a_closed_handle_raises]
%   - file-open! refuses a contradictory option set loudly, HE's own rule:
%     'c' demands 'w', so "rc" is an error rather than a silent read [tested: lib_file:create_without_write_is_refused, an_unknown_option_letter_is_refused]
%   - the HE file-mode alphabet is explicitly recorded as a language
%     mechanism rather than mistaken for an undeclared engine policy [tested:
%     test_a_planted_closed_policy_list_is_reported_by_the_inventory_lane;
%     commit=42b5d28232e75c32b20a1d5bf1f740fec134938d].
%   - a text operation on a binary handle and a byte operation on a text handle
%     refuse by name, because the host's loose stream type check would decode
%     octets as text [tested: lib_file_surface:handle_kinds_are_checked; commit=WORKTREE]
%   - replace-file! and copy-dir! publish with one rename after every staged
%     stream closed, so a reader sees the old entry or the complete new one
%     [tested: lib_file_surface:replace_preserves_destination_on_failure,
%     lib_file_surface:copy_dir_publishes_a_complete_tree; commit=WORKTREE]
%   - dir-walk and dir-glob report symbolic links and enter them only under
%     (follow-links True), where a link back to the current chain is reported
%     and not entered [tested: lib_file_surface:walk_reports_links_without_entering,
%     lib_file_surface:walk_follows_links_without_looping; commit=WORKTREE]
%   - path-normalize, path-absolute, path-relative and path-resolve answer
%     what CPython's posixpath answers [tested: test_normalize_agrees_with_posixpath,
%     test_relative_agrees_with_posixpath, test_absolute_agrees_with_posixpath,
%     test_resolve_agrees_with_posixpath; commit=WORKTREE]
%   - with-file and with-temp-dir release their resource on exhaustion, cut
%     and exception [tested: lib_file_surface:with_file_closes_on_every_exit; commit=WORKTREE]
% Fails when:
%   - the file is missing and the options do not say to create it. That is an
%     error, not a failure, so it cannot be mistaken for an empty file.
% Owns resources:
%   - one open stream per handle, until file-close! releases it. HE's stdlib
%     lists no close operation; leaving a process to leak descriptors is not
%     something to copy, so file-close! is added and documented as an addition.
%   - a staging directory beside a publication target, removed on every exit
%     of replace-file!, copy-file! and copy-dir!.
%   - the handle or directory a scope acquires, released by the scope's cleanup.
% Guarded by:
%   - '$metta_files' serialises handle allocation and the handle table.
% Decides:
%   - list-dir!, dir-walk and dir-glob order entries by codepoint within each
%     directory; a walk and a glob are depth first.
%   - wildcards skip names beginning with a dot unless (hidden True) or the
%     pattern component itself begins with a dot, the shell's rule.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None


:- module(lib_file,
          [ 'append-bytes!'/3,
            'append-file!'/3,
            'copy-dir!'/3,
            'copy-file!'/3,
            'delete-dir!'/2,
            'delete-file!'/2,
            'delete-tree!'/2,
            'dir-exists'/2,
            'dir-glob'/3,
            'dir-glob'/4,
            'dir-walk'/2,
            'dir-walk'/3,
            'exit!'/2,
            'file-close!'/2,
            'file-exists'/2,
            'file-get-size!'/2,
            'file-kind'/2,
            'file-lines!'/2,
            'file-metadata!'/2,
            'file-open!'/3,
            'file-read-bytes!'/2,
            'file-read-bytes!'/3,
            'file-read-exact!'/3,
            'file-read-to-string!'/2,
            'file-seek!'/3,
            'file-space!'/2,
            'file-write!'/3,
            'file-write-bytes!'/3,
            'list-dir!'/2,
            'make-dir!'/2,
            'make-link!'/3,
            'path-absolute'/2,
            'path-extension'/2,
            'path-join'/3,
            'path-name'/2,
            'path-normalize'/2,
            'path-parent'/2,
            'path-parts'/2,
            'path-relative'/3,
            'path-resolve'/2,
            'path-stem'/2,
            'read-bytes!'/2,
            'read-file!'/2,
            'read-link'/2,
            'rename-file!'/3,
            'replace-file!'/3,
            'same-file'/3,
            'stderr!'/2,
            'stdin-to-string!'/1,
            'temp-dir!'/2,
            'temp-path!'/2,
            'with-file'/4,
            'with-temp-dir'/3,
            'write-bytes!'/3,
            'write-file!'/3,
            stderr/1,
            stdin/1,
            stdout/1
          ]).

% Guarantees: private helpers and autoload declarations belong to this module.
% [tested: engine_modules; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
% Assumes: engine operations resolve through metta_engine's published exports.
% [source: engine/metta.pl:metta_engine_reexport/2; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
:- set_module(base(metta_engine)).

:- use_module('../lib_string/lib_string', [metta_text/2, 'string-lines'/2]).
:- use_module(library(lists), [append/3, nth1/3, member/2, memberchk/2, reverse/2]).
:- use_module(library(apply), [exclude/3, maplist/3, foldl/4]).
:- use_module(library(error), [must_be/2, domain_error/2, existence_error/2, type_error/2]).
:- use_module(library(filesex),
              [directory_file_path/3, make_directory_path/1,
               delete_directory_and_contents/1, link_file/3]).
:- use_module(library(readutil), [read_stream_to_codes/2]).
:- use_module(library(solution_sequences), [distinct/2]).

:- dynamic metta_file/2.            % Handle, Stream
%The counter is a FLAG rather than a dynamic fact, and the difference is a
%WRONG ANSWER rather than a style. A fact is source, and importing this
%library into a SECOND space consults the file again, which put the counter
%back to zero and made the next mint hand out a name that was already in use:
%`(dict-space ((a 1) (b 2)))` in a second space answered a size of four,
%because it had added its two entries on top of the first dict's two in
%`&json-1` [tested: test_a_dict_is_a_space_a_comprehension_can_build;
%commit=657ae9672c07b628f8a20c7fe39aa43e58b0014f]. A flag lives outside the source, so re-loading cannot
%reset it, and its update is atomic, which is the whole of what the mutex was
%for [source: SWI-Prolog 10.1 Reference Manual, flag/3, "The update is
%atomic. This predicate can be used to create a shared global counter"].
% POSIX's own numbering, taken rather than invented: 0 is standard input, 1
% standard output and 2 standard error, in this table and in every process this
% engine runs in. So the handle surface that already reads, writes and measures
% a file reaches the three streams as well, and (file-read-to-string! (stdin))
% is the longhand stdin-to-string! is the short spelling of. The alias atoms
% ARE the streams: every SWI predicate that takes a stream takes an alias.
%
% These are a second SPELLING, not a second mechanism. stderr! and
% stdin-to-string! stay the way to write a diagnostic and read the input; the
% handles are what lets file-read-exact!, file-write! and file-get-size! reach
% the same three streams without a further operation each.
metta_file(0, user_input).
metta_file(1, user_output).
metta_file(2, user_error).

% Facts rather than one predicate over a list, because the numbering is POSIX's
% rather than a choice this engine makes, and three facts keep it out of the
% closed-policy scan.
standard_stream(0, stdin).
standard_stream(1, stdout).
standard_stream(2, stderr).

%! stdin(-Handle:integer) is det.
%
% The handle for standard input, which is 0; every handle operation takes it,
% so (file-read-to-string! (stdin)) reads standard input through EOF.
'stdin'(0).

%! stdout(-Handle:integer) is det.
%
% The handle for standard output, which is 1; (file-write! (stdout) $text)
% writes without a newline.
'stdout'(1).

%! stderr(-Handle:integer) is det.
%
% The handle for standard error, which is 2; (file-write! (stderr) $text) is
% stderr! reached through the handle surface.
'stderr'(2).

% Minting starts at 3 because 0, 1 and 2 are taken, exactly as they are in a
% process. Nothing pins a particular handle number: every caller binds whatever
% file-open! answers.
next_file_handle(Handle) :-
    flag('$metta_file_handle', Previous, Previous + 1),
    Handle is Previous + 3.

known_file(Handle, Stream) :-
    (   metta_file(Handle, Stream)
    ->  true
    ;   existence_error(metta_file_handle, Handle)
    ).

% The host's stream type check is loose: read_string/3 and write/2 accept a
% binary stream and would decode or encode octets as text without a word, so
% the library asks the stream what it is before every text or byte operation.
% get_byte/2 and put_byte/2 already refuse a text stream; the check here is
% what makes both directions refuse by the same name with the same remedy.
text_handle(Operation, Handle, Stream) :-
    known_file(Handle, Stream),
    (   stream_property(Stream, type(text))
    ->  true
    ;   throw(error('file-handle-kind'(Operation, Handle, binary),
                    context(Operation,
                            'Use file-read-bytes! and file-write-bytes! on a handle opened with b')))
    ).

binary_handle(Operation, Handle, Stream) :-
    known_file(Handle, Stream),
    (   stream_property(Stream, type(binary))
    ->  true
    ;   throw(error('file-handle-kind'(Operation, Handle, text),
                    context(Operation,
                            'Open the file with the option letter b to read or write bytes')))
    ).

%! 'file-open!'(+Path:any, +Options:any, -Handle:integer) is det.
%
% Open a file and answer a handle. The option letters are HE's: r read, w
% write, c create if absent, a append, t truncate; c demands w or a, so "rc" is
% refused loudly rather than quietly opening for reading. The letter b opens
% the file for bytes, so file-read-bytes! and file-write-bytes! apply and the
% text operations refuse; without it the handle carries UTF-8 text.
'file-open!'(Path, Options, Handle) :-
    metta_text(Path, PathText),
    metta_text(Options, OptionText),
    string_chars(OptionText, Letters),
    % policy-inventory-exempt: mechanism-internal; reason=r w c a and t are the fixed HE file-mode instruction alphabet and b is the binary letter C and Python share; evidence=lib/lib_file/lib_file.pl:file-open!/3
    (   forall(member(Letter, Letters), memberchk(Letter, [r, w, c, a, t, b]))
    ->  true
    ;   throw(error(domain_error(file_open_options, Options),
                    context('file-open!'/2, 'options are drawn from r w c a t b')))
    ),
    (   memberchk(c, Letters), \+ memberchk(w, Letters), \+ memberchk(a, Letters)
    ->  throw(error(domain_error(file_open_options, Options),
                    context('file-open!'/2, 'c demands w or a')))
    ;   true
    ),
    file_open_mode(Letters, Mode),
    (   Mode == read, \+ exists_file(PathText)
    ->  existence_error(source_sink, PathText)
    ;   true
    ),
    (   memberchk(b, Letters)
    ->  StreamOptions = [type(binary)]
    ;   StreamOptions = [encoding(utf8)]
    ),
    open(PathText, Mode, Stream, StreamOptions),
    next_file_handle(Handle),
    with_mutex('$metta_files', assertz(metta_file(Handle, Stream))).

%append wins over write because a caller asking for both means "add to it",
%and read plus write is SWI's update mode, which keeps the existing content.
file_open_mode(Letters, Mode) :-
    (   memberchk(a, Letters)
    ->  Mode = append
    ;   memberchk(w, Letters), memberchk(r, Letters), \+ memberchk(t, Letters)
    ->  Mode = update
    ;   memberchk(w, Letters)
    ->  Mode = write
    ;   Mode = read
    ).

%! 'file-read-to-string!'(+Handle:integer, -Content:string) is det.
%
% Read from the cursor to the end of a text handle as one String.
'file-read-to-string!'(Handle, Content) :-
    text_handle('file-read-to-string!', Handle, Stream),
    read_string(Stream, _, Content).

%! 'file-read-exact!'(+Handle:integer, +Count:integer, -Content:string) is det.
%
% Read at most Count characters from a text handle's cursor, HE's contract: a
% short read near the end of the file is the answer, not an error.
'file-read-exact!'(Handle, Count, Content) :-
    text_handle('file-read-exact!', Handle, Stream),
    must_be(integer, Count),
    Wanted is max(0, Count),
    read_string(Stream, Wanted, Content).

%! 'file-write!'(+Handle:integer, +Content:any, -Done:boolean) is det.
%
% Write text to a text handle and flush, adding no newline.
'file-write!'(Handle, Content, true) :-
    text_handle('file-write!', Handle, Stream),
    metta_text(Content, Text),
    write(Stream, Text),
    flush_output(Stream).

%! 'file-read-bytes!'(+Handle:integer, -Bytes:list) is det.
%! 'file-read-bytes!'(+Handle:integer, +Count:integer, -Bytes:list) is det.
%
% Read the remaining bytes, or at most Count bytes, from a binary handle's
% cursor as an expression of integers 0 to 255. A short read at the end of the
% file is the answer. A text handle refuses.
'file-read-bytes!'(Handle, Bytes) :-
    binary_handle('file-read-bytes!', Handle, Stream),
    read_stream_to_codes(Stream, Bytes).
'file-read-bytes!'(Handle, Count, Bytes) :-
    binary_handle('file-read-bytes!', Handle, Stream),
    must_be(integer, Count),
    Wanted is max(0, Count),
    read_bytes_up_to(Stream, Wanted, Bytes).

read_bytes_up_to(_, 0, []) :- !.
read_bytes_up_to(Stream, Count, Bytes) :-
    get_byte(Stream, Byte),
    (   Byte == -1
    ->  Bytes = []
    ;   Bytes = [Byte|Rest],
        Remaining is Count - 1,
        read_bytes_up_to(Stream, Remaining, Rest)
    ).

%! 'file-write-bytes!'(+Handle:integer, +Bytes:list, -Done:boolean) is det.
%
% Write an expression of integers 0 to 255 to a binary handle and flush. The
% bytes are validated before anything is written. A text handle refuses.
'file-write-bytes!'(Handle, Bytes, true) :-
    binary_handle('file-write-bytes!', Handle, Stream),
    bytes_list('file-write-bytes!', Bytes),
    put_bytes(Stream, Bytes),
    flush_output(Stream).

% The host writes a string of codes 0 to 255 on a binary stream as exactly
% those bytes, one write for the whole expression rather than one call a byte
% [tested: lib_file_surface:bytes_round_trip_every_value; commit=WORKTREE].
put_bytes(Stream, Bytes) :-
    string_codes(Text, Bytes),
    write(Stream, Text).

bytes_list(Operation, Bytes) :-
    catch(must_be(list(between(0, 255)), Bytes), error(Formal, _),
          throw(error(Formal,
                      context(Operation, 'Bytes are an expression of integers 0 to 255')))).

%! 'file-seek!'(+Handle:integer, +Position:integer, -Done:boolean) is det.
%
% Move the cursor to a byte offset from the start of the file, so the next
% read starts there; a negative position moves to the start.
'file-seek!'(Handle, Position, true) :-
    known_file(Handle, Stream),
    must_be(integer, Position),
    Target is max(0, Position),
    seek(Stream, Target, bof, _).

%! 'file-get-size!'(+Handle:integer, -Size:integer) is det.
%
% Answer the size of the whole file in bytes, not of what is left to read,
% so seeking does not change the answer; a handle without a file name measures
% the stream position instead.
'file-get-size!'(Handle, Size) :-
    known_file(Handle, Stream),
    (   stream_property(Stream, file_name(Name)),
        exists_file(Name)
    ->  size_file(Name, Size)
    ;   stream_property(Stream, position(Position)),
        stream_position_data(char_count, Position, Size)
    ).

%! 'file-close!'(+Handle:integer, -Done:boolean) is det.
%
% Close a handle file-open! gave. Closing twice is silent, because a cleanup
% path should not have to check first; a failed close raises by name, because
% a write that never reached the disk is data lost. The three standard streams
% are refused: the process owns them and a closed one cannot be put back.
%
% Not in HE's stdlib. A process that can open files and never close them leaks
% descriptors until it dies, so this exists.
'file-close!'(Handle, _) :-
    standard_stream(Handle, Name),
    !,
    throw(error('standard-stream-not-closable'('file-close!', Name),
                context('file-close!',
                        'The process owns it; close a stream file-open! gave you'))).
'file-close!'(Handle, true) :-
    (   metta_file(Handle, Stream)
    ->  with_mutex('$metta_files', retractall(metta_file(Handle, _))),
        catch(close(Stream), Error, metta_file_refusal('file-close!', Error))
    ;   true
    ).

%! 'with-file'(+Path:any, +Options:any, +Function:any, -Answer:any) is nondet.
%
% Open Path with file-open!'s option letters, apply Function to the handle and
% answer every result of that application; the handle closes when the answers
% are exhausted, when the caller stops after one, and when the body raises.
% Function is a lambda, a function name or a partial application, as par-map
% takes. A close failure raises unless the body already raised.
'with-file'(Path, Options, Function, Answer) :-
    current_metta_module(Module),
    setup_call_cleanup('file-open!'(Path, Options, Handle),
                       eval_metta_in_module(Module, [Function, Handle], Answer),
                       'file-close!'(Handle, _)).

%! 'with-temp-dir'(+Prefix:any, +Function:any, -Answer:any) is nondet.
%
% Mint a fresh directory with temp-dir!, apply Function to its path and answer
% every result; the directory and everything under it are removed when the
% answers are exhausted, when the caller stops after one, and when the body
% raises. A body that already removed or renamed the directory is fine.
'with-temp-dir'(Prefix, Function, Answer) :-
    current_metta_module(Module),
    setup_call_cleanup('temp-dir!'(Prefix, Directory),
                       eval_metta_in_module(Module, [Function, Directory], Answer),
                       release_temp_dir(Directory)).

release_temp_dir(Directory) :-
    (   path_exists(Directory)
    ->  catch(delete_directory_and_contents(Directory), Error,
              metta_file_refusal('with-temp-dir', Error))
    ;   true
    ).

%! 'read-file!'(+Path:any, -Content:string) is det.
%
% Read a whole UTF-8 file as one String without the open/close dance. A
% missing file is an error rather than a failure, so it can never be mistaken
% for an empty file. Not HE's, and named so it cannot be mistaken for HE's.
'read-file!'(Path, Content) :-
    metta_text(Path, PathText),
    (   exists_file(PathText)
    ->  true
    ;   existence_error(source_sink, PathText)
    ),
    setup_call_cleanup(open(PathText, read, Stream, [encoding(utf8)]),
                       read_string(Stream, _, Content),
                       close(Stream)).

%! 'write-file!'(+Path:any, +Content:any, -Done:boolean) is det.
%
% Create or truncate the file at Path in place and write UTF-8 text. An open
% handle or a hard link to the file keeps seeing it; replace-file! is the
% form that publishes a new file by rename instead.
'write-file!'(Path, Content, true) :-
    metta_text(Path, PathText),
    metta_text(Content, Text),
    setup_call_cleanup(open(PathText, write, Stream, [encoding(utf8)]),
                       write(Stream, Text),
                       close(Stream)).

%! 'append-file!'(+Path:any, +Content:any, -Done:boolean) is det.
%
% Append UTF-8 text to the file at Path, creating it when absent.
'append-file!'(Path, Content, true) :-
    metta_text(Path, PathText),
    metta_text(Content, Text),
    setup_call_cleanup(open(PathText, append, Stream, [encoding(utf8)]),
                       write(Stream, Text),
                       close(Stream)).

%! 'read-bytes!'(+Path:any, -Bytes:list) is det.
%
% Read a whole file as an expression of integers 0 to 255. A missing file is
% an error rather than a failure.
'read-bytes!'(Path, Bytes) :-
    metta_text(Path, PathText),
    (   exists_file(PathText)
    ->  true
    ;   existence_error(source_sink, PathText)
    ),
    setup_call_cleanup(open(PathText, read, Stream, [type(binary)]),
                       read_stream_to_codes(Stream, Bytes),
                       close(Stream)).

%! 'write-bytes!'(+Path:any, +Bytes:list, -Done:boolean) is det.
%
% Create or truncate the file at Path in place and write an expression of
% integers 0 to 255. The bytes are validated before the file is touched.
'write-bytes!'(Path, Bytes, true) :-
    metta_text(Path, PathText),
    bytes_list('write-bytes!', Bytes),
    setup_call_cleanup(open(PathText, write, Stream, [type(binary)]),
                       put_bytes(Stream, Bytes),
                       close(Stream)).

%! 'append-bytes!'(+Path:any, +Bytes:list, -Done:boolean) is det.
%
% Append an expression of integers 0 to 255 to the file at Path, creating it
% when absent. The bytes are validated before the file is touched.
'append-bytes!'(Path, Bytes, true) :-
    metta_text(Path, PathText),
    bytes_list('append-bytes!', Bytes),
    setup_call_cleanup(open(PathText, append, Stream, [type(binary)]),
                       put_bytes(Stream, Bytes),
                       close(Stream)).

%! 'replace-file!'(+Path:any, +Content:any, -Done:boolean) is det.
%
% Publish a new file at Path by rename: the content is written to a staging
% file beside the destination, closed, and renamed over Path in one step, so
% a reader sees the old file or the complete new one and never a partial
% write. A String, Symbol or Number is UTF-8 text; an expression of integers
% 0 to 255 is bytes. A failed write, close or rename keeps the old file.
'replace-file!'(Path, Content, true) :-
    metta_text(Path, To),
    content_writer('replace-file!', Content, Writer),
    catch(metta_staged_publish(To, Writer), Error,
          metta_file_refusal('replace-file!', Error)).

% Text or bytes is read off the content's structure: an expression is bytes,
% anything a text coercion accepts is text. Validation runs before staging.
content_writer(Operation, Content, Writer) :-
    (   is_list(Content)
    ->  bytes_list(Operation, Content),
        Writer = write_bytes_to(Content)
    ;   metta_text(Content, Text),
        Writer = write_text_to(Text)
    ).

write_text_to(Text, Path) :-
    setup_call_cleanup(open(Path, write, Stream, [encoding(utf8)]),
                       write(Stream, Text),
                       close(Stream)).

write_bytes_to(Bytes, Path) :-
    setup_call_cleanup(open(Path, write, Stream, [type(binary)]),
                       put_bytes(Stream, Bytes),
                       close(Stream)).

%! 'file-lines!'(+Path:any, -Lines:list) is det.
%
% The lines of a UTF-8 file as an expression of Strings, split on LF with one
% terminal empty line omitted; CR and NUL stay data. file-space! is the form
% that makes the lines matchable.
'file-lines!'(Path, Lines) :-
    'read-file!'(Path, Content),
    'string-lines'(Content, Lines).

%! 'file-space!'(+Path:any, -Space:any) is det.
%
% A file as a SPACE, the mettafied reading of reading a file: its lines become
% (line Number Text) atoms in a fresh space, so the file is queryable with
% match instead of being one long string to take apart. The line number is
% kept because a space is unordered, and losing which line came first would
% make the space strictly less useful than the string it replaced.
%
%    (let $log (file-space! "app.log")
%      (match $log (line $n $text) ($n $text)))
'file-space!'(Path, Space) :-
    'file-lines!'(Path, Lines),
    findall([line, Index, Text], nth1(Index, Lines, Text), Rows),
    'new-space'(Space),
    catch(spaces:metta_add_atoms(Space, Rows), Error,
          (spaces:metta_release_space(Space), throw(Error))).

%! 'temp-path!'(+Prefix:any, -Path:string) is det.
%
% A unique fresh path in the system temporary directory, created exclusively
% so concurrent runners cannot mint the same name; the caller owns the file
% from that point (write-file! truncates it, delete-file! ends it). The
% prefix names the file and may not contain a separator.

% tmp_file_stream/3 creates the file exclusively, which is what makes the
% name safe against a concurrent runner minting at the same moment. The
% shipped text example uses it so two checkouts running the corpus at once
% cannot collide on a fixed name
% [tested: examples/ch08-data/08-03-the-shipped-libraries/03-text_lib.metta].
'temp-path!'(Prefix, PathString) :-
    metta_text(Prefix, PrefixText),
    refuse_separator('temp-path!', PrefixText),
    tmp_file_stream(Path, Stream, [encoding(utf8), extension(txt)]),
    close(Stream),
    file_directory_name(Path, Dir),
    file_base_name(Path, Base),
    atomic_list_concat([Dir, '/', PrefixText, '-', Base], Unique),
    catch(rename_file(Path, Unique), Error,
          ( delete_file(Path), metta_file_refusal('temp-path!', Error) )),
    atom_string(Unique, PathString).

%! 'temp-dir!'(+Prefix:any, -Path:string) is det.
%
% A unique fresh directory in the system temporary directory, created
% exclusively so concurrent runners cannot mint the same name; the caller
% owns it and removes it with delete-dir! or delete-tree!. The prefix names
% the directory and may not contain a separator.

% make_directory/1 is the exclusive act here, as tmp_file_stream/3's
% exclusive create is for temp-path!: tmp_file/2 supplies a name and creates
% nothing, and mkdir refuses a name that is already taken, so two runners
% cannot both believe they own the directory.
%
% A prefix NAMES the directory and does not place it. tmp_file/2 pastes it
% into the path without sanitising, so tmp_file('../x', P) answers
% '/tmp/swipl_../x_PID_N', a path outside the temporary directory
% [measured 2026-09-05]. A separator is refused here rather than acted on.
'temp-dir!'(Prefix, PathString) :-
    metta_text(Prefix, PrefixText),
    refuse_separator('temp-dir!', PrefixText),
    atom_string(PrefixAtom, PrefixText),
    catch(( tmp_file(PrefixAtom, Path), make_directory(Path) ), Error,
          metta_file_refusal('temp-dir!', Error)),
    atom_string(Path, PathString).

refuse_separator(Operation, Text) :-
    (   sub_string(Text, _, _, _, "/")
    ->  throw(error('file-name-not-a-path'(Operation, Text),
                    context(Operation,
                            'Name the file without a separator and place it with path-join')))
    ;   true
    ).

%! 'delete-file!'(+Path:any, -Done:boolean) is det.
%
% Remove a regular file; an absent file is already removed and answers True.
'delete-file!'(Path, true) :-
    metta_text(Path, PathText),
    (   exists_file(PathText)
    ->  delete_file(PathText)
    ;   true
    ).

%! 'delete-tree!'(+Path:any, -Done:boolean) is det.
%
% Remove whatever is at Path: a directory with everything under it, a file, or
% a symbolic link, which is unlinked without touching its target. A missing
% path raises.
'delete-tree!'(Path, true) :-
    metta_text(Path, PathText),
    catch(delete_tree(PathText), Error, metta_file_refusal('delete-tree!', Error)).

delete_tree(Path) :-
    (   is_link(Path)
    ->  delete_file(Path)
    ;   exists_directory(Path)
    ->  delete_directory_and_contents(Path)
    ;   access_file(Path, exist)
    ->  delete_file(Path)
    ;   existence_error(file, Path)
    ).

%! 'list-dir!'(+Path:any, -Entries:list) is det.
%
% The names in a directory, without . and .., as Strings sorted by codepoint.
% A missing directory raises.
'list-dir!'(Path, Entries) :-
    metta_text(Path, PathText),
    (   exists_directory(PathText)
    ->  true
    ;   existence_error(directory, PathText)
    ),
    sorted_entries(PathText, Names),
    maplist(entry_to_string, Names, Entries).

% One directory listing, . and .. removed, sorted by codepoint so that a walk,
% a glob and a listing agree on the order and a test can state it.
sorted_entries(Directory, Names) :-
    directory_files(Directory, Raw),
    exclude(dot_entry, Raw, Kept),
    msort(Kept, Names).

%Named predicates rather than yall lambdas: yall copy_terms the lambda for
%every element, about four times the inferences of an ordinary call [measured
%2026-08-15, maplist over 100,000 elements: 1301283 against 300004].
dot_entry('.').
dot_entry('..').

entry_to_string(Name, Text) :- atom_string(Name, Text).

%! 'dir-walk'(+Path:any, -Entry:string) is nondet.
%! 'dir-walk'(+Path:any, +Options:list, -Entry:string) is nondet.
%
% Answer every descendant of a directory, one full path per answer, depth
% first with each directory's names in codepoint order. A symbolic link is
% reported and not entered unless Options holds (follow-links True); a link
% whose target is a directory already on the current chain is then reported
% and still not entered, so a cycle cannot loop. Hidden names are included.
% An unreadable directory raises.
'dir-walk'(Path, Entry) :-
    'dir-walk'(Path, [], Entry).
'dir-walk'(Path, Options, Entry) :-
    metta_text(Path, RootText),
    atom_string(Root, RootText),
    walk_options('dir-walk', [follow-links], Options, Pairs),
    walk_option(follow-links, Pairs, false, Follow),
    (   exists_directory(Root)
    ->  true
    ;   existence_error(directory, Root)
    ),
    catch(walk_entries(Root, [Root], Follow, Full), Error,
          metta_file_refusal('dir-walk', Error)),
    atom_string(Full, Entry).

walk_entries(Directory, Chain, Follow, Entry) :-
    sorted_entries(Directory, Names),
    member(Name, Names),
    directory_file_path(Directory, Name, Full),
    (   Entry = Full
    ;   enters(Full, Chain, Follow),
        walk_entries(Full, [Full|Chain], Follow, Entry)
    ).

% Whether a traversal descends into an entry: a real directory always; a link
% to a directory only when following and only when its target is not already
% an ancestor by physical identity, which is what stops a cycle.
enters(Full, Chain, Follow) :-
    (   is_link(Full)
    ->  Follow == true,
        exists_directory(Full),
        \+ ( member(Ancestor, Chain), same_file(Ancestor, Full) )
    ;   exists_directory(Full)
    ).

is_link(Path) :-
    catch(read_link(Path, _, _), _, fail).

%! 'dir-glob'(+Directory:any, +Pattern:any, -Path:string) is nondet.
%! 'dir-glob'(+Directory:any, +Pattern:any, +Options:list, -Path:string) is nondet.
%
% Answer every path under Directory matching a relative pattern of
% slash-separated components, in depth-first codepoint order. A component
% uses the host's wildcard grammar: * and ? match within a name, [abc] and
% [a-c] match one character, {alt,alt} alternates, and \ escapes the next
% character. The component ** matches zero or more directory levels, so
% "**/*.txt" finds every text file below Directory. A wildcard skips names
% beginning with a dot unless Options holds (hidden True) or the component
% itself begins with a dot; ** enters symbolic links only under
% (follow-links True) and never re-enters a directory on its chain. A literal
% component is looked up without listing, so a pattern without wildcards
% answers the path exactly when it exists. An absolute or empty pattern and a
% malformed component raise. Each path is answered once.
'dir-glob'(Directory, Pattern, Path) :-
    'dir-glob'(Directory, Pattern, [], Path).
'dir-glob'(Directory, Pattern, Options, Path) :-
    metta_text(Directory, RootText),
    atom_string(Root, RootText),
    metta_text(Pattern, PatternText),
    walk_options('dir-glob', [hidden, follow-links], Options, Pairs),
    walk_option(hidden, Pairs, false, Hidden),
    walk_option(follow-links, Pairs, false, Follow),
    glob_components(PatternText, Components),
    (   exists_directory(Root)
    ->  true
    ;   existence_error(directory, Root)
    ),
    catch(distinct(Full, glob_select(Components, Root, [], [Root], Hidden, Follow, Full)),
          Error, glob_refusal(PatternText, Error)),
    atom_string(Full, Path).

% A pattern is components between separators; empty components and . are
% dropped, so "a//b" and "a/./b" read as "a/b", and a run of ** is one **.
glob_components(Pattern, Components) :-
    (   Pattern == ""
    ->  domain_error(glob_pattern, Pattern)
    ;   sub_string(Pattern, 0, 1, _, "/")
    ->  throw(error(domain_error(glob_pattern, Pattern),
                    context('dir-glob', 'Give a relative pattern; the directory is the first argument')))
    ;   true
    ),
    split_string(Pattern, "/", "", Raw),
    exclude(empty_component, Raw, Kept),
    maplist(component_atom, Kept, Atoms),
    collapse_recursive(Atoms, Components).

empty_component("").
empty_component(".").

component_atom(Text, Atom) :- atom_string(Atom, Text).

collapse_recursive([], []).
collapse_recursive(['**', '**'|More], Components) :- !,
    collapse_recursive(['**'|More], Components).
collapse_recursive([Component|More], [Component|Components]) :-
    collapse_recursive(More, Components).

% The selector walk is CPython's glob structure: a literal component is joined
% without a listing, a wildcard component lists one directory and filters it,
% and ** recurses through directories while the same tail stays pending
% [source: https://github.com/python/cpython/blob/823f0323ee6ec1402088b73bce1a38473cac36dc/Lib/glob.py;
% commit=WORKTREE]. Rel is the matched relative components so far, reversed.
glob_select([], Root, Rel, _, _, _, Full) :-
    relative_path(Root, Rel, Full),
    path_exists(Full).
glob_select(['**'|Rest], Root, Rel, Chain, Hidden, Follow, Full) :-
    (   glob_select(Rest, Root, Rel, Chain, Hidden, Follow, Full)
    ;   relative_path(Root, Rel, Current),
        sorted_entries(Current, Names),
        member(Name, Names),
        visible(Name, '**', Hidden),
        directory_file_path(Current, Name, Sub),
        enters(Sub, Chain, Follow),
        glob_select(['**'|Rest], Root, [Name|Rel], [Sub|Chain], Hidden, Follow, Full)
    ).
glob_select([Component|Rest], Root, Rel, Chain, Hidden, Follow, Full) :-
    Component \== '**',
    (   wildcard_component(Component)
    ->  relative_path(Root, Rel, Current),
        sorted_entries(Current, Names),
        member(Name, Names),
        visible(Name, Component, Hidden),
        wildcard_match(Component, Name)
    ;   Name = Component
    ),
    (   Rest == []
    ->  relative_path(Root, [Name|Rel], Full),
        path_exists(Full)
    ;   relative_path(Root, [Name|Rel], Sub),
        exists_directory(Sub),
        glob_select(Rest, Root, [Name|Rel], [Sub|Chain], Hidden, Follow, Full)
    ).

wildcard_component(Component) :-
    atom_codes(Component, Codes),
    member(Code, Codes),
    memberchk(Code, [0'*, 0'?, 0'[, 0'{, 0'\\]),
    !.

% The shell's dotfile rule: a wildcard never matches a leading dot unless the
% component was written with one, and (hidden True) lifts the rule.
visible(Name, Component, Hidden) :-
    (   Hidden == true
    ->  true
    ;   sub_atom(Component, 0, 1, _, '.')
    ->  true
    ;   \+ sub_atom(Name, 0, 1, _, '.')
    ).

relative_path(Root, [], Root) :- !.
relative_path(Root, Rel, Path) :-
    reverse(Rel, Forward),
    atomic_list_concat(Forward, '/', Relative),
    directory_file_path(Root, Relative, Path).

glob_refusal(Pattern, error(syntax_error(Detail), _)) :- !,
    throw(error(domain_error(glob_pattern, Pattern),
                context('dir-glob', Detail))).
glob_refusal(_, Error) :-
    metta_file_refusal('dir-glob', Error).

% Options are a proper expression of unique (Name Bool) pairs, the same shape
% lib_csv reads, so a walk and a glob configure the way a CSV dialect does.
walk_options(Operation, Allowed, Options, Pairs) :-
    (   is_list(Options)
    ->  true
    ;   throw(error(type_error(list, Options),
                    context(Operation, 'Options are an expression of (Name Value) pairs')))
    ),
    foldl(walk_option_pair(Operation, Allowed), Options, [], Pairs).

walk_option_pair(Operation, Allowed, Option, Before, [Name-Value|Before]) :-
    (   is_list(Option), Option = [Name0, Value], atom(Name0),
        option_name(Name0, Name), memberchk(Name, Allowed),
        memberchk(Value, [true, false])
    ->  true
    ;   throw(error(domain_error(walk_option, Option),
                    context(Operation, 'Options are (follow-links Bool) and (hidden Bool)')))
    ),
    (   memberchk(Name-_, Before)
    ->  throw(error(domain_error(duplicate_walk_option, Name0),
                    context(Operation, 'Give each option once')))
    ;   true
    ).

option_name('follow-links', follow-links).
option_name(hidden, hidden).

walk_option(Name, Pairs, Default, Value) :-
    (   memberchk(Name-Found, Pairs)
    ->  Value = Found
    ;   Value = Default
    ).

%! 'file-exists'(+Path:any, -Answer:boolean) is det.
%
% True when a regular file exists at the path, following links, False
% otherwise. No ! because it changes nothing.

%The engine's own exists_file is not usable for this. It registers with zero
%inputs, so (exists_file "p") is a arity error, function_input_arities(
%exists_file,[0]) against 1, and the only spelling that works is the guard
%idiom (let $p (exists_file) ...) where a missing file FAILS the whole call.
%A library of file operations needs a question you can ask.
'file-exists'(Path, Answer) :-
    metta_text(Path, PathText),
    ( exists_file(PathText) -> Answer = true ; Answer = false ).

%! 'dir-exists'(+Path:any, -Answer:boolean) is det.
%
% True when a directory exists at the path, following links, False otherwise.
'dir-exists'(Path, Answer) :-
    metta_text(Path, PathText),
    ( exists_directory(PathText) -> Answer = true ; Answer = false ).

%! 'file-kind'(+Path:any, -Kind:atom) is det.
%
% Classify the entry at Path without following it: link for a symbolic link,
% dangling or not; directory; file; other for an entry that exists and is
% none of those, such as a FIFO, socket or device; missing when nothing is
% observable at the path.
'file-kind'(Path, Kind) :-
    metta_text(Path, PathText),
    (   is_link(PathText)
    ->  Kind = link
    ;   exists_directory(PathText)
    ->  Kind = directory
    ;   exists_file(PathText)
    ->  Kind = file
    ;   access_file(PathText, exist)
    ->  Kind = other
    ;   Kind = missing
    ).

% An entry is present when the host can see it or when it is a link, dangling
% included: access_file/2 follows links and reports a dangling one as absent.
path_exists(Path) :-
    (   access_file(Path, exist)
    ->  true
    ;   is_link(Path)
    ).

%! 'same-file'(+Left:any, +Right:any, -Answer:boolean) is det.
%
% True when both paths name one physical file or directory, through links,
% hard links and different spellings; False when they differ or either is
% missing.
'same-file'(Left, Right, Answer) :-
    metta_text(Left, LeftText),
    metta_text(Right, RightText),
    ( same_file(LeftText, RightText) -> Answer = true ; Answer = false ).

%! 'read-link'(+Path:any, -Target:string) is det.
%
% The text a symbolic link holds, exactly as it was written, relative or
% absolute; a path that is not a link raises with its kind.
'read-link'(Path, Target) :-
    metta_text(Path, PathText),
    (   catch(read_link(PathText, Link, _), _, fail)
    ->  atom_string(Link, Target)
    ;   'file-kind'(PathText, Kind),
        throw(error('file-kind-mismatch'('read-link', PathText, link, Kind),
                    context('read-link', 'Ask file-kind first; only a link has a target')))
    ).

%! 'make-link!'(+Target:any, +Path:any, -Done:boolean) is det.
%
% Create a symbolic link at Path holding Target exactly as written; a relative
% target is read relative to the link's own directory. The target need not
% exist. An existing entry at Path raises.
'make-link!'(Target, Path, true) :-
    metta_text(Target, TargetText),
    metta_text(Path, PathText),
    (   path_exists(PathText)
    ->  throw(error('file-already-exists'('make-link!', PathText),
                    context('make-link!', 'Remove the entry or choose another path')))
    ;   true
    ),
    atom_string(TargetAtom, TargetText),
    atom_string(PathAtom, PathText),
    catch(link_file(TargetAtom, PathAtom, symbolic), Error,
          metta_file_refusal('make-link!', Error)).

% Path operations use SWI's lexical POSIX path convention. No filesystem
% lookup occurs, including for nonexistent paths and dot components.
% [tested: lib_file_surface:lexical_paths; commit=504f8dddfa890ced97e795a13ab10e239b1de2ce]

%! 'path-join'(+Directory:any, +Name:any, -Path:string) is det.
%
% Join lexical paths; an absolute second path replaces the first.
'path-join'(Directory, Name, Path) :-
    metta_text(Directory, DirectoryText),
    metta_text(Name, NameText),
    atom_string(Dir, DirectoryText),
    atom_string(Base, NameText),
    directory_file_path(Dir, Base, Joined),
    atom_string(Joined, Path).

%! 'path-parent'(+Path:any, -Parent:string) is det.
%
% Lexical parent directory; a bare filename has parent dot.
'path-parent'(Path, Parent) :-
    metta_text(Path, Text),
    file_directory_name(Text, Directory),
    atom_string(Directory, Parent).

%! 'path-name'(+Path:any, -Name:string) is det.
%
% Lexical final path component.
'path-name'(Path, Name) :-
    metta_text(Path, Text),
    file_base_name(Text, Base),
    atom_string(Base, Name).

%! 'path-extension'(+Path:any, -Extension:string) is det.
%
% Text after the final dot in the filename, without the dot; empty when
% absent. A name that is only an extension, such as .env, has extension env.
'path-extension'(Path, Extension) :-
    metta_text(Path, Text),
    file_base_name(Text, Base),
    file_name_extension(_, Ext, Base),
    atom_string(Ext, Extension).

%! 'path-stem'(+Path:any, -Stem:string) is det.
%
% The final path component without its extension, the complement of
% path-extension: "a/b.tar.gz" has stem "b.tar", and ".env" has stem "".
'path-stem'(Path, Stem) :-
    metta_text(Path, Text),
    file_base_name(Text, Base),
    file_name_extension(StemAtom, _, Base),
    atom_string(StemAtom, Stem).

%! 'path-parts'(+Path:any, -Parts:list) is det.
%
% The components of a path as an expression of Strings: "/" first for an
% absolute path, empty and dot components dropped, .. kept. "" answers ().
'path-parts'(Path, Parts) :-
    metta_text(Path, Text),
    path_root(Text, Root, Rest),
    split_string(Rest, "/", "", Raw),
    exclude(empty_component, Raw, Components),
    (   Root == ""
    ->  Parts = Components
    ;   Parts = [Root|Components]
    ).

%! 'path-normalize'(+Path:any, -Normalized:string) is det.
%
% Collapse repeated separators and dot components and resolve .. lexically,
% as CPython's posixpath.normpath does: "a/./b/../c" is "a/c", ".." stays at
% the start of a relative path, "/.." is "/", exactly two leading slashes are
% kept, and "" is ".". No filesystem lookup occurs, so a .. across a symbolic
% link is resolved as if the link were a directory; path-resolve consults the
% filesystem.
'path-normalize'(Path, Normalized) :-
    metta_text(Path, Text),
    normalize_text(Text, Normalized).

% [source: https://github.com/python/cpython/blob/823f0323ee6ec1402088b73bce1a38473cac36dc/Lib/posixpath.py,
% normpath; commit=WORKTREE]. A .. is kept at the start of a relative path or
% after another .., pops a component otherwise, and is dropped at the root.
normalize_text("", ".") :- !.
normalize_text(Text, Normalized) :-
    path_root(Text, Root, Rest),
    split_string(Rest, "/", "", Raw),
    foldl(normalize_component(Root), Raw, [], Reversed),
    reverse(Reversed, Components),
    atomic_list_concat(Components, '/', Joined),
    atom_string(Joined, JoinedText),
    string_concat(Root, JoinedText, Result),
    (   Result == ""
    ->  Normalized = "."
    ;   Normalized = Result
    ).

normalize_component(_, "", Stack, Stack) :- !.
normalize_component(_, ".", Stack, Stack) :- !.
normalize_component(Root, "..", Stack, Next) :- !,
    (   Root == "", Stack == []
    ->  Next = [".."]
    ;   Stack = [".."|_]
    ->  Next = [".."|Stack]
    ;   Stack = [_|Popped]
    ->  Next = Popped
    ;   Next = Stack
    ).
normalize_component(_, Component, Stack, [Component|Stack]).

% POSIX keeps exactly two leading slashes as a distinct root; one or three or
% more are the ordinary root.
path_root(Text, Root, Rest) :-
    string_codes(Text, Codes),
    leading_slashes(Codes, 0, Count, RestCodes),
    string_codes(Rest, RestCodes),
    (   Count == 0
    ->  Root = ""
    ;   Count == 2
    ->  Root = "//"
    ;   Root = "/"
    ).

leading_slashes([0'/|Codes], Seen, Count, Rest) :- !,
    Next is Seen + 1,
    leading_slashes(Codes, Next, Count, Rest).
leading_slashes(Codes, Count, Count, Codes).

%! 'path-absolute'(+Path:any, -Absolute:string) is det.
%
% Anchor a relative path to the process working directory and normalize it
% lexically, as CPython's posixpath.abspath does; no links are resolved.
'path-absolute'(Path, Absolute) :-
    metta_text(Path, Text),
    absolute_text(Text, Absolute).

absolute_text(Text, Absolute) :-
    (   sub_string(Text, 0, 1, _, "/")
    ->  normalize_text(Text, Absolute)
    ;   working_directory(Working, Working),
        atom_string(Working, WorkingText),
        atomics_to_string([WorkingText, "/", Text], Joined),
        normalize_text(Joined, Absolute)
    ).

%! 'path-relative'(+Path:any, +Start:any, -Relative:string) is det.
%
% The path from the directory Start to Path, lexically, as CPython's
% posixpath.relpath does: both are made absolute, the common prefix is
% dropped, and one .. is written per remaining component of Start; the same
% place is ".". An empty Path raises.
'path-relative'(Path, Start, Relative) :-
    metta_text(Path, PathText),
    metta_text(Start, StartText),
    (   PathText == ""
    ->  throw(error(domain_error(path, PathText),
                    context('path-relative', 'Give a path; the start directory is the second argument')))
    ;   true
    ),
    absolute_text(PathText, PathAbsolute),
    absolute_text(StartText, StartAbsolute),
    absolute_components(PathAbsolute, PathParts),
    absolute_components(StartAbsolute, StartParts),
    common_prefix(StartParts, PathParts, Shared),
    length(Shared, Common),
    length(StartParts, StartLength),
    Ups is StartLength - Common,
    length(Dots, Ups),
    maplist(=(".."), Dots),
    length(Prefix, Common),
    append(Prefix, Tail, PathParts),
    append(Dots, Tail, Components),
    (   Components == []
    ->  Relative = "."
    ;   atomic_list_concat(Components, '/', Joined),
        atom_string(Joined, Relative)
    ).

% [source: https://github.com/python/cpython/blob/823f0323ee6ec1402088b73bce1a38473cac36dc/Lib/posixpath.py,
% relpath; commit=WORKTREE]. The absolute paths are already normalized, so
% stripping the root and splitting gives the component lists relpath compares.
absolute_components(Absolute, Parts) :-
    path_root(Absolute, _, Rest),
    split_string(Rest, "/", "", Raw),
    exclude(empty_component, Raw, Parts).

common_prefix([X|Xs], [Y|Ys], [X|Shared]) :-
    X == Y, !,
    common_prefix(Xs, Ys, Shared).
common_prefix(_, _, []).

%! 'path-resolve'(+Path:any, -Resolved:string) is det.
%
% The absolute path with every symbolic link on the way replaced by what it
% points to, as CPython's non-strict posixpath.realpath does: a relative path
% starts at the process working directory, a link's target is read before any
% later .. applies, a link loop or a missing component is kept as written,
% and the result is normalized.
'path-resolve'(Path, Resolved) :-
    metta_text(Path, Text),
    (   sub_string(Text, 0, 1, _, "/")
    ->  Start = "/"
    ;   working_directory(Working, Working),
        atom_string(Working, WorkingText),
        normalize_text(WorkingText, Start)
    ),
    split_string(Text, "/", "", Parts),
    empty_assoc(Seen),
    resolve_parts(Parts, Start, Seen, ResolvedText),
    normalize_text(ResolvedText, Resolved).

% [source: https://github.com/python/cpython/blob/823f0323ee6ec1402088b73bce1a38473cac36dc/Lib/posixpath.py,
% realpath; commit=WORKTREE]. The pending components are a stack; a link's
% target components are pushed in front of the rest, behind a marker that
% records the link's fully resolved target when the target has been consumed.
% A link met again while still unresolved is a loop and stays as written.
resolve_parts([], Path, _, Path).
resolve_parts([resolved(Link)|Rest], Path, Seen0, Resolved) :- !,
    put_assoc(Link, Seen0, Path, Seen),
    resolve_parts(Rest, Path, Seen, Resolved).
resolve_parts([""|Rest], Path, Seen, Resolved) :- !,
    resolve_parts(Rest, Path, Seen, Resolved).
resolve_parts(["."|Rest], Path, Seen, Resolved) :- !,
    resolve_parts(Rest, Path, Seen, Resolved).
resolve_parts([".."|Rest], Path, Seen, Resolved) :- !,
    parent_text(Path, Parent),
    resolve_parts(Rest, Parent, Seen, Resolved).
resolve_parts([Name|Rest], Path, Seen0, Resolved) :-
    child_text(Path, Name, Child),
    (   get_assoc(Child, Seen0, Known)
    ->  (   Known == unresolved
        ->  resolve_parts(Rest, Child, Seen0, Resolved)
        ;   resolve_parts(Rest, Known, Seen0, Resolved)
        )
    ;   catch(read_link(Child, Link, _), _, fail)
    ->  atom_string(Link, LinkText),
        (   sub_string(LinkText, 0, 1, _, "/")
        ->  Reset = "/"
        ;   Reset = Path
        ),
        put_assoc(Child, Seen0, unresolved, Seen),
        split_string(LinkText, "/", "", Targets),
        append(Targets, [resolved(Child)|Rest], Pending),
        resolve_parts(Pending, Reset, Seen, Resolved)
    ;   resolve_parts(Rest, Child, Seen0, Resolved)
    ).

parent_text("/", "/") :- !.
parent_text(Path, Parent) :-
    sub_string(Path, Before, 1, _, "/"),
    \+ ( sub_string(Path, Later, 1, _, "/"), Later > Before ),
    !,
    (   Before == 0
    ->  Parent = "/"
    ;   sub_string(Path, 0, Before, _, Parent)
    ).

child_text("/", Name, Child) :- !,
    string_concat("/", Name, Child).
child_text(Path, Name, Child) :-
    atomics_to_string([Path, "/", Name], Child).

%! 'make-dir!'(+Path:any, -Done:boolean) is det.
%
% Create a directory and missing parents; an existing directory succeeds.
'make-dir!'(Path, true) :-
    metta_text(Path, Text),
    atom_string(Directory, Text),
    catch(make_directory_path(Directory), Error,
          metta_file_refusal('make-dir!', Error)).

%! 'delete-dir!'(+Path:any, -Done:boolean) is det.
%
% Remove an empty directory; missing or nonempty directories raise.
% delete-tree! removes a directory with its contents.
'delete-dir!'(Path, true) :-
    metta_text(Path, Text),
    catch(delete_directory(Text), Error,
          metta_file_refusal('delete-dir!', Error)).

%! 'rename-file!'(+Source:any, +Destination:any, -Done:boolean) is det.
%
% Rename a file or directory within one filesystem, the host's own rename: a
% file replaces an existing file and a directory replaces an existing empty
% directory in one step, so a reader sees the old entry or the new one. A
% missing source, a same-file rename, a file onto a directory, a directory
% onto a file or a nonempty directory, and a destination on another
% filesystem raise; nothing is ever copied.
'rename-file!'(Source, Destination, true) :-
    metta_text(Source, From),
    metta_text(Destination, To),
    (   path_exists(From)
    ->  true
    ;   throw(error('file-not-found'('rename-file!', file, From),
                    context('rename-file!', 'Create the missing path or correct its spelling')))
    ),
    (   same_file(From, To)
    ->  throw(error('file-permission-denied'('rename-file!', rename, same_file, To),
                    context('rename-file!', 'Choose a different destination')))
    ;   true
    ),
    catch(rename_file(From, To), error(_, context(_, Message)),
          throw(error('file-operation-failed'('rename-file!', Message),
                      context('rename-file!',
                              'Rename within one filesystem, a file onto a file or a directory onto an empty directory')))).

%! 'copy-file!'(+Source:any, +Destination:any, -Done:boolean) is det.
%
% Copy bytes to a destination filename with staged replacement: the copy is
% written beside the destination, both streams close, and one rename
% publishes it, so an existing destination is replaced only after the
% complete copy succeeds. A directory destination and copying a file onto
% itself are errors.

% Acquire the staging directory with mkdir, which refuses an existing name.
% tmp_file/2 supplies a name only; no guessed filename is opened for writing.
% [tested: lib_file_surface:copy_is_binary_and_replaces_only_after_success,
% lib_file_surface:failed_copy_preserves_destination; commit=504f8dddfa890ced97e795a13ab10e239b1de2ce]
'copy-file!'(Source, Destination, true) :-
    metta_text(Source, From),
    metta_text(Destination, To),
    catch(metta_copy_file(From, To), Error,
          metta_file_refusal('copy-file!', Error)).

metta_copy_file(From, To) :-
    (   exists_file(To), same_file(From, To)
    ->  throw(error(permission_error(copy, same_file, To),
                    context('copy-file!', 'Choose a different destination')))
    ;   true
    ),
    metta_staged_publish(To, metta_copy_bytes(From)).

% One publication protocol for copy-file!, replace-file! and copy-dir!: a
% sibling staging directory acquired with mkdir, the writer filling
% StageDirectory/contents, one rename onto the destination, and the staging
% directory removed on every exit. The destination changes only after every
% staged stream has closed, because the writer closes before it returns.
metta_staged_publish(To, Writer) :-
    file_directory_name(To, Parent),
    (   exists_directory(Parent)
    ->  true
    ;   existence_error(directory, Parent)
    ),
    tmp_file(metta_stage, Temp),
    file_base_name(Temp, Base),
    directory_file_path(Parent, Base, StageDirectory),
    setup_call_cleanup(
        make_directory(StageDirectory),
        ( directory_file_path(StageDirectory, contents, Stage),
          call(Writer, Stage),
          publish(Stage, To) ),
        delete_directory_and_contents(StageDirectory)).

% The host reports a refused rename as an existence error on the STAGE with
% the operating system's reason in the context; the reason is the fact worth
% reporting, and the stage name is not.
publish(Stage, To) :-
    catch(rename_file(Stage, To), error(_, context(_, Reason)),
          throw(publication_refused(To, Reason))).

metta_copy_bytes(From, Stage) :-
    setup_call_cleanup(
        open(From, read, Input, [type(binary)]),
        setup_call_cleanup(
            open(Stage, write, Output, [type(binary)]),
            copy_stream_data(Input, Output),
            close(Output)),
        close(Input)).

%! 'copy-dir!'(+Source:any, +Destination:any, -Done:boolean) is det.
%
% Copy a directory tree to a new path: the contents of Source become the
% contents of Destination, which must not exist; missing parents of
% Destination are created. Regular files are copied byte for byte, symbolic
% links are recreated with the text they hold, and a FIFO, socket or device
% raises. The tree is built in a staging directory beside Destination and
% published with one rename, so a reader sees no tree or the whole tree, and
% a failure leaves nothing behind. A destination inside the source raises
% before anything is written. Ownership, modes and times are not copied.
'copy-dir!'(Source, Destination, true) :-
    metta_text(Source, From0),
    metta_text(Destination, To0),
    (   exists_directory(From0)
    ->  true
    ;   path_exists(From0)
    ->  'file-kind'(From0, Kind),
        throw(error('file-kind-mismatch'('copy-dir!', From0, directory, Kind),
                    context('copy-dir!', 'Copy a file with copy-file!')))
    ;   throw(error('file-not-found'('copy-dir!', directory, From0),
                    context('copy-dir!', 'Create the missing path or correct its spelling')))
    ),
    (   path_exists(To0)
    ->  throw(error('file-already-exists'('copy-dir!', To0),
                    context('copy-dir!', 'Remove the entry, delete-tree! it, or choose another path')))
    ;   true
    ),
    absolute_text(From0, From),
    absolute_text(To0, To),
    (   path_within(To, From)
    ->  throw(error('file-overlap'('copy-dir!', From0, To0),
                    context('copy-dir!', 'Choose a destination outside the source')))
    ;   true
    ),
    catch(( file_directory_name(To, Parent),
            make_directory_path(Parent),
            metta_staged_publish(To, copy_tree(From)) ),
          Error, metta_file_refusal('copy-dir!', Error)).

% Lexical containment over the two absolute, normalized paths: equal, or the
% candidate continues the source at a separator.
path_within(Path, Directory) :-
    (   Path == Directory
    ->  true
    ;   string_concat(Directory, "/", Prefix),
        sub_string(Path, 0, _, _, Prefix)
    ).

copy_tree(From, Stage) :-
    make_directory(Stage),
    copy_entries(From, Stage).

copy_entries(From, To) :-
    sorted_entries(From, Names),
    forall(member(Name, Names),
           ( directory_file_path(From, Name, Source),
             directory_file_path(To, Name, Target),
             copy_entry(Source, Target) )).

copy_entry(Source, Target) :-
    (   catch(read_link(Source, Link, _), _, fail)
    ->  link_file(Link, Target, symbolic)
    ;   exists_directory(Source)
    ->  make_directory(Target),
        copy_entries(Source, Target)
    ;   exists_file(Source)
    ->  metta_copy_bytes(Source, Target)
    ;   access_file(Source, exist)
    ->  throw(error('file-kind-mismatch'('copy-dir!', Source, file, other),
                    context('copy-dir!', 'Remove the FIFO, socket or device from the source tree')))
    ;   existence_error(file, Source)
    ).

%! 'file-metadata!'(+Path:any, -Space:any) is det.
%
% Snapshot kind, modified Unix time and file size as queryable atoms in a new
% space: (kind file|directory), (modified Seconds) and, for a file, (size
% Bytes). Links are followed; file-kind classifies the entry itself.

% Read all metadata before allocating the snapshot. A failed stat never
% leaves a partly populated space behind.
% [tested: lib_file_surface:metadata_is_queryable; commit=504f8dddfa890ced97e795a13ab10e239b1de2ce]
'file-metadata!'(Path, Space) :-
    metta_text(Path, Text),
    catch(metta_file_metadata(Text, Rows), Error,
          metta_file_refusal('file-metadata!', Error)),
    'new-space'(Space),
    catch(spaces:metta_add_atoms(Space, Rows), Error,
          (spaces:metta_release_space(Space), throw(Error))).

metta_file_metadata(Path, Rows) :-
    time_file(Path, Modified),
    (   exists_directory(Path)
    ->  Rows = [[kind, directory], [modified, Modified]]
    ;   size_file(Path, Size),
        Rows = [[kind, file], [size, Size], [modified, Modified]]
    ).

% Standard stream aliases follow the host's redirections and remain owned
% by the process. These operations never close them.
% [tested: test_standard_streams_and_explicit_exit; commit=504f8dddfa890ced97e795a13ab10e239b1de2ce]

%! 'stderr!'(+Content:any, -Done:boolean) is det.
%
% Write text to stderr and flush, without adding a newline.
'stderr!'(Content, true) :-
    metta_text(Content, Text),
    catch((write(user_error, Text), flush_output(user_error)), Error,
          metta_file_refusal('stderr!', Error)).

%! 'stdin-to-string!'(-Content:string) is det.
%
% Consume standard input through EOF as UTF-8 text.
'stdin-to-string!'(Content) :-
    catch(read_string(user_input, _, Content), Error,
          metta_file_refusal('stdin-to-string!', Error)).

%! 'exit!'(+Status:integer, -Never:any) is det.
%
% Terminate the entire process with integer status 0 through 255, including
% an embedding host; not an application-level return, so MeTTa catch does not
% turn it into a local value.

% This is process termination, including when embedded. SWI halt's unwind
% cannot be used as a catchable application-level return protocol.
% [tested: test_exit_is_process_termination_even_inside_catch; commit=504f8dddfa890ced97e795a13ab10e239b1de2ce]
'exit!'(Status, _) :-
    (   integer(Status), between(0, 255, Status)
    ->  halt(Status)
    ;   throw(error(domain_error(exit_status, Status),
                    context('exit!', 'Use an integer exit status from 0 to 255')))
    ).

% A refusal this library already named passes through unchanged, so a nested
% operation's own name and remedy reach the caller.
metta_file_refusal(_, error(Formal, Context)) :-
    compound(Formal), functor(Formal, Name, _), library_refusal(Name), !,
    throw(error(Formal, Context)).
metta_file_refusal(Operation, error(existence_error(Kind, Path), _)) :- !,
    throw(error('file-not-found'(Operation, Kind, Path),
                context(Operation, 'Create the missing path or correct its spelling'))).
metta_file_refusal(Operation, error(permission_error(Action, Kind, Path), _)) :- !,
    throw(error('file-permission-denied'(Operation, Action, Kind, Path),
                context(Operation, 'Check access permissions and choose a valid source or destination'))).
metta_file_refusal(Operation, Error) :-
    throw(error('file-operation-failed'(Operation, Error),
                context(Operation, 'Check the path, available storage and stream state before retrying'))).

library_refusal('file-not-found').
library_refusal('file-permission-denied').
library_refusal('file-operation-failed').
library_refusal('standard-stream-not-closable').
library_refusal('file-name-not-a-path').
library_refusal('file-handle-kind').
library_refusal('file-already-exists').
library_refusal('file-overlap').
library_refusal('file-kind-mismatch').

:- multifile prolog:error_message//1.
prolog:error_message('file-not-found'(Operation, Kind, Path)) -->
    [ 'file-not-found: ~w could not find ~w ~q; create the path or correct its spelling'
      -[Operation, Kind, Path] ].
prolog:error_message('file-permission-denied'(Operation, Action, Kind, Path)) -->
    [ 'file-permission-denied: ~w cannot ~w ~w ~q; check permissions and choose a valid source or destination'
      -[Operation, Action, Kind, Path] ].
prolog:error_message('file-operation-failed'(Operation, Error)) -->
    [ 'file-operation-failed: ~w: ~q; check the path, storage and stream state before retrying'
      -[Operation, Error] ].
prolog:error_message('standard-stream-not-closable'(Operation, Name)) -->
    [ 'standard-stream-not-closable: ~w refuses ~w; the process owns it, so \c
       close a stream file-open! gave you'-[Operation, Name] ].
prolog:error_message('file-name-not-a-path'(Operation, Name)) -->
    [ 'file-name-not-a-path: ~w was given ~q, which contains a separator; name \c
       the file and place it with path-join'-[Operation, Name] ].
prolog:error_message('file-handle-kind'(Operation, Handle, Kind)) -->
    [ 'file-handle-kind: ~w was given handle ~w, which carries ~w; open the file \c
       with b for bytes and without it for text'-[Operation, Handle, Kind] ].
prolog:error_message('file-already-exists'(Operation, Path)) -->
    [ 'file-already-exists: ~w refuses to replace ~q; remove the entry or choose \c
       another path'-[Operation, Path] ].
prolog:error_message('file-overlap'(Operation, Source, Destination)) -->
    [ 'file-overlap: ~w cannot copy ~q into ~q, which lies inside it; choose a \c
       destination outside the source'-[Operation, Source, Destination] ].
prolog:error_message('file-kind-mismatch'(Operation, Path, Expected, Actual)) -->
    [ 'file-kind-mismatch: ~w expected ~q to be a ~w and found ~w'
      -[Operation, Path, Expected, Actual] ].

%Every deterministic file operation succeeds exactly once: a missing file
%raises rather than failing, and an unknown handle raises rather than failing,
%so there is no semidet case among them. det/1 turns that from a comment into
%a check. The traversals and scopes are nondeterministic by contract and stay
%out of the list, as do the two-clause tables used as filters: dot_entry/1,
%is_link/1, path_exists/1, wildcard_component/1 and visible/3 FAIL for what
%they do not describe, which is their whole job.
:- det('file-open!'/3).
:- det('file-read-to-string!'/2).
:- det('file-read-exact!'/3).
:- det('file-write!'/3).
:- det('file-read-bytes!'/2).
:- det('file-read-bytes!'/3).
:- det('file-write-bytes!'/3).
:- det('file-seek!'/3).
:- det('file-get-size!'/2).
:- det('file-close!'/2).
:- det('read-file!'/2).
:- det('write-file!'/3).
:- det('append-file!'/3).
:- det('read-bytes!'/2).
:- det('write-bytes!'/3).
:- det('append-bytes!'/3).
:- det('replace-file!'/3).
:- det('file-lines!'/2).
:- det('file-space!'/2).
:- det('delete-file!'/2).
:- det('delete-tree!'/2).
:- det('temp-path!'/2).
:- det('temp-dir!'/2).
:- det('stdin'/1).
:- det('stdout'/1).
:- det('stderr'/1).
:- det('list-dir!'/2).
:- det('file-exists'/2).
:- det('dir-exists'/2).
:- det('file-kind'/2).
:- det('same-file'/3).
:- det('read-link'/2).
:- det('make-link!'/3).
:- det('path-join'/3).
:- det('path-parent'/2).
:- det('path-name'/2).
:- det('path-extension'/2).
:- det('path-stem'/2).
:- det('path-parts'/2).
:- det('path-normalize'/2).
:- det('path-absolute'/2).
:- det('path-relative'/3).
:- det('path-resolve'/2).
:- det('make-dir!'/2).
:- det('delete-dir!'/2).
:- det('rename-file!'/3).
:- det('copy-file!'/3).
:- det('copy-dir!'/3).
:- det('file-metadata!'/2).
:- det('stderr!'/2).
:- det('stdin-to-string!'/1).
:- det(next_file_handle/1).
:- det(file_open_mode/2).
:- det(entry_to_string/2).
:- det(sorted_entries/2).
:- det(normalize_text/2).
:- det(absolute_text/2).
:- det(path_root/3).
:- det(relative_path/3).
