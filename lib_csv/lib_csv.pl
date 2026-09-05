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

:- use_module(library(csv)).
:- use_module(library(error)).

:- multifile seam:foreign_space/1.
:- multifile seam:foreign_capability/2.
:- multifile seam:foreign_atoms/2.
:- multifile seam:foreign_refuse/2.

'csv-space'(Path, Space) :-
    must_be(text, Path),
    catch(absolute_file_name(Path, Absolute, [access(none), file_errors(error)]),
          Error, csv_file_error(Path, Error)),
    % Opening checks permissions and rejects directories now. No descriptor
    % survives the validation call, and each later scan reopens the path.
    setup_call_cleanup(csv_open(Absolute, Stream), true, close(Stream)),
    atom_concat('&csv:', Absolute, Space).

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
    setup_call_cleanup(csv_open(Path, Stream),
                       csv_atoms(Stream, Path, Options, 1, Atom),
                       close(Stream)).

csv_open(Path, Stream) :-
    catch(open(Path, read, Stream, [encoding(utf8)]),
          Error, csv_file_error(Path, Error)).

csv_atoms(Stream, Path, Options, Number, Atom) :-
    catch(( csv_read_row(Stream, Row, Options)
          -> true
          ;  throw(error(csv_malformed_row(Path, Number, invalid_quoting),
                         context('csv-space',
                                 'close quoted fields and double embedded quotes'))) ),
          Error, csv_row_error(Path, Number, Error)),
    Row \== end_of_file,
    (   Row =.. [row|Fields],
        maplist(atom_string, Fields, Strings),
        Atom = [row|Strings]
    ;   Next is Number + 1,
        csv_atoms(Stream, Path, Options, Next, Atom)
    ).

csv_row_error(Path, Number, error(domain_error(row_arity(Expected), Actual), _)) :-
    !,
    throw(error(csv_malformed_row(Path, Number, width(Expected, Actual)),
                context('csv-space',
                        'make every record contain the same number of fields as the first'))).
csv_row_error(Path, _, Error) :- csv_file_error(Path, Error).

csv_file_error(Path, error(existence_error(_, _), _)) :-
    !,
    throw(error(csv_file_missing(Path),
                context('csv-space', 'create the CSV file or correct its path'))).
csv_file_error(Path, error(permission_error(_, _, _), _)) :-
    !,
    throw(error(csv_permission_denied(Path),
                context('csv-space', 'grant read permission to a regular CSV file and search permission to its directories'))).
csv_file_error(Path, error(io_error(Action, _), _)) :-
    !,
    throw(error(csv_io_error(Path, Action),
                context('csv-space', 'check the file and storage device, then retry the query'))).
csv_file_error(_, Error) :- throw(Error).

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
