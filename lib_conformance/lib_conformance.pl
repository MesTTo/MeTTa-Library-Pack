% Purpose: prove a foreign space provider before its users find out, for the
%   tier that had no way to do it. metta.testing.check_space_provider takes a
%   Python OBJECT, and a Prolog provider is a set of multifile clauses with no
%   object to pass, so the conformance kit covered the seam's convenient tier
%   and not the one EXTENDING.md recommends for speed: the tier whose authors
%   are, by construction, the ones optimising rather than following the
%   default path.
%
%   The checks are the Python kit's, asked of a SPACE NAME instead of an
%   object, so a provider written in either language is held to one contract.
% Assumes:
%   - the provider is registered and seam:foreign_space/1 answers for it;
%     an unregistered name is a refusal rather than a pass
%     [tested: conformance_refuses_a_space_that_is_not_foreign]
%   - enumeration is the oracle. A provider that does not enumerate cannot be
%     checked this way and says so, which is the same limit the Python kit has
% Guarantees:
%   - a provider that under-approximates its match is refused, naming the atom,
%     over the whole pattern family: itself, each position opened to a fresh
%     variable, and repeated-variable folds
%     [tested: conformance_catches_an_under_approximating_matcher,
%     conformance_catches_a_ground_only_matcher]
%   - a repeated or peek source whose second enumeration disagrees is refused,
%     and a linear source is never asked twice
%     [tested: conformance_catches_a_source_that_drains]
%   - a writable provider round-trips a canary through its own add, enumerate
%     and remove, and is left as found
%     [tested: conformance_round_trips_a_canary]
%   - a capability declared with no hook clause behind it is refused, which is
%     a registration-time mistake that otherwise surfaces inside a callback
%     [tested: conformance_catches_a_capability_with_no_hook]
%   - a clause whose body is module-qualified is admitted only when its leading
%     ownership guard succeeds in that module; the operation behind the guard
%     is never run [tested: a_qualified_hook_body_runs_only_its_leading_guard,
%     a_qualified_hook_body_with_a_failing_guard_is_refused; commit=90362cf551149c822a05fb26fbf80d0c2ce11fa4]
%   - a false exact pushdown claim is refused, which is the one claim in the
%     seam that costs answers
%     [tested: conformance_catches_a_false_exact_claim]
% Fails when:
%   - the space holds nothing. Every check here is over the atoms the provider
%     holds, so an empty space passes vacuously and says so in its report
%     rather than pretending.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- use_module(library(lists)).

:- multifile prolog:error_message//1.

%The whole kit. Answers the checks it ran, one STRING per check, so a caller
%sees what was covered rather than a bare true, and a MeTTa caller gets the
%type a message has. The source discipline is READ, not supplied: the
%engine already holds each context's declared class through metta_source/2
%((source Ctx Kind), repeated when undeclared), so the checker asks the
%declaration the enforcement reads rather than trusting a caller's claim.
metta_check_space_provider(Space, Checks) :-
    must_be(atom, Space),
    refuse_unforeign_space(Space),
    conformance_capabilities(Space, CapabilityChecks),
    conformance_atoms(Space, Atoms),
    conformance_match(Space, Atoms, MatchCheck),
    conformance_source(Space, Atoms, SourceCheck),
    conformance_round_trip(Space, RoundTripCheck),
    conformance_pushdown(Space, Atoms, PushdownCheck),
    conformance_plan(Space, Atoms, PlanCheck),
    append(CapabilityChecks,
           [MatchCheck, SourceCheck, RoundTripCheck, PushdownCheck,
            PlanCheck],
           Checks).

refuse_unforeign_space(Space) :-
    (   seam:foreign_space(Space)
    ->  true
    ;   throw(error(metta_conformance_not_foreign(Space), none))
    ).

%Every capability the space declares has a hook with a clause behind it. A
%declaration with nothing behind it is the Prolog shape of the Python kit's
%"can_run says yes and the method is not there": it surfaces as a silent
%failure inside a callback rather than as a mistake at registration.
conformance_capabilities(Space, Checks) :-
    findall(Check, conformance_capability(Space, Check), Checks).

