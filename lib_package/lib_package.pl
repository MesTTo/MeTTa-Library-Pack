% Purpose: interpret package argument records, prepare them explicitly, and own
% their activation and retirement through the existing source loader.
% Assumes: the engine sequences requires first and bounds normalisation.
% [source: engine/metta/interop.pl:metta_perform_package_rows/2; commit=561cfeaa23b27fc84f86a9bcccf6ccf8b9d2e73f].
% Guarantees: local boot validation precedes effects; receipts belong to the
% source; setup publishes only successful work under a directory lock.
% [tested: lib_package; commit=561cfeaa23b27fc84f86a9bcccf6ccf8b9d2e73f].
% Guarantees: asking whether a head is already loaded never DEFINES it, so
% performing a backing row cannot re-enter the translation of a name that
% row is registering.
% [tested: lib_package:a_backing_row_registers_before_the_equations_calling_it_translate;
% commit=49be31cf5e016a873b058fd8b278bdd5408a9d23].
% Owns resources: package_acquired/5 records live answers until reverse release
% on withdrawal, replacement, failed activation, space release or process exit.
% Artifact streams, metadata spaces, directory locks and staged files close on
% all outcomes. Persistent receipts and lock files survive source withdrawal.
% Guarded by: source single-flight protects loads; package_claims protects seam
% installation; the directory mutex and OS write lock protect setup publication.
% Decides: package-load equations supplied by requirements replace this default;
% source order chooses a backing when several claimed rows cover the same head.
% Open Obligations: Python manifest.py has not adopted the bootable-door protocol.
% Generic native shadow restoration and shared-source retirement remain open;
% docs/record/lib-package-laws-6-13.md records their executable counterexamples.

:- module(lib_package, ['setup!'/2, 'get-property'/3, 'package-prolog'/3]).
:- set_module(base(metta_engine)).
:- use_module(library(error)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(filesex)).
:- use_module(library(prolog_wrap)).
:- use_module(library(debug), [debug/3]).
:- use_module(library(assoc), [empty_assoc/1, get_assoc/3, put_assoc/4]).
:- use_module(library(readutil), [read_file_to_string/3, read_line_to_string/2]).
:- use_module('../_support/owned_resources', [with_outcome_cleanup/3]).

:- multifile seam:extension_builtin/2, seam:builtin_type_declaration/2,
             seam:foreign_space/1, seam:foreign_capability/2,
             seam:foreign_atoms/2, seam:foreign_match/3, seam:space_released/1,
             seam:foreign_add/2, seam:foreign_remove/3.
seam:extension_builtin('setup!', oracleIO).
seam:extension_builtin('package-prolog', oracleIO).
% Extend the existing arity family without redeclaring its one-input facet.
:- multifile metta_engine:builtin_implementation/2.
metta_engine:builtin_implementation('get-property'/2, prolog(lib_package)).
seam:builtin_type_declaration('setup!', [->, 'Atom', 'Bool']).
seam:builtin_type_declaration('get-property', [->, 'Atom', 'Atom', '%Undefined%']).
seam:builtin_type_declaration('package-prolog', [->, 'Atom', 'Atom', 'Bool']).

:- dynamic package_hooks_ready/0,
           package_acquired/5, package_dependency/4, package_pin/4,
           package_catalog_entry/1, package_identity/3, package_pending_requirement/2.
:- volatile package_hooks_ready/0, package_acquired/5.
% Handles are external effects: a Prolog transaction must not resurrect a
% released handle or discard the only cleanup record for an acquired one.
:- '$notransact'(package_acquired/5).
:- '$notransact'(package_pending_requirement/2).
:- meta_predicate package_context(+, +, 0), package_loading(+, +, 0).
:- seam:context_reader(package_mode(Mode), '$metta_package_mode', value(Mode)).
:- seam:context_reader(package_setup_state(State), '$metta_package_setup', value(State)).
:- seam:context_reader(package_stack(Stack), '$metta_package_stack', value(Stack)).

% No per-atom work occurs here. A source without package rows pays two indexed
% load lookups and the deterministic cleanup scope, independently of its size.
package_loading(Path, Space, Goal) :-
    findall(Load, filereader:metta_source_load(Path, Space, Load, _), Before),
    with_outcome_cleanup(true, once(Goal),
                         package_loading_finish(Path, Space, Before)).

