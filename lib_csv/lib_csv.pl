% Purpose: parse, encode, stream and store lossless UTF-8 CSV records.
% Guarantees: fields remain Strings, duplicate answers survive, widths are
% checked before filtering, and live descriptors own no mutable registry.
% [tested: lib_csv, lib_csv_surface; commit=bd027d8b7a9ef1d96fb4cdb160c9b3eb4157d52e].
% Streaming traversal and append validation retain bounded input storage.
% [measured 2026-09-11: 98808/101568 peak live global bytes at 1000 to 100000 records;
% command=swipl --on-error=status -q -s tests/prolog/lib_csv_stream_bench.pl;
% fixture=20-byte UTF-8 records, SWI-Prolog 10.1.13; commit=bd027d8b7a9ef1d96fb4cdb160c9b3eb4157d52e].
% Owns resources: traversal streams close on exhaustion, cut or exception;
% unreturned snapshots and unpublished staging files are released on failure.
% [tested: lib_csv_surface; commit=bd027d8b7a9ef1d96fb4cdb160c9b3eb4157d52e].
% Guarded by: snapshot allocation uses $metta_native_storage; writers use
% the canonical path mutex and the persistent .metta-csv.lock advisory lock.
% [tested: lib_csv_surface, test_csv_concurrent_process_appends; commit=bd027d8b7a9ef1d96fb4cdb160c9b3eb4157d52e].
% Decides: preserve text, use explicit dialects, distinguish blank records
% from singleton empty fields, and publish complete file replacements.
% [source: lib/lib_csv/lib_csv.pl:csv_config/2, csv_publish/5; commit=bd027d8b7a9ef1d96fb4cdb160c9b3eb4157d52e].

:- module(lib_csv,
          ['csv-space'/2, 'csv-space'/3,
           'csv-snapshot!'/2, 'csv-snapshot!'/3,
           'csv-parse'/2, 'csv-parse'/3,
           'csv-encode'/2, 'csv-encode'/3,
           'csv-read!'/2, 'csv-read!'/3,
           'csv-write!'/3, 'csv-write!'/4,
           'csv-append!'/3, 'csv-append!'/4]).
:- set_module(base(metta_engine)).
:- use_module('support/csv_codec', []).
:- use_module('../_support/owned_resources', [with_outcome_cleanup/3]).
:- use_module('../lib_string/lib_string', [metta_text/2]).
:- use_module(library(error), [must_be/2, domain_error/2]).
:- use_module(library(apply), [maplist/3]).
:- use_module(library(lists), [memberchk/2]).
:- use_module(library(pure_input), [stream_to_lazy_codes/2]).
:- use_module(library(filesex), [directory_file_path/3, delete_directory_and_contents/1]).
:- meta_predicate csv_with_input(+, +, -, 0).

:- multifile seam:foreign_space/1, seam:foreign_capability/2,
             seam:foreign_atoms/2, seam:foreign_refuse/2.

%! 'csv-space'(+Path:any, -Space:'SpaceType') is det.
%! 'csv-space'(+Path:any, +Options:list, -Space:'SpaceType') is det.
%
% Return a live read-only space of (row Field...) atoms. Each query reopens
% the UTF-8 file and preserves order and duplicate rows. Fields are Strings.
% Options are unique (separator String), (quote String), (newline String),
% (width infer|any|Number), and (skip Number) expressions. Defaults are comma,
% double quote, CRLF, inferred width and zero skipped records. An empty quote
% disables quoting. Skipped records still establish and validate width.
% Quote literal option data, for example (quote ((quote ""))). The parameter
% evaluates, so a function may also compute and return the complete options.
'csv-space'(Path, Space) :- 'csv-space'(Path, [], Space).
'csv-space'(Path, Options, Space) :-
    csv_config(Options, Config), csv_path('csv-space', Path, Absolute),
    csv_with_input('csv-space', Absolute, _, true),
    csv_descriptor(Absolute, Config, Space).

