% Purpose: resolve package requirements from catalogs, adjacent files and pins.
% Assumes: included in lib_package; the engine calls package_require/3 before
% selecting the package interpreter [source: metta_perform_package_requires/3;
% commit=WORKTREE].
% Guarantees: import resolution starts no process; only setup may fetch Git.
% [tested: lib_package:offline_git_requires_a_lock; commit=WORKTREE].
% Guarded by: metta_source_singleflight/2 owns source loads; package_catalog
% serializes pin and dependency publication before acquiring another flight.
% Owns resources: pending requirement edges are visible outside transactions
% and removed when their child import settles, including exceptions.

seam:foreign_space('&catalogs').
seam:foreign_capability('&catalogs', match).
seam:foreign_capability('&catalogs', enumerate).
seam:foreign_capability('&catalogs', add).
seam:foreign_capability('&catalogs', remove).
seam:foreign_atoms('&catalogs', Row) :- package_catalog_row(Row).
seam:foreign_match('&catalogs', Row, _) :- package_catalog_row(Row).
seam:foreign_add('&catalogs', Row) :-
    ( Row = [package, Name, Path], atom(Name), (atom(Path);string(Path))
    ; Row = [catalog, Space], nonvar(Space), 'is-space'(Space, true) ), !,
    assertz(package_catalog_entry(Row), Ref), filereader:record_source_assertion(Ref).
seam:foreign_add('&catalogs', Row) :-
    throw(error(type_error(package_catalog_row, Row), none)).
seam:foreign_remove('&catalogs', Row, Result) :-
    ( retract(package_catalog_entry(Row)) -> Result = true ; Result = false ).

package_catalog_row(Row) :- package_catalog_entry(Row).
package_catalog_row([package, Name, Where]) :-
    package_catalog_entry([catalog, Space]),
    metta_host_stored(Space, [package, Name, Where]).

package_catalog_row([package, Name, Where]) :-
    metta_engine:standard_library_path(Base),
    ( nonvar(Name) -> atom(Name)
    ; directory_files(Base, Entries), member(Name, Entries) ),
    \+ memberchk(Name, ['.', '..']),
    directory_file_path(Base, Name, Directory), exists_directory(Directory),
    file_name_extension(Name, metta, File),
    directory_file_path(Directory, File, Source), exists_file(Source),
    absolute_file_name(Source, Where).

package_require(Source, Space, Required) :-
    package_resolve_requirement(Source, Required, Path, Pin),
    filereader:metta_source_load(Source, Space, Load, _),
    Owner = owner(Source, Space, Load),
    setup_call_cleanup(
        with_mutex(package_catalog,
            ( package_check_pin(Source, Pin),
              package_check_cycle(Source, Path),
              ( package_dependency(Owner, Required, Path, Pin) -> true
              ; assertz(package_dependency(Owner, Required, Path, Pin), Ref),
                filereader:record_source_assertion(Ref) ),
              assertz(package_pending_requirement(Source, Path), Flight) )),
        ( package_collect_requirement(Required, Path),
          metta_engine:importer_helper(Space, Path) ),
        erase(Flight)).

package_resolve_requirement(Source, Required, Path, Pin) :-
    ( nonvar(Required), Required = [git, Url0, Rev0]
    -> lib_gitimport:git_atom(Url0, Url),
       lib_gitimport:git_validate_sha('package requires', Rev0, Rev),
       lib_gitimport:git_repository_name(Url, Name),
       Pin = pin(Name, Url, Rev),
       with_mutex(package_catalog, package_check_pin(Source, Pin)),
       package_git_requirement(Source, Url, Rev, Name, Path)
    ; Pin = none,
      ( package_relative_requirement(Required)
      -> file_directory_name(Source, Directory),
         absolute_file_name(Required, Candidate,
                            [relative_to(Directory), access(none)]),
         package_existing_source(Required, Candidate, Path)
      ; atom(Required),
        findall(Where, eval([match, '&catalogs', [package, Required, Where], Where], _), Found),
        Found \== []
      -> with_mutex(package_catalog, package_named_identity(Required, Found, Path))
      ; package_missing_requirement(Required) ) ).

% Catalog names determine identity; path-only requirements have no name claim.
% Equal source digests collapse aliases to the first canonical path. Every
% catalog answer is checked, so an ambiguous second answer cannot hide behind
% once/1. Source withdrawal retires its name claim with the ordinary journal.
package_named_identity(Name, Found, Path) :-
    maplist(package_existing_source(Name), Found, Paths),
    Paths = [First|_], filereader:metta_source_digest(First, Digest),
    forall(member(Candidate, Paths),
           package_same_identity(Name, First, Digest, Candidate)),
    ( package_identity(Name, Existing, Earlier)
    -> package_same_identity(Name, Existing, Earlier, First), Path = Existing
    ; Path = First, assertz(package_identity(Name, First, Digest), Ref),
      filereader:record_source_assertion(Ref) ).