package_loading_finish(Path, Space, Before, Outcome) :-
    findall(Load, filereader:metta_source_load(Path, Space, Load, _), After),
    ( Outcome == exit
    -> subtract(Before, After, Retired), package_release_loads(Retired, Outcome)
    ; findall(L, (package_acquired(L, Path, Space, _, _), \+ memberchk(L, Before)), All),
      sort(All, New),
      setup_call_cleanup(true, package_release_loads(New, Outcome),
          forall((member(L, After), \+ memberchk(L, Before)),
                 filereader:withdraw_source_load(Path, Space, _))) ).

package_context(Path, Space, Goal) :-
    filereader:metta_source_load(Path, Space, Load, _),
    file_directory_name(Path, Directory), space_module(Space, Module),
    ( package_stack(Stack) -> true ; Stack = [] ),
    metta_with_trailed('$metta_package_stack', [Path|Stack],
        filereader:with_owning_source_load(Load,
            filereader:with_working_directory(Directory,
                metta_engine:with_metta_module(Module, Goal)))).

package_load(Path, Space, Rows) :-
    package_install_hooks,
    space_module(Space, Module),
    ( metta_engine:metta_host_function_callable_from(Module, 'package-load')
    -> maplist(package_argument_row, Rows, Arguments),
       Call = ['package-load', [quote, Path], [quote, Space], [quote, Arguments]],
       findall(Result, evalc(Call, Space, Result), Results),
       ( Results == [] -> throw(error(existence_error(package_result, Call), none))
       ; forall(member(Result, Results), package_answer(Call, Result)) )
    ; package_default(Path, Space, Rows) ).

package_argument_row(Kind-Value, [Kind, Value]).

package_default(Path, Space, Rows) :-
    package_versions(Rows),
    package_register_claims,
    ( package_mode(setup)
    -> package_prepare(Path, Space, Rows)
    ; package_normal_rows(Space, Rows, Normal),
      package_boot_admission(Path, Space, Normal),
      package_backings(Path, Space, Normal, Selected),
      package_validate_boots(Space, Normal),
      package_perform_rows(Path, Space, Normal, Selected) ).

package_versions(Rows) :-
    forall(member(version-Version, Rows),
           ( atomic(Version) -> true
           ; throw(error(domain_error(package_constant_version, Version),
                         context(package, 'version must be a literal'))) )).

package_normal_rows(Space, Rows, Normal) :-
    findall(Kind-Row,
        ( member(Kind-Written, Rows),
          package_operation(Kind),
          metta_engine:metta_package_normalise(Space, Written, Row) ), Normal).

package_operation(backing).
package_operation(boot).
package_operation(setup).

package_boot_admission(Path, Space, Rows) :-
    ( memberchk(boot-_, Rows),
      metta_engine:metta_reference_option(Space, load, Policy), Policy \== eager
    -> throw(error(permission_error(Policy, package_boot, Path),
                   context(package, 'boot rows require eager loading')))
    ; true ).

% Three traversals of the package's rows, never the load's other atoms:
% inspect candidates, choose each head's first claimant, then prove coverage.
% Head membership uses an assoc, giving O(h log h) for h named backing heads.
package_backings(Path, Space, Rows, Selected) :-
    findall(Row, member(backing-Row, Rows), Backings),
    maplist(package_backing_info(Path, Space), Backings, Infos),
    empty_assoc(Empty),
    package_choose(Infos, Empty, Covered, Selected),
    forall(member(selected(_, Chosen, Known), Selected),
           package_check_selection(Path, Space, Chosen, Known)),
    forall(member(info(Row, unclaimed, Names, _), Infos),
           package_coverage(Path, Space, Row, Names, Covered)).

package_backing_info(Path, Space, Row, info(Row, Claimed, Names, Contracts)) :-
    ( nonvar(Row), Row = [Token, _, Pattern], atom(Token)
    -> true
    ; throw(error(domain_error(package_backing, Row),
                  context(package, 'an unreduced backing must name token, artifact and heads'))) ),
    ( package_claim(perform, Row, _)
    -> Claimed = claimed,
       ( is_list(Pattern), maplist(atom, Pattern)
       -> Names = Pattern, Contracts = unread
       ; copy_term(Row, Copy), Copy = [_, _, CopyPattern],
         package_contract(Path, Space, Copy, CopyPattern, Names, Contracts) )
    ; Claimed = unclaimed, Contracts = [],
      ( is_list(Pattern), maplist(atom, Pattern) -> Names = Pattern
      ; throw(error(existence_error(package_claim, Row),
                    context(package, 'unclaimed backing has no readable head signature'))) ) ).