%! 'csv-snapshot!'(+Path:any, -Space:'SpaceType') is det.
%! 'csv-snapshot!'(+Path:any, +Options:list, -Space:'SpaceType') is det.
%
% Read once into a fresh mutable space of (row Number Field...) atoms.
% Number is the file's one-based logical record number, including skipped
% headers. Preserve duplicates and Strings. Options are csv-space's. Failed
% reads, writes, cancellation and output matching release the new space.
'csv-snapshot!'(Path, Space) :- 'csv-snapshot!'(Path, [], Space).
'csv-snapshot!'(Path, Options, Space) :-
    csv_config(Options, Config), csv_path('csv-snapshot!', Path, Absolute),
    with_outcome_cleanup(
        Owned = owned(none),
        ( csv_new_snapshot(Owned, New),
          forall(csv_file_rows('csv-snapshot!', Absolute, Config, Number, Fields),
                 csv_store_row(New, [row, Number|Fields])),
          Space = New ),
        csv_release_unreturned(Owned)).

%! 'csv-parse'(+Text:any, -Rows:list) is det.
%! 'csv-parse'(+Text:any, +Options:list, -Rows:list) is det.
%
% Parse text into a list of field lists. Preserve empty fields, duplicates,
% Unicode, whitespace, NUL and quoted newlines. A blank record has zero fields;
% a quoted empty field has one. Options are csv-space's. Malformed records
% raise with their logical number; empty input produces an empty list.
'csv-parse'(Text, Rows) :- 'csv-parse'(Text, [], Rows).
'csv-parse'(Text, Options, Rows) :-
    csv_config(Options, Config), metta_text(Text, String),
    csv_codec:utf8_bytes(String, Bytes), csv_compile(Config, Syntax, Width, Skip),
    findall(Fields, csv_rows('csv-parse', text, Syntax, Width, Skip, Bytes, 1, _, Fields), Rows).

%! 'csv-encode'(+Rows:list, -Text:string) is det.
%! 'csv-encode'(+Rows:list, +Options:list, -Text:string) is det.
%
% Encode field lists as CSV. Every field must be a String. Quote and escape
% fields when needed, including a singleton empty field. Options are
% csv-space's; newline selects CRLF, LF or CR output and skip only affects
% reading. Empty rows encode as blank records. Empty input produces "".
'csv-encode'(Rows, Text) :- 'csv-encode'(Rows, [], Text).
'csv-encode'(Rows, Options, Text) :-
    csv_config(Options, Config), must_be(list, Rows),
    csv_compile(Config, Syntax, Width, _),
    with_output_to(string(Text),
                   csv_write_rows(current_output, 'csv-encode', text, Syntax, Width, Rows, 1)).

%! 'csv-read!'(+Path:any, -Fields:list) is nondet.
%! 'csv-read!'(+Path:any, +Options:list, -Fields:list) is nondet.
%
% Stream one field list per answer from a UTF-8 file, preserving order and
% duplicates. Options are csv-space's. Width checking precedes answer
% filtering. Only consumed records are validated. Exhaustion, cut and
% cancellation close the traversal's independent stream.
'csv-read!'(Path, Fields) :- 'csv-read!'(Path, [], Fields).
'csv-read!'(Path, Options, Fields) :-
    csv_config(Options, Config), csv_path('csv-read!', Path, Absolute),
    csv_file_rows('csv-read!', Absolute, Config, _, Fields).

%! 'csv-write!'(+Path:any, +Rows:list, -Written:boolean) is det.
%! 'csv-write!'(+Path:any, +Rows:list, +Options:list, -Written:boolean) is det.
%
% Atomically replace a UTF-8 CSV file with field lists and return True.
% Options are csv-space's; skip does not discard output. Validate Strings
% and widths, close staging, then publish. Failures before publication preserve
% the destination. A staging-cleanup error reports whether publication occurred.
% Writers coordinate through a persistent sibling .metta-csv.lock file.
'csv-write!'(Path, Rows, Written) :- 'csv-write!'(Path, Rows, [], Written).
'csv-write!'(Path, Rows, Options, true) :- csv_change('csv-write!', Path, Rows, Options, replace).

