% Purpose: expose UTF-8 CSV records as a read-only foreign MeTTa space.
% Assumes: lib_csv.metta imports this file into the engine's owning module.
% Guarantees: each scan streams records, preserves field text, and refuses
% malformed records with their logical record number and a remedy.
% [tested: lib_csv; commit=504f8dddfa890ced97e795a13ab10e239b1de2ce]
% Owns resources: each scan owns one stream, released on exhaustion, cut, or
% exception by setup_call_cleanup/3; a space descriptor owns no resource.
% [tested: lib_csv:cut_and_error_release_the_stream; commit=504f8dddfa890ced97e795a13ab10e239b1de2ce]
% Guarded by: no mutable registry; each enumeration has independent state.
% Decides: comma separator, UTF-8, quoted fields, literal field text, and
% equal row widths; the first record is data, including a header if present.
% [tested: lib_csv:text_and_quoting, lib_csv:ragged_rows; commit=504f8dddfa890ced97e795a13ab10e239b1de2ce]


:- module(lib_csv,
          [ 'csv-snapshot!'/2,
            'csv-space'/2
          ]).

% Guarantees: private helpers and autoload declarations belong to this module.
% [tested: engine_modules; commit=WORKTREE]
% Assumes: engine operations resolve through metta_engine's published exports.
% [source: engine/metta.pl:metta_engine_reexport/2; commit=WORKTREE]
:- set_module(base(metta_engine)).

:- use_module(library(csv)).
:- use_module(library(error)).

:- multifile seam:foreign_space/1.
:- multifile seam:foreign_capability/2.
:- multifile seam:foreign_atoms/2.
:- multifile seam:foreign_refuse/2.

'csv-space'(Path, Space) :-
    must_be(text, Path),
    catch(absolute_file_name(Path, Absolute, [access(none), file_errors(error)]),
          Error, csv_file_error('csv-space', Path, Error)),
    % Opening checks permissions and rejects directories now. No descriptor
    % survives the validation call, and each later scan reopens the path.
    setup_call_cleanup(csv_open('csv-space', Absolute, Stream), true, close(Stream)),
    atom_concat('&csv:', Absolute, Space).

% The snapshot door. csv-space is a live VIEW: it holds no rows, every query
% reopens and reparses the file, and later queries see later contents. This
% reads the file ONCE into a native space, so repeated queries pay one parse
% between them and the rows do not move underneath a program.
%
% The record NUMBER comes with the snapshot rather than being a second choice.
% A space is unordered, so without it a space of rows can neither say which
% record came first nor skip a header; and a number is only an IDENTITY once
% the rows are fixed, which is exactly what a snapshot fixes. That pairing is
% file-space!'s, whose (line Number Text) atoms are the same shape one level
% down.
%
% csv-space's (row Field...) is left alone. Its shape is a shipped semantics
% with an example, a suite and a reference page reading (row $id $amount) as a
% relation, and a leading number would put a $_ in every one of those queries.
'csv-snapshot!'(Path, Space) :-
    must_be(text, Path),
    catch(absolute_file_name(Path, Absolute, [access(none), file_errors(error)]),
          Error, csv_file_error('csv-snapshot!', Path, Error)),
    csv_options(Options, [convert(false)]),
    setup_call_cleanup(csv_open('csv-snapshot!', Absolute, Stream),
                       csv_snapshot_rows(Stream, Absolute, Options, 1, Rows),
                       close(Stream)),
    'new-space'(Space),
    catch(spaces:metta_add_atoms(Space, Rows), AddError,
          ( spaces:metta_release_space(Space), throw(AddError) )).

% One pass, the same reader csv_atoms/5 pulls with and the same refusals, with
% the record number kept rather than only counted. Reading the whole file with
% csv_read_file/3 would parse it once too, but a malformed record would raise
% without the number that names it.
csv_snapshot_rows(Stream, Path, Options, Number, Rows) :-
    catch(( csv_read_row(Stream, Row, Options)
          -> true
          ;  throw(error(csv_malformed_row(Path, Number, invalid_quoting),
                         context('csv-snapshot!',
                                 'close quoted fields and double embedded quotes'))) ),
          Error, csv_row_error('csv-snapshot!', Path, Number, Error)),
    (   Row == end_of_file
    ->  Rows = []
    ;   Row =.. [row|Fields],
        maplist(atom_string, Fields, Strings),
        Rows = [[row, Number | Strings] | Rest],
        Next is Number + 1,
        csv_snapshot_rows(Stream, Path, Options, Next, Rest)
    ).