package_check_selection(Path, Space, Row, Known) :-
    Row = [_, _, Pattern],
    ( Known == unread
    -> package_contract(Path, Space, Row, Pattern, Names, Contracts)
    ; Names = Pattern, Contracts = Known ),
    package_native_admission(Path, Space, Row, Names, Contracts),
    package_validate_backing(Path, Space, Row, Names, Contracts).

package_choose([], Covered, Covered, []).
package_choose([info(Row, Claim, Names, Contracts)|Infos], Seen, Covered, Selected) :-
    ( Claim == claimed
    -> partition(package_head_seen(Seen), Names, Used, Fresh),
       foldl(package_cover_head(Row), Fresh, Seen, Next),
       ( ( Names == [] ; Fresh \== [] )
       -> Row = [Token, Artifact, _],
          Chosen = [Token, Artifact, Fresh],
          Selected = [selected([Token, Artifact, Used], Chosen, Contracts)|Rest]
       ; Next = Seen, Selected = [available(Row)|Rest] )
    ; Next = Seen, Selected = [available(Row)|Rest] ),
    package_choose(Infos, Next, Covered, Rest).

package_head_seen(Seen, Name) :- get_assoc(Name, Seen, _).
package_cover_head(Row, Name, Seen, Next) :- put_assoc(Name, Seen, Row, Next).

package_coverage(Path, Space, Row, Names, Covered) :-
    findall(Name,
        ( member(Name, Names), \+ get_assoc(Name, Covered, _),
          \+ package_source_equation(Path, Space, Name, _) ), Missing),
    ( Missing == [] -> true
    ; findall(Pattern, package_claim(perform, Pattern, _), Claims),
      throw(error(existence_error(package_backing, Missing),
                  context(package, unclaimed(Row, available_claims(Claims))))) ).

package_source_equation(Path, Space, Name, Inputs) :-
    filereader:metta_source_load(Path, Space, Load, _),
    spaces:metta_native_pair(Space, ['=', [Name|Args], _], _, Ref),
    filereader:source_load_assertion(Load, stored, Ref),
    length(Args, Inputs).

package_source_type(Path, Space, Name, Type) :-
    filereader:metta_source_load(Path, Space, Load, _),
    spaces:metta_native_pair(Space, [':', Name, Type], _, Ref),
    filereader:source_load_assertion(Load, stored, Ref).

package_validate_backing(Path, Space, Row, Names, Contracts) :-
    Row = [Token|_],
    forall(member(Name, Names),
        ( metta_engine:refuse_other_tiers_name(Name, Token),
          forall(member(contract(Name, Arity, Type), Contracts),
                 package_validate_head(Path, Space, Row, Name, Arity, Type)),
          findall(Arrow, member(contract(Name, _, Arrow), Contracts), Arrows),
          forall(package_source_type(Path, Space, Name, Declared),
                 ( metta_engine:declared_predicate_arity(Declared, DeclaredArity),
                   Inputs is DeclaredArity - 1,
                   ( package_source_equation(Path, Space, Name, Inputs) -> true
                   ; package_agree_type(Name, Declared, Arrows) ) )) )).

package_validate_head(Path, Space, Row, Name, Arity, _) :-
    Inputs is Arity - 1,
    ( package_source_equation(Path, Space, Name, Inputs)
    -> throw(error(permission_error(register, package_tier_collision, Name/Inputs),
                   context(package, Path)))
    ; true ),
    package_open_head(Path, Space, Row, Name, Arity).

package_agree_type(Name, Declared, Artifacts) :-
    ( metta_engine:metta_arrow_type_chain(Declared, Left),
      member(Artifact, Artifacts),
      metta_engine:metta_arrow_type_chain(Artifact, Right),
      same_length(Left, Right), maplist(package_type_agrees, Left, Right)
    -> true
    ; throw(error(type_error(package_backing_arrow(Name, Artifacts), Declared),
                  context(package, 'declaration disagrees with the artifact contract'))) ).

package_type_agrees(A, B) :-
    ( A == '%Undefined%' ; B == '%Undefined%' ; unifiable(A, B, _) ), !.

package_validate_boots(Space, Rows) :-
    forall(member(boot-Row, Rows), package_validate_boot(Space, Row)).