%! 'csv-append!'(+Path:any, +Rows:list, -Written:boolean) is det.
%! 'csv-append!'(+Path:any, +Rows:list, +Options:list, -Written:boolean) is det.
%
% Append field lists as one atomic file transaction and return True. Create
% a missing file. Validate existing CSV, retain its bytes and width, and add
% a terminator after a valid unterminated last record when needed. Options
% are csv-space's. Cost is linear in old and new bytes; batch related rows.
% A persistent .metta-csv.lock coordinates writers using the same path.
'csv-append!'(Path, Rows, Written) :- 'csv-append!'(Path, Rows, [], Written).
'csv-append!'(Path, Rows, Options, true) :- csv_change('csv-append!', Path, Rows, Options, append).

csv_default(config(",", "\"", "\r\n", infer, 0)).

csv_config(Options, config(Separator, Quote, Newline, Width, Skip)) :-
    must_be(list, Options), csv_options(Options, [], Pairs),
    csv_default(config(DefaultSep, DefaultQuote, DefaultEnd, DefaultWidth, DefaultSkip)),
    csv_option(separator, Pairs, DefaultSep, Separator),
    csv_option(quote, Pairs, DefaultQuote, Quote),
    csv_option(newline, Pairs, DefaultEnd, Newline),
    csv_option(width, Pairs, DefaultWidth, Width),
    csv_option(skip, Pairs, DefaultSkip, Skip),
    csv_character(separator, Separator, false), csv_character(quote, Quote, true),
    ( Separator == Quote -> domain_error(distinct_csv_separator_and_quote, Separator) ; true ),
    must_be(string, Newline),
    ( memberchk(Newline, ["\r\n", "\n", "\r"])
    -> true ; domain_error(csv_newline, Newline) ),
    must_be(ground, Width),
    ( memberchk(Width, [infer, any]) -> true ; must_be(nonneg, Width) ),
    must_be(nonneg, Skip).

csv_options([], Pairs, Pairs).
csv_options([Option|More], Before, Pairs) :-
    ( is_list(Option), Option = [Name, Value], atom(Name),
      memberchk(Name, [separator, quote, newline, width, skip])
    -> true ; domain_error(csv_option, Option) ),
    ( memberchk(Name-_, Before) -> domain_error(duplicate_csv_option, Name) ; true ),
    csv_options(More, [Name-Value|Before], Pairs).

csv_option(Name, Pairs, Default, Value) :-
    ( memberchk(Name-Found, Pairs) -> Value = Found ; Value = Default ).

csv_character(_Name, Text, AllowEmpty) :-
    csv_codec:utf8_bytes(Text, _), string_codes(Text, Codes),
    ( ( AllowEmpty == true, Codes == [] )
    ; Codes = [Code], \+ memberchk(Code, [10,13]) ), !.
csv_character(Name, Text, _) :- domain_error(csv_character(Name), Text).

csv_compile(config(Separator, Quote, Ending, Width0, Skip),
            syntax(SepBytes, QuoteBytes, EndBytes), Width, Skip) :-
    maplist(string_bytes_utf8, [Separator, Quote, Ending], [SepBytes, QuoteBytes, EndBytes]),
    ( Width0 == infer -> true ; Width = Width0 ).
string_bytes_utf8(Text, Bytes) :- string_bytes(Text, Bytes, utf8).

csv_descriptor(Path, Config, Space) :-
    ( csv_default(Config)
    -> atom_concat('&csv:', Path, Space)
    ;  term_string(csv(Path, Config), Payload, [quoted(true), ignore_ops(true)]),
       atom_concat('&csv-v1:', Payload, Space) ).

