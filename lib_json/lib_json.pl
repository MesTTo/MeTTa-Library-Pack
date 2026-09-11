% Purpose: JSON values, object spaces, document files and streaming JSON Lines.
% Guarantees: duplicate fields remain separate answers; failed construction
% releases its allocations and combines primary and cleanup errors; encoding
% refuses cycles and unrepresentable fields
% [tested: lib_json_surface; commit=WORKTREE].
% Owns resources: returned objects follow the engine's space ownership; the
% decoder does not reclaim successful answers. Readers close on exhaustion,
% cut and error. Writers publish only after closing their staging file and
% remove staging on every exit
% [tested: lib_json_surface; commit=WORKTREE].
% Guarded by: '$metta_native_storage' protects allocation and name reservation;
% each encoder snapshots an object once, with a call-local library(assoc) map.
% Concurrent changes to different objects are not one transaction
% [source: lib/lib_json/lib_json.pl:json_new_space/2,
% lib/lib_json/lib_json.pl:json_space_value/4; commit=5e212d77a567d6d6c118529e4a226e5047ec2cfd].
% Decides: objects are spaces, arrays are expressions, null is Null. Object
% lookup retains get-value's key unification and answer multiplicity. JSON Lines
% uses UTF-8 without a BOM, one value per physical line, and no blank lines
% [tested: lib_json_surface; commit=5e212d77a567d6d6c118529e4a226e5047ec2cfd].

:- module(lib_json,
          ['dict-space'/2, 'get-keys'/2, 'get-value'/3,
           'json-decode'/2, 'json-encode'/2, 'json-pretty'/2, 'json-pretty'/3,
           'json-read!'/2, 'json-write!'/3,
           'json-lines-decode'/2, 'json-lines-encode'/2,
           'json-lines-read!'/2, 'json-lines-write!'/3, 'json-at'/3]).
:- set_module(base(metta_engine)).
:- use_module('../../engine/json_codec',
              [json_codec_read/3, json_codec_write/3, json_codec_write/4]).
:- use_module('../lib_string/lib_string', [metta_text/2]).
:- use_module('../_support/owned_resources', [with_outcome_cleanup/3]).
:- use_module(library(apply), [maplist/2]).
:- use_module(library(assoc), [empty_assoc/1, get_assoc/3, put_assoc/4]).
:- use_module(library(error), [must_be/2, type_error/2, instantiation_error/1]).
:- use_module(library(filesex), [directory_file_path/3, delete_directory_and_contents/1]).
:- use_module(library(lists), [nth0/3]).
:- use_module(library(readutil), [read_stream_to_codes/2, read_line_to_codes/2]).
:- meta_predicate json_file_write(+, 1).

lib_json_options([shape(classic), true(@(true)), false(@(false)), null(@(null))]).

%! 'dict-space'(+Pairs:list, -Space:'SpaceType') is det.
%
% Build a fresh object space from (Key Value) pairs. Keys and values are data,
% including from and internal. Duplicate pairs stay distinct. Validate the whole
% list before allocation; failed construction releases every space it created.
'dict-space'(Pairs, Space) :-
    json_acyclic(Pairs),
    must_be(list, Pairs),
    maplist(json_pair, Pairs),
    with_outcome_cleanup(
        Owned = owned([]),
        ( json_new_space(Owned, New),
          maplist(add_sexp(New), Pairs),
          Space = New ),
        json_release_unreturned(Owned)).

json_pair(Pair) :-
    ( is_list(Pair), Pair = [_, _]
    -> true
    ;  type_error(key_value_pair, Pair) ).

%! 'get-keys'(+Space:'SpaceType', -Key:any) is nondet.
%
% Enumerate object keys in storage order, preserving duplicates. Use collapse
% to collect them. Non-pair atoms do not participate in this pattern query.
'get-keys'(Space, Key) :- 'get-atoms'(Space, [Key, _]).

%! 'get-value'(+Space:'SpaceType', +Key:any, -Value:any) is nondet.
%
% Enumerate values whose keys unify with Key. A missing key has no answers.
% Symbols and Strings are distinct keys, as in an ordinary space query.
'get-value'(Space, Key, Value) :- 'get-atoms'(Space, [Key, Value]).