package_validate_boot(Space, Row) :-
    ( package_claim(perform, Row, _) -> true
    ; throw(error(existence_error(package_claim, Row),
                  context(package, 'no perform equation claims this boot row'))) ),
    Row = [Token|Arguments],
    findall(Type,
            % policy-inventory-exempt: mechanism-internal; reason=the two places a boot row's declaration can be written, the file's own space and the seam where claims live; evidence=lib/lib_package/lib_package.pl:package_validate_boot/2
            ( member(Home, [Space, '&metta']),
              metta_host_stored(Home, [':', Token, Type]) ), Types),
    ( Types == [] -> true
    ; member(Type, Types), metta_engine:metta_arrow_type_chain(Type, Chain),
      append(Expected, [_], Chain), same_length(Arguments, Expected),
      space_module(Space, Module),
      metta_engine:with_metta_module(Module,
          lib_package:maplist(package_argument_type, Arguments, Expected))
    -> true
    ; throw(error(type_error(package_boot_signature(Token, Types), Row),
                  context(package, 'all boot rows are checked before any performs'))) ).

% policy-inventory-exempt: mechanism-internal; reason=the two declarations that accept any argument, so a boot row carrying one is checked no further; evidence=engine/metta/prelude.pl:prelude_declaration/2
package_argument_type(_, Type) :- memberchk(Type, ['Atom', '%Undefined%']), !.
package_argument_type(Value, Type) :- metta_engine:has_type(Value, Type).

package_perform_rows(_, _, [], _).
package_perform_rows(Path, Space, [Kind-Row|Rows], Selected) :-
    ( Kind == boot -> package_perform(Path, Space, boot, Row), Next = Selected
    ; Kind == backing
    -> Selected = [Selection|Next],
       ( Selection = selected(Alternative, Chosen, _)
       -> package_perform(Path, Space, backing, Chosen),
          ( Alternative = [_, _, []] -> true
          ; metta_add_atom(Space, [available, Alternative], _) )
       ; metta_add_atom(Space, [available, Row], _) )
    ; Next = Selected ),
    package_perform_rows(Path, Space, Rows, Next).

package_perform(Path, Space, Kind, Row) :-
    filereader:metta_source_load(Path, Space, Load, _),
    debug(packages, 'perform ~q in ~q because its claim and contracts passed', [Row, Space]),
    package_perform_row(Path, Space, Row, CallRow),
    State = answers(0),
    forall(metta_engine:metta_package_perform(Space, [perform, CallRow], Answer),
           ( package_answer([perform, CallRow], Answer),
             arg(1, State, N), Next is N+1, nb_setarg(1, State, Next),
             assertz(package_acquired(Load, Path, Space, Row, Answer)),
             metta_add_atom(Space, [performed, Row, Answer], _),
             package_merge_answer(Kind-Row, Space, Answer) )),
    ( arg(1, State, 0)
    -> throw(error(existence_error(package_result, Row),
                   context(package, 'the claimant returned no answer')))
    ; ( Kind == backing -> package_installed_heads(Space, Row) ; true ) ).

package_answer(Call, Answer) :-
    ( Answer =@= Call
    -> throw(error(existence_error(package_claim, Call), none))
    ; nonvar(Answer), Answer = ['Error'|_]
    -> throw(error(package_perform_failed(Call, Answer), none))
    ; true ).

package_merge_answer(backing-Row, Space, Answer) :-
    nonvar(Answer), metta_engine:metta_space_name(Answer),
    'is-space'(Answer, true), Answer \== Space, !,
    Row = [_, _, Names],
    ( Names == [] -> From = [from, Answer]
    ; From = [from, Answer, [only, Names]] ),
    metta_add_atom(Space, From, _).
package_merge_answer(_, _, _).

package_installed_heads(Space, [_, _, Names]) :-
    space_module(Space, Module),
    forall(member(Name, Names),
           ( metta_engine:metta_host_function_callable_from(Module, Name) -> true
           ; throw(error(existence_error(package_export, Name),
                         context(package, 'the selected claimant did not install this head'))) )).

% Reading a claim does not execute its body or bind the caller's row. Dispatch
% itself is the engine's ordinary unification in the seam execution module.
package_claim(Head, Row, Body) :-
    metta_host_stored('&metta', ['=', [Head, Pattern], Body]),
    ( var(Row) -> Row = Pattern ; unifiable(Pattern, Row, _) ).

package_release_claim(Row, Handle) :-
    metta_host_stored('&metta', ['=', [release, Pattern, Result], _]),
    unifiable(Pattern-Result, Row-Handle, _), !.