csv_descriptor_data(Space, Path, Config) :-
    atom(Space),
    ( atom_concat('&csv:', Path, Space)
    -> is_absolute_file_name(Path), csv_default(Config)
    ; atom_concat('&csv-v1:', Payload, Space)
    -> ( catch(csv_decode_descriptor(Payload, Path, Config), error(syntax_error(_), _), fail)
       -> true
       ;  throw(error(csv_invalid_descriptor(Space), context('csv-space', _))) )
    ).

csv_decode_descriptor(Payload, Path, Config) :-
    read_term_from_atom(Payload, Term, [syntax_errors(error), module(lib_csv)]),
    ground(Term), acyclic_term(Term), Term = csv(Path, Config),
    atom(Path), is_absolute_file_name(Path), Config = config(Sep, Quote, End, Width, Skip),
    csv_config([[separator,Sep], [quote,Quote], [newline,End], [width,Width], [skip,Skip]], Config),
    term_string(Term, Canonical, [quoted(true), ignore_ops(true)]), atom_string(Payload, Canonical).

seam:foreign_space(Space) :- csv_descriptor_data(Space, _, _).
seam:foreign_capability(Space, enumerate) :- csv_descriptor_data(Space, _, _).
seam:foreign_refuse(Space, Capability) :-
    csv_descriptor_data(Space, _, _),
    throw(error(csv_read_only(Space, Capability),
                context('csv-space', 'copy rows into (new-space) to edit them; CSV spaces only enumerate'))).
seam:foreign_atoms(Space, [row|Fields]) :-
    csv_descriptor_data(Space, Path, Config), csv_file_rows('csv-space', Path, Config, _, Fields).

csv_file_rows(Caller, Path, Config, Number, Fields) :-
    csv_with_input(Caller, Path, Stream,
                   csv_stream_rows(Caller, Path, Config, Number, Fields, Stream)).

% The cleanup goal holds its arguments. Keep the lazy root inside this
% tail-recursive worker so consumed input can be collected.
% https://github.com/SWI-Prolog/swipl-devel/blob/fc7ef84b949378b729052c3ade79c90ce5416abb/library/pure_input.pl
csv_stream_rows(Caller, Path, Config, Number, Fields, Stream) :-
    csv_compile(Config, Syntax, Width, Skip),
    stream_to_lazy_codes(Stream, Bytes),
    csv_rows(Caller, Path, Syntax, Width, Skip, Bytes, 1, Number, Fields).

csv_rows(Caller, Source, Syntax, Width, Skip, Bytes, Number, Index, Row) :-
    ( Bytes = [] -> fail
    ; csv_record(Caller, Source, Syntax, Width, Number, Bytes, Rest, Fields),
      ( Number > Skip, Index = Number, Row = Fields
      ; Next is Number + 1,
        csv_rows(Caller, Source, Syntax, Width, Skip, Rest, Next, Index, Row) ) ).

csv_record(Caller, Source, Syntax, Width, Number, Bytes, Rest, Fields) :-
    catch(( phrase(csv_codec:record(Fields, Syntax), Bytes, Rest)
          -> csv_width(Width, Fields, Caller, Source, Number)
          ;  csv_malformed(Caller, Source, Number, invalid_quoting) ),
          error(representation_error(Encoding), _),
          csv_malformed(Caller, Source, Number, Encoding)).

csv_width(Width, Fields, Caller, Source, Number) :-
    must_be(list, Fields), length(Fields, Actual),
    ( var(Width) -> Width = Actual
    ; Width == any -> true
    ; Width =:= Actual -> true
    ; csv_malformed(Caller, Source, Number, width(Width, Actual)) ).

csv_write_rows(_, _, _, _, _, [], _).
csv_write_rows(Stream, Caller, Path, Syntax, Width, [Fields|More], Number) :-
    csv_width(Width, Fields, Caller, Path, Number),
    csv_codec:encoded_record(Fields, Syntax, Bytes),
    csv_codec:utf8_text(Bytes, Text), format(Stream, '~s', [Text]),
    Next is Number + 1, csv_write_rows(Stream, Caller, Path, Syntax, Width, More, Next).