%! 'json-decode'(+Text:any, -Value:any) is det.
%
% Decode one JSON document. Objects become spaces, arrays become expressions,
% strings and numbers retain their types, and literals become True, False and
% Null. Duplicate fields remain queryable. Malformed or trailing content raises.
'json-decode'(Text, Value) :-
    metta_text(Text, Json),
    lib_json_options(Options),
    json_codec_read(Json, Term, Options),
    with_outcome_cleanup(
        Owned = owned([]),
        ( json_to_metta(Term, Decoded, Owned), Value = Decoded ),
        json_release_unreturned(Owned)).

% The engine's allocator uses this mutex too, including foreign claims. Reserve
% a vacant name and record ownership before creation hooks can throw.
% nb_setarg copies the new cell and shares its old tail on SWI >= 9.3.18.
% https://github.com/SWI-Prolog/swipl-devel/commit/7de5ef58661b9d776627ad0f1167197a89430d0c
json_new_space(Owned, Space) :-
    with_mutex('$metta_native_storage',
        sig_atomic(( json_available_name(Space),
                     arg(1, Owned, Before),
                     nb_setarg(1, Owned, [Space|Before]),
                     ensure_native_storage_module(Space, _) ))).

json_available_name(Space) :-
    flag('$metta_json_space', Previous, Previous + 1),
    Next is Previous + 1,
    atom_concat('&json-', Next, Candidate),
    ( metta_space_operand(Candidate)
    -> json_available_name(Space)
    ;  Space = Candidate ).

json_release_unreturned(_, exit) :- !.
json_release_unreturned(Owned, How) :-
    arg(1, Owned, Spaces),
    json_release_all(Spaces, Errors),
    ( Errors == []
    -> true
    ;  throw(error(json_space_cleanup_failed(Errors), context(lib_json, How))) ).

json_release_all([], []).
json_release_all([Space|Rest], Errors) :-
    catch(( spaces:metta_release_space(Space)
          -> true
          ;  throw(error(json_space_release_failed(Space), _)) ), Error, true),
    ( var(Error) -> Errors = Tail ; Errors = [Space-Error|Tail] ),
    json_release_all(Rest, Tail).

json_to_metta(json(Pairs), Space, Owned) =>
    json_new_space(Owned, Space),
    json_object_fields(Pairs, Space, Owned).
json_to_metta(@(Literal), Value, _) => json_literal(Literal, Value).
json_to_metta([], Value, _) => Value = [].
json_to_metta([Head|Tail], Value, Owned) =>
    Value = [First|Rest],
    json_to_metta(Head, First, Owned),
    json_to_metta_list(Tail, Rest, Owned).
json_to_metta(Value, Out, _), atomic(Value) => Out = Value.

json_to_metta_list([], [], _).
json_to_metta_list([Head|Tail], [Value|Rest], Owned) :-
    json_to_metta(Head, Value, Owned),
    json_to_metta_list(Tail, Rest, Owned).

json_object_fields([], _, _).
json_object_fields([Key=Value|Rest], Space, Owned) :-
    json_to_metta(Value, Metta, Owned),
    add_sexp(Space, [Key, Metta]),
    json_object_fields(Rest, Space, Owned).

json_literal(true, true).
json_literal(false, false).
json_literal(null, 'Null').

%! 'json-encode'(+Value:any, -Text:string) is det.
%
% Encode one compact JSON document. Objects are spaces of (Key Value) fields;
% every stored atom must be a pair. Repeated aliases are valid, but cyclic
% objects or expressions raise cyclic_json_value. Non-finite numbers raise.
'json-encode'(Value, Text) :-
    metta_to_json(Value, Term),
    lib_json_options(Options),
    json_codec_write(Term, Text, Options).

%! 'json-pretty'(+Value:any, -Text:string) is det.
%
% Format JSON with SWI's default target width of 72 columns and two-space
% indentation. Short documents can remain on one line; long strings are not split.
'json-pretty'(Value, Text) :- 'json-pretty'(Value, 72, Text).

%! 'json-pretty'(+Value:any, +Width:nonneg, -Text:string) is det.
%
% Format JSON with a nonnegative target column width. Zero selects compact
% encoding; one puts nonempty containers on multiple lines. Width is a layout
% target, not a truncation limit. The value and error contracts match json-encode.
'json-pretty'(Value, Width, Text) :-
    must_be(nonneg, Width),
    metta_to_json(Value, Term),
    lib_json_options(Options),
    json_codec_write(Term, Text, Options, Width).

metta_to_json(Value, Term) :-
    json_acyclic(Value),
    empty_assoc(Empty),
    json_value(Value, Term, Empty, _),
    json_acyclic(Term).