% Source rollback and seam withdrawal can remove equations. Derive readiness
% from the claim itself, and never charge the bootstrap to an importing source.
% [tested: lib_package:default_claim_recovers_after_withdrawal_and_failed_activation; commit=561cfeaa23b27fc84f86a9bcccf6ccf8b9d2e73f].
package_register_claims :-
    ( package_default_claim -> true
    ; with_mutex(package_claims,
        ( package_default_claim -> true
        ; filereader:with_owning_source_load(none, lib_package:
            ( forall(metta_engine:metta_loader_source(Text),
                     filereader:process_loader_string(Text, _, '&metta')),
              forall(package_loader_source(Text),
                     filereader:process_loader_string(Text, _, '&metta')) )) )) ),
    package_install_hooks.

package_default_claim :-
    metta_host_stored('&metta', ['=', [perform, Pattern], Body]),
    Pattern-Body =@= [prolog, File, Names]-['package-prolog', File, Names], !.

package_loader_source("(: release (-> Atom Atom %Undefined%))").
package_loader_source("(: package-contract (-> Atom %Undefined%))").
package_loader_source("(= (perform (prolog $file $names)) (package-prolog $file $names))").

package_install_hooks :-
    ( package_hooks_ready -> true
    ; with_mutex(package_claims,
        ( package_hooks_ready -> true
        ; wrap_predicate(metta_engine:metta_unimport(Space, Path), package_lifetime,
                         Wrapped, lib_package:package_unimport(Space, Path, Wrapped)),
          wrap_predicate(metta_engine:metta_reference_check_manifest(Home, File, Forms, Seen0, Seen),
                         package_admission, Manifest,
                         lib_package:package_manifest(Home, File, Forms, Seen0, Seen, Manifest)),
          at_halt(lib_package:package_close_all),
          assertz(package_hooks_ready) )) ).

:- meta_predicate package_manifest(+, +, +, +, -, 0).
package_manifest(_, Path, Forms, _, _, Goal) :-
    ( member(Parsed, Forms), parsed_form_parts(Parsed, _, _, Row),
      filereader:package_row(Row, boot, _)
    -> throw(error(permission_error(non_eager, package_boot, Path),
                   context(package, 'boot rows require eager loading')))
    ; call(Goal) ).

:- meta_predicate package_unimport(+, +, 0).
package_unimport(Space, Path, Goal) :-
    metta_engine:resolve_space_form(Space, Home),
    metta_engine:resolve_module_form(Path, File),
    metta_engine:resolve_unimport_path(Home, File, Canonical),
    findall(Load, filereader:metta_source_load(Canonical, Home, Load, _), Loads),
    call(Goal), package_release_loads(Loads, exit).

seam:space_released(Space) :-
    findall(Load, package_acquired(Load, _, Space, _, _), All), sort(All, Loads),
    package_release_loads(Loads, exit).

package_close_all :-
    findall(Load, package_acquired(Load, _, _, _, _), All), sort(All, Loads),
    package_release_loads(Loads, exit).

% O(h*l), h = live answers, l = retiring loads. Release order is the reverse
% of acquisition, including across sources. Every release is attempted.
package_release_loads(Loads, Outcome) :-
    findall(held(Space, Row, Handle),
        ( package_acquired(Load, _, Space, Row, Handle), memberchk(Load, Loads) ), Held),
    forall(member(Load, Loads), retractall(package_acquired(Load, _, _, _, _))),
    reverse(Held, Reverse), maplist(package_release_one, Reverse, Results),
    exclude(==(ok), Results, Errors),
    ( Errors == [] -> true
    ; throw(error(package_release_errors(Outcome, Errors), none)) ).

package_release_one(held(Space, Row, Handle), Outcome) :-
    catch(( package_release_claim(Row, Handle)
          -> ( once(metta_engine:metta_package_perform(Space, [release, Row, Handle], Result))
             -> package_answer([release, Row, Handle], Result), Outcome = ok
             ; Outcome = failed(Row, Handle) )
          ; Outcome = ok ), Error, Outcome = raised(Row, Handle, Error)).

'get-property'(perform, claims, Pattern) :-
    package_register_claims, package_claim(perform, Pattern, _).
'get-property'(Subject, Key, Value) :-
    Subject \== perform,
    ( metta_engine:metta_space_name(Subject) -> Home = Subject
    ; package_resolve_source(Subject, Path),
      metta_engine:metta_reference_library_home(Home, Path) ),
    ( Key == available -> metta_host_stored(Home, [available, Value])
    ; metta_host_stored(Home, ['=', [package, Key], Value]) ).