package_same_identity(Name, Existing, Digest, Candidate) :-
    filereader:metta_source_digest(Candidate, Other),
    ( Digest == Other -> true
    ; throw(error(permission_error(resolve, package_identity, Name),
                  context(package, different_sources(Existing, Candidate)))) ).

package_relative_requirement(Required) :-
    ( atom(Required) -> atom_string(Required, Text) ; string(Required), Text = Required ),
    ( sub_string(Text, _, _, _, "/") ; sub_string(Text, _, 6, 0, ".metta") ), !.

package_existing_source(Required, Candidate, Path) :-
    catch(metta_engine:resolve_metta_import_path(Candidate, Path),
          error(existence_error(source_sink, _), _),
          package_missing_requirement(Required)).

package_missing_requirement(Required) :-
    throw(error(existence_error(package_requirement, Required),
                context('package requires',
                        'requirement is absent; run !(setup! (library X)) or add its catalog row'))).

package_check_pin(_, none).
package_check_pin(Source, pin(Name, Url, Rev)) :-
    ( package_pin(Name, OtherRev, OtherUrl, OtherSource),
      (OtherRev \== Rev ; OtherUrl \== Url)
    -> throw(error(domain_error(conflicting_package_pin, Name),
                   context(package, pins(OtherSource-OtherUrl-OtherRev, Source-Url-Rev))))
    ; package_pin(Name, Rev, Url, Source) -> true
    ; assertz(package_pin(Name, Rev, Url, Source), Ref),
      filereader:record_source_assertion(Ref) ).

% Check the dependency graph before entering another source flight. This also
% detects a cycle split between two threads, which a thread-local stack misses.
% O((v+e) log v) reachable nodes/edges with a shared assoc visited set.
% Every node expands once, including when a diamond reaches it by two paths.
package_check_cycle(Source, Path) :-
    empty_assoc(Seen),
    ( package_dependency_route([Path-[Path]], Source, Seen, Reverse)
    -> reverse(Reverse, Route),
       throw(error(permission_error(load, package_cycle, [Source|Route]),
                   context(package, 'move the shared definitions into a third library')))
    ; true ).

package_dependency_route([Path-Route|_], Path, _, Route) :- !.
package_dependency_route([Path-Route|Pending], Target, Seen, Found) :-
    ( get_assoc(Path, Seen, _) -> Next = Seen, Work = Pending
    ; put_assoc(Path, Seen, true, Next),
      findall(Child-[Child|Route],
              (package_dependency(owner(Path, _, _), _, Child, _)
              ;package_pending_requirement(Path, Child)), Children),
      append(Children, Pending, Work) ),
    package_dependency_route(Work, Target, Next, Found).

package_git_requirement(Source, Url, Rev, Name, Path) :-
    ( package_mode(setup)
    -> package_setup_root(Source, Root), file_directory_name(Root, Directory),
       directory_file_path(Directory, repos, Base),
       lib_gitimport:'git-import!'(Url, '', Base, Rev, _),
       lib_gitimport:git_library_path(Name, Checkout),
       directory_file_path(Checkout, Name, Stem),
       package_existing_source([git, Url, Rev], Stem, Path)
    ; package_locked_requirement(Source, [git, Url, Rev], Locked)
    -> package_existing_source([git, Url, Rev], Locked, Path)
    ; lib_gitimport:git_pinned_dependency(Url, Rev),
      lib_gitimport:git_library_path(Name, Checkout)
    -> directory_file_path(Checkout, Name, Stem),
       package_existing_source([git, Url, Rev], Stem, Path)
    ; package_missing_requirement([git, Url, Rev]) ).

package_setup_root(Default, Root) :-
    ( package_stack(Stack), Stack \== [] -> last(Stack, Root) ; Root = Default ).

package_locked_requirement(Source, Required, Path) :-
    package_setup_root(Source, Root), file_directory_name(Root, Directory),
    directory_file_path(Directory, 'lock.metta', File), exists_file(File),
    package_read_rows(File, Rows),
    member([requires, Stored, Path], Rows),
    Stored = [git, Url0, Rev0], Required = [git, Url, Rev],
    lib_gitimport:git_atom(Url0, Url), lib_gitimport:git_atom(Rev0, Rev).

package_collect_requirement(Required, Path) :-
    ( package_setup_state(State)
    -> arg(1, State, Rows), Row = [requires, Required, Path],
       ( memberchk(Row, Rows) -> true ; nb_setarg(1, State, [Row|Rows]) )
    ; true ).

package_resolve_source(Spec, Path) :-
    ( nonvar(Spec), Spec = [library|_]
    -> metta_engine:resolve_module_form(Spec, File)
    ; Spec = File ),
    package_existing_source(Spec, File, Path).