csv_path(Caller, Path, Absolute) :-
    must_be(text, Path),
    catch(absolute_file_name(Path, Absolute, [access(none), file_errors(error)]),
          Error, csv_file_error(Caller, Path, Error)).

csv_with_input(Caller, Path, Stream, Goal) :-
    catch(setup_call_cleanup(open(Path, read, Stream, [type(binary)]), Goal, close(Stream)),
          Error, csv_file_error(Caller, Path, Error)).

csv_new_snapshot(Owned, Space) :-
    with_mutex('$metta_native_storage',
        sig_atomic(( csv_available_name(Space), nb_setarg(1, Owned, Space),
                     ensure_native_storage_module(Space, _) ))).

csv_available_name(Space) :-
    flag('$metta_csv_snapshot', Previous, Previous + 1), Next is Previous + 1,
    atom_concat('&csv-snapshot-', Next, Candidate),
    ( metta_space_operand(Candidate) -> csv_available_name(Space) ; Space = Candidate ).

csv_store_row(Space, Row) :-
    ( add_sexp(Space, Row) -> true ; throw(error(csv_snapshot_write_failed(Space), context('csv-snapshot!', _))) ).

csv_release_unreturned(_, exit) :- !.
csv_release_unreturned(Owned, How) :-
    arg(1, Owned, Space),
    ( Space == none -> true
    ; catch(( spaces:metta_release_space(Space)
            -> true ; throw(error(csv_snapshot_release_failed(Space), _)) ), Error, true),
      ( var(Error) -> true
      ; throw(error(csv_snapshot_cleanup_failed(Space, How, Error), context('csv-snapshot!', _))) ) ).

csv_change(Caller, Path, Rows, Options, Mode) :-
    csv_config(Options, Config), must_be(list, Rows), csv_path(Caller, Path, Absolute),
    atom_concat(Absolute, '.metta-csv.lock', Lock),
    catch(with_mutex(Absolute,
              setup_call_cleanup(open(Lock, append, Guard, [type(binary), lock(write)]),
                  csv_publish(Caller, Absolute, Rows, Config, Mode), close(Guard))),
          Error, csv_file_error(Caller, Absolute, Error)).

csv_publish(Caller, Path, Rows, Config, Mode) :-
    file_directory_name(Path, Parent), tmp_file(metta_csv, Temporary),
    file_base_name(Temporary, Base), directory_file_path(Parent, Base, Directory),
    Publication = publication(Directory, false),
    with_outcome_cleanup(make_directory(Directory),
        ( directory_file_path(Directory, contents, Stage),
          csv_compile(Config, Syntax, Width, _),
          setup_call_cleanup(open(Stage, write, Stream,
                                  [encoding(utf8), newline(posix), bom(false)]),
              ( csv_existing(Mode, Caller, Path, Stream, Syntax, Width, Rows, Number),
                csv_write_rows(Stream, Caller, Path, Syntax, Width, Rows, Number) ),
              close(Stream)),
          sig_atomic((rename_file(Stage, Path), nb_setarg(2, Publication, true))) ),
        csv_remove_stage(Publication)).

csv_existing(replace, _, _, _, _, _, _, 1).
csv_existing(append, Caller, Path, Output, Syntax, Width, Rows, Number) :-
    setup_call_cleanup(
        catch(open(Path, read, Input, [type(binary)]),
              error(existence_error(source_sink, _), _), Input = missing),
        ( Input == missing -> Number = 1
        ; csv_validate_stream(Caller, Path, Input, Syntax, Width, Number),
          seek(Input, 0, bof, _),
          set_stream(Output, encoding(octet)), copy_stream_data(Input, Output),
          set_stream(Output, encoding(utf8)),
          csv_append_boundary(Input, Output, Syntax, Rows) ),
        ( Input == missing -> true ; close(Input) )).