% Requirement resolution and the catalog.

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
    % policy-inventory-exempt: mechanism-internal; reason=POSIX's own two directory entries, which directory_files/2 always returns and no operator chooses; evidence=lib/lib_package/lib_package.pl:package_catalog_row/1
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

% Native artifact contracts and selected publication.

package_perform_row(Path, Space, [prolog, Locator, Names], [prolog, File, Names]) :- !,
    package_native_path(Path, Space, Locator, File).
package_perform_row(_, _, Row, Row).

% The file a head's clauses came from, asked WITHOUT resolving the predicate.
% predicate_property/2 resolves its head first, and on an undefined one that
% resolution fires SWI's undefined-procedure hook, which this engine answers by
% translating the name's MeTTa equations. Asked while a backing row is being
% performed, that turns registering `math-rational`/3 into a re-entrant
% translation of `math-rational`/1, whose body calls arity 3 -- still
% unregistered, because the frame that would have registered it is the one
% asking. The unary equation then compiles to a function_overapplication goal,
% and by the time that goal runs and renders its message the arity set it
% prints contains the very arity it refuses, so the error refutes itself
% [measured 2026-09-21: predicate_property(M:H, file(F)) fires the hook on an
% undefined head while current_predicate/2 does not and still answers for an
% imported one; tested: lib_package:a_backing_row_registers_before_the_equations_calling_it_translate].
% Guarding on current_predicate/2 is what makes "asking never defines" true by
% shape, rather than by which of the load's two halves happens to run first.
package_head_source(Module, Head, File) :-
    current_predicate(_, Module:Head),
    predicate_property(Module:Head, file(File)).

% A home may already contain a required source's backing. Check that source
% before consulting another file, while its directives have made no changes.
package_native_admission(Path, Space, [prolog, Locator, _], Names, Contracts) :- !,
    package_native_path(Path, Space, Locator, File),
    metta_engine:check_prolog_function_names(Names, File, true),
    space_module(Space, Module),
    forall((member(contract(Name, Arity, _), Contracts), memberchk(Name, Names),
            metta_engine:metta_reference_prolog_head(Space, Name, Arity),
            functor(Head, Name, Arity), package_head_source(Module, Head, Owner)),
           ( Owner == File -> true
           ; throw(error(metta_name_owned_by_source(Name, Owner),
                         context(package, File))) )).
package_native_admission(_, _, _, _, _).

% Reusing the same artifact does not replace an occupied host predicate.
% Every other case passes through OPEN before the artifact can run directives.
package_open_head(Path, Space, [prolog, Locator, _], Name, Arity) :-
    package_native_path(Path, Space, Locator, File),
    space_module(Space, Module), functor(Head, Name, Arity),
    package_head_source(Module, Head, File), !.
package_open_head(_, _, [Token|_], Name, Arity) :-
    metta_host_open_function(Name, Token, Arity).

% Native clauses have process lifetime; only their MeTTa registration belongs
% to the source. Direct load_files/2 keeps import offline even when a compiled
% artifact is stale and the ordinary loader would invoke a compiler child.
'package-prolog'(File, Names, true) :-
    metta_engine:check_prolog_function_names(Names, File, true),
    current_metta_space(Home), space_module(Home, Module),
    metta_engine:metta_reference_check_prolog_source(File),
    package_load_native(File, Owner),
    % Declarations also apply when SWI reuses an already-loaded module. Read
    % them before selecting exports, so an alternative cannot register names
    % assigned to an earlier backing or leak an undeclared arity.
    package_native_declarations(File, Home, Owner, Names),
    package_native_manifest(File, Declared, Inferred), append(Declared, Inferred, All),
    forall((member(Name, Names), package_named_contract(Name, Declared, All, Arity, _)),
           ( ( Owner == Module -> true
             ; Owner:export(Name/Arity), Module:import(Owner:Name/Arity) ),
             metta_engine:metta_reference_register_prolog(Home, Module, Name, Arity) )).

% Artifact clauses have process lifetime in their own namespace. Import only
% selected heads into the home: importing all exports also occupies unselected
% equation names, even though those predicates were never registered in MeTTa.
% SWI load_files/2 imports([]) separates loading from namespace publication:
% https://www.swi-prolog.org/pldoc/doc_for?object=load_files/2
% [tested: lib_package:unselected_native_exports_leave_equation_heads_free; commit=561cfeaa23b27fc84f86a9bcccf6ccf8b9d2e73f].
package_load_native(File, Owner) :-
    ( source_file_property(File, module(Context)) -> true
    ; source_file_property(File, load_context(Context, _, _)) -> true
    ; atom_concat('$metta_package:', File, Context),
      set_module(Context:base(metta_engine)) ),
    filereader:with_owning_source_load(none,
        metta_engine:loading_loudly(
            load_files(Context:File, [expand(true), if(changed), imports([])]))),
    ( source_file_property(File, module(Owner)) -> true ; Owner = Context ).

