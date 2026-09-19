% Purpose: interpret package argument records, prepare them explicitly, and own
% their activation and retirement through the existing source loader.
% Assumes: the engine sequences requires first and bounds normalisation.
% [source: engine/metta/interop.pl:metta_perform_package_rows/2; commit=WORKTREE].
% Guarantees: local boot validation precedes effects; receipts belong to the
% source; setup publishes only successful work under a directory lock.
% [tested: lib_package; commit=WORKTREE].
% Owns resources: package_acquired/5 records live answers until reverse release
% on withdrawal, replacement, failed activation, space release or process exit.
% Guarded by: source single-flight protects loads; package_claims protects seam
% installation; the directory mutex and OS write lock protect setup publication.
% Decides: package-load equations supplied by requirements replace this default;
% source order chooses a backing when several claimed rows cover the same head.
% Open Obligations: Python manifest.py has not adopted the bootable-door protocol.

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
% Extend the existing arity family without re-declaring its one-input facet.
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

:- include('catalog.pl').
:- include('native.pl').
:- include('setup.pl').

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
% [tested: lib_package:default_claim_recovers_after_withdrawal_and_failed_activation; commit=WORKTREE].
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