conformance_capability(Space, Check) :-
    % policy-inventory-exempt: mechanism-internal; reason=these five names are the fixed foreign-provider protocol hooks checked for every declared capability; evidence=lib/lib_conformance/lib_conformance.pl:conformance_capability/2
    member(Capability, [match, enumerate, add, remove, clear]),
    foreign_provides(Space, Capability),
    capability_hook(Capability, Hook),
    (   conformance_hook_defined(Hook, Space)
    ->  format(string(Check), '~w: declared, ~w has clauses', [Capability, Hook])
    ;   throw(error(metta_conformance_no_hook(Space, Capability, Hook), none))
    ).

capability_hook(match, seam:foreign_match/3).
capability_hook(enumerate, seam:foreign_atoms/2).
capability_hook(add, seam:foreign_add/2).
capability_hook(remove, seam:foreign_remove/3).
capability_hook(clear, seam:foreign_clear/1).

%number_of_clauses rather than clause/2: the hooks are static multifile
%predicates, and asking a static predicate for its clauses is a permission
%error on a system built with protect_static_code.
%
%The hook is asked of the module capability_hook/2 names, which is the whole
%content of that qualification. It used to be asked of the engine's module,
%which was right only while the seams lived there: with them in `seam` the
%engine's module has no clause of any of them and every declared capability
%reported as undeclared.
%Asked PER SPACE, because the predicate having clauses is a receipt and a
%clause that serves THIS space is the payload: the day MORK gained its own
%clear hook, every other provider's undeclared clear satisfied a
%whole-predicate count and this check stopped catching the thing it exists
%for [measured 2026-08-26 under `-- extensions`, where the hookless probe
%passed while MORK's clause supplied the count]. The seam's ownership-guard
%protocol (engine/ext_points.pl) is what makes the per-space question
%decidable without performing the operation: a hook clause's leading body
%goal is the pure ownership test, so admitting a space costs a lookup.
conformance_hook_defined(Module:Name/Arity, Space) :-
    functor(Probe, Name, Arity),
    (   conformance_clause_access(Module:Probe, denied)
    ->  %A system built with protect_static_code refuses clause/2 on static
        %code, so the whole-predicate count is the only answer available
        %there. It is the weaker claim, and it is made only where the
        %stronger one cannot be.
        catch(predicate_property(Module:Probe, number_of_clauses(Count)), _, fail),
        Count > 0
    ;   conformance_hook_admits(Module:Name/Arity, Space)
    ),
    !.

conformance_clause_access(Module:Probe, Access) :-
    catch(( clause(Module:Probe, _) -> Access = present ; Access = absent ),
          error(permission_error(_, _, _), _),
          Access = denied).

%Two clause shapes serve one protocol. A clause that BINDS the space in its
%head has already said which space it serves, so head unification decides
%and nothing runs. A clause that leaves it a variable decides ownership in
%its body, and the protocol fixes the leading goal as that pure test, so
%admitting a space costs one lookup and never performs the operation.
conformance_hook_admits(Module:Name/Arity, Space) :-
    functor(Probe, Name, Arity),
    clause(Module:Probe, Body),
    arg(1, Probe, Owner),
    (   var(Owner)
    ->  Owner = Space,
        conformance_guard_admits(Body)
    ;   Owner == Space
    ),
    !.

%Only the LEADING goal runs. clause/2 returns a body qualified with the module
%that owns it, so strip that qualification before inspecting conjunction/2,
%then put the module back on the one goal that may run. Without the strip the
%top-level functor is :/2, the conjunction clause never matches, and the
%catch-all executes the hook's operation as well as its ownership guard.
%A fact applies unconditionally; a guard that throws is not an admission.
conformance_guard_admits(Qualified) :-
    strip_module(Qualified, Module, Body),
    conformance_guard_admits_in(Module, Body).

conformance_guard_admits_in(_, true) :- !.
conformance_guard_admits_in(Module, (Guard, _)) :- !,
    catch(call(Module:Guard), _, fail).
conformance_guard_admits_in(Module, Guard) :-
    catch(call(Module:Guard), _, fail).

conformance_atoms(Space, Atoms) :-
    (   foreign_provides(Space, enumerate)
    ->  findall(Atom, seam:foreign_atoms(Space, Atom), Atoms)
    ;   Atoms = []
    ).

%The seam's central soundness claim, checked the way the Python kit checks it:
%every atom the provider holds is matched against ITSELF, and the provider has
%to answer it. A provider may over-approximate freely, because the engine
%re-unifies; it may never under-approximate, and one that filters too eagerly
%answers an empty set in production with nothing to say why.
conformance_match(Space, [], Check) :- !,
    ( foreign_provides(Space, enumerate)
      -> Check = "match: the space is empty, so the contract is untested"
      ;  Check = "match: the space does not enumerate, so there is no oracle" ).
conformance_match(Space, Atoms, Check) :-
    forall(member(Atom, Atoms), conformance_answers_itself(Space, Atom)),
    forall(( member(Atom, Atoms),
             conformance_family_pattern(Atom, Pattern) ),
           conformance_family_covered(Space, Atoms, Pattern)),
    length(Atoms, Count),
    format(string(Check),
           'match: over-approximation holds over ~w atoms and their pattern families',
           [Count]).

conformance_answers_itself(Space, Atom) :-
    (   \+ \+ match_foreign(Space, Atom, answered, answered)
    ->  true
    ;   throw(error(metta_conformance_under_approximates(Space, Atom), none))
    ).

%The pattern FAMILY, the Python kit's own construction asked through the
%seam: every stored atom vouches for itself, for each argument position
%opened to a fresh variable, and for the repeated-variable fold wherever
%two ground arguments coincide. A provider that only handles ground
%patterns, or that filters a repeated variable's occurrences
%independently, fails here naming the pattern instead of answering
%wrongly in production.
conformance_family_pattern([Head|Args], [Head|Opened]) :-
    Args \== [],
    nth1(Position, Args, _),
    conformance_open_argument(Args, Position, Opened).
conformance_family_pattern([Head|Args], [Head|Folded]) :-
    nth1(I, Args, A), nth1(J, Args, B),
    I < J, A == B, ground(A),
    conformance_fold_arguments(Args, I, J, Folded).

conformance_open_argument(Args, Position, Opened) :-
    length(Args, N), length(Opened, N),
    forall(( nth1(K, Args, Arg), K \== Position ),
           nth1(K, Opened, Arg)).

conformance_fold_arguments(Args, I, J, Folded) :-
    length(Args, N), length(Folded, N),
    nth1(I, Folded, Shared), nth1(J, Folded, Shared),
    forall(( nth1(K, Args, Arg), K \== I, K \== J ),
           nth1(K, Folded, Arg)).

%Every stored atom unifying the pattern must be COVERED by some yielded
%candidate: a candidate covers a stored atom when the atom unifies with
%it, which licenses over-approximation (a more general candidate covers)
%and forbids omission. Multiset discipline: each stored occurrence
%consumes its own candidate, because multiplicity is observable and a
%provider deduplicating two equal stored atoms would answer one row
%where the space holds two.
conformance_family_covered(Space, Atoms, Pattern) :-
    findall(Stored, ( member(Stored, Atoms), \+ \+ Stored = Pattern ),
            Expected),
    %Asked through the engine's router rather than the raw hook, because a
    %provider that does not declare match is served by the enumeration
    %fallback, and holding it to a hook it never claimed would refuse the
    %seam's own routing: the shipped C example provider declares only
    %enumerate and the four writes, and the raw read refused it here.
    findall(Candidate,
            ( copy_term(Pattern, Candidate),
              match_foreign(Space, Candidate, answered, answered) ),
            Candidates),
    (   conformance_covers(Candidates, Expected)
    ->  true
    ;   throw(error(metta_conformance_family_missed(Space, Pattern,
                                                    Expected, Candidates),
                    none))
    ).

conformance_covers(_, []).
conformance_covers(Candidates, [Stored|Rest]) :-
    select(Candidate, Candidates, Remaining),
    \+ \+ Stored = Candidate,
    !,
    conformance_covers(Remaining, Rest).

%The source discipline, read from the declaration the engine enforces:
%a repeated or peek context re-enumerates identically, so the second
%enumeration is compared with the first as a multiset; a linear context
%is one-shot, so asking twice would itself violate the discipline and
%the check says so instead.
conformance_source(Space, _, Check) :-
    \+ foreign_provides(Space, enumerate), !,
    Check = "source: the space does not enumerate, so there is nothing to re-enumerate".
conformance_source(Space, _, Check) :-
    metta_source(Space, linear), !,
    Check = "source: linear, so the second enumeration is not asked".
conformance_source(Space, First, Check) :-
    metta_source(Space, Kind),
    findall(Atom, seam:foreign_atoms(Space, Atom), Second),
    msort(First, SortedFirst),
    msort(Second, SortedSecond),
    (   SortedFirst =@= SortedSecond
    ->  format(string(Check), 'source: ~w, two enumerations agree', [Kind])
    ;   throw(error(metta_conformance_source_disagrees(Space, Kind), none))
    ).

%The lens literature's GetPut law through the seam: add then enumerate
%answers the stored atom back, and the canary leaves again through the
%provider's own remove, so the space is left as found. Only asked of a
%provider declaring BOTH writes; a read-only provider has no door to
%check and says so.
conformance_round_trip(Space, Check) :-
    (   foreign_provides(Space, add),
        foreign_provides(Space, remove),
        foreign_provides(Space, enumerate)
    ->  gensym('metta-conformance-canary-', Marker),
        Canary = ['metta-conformance-canary', Marker],
        setup_call_cleanup(
            seam:foreign_add(Space, Canary),
            (   \+ \+ ( seam:foreign_atoms(Space, Held),
                        Held =@= Canary )
            ->  Check = "round trip: add then enumerate answers the atom, and remove takes it back"
            ;   throw(error(metta_conformance_round_trip(Space, Canary),
                            none))
            ),
            seam:foreign_remove(Space, Canary, _))
    ;   Check = "round trip: not asked, the provider does not declare add, remove and enumerate together"
    ).

%The one claim in the seam that can cost answers. exact licenses truncating at
%the caller's bound, so a provider that truncates while yielding candidates
%that do not match answers fewer rows than exist, and under-answering is the
%one thing the contract forbids.
%
%Checked per pattern, because the claim is per pattern: a backend is usually
%exact on an indexed equality and inexact on a scan.
conformance_pushdown(_, [], "pushdown: no atoms to check the claim against") :- !.
conformance_pushdown(Space, Atoms, Check) :-
    include(conformance_claims_exact(Space), Atoms, Exact),
    forall(member(Atom, Exact), conformance_exactly(Space, Atom)),
    length(Exact, Claimed),
    length(Atoms, Total),
    format(string(Check), 'pushdown: ~w of ~w patterns claimed exact, and are',
           [Claimed, Total]).

conformance_claims_exact(Space, Atom) :-
    foreign_pushdown_class(Space, Atom, exact).

conformance_exactly(Space, Atom) :-
    forall(seam:foreign_match(Space, Candidate, []),
           conformance_candidate_matches(Space, Atom, Candidate)).

conformance_candidate_matches(Space, Atom, Candidate) :-
    (   \+ \+ Atom = Candidate
    ->  true
    ;   throw(error(metta_conformance_false_exact(Space, Atom, Candidate), none))
    ).

%The one claim in this seam the engine cannot check for itself. Everywhere else
%a provider may over-approximate, because the engine re-unifies each candidate
%it yields and that is cheap; verifying one row of a JOIN means running the
%join, so the engine has to trust a claim on the hot path. That is exactly what
%a conformance kit should not do, so the same conjunction is asked of the
%provider and of a native space holding the atoms the provider holds.
conformance_plan(Space, _, Check) :-
    \+ foreign_provides(Space, plan), !,
    Check = "plan: not declared, so a conjunction takes the engine's split".
conformance_plan(_, [], Check) :- !,
    Check = "plan: declared, and the space holds nothing to join".
conformance_plan(_, Atoms, Check) :-
    \+ conformance_join_shape(Atoms, _, _), !,
    Check = "plan: declared, and no stored atom has arguments to join on".
conformance_plan(Space, Atoms, Check) :-
    conformance_join_shape(Atoms, Left, Right),
    conformance_rows(Space, Left, Right, Claimed),
    setup_call_cleanup(
        conformance_native_copy(Atoms, Native),
        conformance_rows(Native, Left, Right, Split),
        conformance_drop_copy(Native, Atoms)),
    (   Claimed =@= Split
    ->  length(Claimed, N),
        format(string(Check), 'plan: the claim answers the split, ~w rows', [N])
    ;   throw(error(metta_conformance_claim_differs(Space, Claimed, Split), none))
    ).

%A chain self-join on one stored shape: the last argument of the left pattern
%is the first of the right, which is the join every provider holding that shape
%can answer and the smallest one that is not a cartesian product.
conformance_join_shape([Atom|_], Left, Right) :-
    is_list(Atom), Atom = [Head|Args], Args \== [], !,
    length(Args, N),
    length(LeftArgs, N), length(RightArgs, N),
    last(LeftArgs, Shared), RightArgs = [Shared|_],
    Left = [Head|LeftArgs], Right = [Head|RightArgs].
conformance_join_shape([_|Atoms], Left, Right) :-
    conformance_join_shape(Atoms, Left, Right).

conformance_rows(Space, Left, Right, Rows) :-
    copy_term(Left-Right, L-R),
    findall(L-R, match(Space, [',', L, R], L-R, _), Unsorted),
    msort(Unsorted, Rows).

conformance_native_copy(Atoms, Native) :-
    gensym('&metta-conformance-', Native),
    forall(member(Atom, Atoms), 'add-atom'(Native, Atom, _)).

conformance_drop_copy(Native, Atoms) :-
    forall(member(Atom, Atoms), 'remove-atom'(Native, Atom, _)).

prolog:error_message(metta_conformance_claim_differs(Space, Claimed, Split)) -->
    [ '~w claims conjunctions and answered ~w where the engine\'s own split \c
       over the same atoms answered ~w. A claim is EXACT: a provider that \c
       cannot answer a conjunction exactly must decline it, because the engine \c
       plans only what you leave and never re-checks a row.'
      -[Space, Claimed, Split] ].
prolog:error_message(metta_conformance_not_foreign(Space)) -->
    [ '~w is not a registered foreign space, so there is no provider to \c
       check. Register it first.'-[Space] ].
prolog:error_message(metta_conformance_no_hook(Space, Capability, PI)) -->
    [ '~w declares the ~w capability and ~w has no clauses. Implement the \c
       hook, or drop the capability from seam:foreign_capability/2.'
      -[Space, Capability, PI] ].
prolog:error_message(metta_conformance_under_approximates(Space, Atom)) -->
    [ '~w holds ~w and matching it answered nothing. A provider may \c
       over-approximate and may never under-approximate: yielding every atom \c
       is always correct, yielding fewer than match is never allowed to be.'
      -[Space, Atom] ].
prolog:error_message(metta_conformance_family_missed(Space, Pattern,
                                                     Expected, Candidates)) -->
    [ '~w misses part of the pattern family for ~w: the stored atoms \c
       unifying it are ~w and the yielded candidates ~w do not cover them. \c
       Every stored atom vouches for itself, for each position opened to a \c
       variable, and for repeated-variable folds; a provider handling only \c
       ground patterns answers wrongly in production.'
      -[Space, Pattern, Expected, Candidates] ].
prolog:error_message(metta_conformance_source_disagrees(Space, Kind)) -->
    [ '~w declares a ~w source and its second enumeration disagrees with \c
       the first: a ~w source re-enumerates identically, so this provider \c
       is linear and should say so with (source ~w linear), where a second \c
       consumption is a loud error instead of a silently different answer.'
      -[Space, Kind, Kind, Space] ].
prolog:error_message(metta_conformance_round_trip(Space, Canary)) -->
    [ '~w stored ~w through its own add and its enumeration does not \c
       answer it back: add then enumerate is identity on the stored atom, \c
       because stored data keeps its literal atoms.'-[Space, Canary] ].
prolog:error_message(metta_conformance_false_exact(Space, Atom, Candidate)) -->
    [ '~w claims exact filtering for ~w and yielded ~w, which does not match \c
       it. exact means every candidate you yield for this pattern unifies \c
       with it, so the caller may stop at its bound; a claim that is wrong \c
       loses answers.'-[Space, Atom, Candidate] ].