package_native_declarations(File, Home, Module, Names) :-
    retractall(metta_engine:pending_metta_export(File, _, _)),
    ( module_property(Owner, file(File)) -> true ; Owner = Module ),
    setup_call_cleanup(open(File, read, Input, [encoding(utf8)]),
        metta_engine:metta_reference_read_exports(Input, File, Owner), close(Input)),
    findall(File-Name-Type, retract(metta_engine:pending_metta_export(File, Name, Type)), Pending),
    include(package_named_declaration(Names), Pending, Selected),
    forall(member(File-Name-Type, Selected),
           ( ( Type = arity(_) -> true ; metta_add_atom(Home, [':', Name, Type], _) ),
             metta_engine:record_extension_membership(File, Name) )).

package_named_declaration(Names, _-Name-_) :- memberchk(Name, Names).

package_contract(Path, Space, [prolog, Locator, Pattern], Pattern, Names, Contracts) :- !,
    package_native_path(Path, Space, Locator, File),
    package_native_manifest(File, Declared, Inferred),
    ( ( var(Pattern) ; package_segment_pattern(Pattern, _, _) )
    -> package_native_exports(Declared, Exports),
       package_heads_pattern(Pattern, Exports, Names),
       include(package_contract_named(Names), Declared, Contracts)
    ; must_be(list, Pattern), maplist(must_be(atom), Pattern), Names = Pattern,
      append(Declared, Inferred, All),
      findall(contract(Name, Arity, Type),
              ( member(Name, Names),
                package_named_contract(Name, Declared, All, Arity, Type) ), Raw),
      sort(Raw, Contracts),
      forall(member(Name, Names),
             ( memberchk(contract(Name, _, _), Contracts) -> true
             ; throw(error(existence_error(procedure, Name),
                           context(package, File))) )) ).
package_contract(_, _, [_, _, Pattern], Pattern, [], []) :- Pattern == [], !.
package_contract(_, _, Row, Pattern, Names, Contracts) :-
    Row = [_, Artifact, _],
    ( nonvar(Artifact), 'is-space'(Artifact, true)
    -> metta_engine:metta_reference_face(Artifact, [], Face),
       findall(contract(Name, Arity, Type),
           ( member(Name/Arity-_, Face), integer(Arity),
             ( metta_host_stored(Artifact, [':', Name, Type]) -> true
             ; package_unknown_arrow(Arity, Type) ) ), All)
    ; package_claim('package-contract', Row, _)
    -> metta_engine:metta_package_normalise('&metta', ['package-contract', Row], Exported),
       must_be(list, Exported), maplist(package_contract_row, Exported, All)
    ; throw(error(existence_error(package_export_contract, Row),
                  context(package, 'the claimant must supply package-contract equations or an artifact space'))) ),
    findall(Name, member(contract(Name, _, _), All), ExportNames), sort(ExportNames, Exports),
    ( is_list(Pattern), maplist(atom, Pattern)
    -> Names = Pattern,
       forall(member(Name, Names),
              (memberchk(Name, Exports) -> true
              ; throw(error(existence_error(package_export, Name), none))))
    ; package_heads_pattern(Pattern, Exports, Names) ),
    include(package_contract_named(Names), All, Contracts).

package_contract_row([':', Name, Type], contract(Name, Arity, Type)) :-
    !,
    must_be(atom, Name),
    ( metta_engine:declared_predicate_arity(Type, Arity) -> true
    ; throw(error(type_error(package_export_arrow, Type), none)) ).
package_contract_row(Row, _) :- throw(error(type_error(package_export_contract, Row), none)).

package_named_contract(Name, Declared, All, Arity, Type) :-
    ( memberchk(export_declaration, Declared)
    -> member(contract(Name, Arity, Type), Declared)
    ; member(contract(Name, Arity, Type), All) ).

package_contract_named(Names, contract(Name, _, _)) :- memberchk(Name, Names).

package_native_exports(Contracts, Names) :-
    findall(Name, member(contract(Name, _, _), Contracts), All), sort(All, Names),
    ( Names == [], \+ memberchk(export_declaration, Contracts)
    -> throw(error(existence_error(package_export_declaration, prolog),
                   context(package, 'variable heads require the artifact export declaration')))
    ; true ).