json_acyclic(Value) :-
    ( acyclic_term(Value)
    -> true
    ;  throw(error(representation_error(cyclic_json_value),
                   context('json-encode', 'JSON values cannot contain cycles'))) ).

% Memoize before recursion so cycles become rational terms and aliases reuse a
% snapshot. Native acyclic_term checks the resulting graph without expanding it.
% CPython's check_circular makes the same cycle/alias distinction:
% https://github.com/python/cpython/blob/v3.14.0/Lib/json/encoder.py
json_value(Value, Term, Before, After) :-
    (   var(Value)
    ->  instantiation_error(Value)
    ;   Value == true
    ->  Term = @(true), After = Before
    ;   Value == false
    ->  Term = @(false), After = Before
    ;   Value == 'Null'
    ->  Term = @(null), After = Before
    ;   json_space(Value)
    ->  json_space_value(Value, Term, Before, After)
    ;   is_list(Value)
    ->  json_array(Value, Term, Before, After)
    ;   atomic(Value)
    ->  Term = Value, After = Before
    ;   type_error(json_value, Value)
    ).

json_space(Value) :-
    ( atom(Value)
    -> sub_atom(Value, 0, 1, _, '&')
    ;  metta_space_operand(Value) ).

json_space_value(Space, Term, Before, After) :-
    (   get_assoc(Space, Before, Known)
    ->  Term = Known, After = Before
    ;   put_assoc(Space, Before, Term, Added),
        findall(Atom, 'get-atoms'(Space, Atom), Atoms),
        json_acyclic(Atoms),
        Term = json(Pairs),
        json_fields(Atoms, Pairs, Added, After)
    ).

json_fields([], [], Cache, Cache).
json_fields([Atom|Rest], [Key=Term|Pairs], Before, After) :-
    ( is_list(Atom), Atom = [Key, Value]
    -> json_value(Value, Term, Before, Next)
    ;  type_error(json_object_field, Atom) ),
    json_fields(Rest, Pairs, Next, After).

json_array([], [], Cache, Cache).
json_array([Value|Rest], [Term|Terms], Before, After) :-
    json_value(Value, Term, Before, Next),
    json_array(Rest, Terms, Next, After).

%! 'json-at'(+Value:any, +Path:list, -Found:any) is nondet.
%
% Follow object keys and zero-based array indexes. An empty Path returns Value.
% Object keys use get-value's unification and preserve duplicate alternatives.
% Missing keys or indexes have no answers; invalid indexes and scalar traversal raise.
'json-at'(Value, Path, Found) :-
    json_acyclic(Path),
    must_be(list, Path),
    json_path(Path, Value, Found).

json_path([], Value, Value).
json_path([Key|Rest], Value, Found) :-
    (   nonvar(Value), json_space(Value)
    ->  'get-value'(Value, Key, Next)
    ;   is_list(Value)
    ->  must_be(nonneg, Key), nth0(Key, Value, Next)
    ;   type_error(json_container, Value)
    ),
    json_path(Rest, Next, Found).

%! 'json-read!'(+Path:any, -Value:any) is det.
%
% Read one UTF-8 JSON file, closing it before creating object spaces. Malformed
% UTF-8, a BOM, invalid JSON and trailing content raise; no partial value is returned.
'json-read!'(Path, Value) :-
    metta_text(Path, File),
    setup_call_cleanup(open(File, read, Stream, [type(binary)]),
                       read_stream_to_codes(Stream, Bytes), close(Stream)),
    json_utf8(Bytes, Text),
    'json-decode'(Text, Value).

%! 'json-write!'(+Path:any, +Value:any, -Written:boolean) is det.
%
% Atomically replace Path with one compact UTF-8 JSON document. Stage beside
% the destination and publish after close succeeds. A failed conversion, write,
% close or rename preserves an existing destination and removes staging.
'json-write!'(Path, Value, Written) :-
    json_file_write(Path, json_write_document(Value)),
    Written = true.

json_write_document(Value, Stream) :-
    'json-encode'(Value, Text),
    json_unicode(Text),
    write(Stream, Text).

%! 'json-lines-decode'(+Text:any, -Value:any) is nondet.
%
% Enumerate JSON values from LF or CRLF lines. Empty input has no records;
% blank lines and a BOM are errors naming the line. A final newline is optional.
% Returned objects remain caller-owned when enumeration advances or is cut.
'json-lines-decode'(Text, Value) :-
    metta_text(Text, Lines),
    setup_call_cleanup(open_string(Lines, Stream),
                       json_lines(Stream, json_codes, 1, Value), close(Stream)).