csv_validate_stream(Caller, Path, Stream, Syntax, Width, Number) :-
    stream_to_lazy_codes(Stream, Bytes),
    csv_validate(Caller, Path, Syntax, Width, Bytes, 1, Number).

csv_validate(Caller, Path, Syntax, Width, Bytes, Number, NextNumber) :-
    ( Bytes = [] -> NextNumber = Number
    ; csv_record(Caller, Path, Syntax, Width, Number, Bytes, Rest, _),
      Next is Number + 1, csv_validate(Caller, Path, Syntax, Width, Rest, Next, NextNumber) ).

csv_append_boundary(_, _, _, []) :- !.
csv_append_boundary(Input, Output, syntax(_, _, Ending), _) :-
    seek(Input, 0, eof, Size),
    ( Size =:= 0 -> true
    ; seek(Input, -1, eof, _), get_byte(Input, Last),
      ( memberchk(Last, [10,13]) -> true
      ; csv_codec:utf8_text(Ending, Text), format(Output, '~s', [Text]) ) ).

csv_remove_stage(publication(Directory, Published), How) :-
    catch(delete_directory_and_contents(Directory), Error, true),
    ( var(Error) -> true
    ; throw(error(csv_staging_cleanup_failed(Directory, Published, How, Error), context(lib_csv, _))) ).

csv_malformed(Caller, Path, Number, Reason) :-
    throw(error(csv_malformed_row(Path, Number, Reason),
                context(Caller, 'use valid UTF-8, close quoted fields, double embedded quotes and match the declared width'))).

csv_file_error(Caller, Path, error(existence_error(_, _), _)) :- !,
    throw(error(csv_file_missing(Path), context(Caller, 'create the CSV file or correct its path'))).
csv_file_error(Caller, Path, error(permission_error(_, _, _), _)) :- !,
    throw(error(csv_permission_denied(Path), context(Caller, 'grant the required file and directory permissions'))).
csv_file_error(Caller, Path, error(io_error(Action, _), _)) :- !,
    throw(error(csv_io_error(Path, Action), context(Caller, 'check the file and storage device, then retry'))).
csv_file_error(_, _, Error) :- throw(Error).

:- multifile prolog:error_message//1.
prolog:error_message(csv_file_missing(Path)) -->
    ['csv_file_missing: ~w; create the CSV file or correct its path'-[Path]].
prolog:error_message(csv_permission_denied(Path)) -->
    ['csv_permission_denied: ~w; grant the required file and directory permissions'-[Path]].
prolog:error_message(csv_malformed_row(Path, Number, Reason)) -->
    ['csv_malformed_row: ~w record ~d (~w); use valid UTF-8, close quotes and match the declared width'-[Path,Number,Reason]].
prolog:error_message(csv_read_only(Space, Capability)) -->
    ['csv_read_only: ~w refuses ~w; copy rows into (new-space) to edit them'-[Space,Capability]].
prolog:error_message(csv_io_error(Path, Action)) -->
    ['csv_io_error: ~w during ~w; check the file and storage device, then retry'-[Path,Action]].
prolog:error_message(csv_invalid_descriptor(Space)) -->
    ['csv_invalid_descriptor: ~w; construct the live view with csv-space'-[Space]].
prolog:error_message(csv_snapshot_write_failed(Space)) -->
    ['csv_snapshot_write_failed: ~w; the native row store refused a write'-[Space]].
prolog:error_message(csv_snapshot_cleanup_failed(Space, How, Error)) -->
    ['csv_snapshot_cleanup_failed: ~w after ~p; release failed with ~p'-[Space,How,Error]].
prolog:error_message(csv_staging_cleanup_failed(Directory, Published, How, Error)) -->
    ['csv_staging_cleanup_failed: ~w; published=~w after ~p; removal failed with ~p'-[Directory,Published,How,Error]].