package_segment_pattern(Pattern, Prefix, Tail) :-
    nonvar(Pattern), is_list(Pattern),
    append(Prefix, [[':seg', Tail]], Pattern).

package_heads_pattern(Pattern, Exports, Exports) :- var(Pattern), !, Pattern = Exports.
package_heads_pattern(Pattern, Exports, Exports) :-
    package_segment_pattern(Pattern, Prefix, Tail), !,
    maplist(must_be(atom), Prefix),
    forall(member(Name, Prefix),
           ( memberchk(Name, Exports) -> true
           ; throw(error(existence_error(package_export, Name), none)) )),
    subtract(Exports, Prefix, Rest),
    ( Tail = Rest -> true
    ; throw(error(domain_error(package_export_pattern, Pattern), none)) ).
package_heads_pattern(Pattern, _, _) :-
    throw(error(domain_error(package_export_pattern, Pattern), none)).

package_native_path(Path, Space, Locator, File) :-
    ( nonvar(Locator), Locator = [library|_]
    -> metta_engine:resolve_module_form(Locator, Resolved)
    ; atomic(Locator) -> Resolved = Locator
    ; metta_engine:metta_package_normalise(Space, Locator, Resolved) ),
    ( (atom(Resolved) ; string(Resolved)) -> true
    ; throw(error(type_error(package_artifact_path, Resolved), context(package, Path))) ),
    file_directory_name(Path, Directory),
    absolute_file_name(Resolved, File,
                       [relative_to(Directory), file_type(prolog), access(none)]),
    ( exists_file(File) -> true
    ; throw(error(existence_error(source_sink, File),
                  context(package, 'backing artifact is missing; run !(setup! (library X))'))) ).

% O(t) Prolog terms in a selected artifact. Source declarations are read once
% per plan. Clause heads are the compatibility contract for an explicit name
% list; a variable head pattern requires actual module/metta_export declarations.
package_native_manifest(File, Declared, Inferred) :-
    setup_call_cleanup(open(File, read, Stream, [encoding(utf8)]),
        package_native_terms(Stream, [], Exports0, [], Heads0), close(Stream)),
    sort(Exports0, Exported), sort(Heads0, Inferred),
    findall(Contract,
        ( member(Export, Exported),
          ( Export == export_declaration -> Contract = export_declaration
          ; ( Export = contract(Name, Arity, Type)
            ; Export = Name/Arity,
              \+ member(contract(Name, Arity, _), Exported),
              package_unknown_arrow(Arity, Type) ),
            Contract = contract(Name, Arity, Type) ) ), Declared).

package_native_terms(Stream, Exports0, Exports, Heads0, Heads) :-
    read_term(Stream, Term, [module(user), syntax_errors(error)]),
    ( Term == end_of_file -> Exports = Exports0, Heads = Heads0
    ; package_native_term(Term, ExportRows, HeadRows),
      append(ExportRows, Exports0, Exports1), append(HeadRows, Heads0, Heads1),
      package_native_terms(Stream, Exports1, Exports, Heads1, Heads) ).

package_native_term((:- module(_, Exports)), [export_declaration|Exports], []) :- !.
package_native_term((:- metta_export(Text)), [export_declaration|Contracts], []) :- !,
    parse_metta_source(Text, Forms),
    findall(contract(Name, Arity, Type),
        ( member(Form, Forms), parsed_form_parts(Form, _, _, Row),
          ( Row = [':', Name, Type], metta_engine:declared_predicate_arity(Type, Arity)
          ; Row = [export, Name, Inputs], integer(Inputs), Inputs >= 0,
            Arity is Inputs + 1,
            package_unknown_arrow(Arity, Type) ) ), Contracts).
package_native_term((:- _), [], []) :- !.
package_native_term((Head :- _), [], Contracts) :- !, package_native_head(Head, Contracts).
package_native_term(Head, [], Contracts) :- package_native_head(Head, Contracts).

package_native_head(Head, [contract(Name, Arity, Type)]) :-
    callable(Head), \+ Head = (_:_), functor(Head, Name, Arity), Arity > 0,
    package_unknown_arrow(Arity, Type), !.
package_native_head(_, []).

package_unknown_arrow(Arity, [->|Types]) :-
    length(Types, Arity), maplist(=('%Undefined%'), Types).

% Explicit preparation and persistent receipts.

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