%! 'json-lines-encode'(+Values:list, -Text:string) is det.
%
% Encode each value as one compact JSON line, ending every record with LF.
% Empty Values returns the empty String. Validate the complete proper list;
% each record follows json-encode's value and error contracts.
'json-lines-encode'(Values, Text) :-
    json_records(Values),
    with_output_to(string(Text), json_write_lines(Values, current_output)).

%! 'json-lines-read!'(+Path:any, -Value:any) is nondet.
%
% Stream UTF-8 JSON Lines from Path, reading at most one record ahead. Invalid
% bytes, JSON and blank lines raise with their line number. Close on exhaustion,
% cut or error; already returned object spaces remain caller-owned.
'json-lines-read!'(Path, Value) :-
    metta_text(Path, File),
    setup_call_cleanup(open(File, read, Stream, [type(binary)]),
                       json_lines(Stream, json_utf8, 1, Value), close(Stream)).

%! 'json-lines-write!'(+Path:any, +Values:list, -Written:boolean) is det.
%
% Atomically replace Path with UTF-8 JSON Lines, serializing one record at a
% time. Every record ends in LF; empty Values writes an empty file. Publication
% and failure cleanup follow json-write!.
'json-lines-write!'(Path, Values, Written) :-
    json_records(Values),
    json_file_write(Path, json_write_lines(Values)),
    Written = true.

json_records(Values) :- json_acyclic(Values), must_be(list, Values).

json_lines(Stream, Decode, Line, Value) :-
    catch(read_line_to_codes(Stream, Codes), Error, json_line_error(Line, Error)),
    Codes \== end_of_file,
    (   catch(( call(Decode, Codes, Text), 'json-decode'(Text, Value) ),
              Error, json_line_error(Line, Error))
    ;   Next is Line + 1,
        json_lines(Stream, Decode, Next, Value)
    ).

json_codes(Codes, Text) :- string_codes(Text, Codes).

json_line_error(Line, Error) :-
    throw(error(json_line(Line, Error),
                context('json-lines', 'Each line must contain one UTF-8 JSON value'))).

% Keep structured causes while using the same message hook as lib_file and lib_csv.
:- multifile prolog:error_message//1.
prolog:error_message(json_line(Line, Error)) -->
    { message_to_string(Error, Message) },
    ['Could not read JSON Lines record ~d: ~s'-[Line, Message]].
prolog:error_message(json_space_cleanup_failed(Errors)) -->
    ['Could not release JSON object spaces: ~q; the error context retains the construction outcome'
     -[Errors]].
prolog:error_message(json_space_release_failed(Space)) -->
    ['Release of JSON object space ~q failed'-[Space]].

json_write_lines([], _).
json_write_lines([Value|Rest], Stream) :-
    json_write_document(Value, Stream),
    nl(Stream),
    json_write_lines(Rest, Stream).

% Native decoding is permissive. Canonical round-trip rejects replacement and
% overlong sequences; scalar bounds reject surrogates and obsolete code points.
% https://www.rfc-editor.org/rfc/rfc3629#section-3
json_utf8(Bytes, Text) :-
    string_bytes(Text, Bytes, utf8),
    string_bytes(Text, Canonical, utf8),
    ( Bytes == Canonical
    -> json_unicode(Text)
    ;  throw(error(representation_error(utf8), context('json-read!', _))) ).

json_unicode(Text) :-
    string_codes(Text, Codes),
    ( maplist(json_scalar_code, Codes)
    -> true
    ;  throw(error(representation_error(unicode_scalar_value), context(lib_json, _))) ).

json_scalar_code(Code) :- Code =< 0x10ffff, (Code < 0xd800 ; Code > 0xdfff).

% Match lib_file:metta_copy_file/2's close-before-publication protocol.
% [source: lib/lib_file/lib_file.pl:metta_copy_file/2; commit=5e212d77a567d6d6c118529e4a226e5047ec2cfd]
json_file_write(Path, Writer) :-
    metta_text(Path, File),
    file_directory_name(File, Parent),
    tmp_file(metta_json, Temporary),
    file_base_name(Temporary, Base),
    directory_file_path(Parent, Base, Directory),
    setup_call_cleanup(make_directory(Directory),
        ( directory_file_path(Directory, contents, Stage),
          setup_call_cleanup(
              open(Stage, write, Stream, [encoding(utf8), newline(posix), bom(false)]),
              call(Writer, Stream), close(Stream)),
          rename_file(Stage, File) ),
        delete_directory_and_contents(Directory)).
