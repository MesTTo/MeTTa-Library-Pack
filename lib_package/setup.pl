% Purpose: prepare package graphs explicitly and persist successful results.
% Guarantees: row equality and artifact existence decide reuse; publication
% occurs only after every setup succeeds [tested: lib_package; commit=WORKTREE].
% Owns resources: temporary metadata spaces, OS lock streams and staged files
% close on all outcomes. Persistent receipts and lock files survive unimport.
% Guarded by: a mutex per canonical directory and a permanent .package.lock
% inode. The staged receipt never replaces the inode peers synchronize on.
% [source: lib/lib_csv/lib_csv.pl:csv_change/5; commit=WORKTREE].

'setup!'(Spec, true) :-
    package_resolve_source(Spec, Path), package_register_claims,
    State = setup([]),
    metta_with_trailed('$metta_package_mode', setup,
        metta_with_trailed('$metta_package_setup', State,
            ( package_setup_path(Path), arg(1, State, Reverse),
              reverse(Reverse, LockRows), file_directory_name(Path, Directory),
              package_with_directory_lock(Directory,
                  package_publish_rows(Directory, 'lock.metta', LockRows)) ))).

package_setup_path(Path) :-
    'new-space'(Space),
    setup_call_cleanup(true,
        metta_engine:importer_helper(Space, Path),
        metta_release_space(Space)).

package_prepare(Path, Space, Rows) :-
    findall(Row,
        ( member(setup-Written, Rows),
          metta_engine:metta_package_normalise(Space, Written, Row),
          package_validate_boot(Space, Row) ), Setup),
    file_directory_name(Path, Directory),
    package_with_directory_lock(Directory,
        package_prepare_locked(Path, Space, Rows, Directory, Setup)).

:- meta_predicate package_with_directory_lock(+, 0).
package_with_directory_lock(Directory, Goal) :-
    directory_file_path(Directory, '.package.lock', Lock),
    % SWI open/4 uses blocking fcntl locks. The mutex covers sibling threads,
    % which POSIX process locks alone do not exclude.
    % https://www.swi-prolog.org/pldoc/man?predicate=open%2F4
    with_mutex(Directory,
        setup_call_cleanup(open(Lock, append, Guard, [type(binary), lock(write)]),
                           Goal, close(Guard))).

package_prepare_locked(Path, Space, Rows, Directory, Setup) :-
    directory_file_path(Directory, 'performed.metta', Receipt),
    ( package_setup_current(Path, Space, Rows, Receipt, Setup, Performed)
    -> debug(packages, 'reuse setup for ~q because rows and outputs are current', [Path])
    ; debug(packages, 'run setup for ~q because receipt, rows or outputs changed', [Path]),
      maplist(package_setup_perform(Space), Setup, Groups), append(Groups, Performed),
      package_setup_artifacts(Path, Space, Rows),
      package_publish_receipt(Directory, Setup, Performed) ),
    forall(member(Row, Performed), metta_add_atom(Space, Row, _)).

package_setup_current(Path, Space, Rows, Receipt, Setup, Performed) :-
    exists_file(Receipt), variant_sha1(Setup, Digest),
    setup_call_cleanup(open(Receipt, read, Input, [encoding(utf8)]),
                       read_line_to_string(Input, Header), close(Input)),
    format(string(Header), '; package-setup ~w', [Digest]),
    package_read_rows(Receipt, Performed),
    maplist(package_performed_row, Performed, Written),
    package_receipt_sequence(Setup, Written),
    catch(package_setup_artifacts(Path, Space, Rows),
          error(existence_error(source_sink, _), _), fail).

package_performed_row([performed, Row, _], Row).

% The digest preserves source multiplicity. Equal adjacent rows form one run:
% every occurrence requires at least one result, with linear comparison cost.
package_receipt_sequence([], []).
package_receipt_sequence([Row|Rows], [Written|Rest]) :-
    Row =@= Written,
    package_receipt_run(Row, Rows, Need, Later),
    package_receipt_run(Row, Rest, Have, Next), Have >= Need,
    package_receipt_sequence(Later, Next).

package_receipt_run(Row, [Written|Rows], Count, Rest) :-
    Row =@= Written, !,
    package_receipt_run(Row, Rows, N, Rest), Count is N + 1.
package_receipt_run(_, Rows, 0, Rows).

package_setup_artifacts(Path, Space, Rows) :-
    findall(backing-Row,
            (member(backing-Written, Rows),
             metta_engine:metta_package_normalise(Space, Written, Row)), Backings),
    package_backings(Path, Space, Backings, _).

package_setup_perform(Space, Row, Receipts) :-
    findall([performed, Row, Answer],
        ( metta_engine:metta_package_perform(Space, [perform, Row], Answer),
          package_answer([perform, Row], Answer) ), Receipts),
    ( Receipts == []
    -> throw(error(existence_error(package_result, Row),
                   context('setup!', 'the claimant returned no answer')))
    ; true ).

package_read_rows(File, Rows) :-
    read_file_to_string(File, Text, [encoding(utf8)]), parse_metta_source(Text, Forms),
    maplist(package_record_form(File), Forms, Rows).

package_record_form(File, Parsed, Row) :-
    parsed_form_parts(Parsed, Kind, _, Row),
    ( Kind == expression -> true
    ; throw(error(domain_error(package_record, Row),
                  context(package, File))) ).

% Reuse lib_file's same-filesystem staged publication. It owns and removes the
% stage even when the writer or rename fails; the receipt remains unchanged.
package_publish_rows(Directory, Name, Rows) :-
    metta_engine:library('lib_file.pl', Library), use_module(Library, []),
    directory_file_path(Directory, Name, File),
    lib_file:metta_staged_publish(File, lib_package:package_write_rows(Rows)).

package_publish_receipt(Directory, Setup, Rows) :-
    metta_engine:library('lib_file.pl', Library), use_module(Library, []),
    directory_file_path(Directory, 'performed.metta', File), variant_sha1(Setup, Digest),
    lib_file:metta_staged_publish(File, lib_package:package_write_receipt(Digest, Rows)).

package_write_receipt(Digest, Rows, File) :-
    setup_call_cleanup(open(File, write, Stream, [encoding(utf8)]),
        ( format(Stream, '; package-setup ~w~n', [Digest]),
          package_write_stream(Rows, Stream) ), close(Stream)).

package_write_rows(Rows, File) :-
    setup_call_cleanup(open(File, write, Stream, [encoding(utf8)]),
        package_write_stream(Rows, Stream), close(Stream)).

package_write_stream(Rows, Stream) :-
    forall(member(Row, Rows), (swrite(Row, Text), format(Stream, '~s~n', [Text]))).