csv_owns_space(Space) :-
    atom(Space),
    atom_concat('&csv:', Path, Space),
    is_absolute_file_name(Path).

seam:foreign_space(Space) :- csv_owns_space(Space).
seam:foreign_capability(Space, enumerate) :- csv_owns_space(Space).

seam:foreign_refuse(Space, Capability) :-
    csv_owns_space(Space),
    throw(error(csv_read_only(Space, Capability),
                context('csv-space',
                        'copy rows into (new-space) to edit them; CSV spaces only enumerate'))).

seam:foreign_atoms(Space, Atom) :-
    csv_owns_space(Space),
    atom_concat('&csv:', Path, Space),
    % SWI-Prolog V10.0.0 library(csv), csv_read_row/3 and csv_options/2:
    % https://github.com/SWI-Prolog/swipl-devel/blob/V10.0.0/library/csv.pl
    % One compiled options record retains the first row's width across pulls.
    csv_options(Options, [convert(false)]),
    setup_call_cleanup(csv_open('csv-space', Path, Stream),
                       csv_atoms(Stream, Path, Options, 1, Atom),
                       close(Stream)).

csv_open(Caller, Path, Stream) :-
    catch(open(Path, read, Stream, [encoding(utf8)]),
          Error, csv_file_error(Caller, Path, Error)).

csv_atoms(Stream, Path, Options, Number, Atom) :-
    catch(( csv_read_row(Stream, Row, Options)
          -> true
          ;  throw(error(csv_malformed_row(Path, Number, invalid_quoting),
                         context('csv-space',
                                 'close quoted fields and double embedded quotes'))) ),
          Error, csv_row_error('csv-space', Path, Number, Error)),
    Row \== end_of_file,
    (   Row =.. [row|Fields],
        maplist(atom_string, Fields, Strings),
        Atom = [row|Strings]
    ;   Next is Number + 1,
        csv_atoms(Stream, Path, Options, Next, Atom)
    ).

% Both funnels carry the CALLER, so a refusal names the door the program used.
% Every csv-space call site passes 'csv-space', so its messages are unchanged.
csv_row_error(Caller, Path, Number, error(domain_error(row_arity(Expected), Actual), _)) :-
    !,
    throw(error(csv_malformed_row(Path, Number, width(Expected, Actual)),
                context(Caller,
                        'make every record contain the same number of fields as the first'))).
csv_row_error(Caller, Path, _, Error) :- csv_file_error(Caller, Path, Error).

csv_file_error(Caller, Path, error(existence_error(_, _), _)) :-
    !,
    throw(error(csv_file_missing(Path),
                context(Caller, 'create the CSV file or correct its path'))).
csv_file_error(Caller, Path, error(permission_error(_, _, _), _)) :-
    !,
    throw(error(csv_permission_denied(Path),
                context(Caller, 'grant read permission to a regular CSV file and search permission to its directories'))).
csv_file_error(Caller, Path, error(io_error(Action, _), _)) :-
    !,
    throw(error(csv_io_error(Path, Action),
                context(Caller, 'check the file and storage device, then retry the query'))).
csv_file_error(_, _, Error) :- throw(Error).

:- multifile prolog:error_message//1.
prolog:error_message(csv_file_missing(Path)) -->
    [ 'csv_file_missing: ~w; create the CSV file or correct its path'-[Path] ].
prolog:error_message(csv_permission_denied(Path)) -->
    [ 'csv_permission_denied: ~w; grant file read and directory search permissions'-[Path] ].
prolog:error_message(csv_malformed_row(Path, Number, Reason)) -->
    [ 'csv_malformed_row: ~w record ~d (~w); close quoted fields, double embedded quotes, and use the first record width'-[Path, Number, Reason] ].
prolog:error_message(csv_read_only(Space, Capability)) -->
    [ 'csv_read_only: ~w refuses ~w; copy rows into (new-space) to edit them'-[Space, Capability] ].
prolog:error_message(csv_io_error(Path, Action)) -->
    [ 'csv_io_error: ~w during ~w; check the file and storage device, then retry'-[Path, Action] ].
