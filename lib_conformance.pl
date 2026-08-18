% Purpose: prove a foreign space provider before its users find out, for the
%   tier that had no way to do it. petta.testing.check_space_provider takes a
%   Python OBJECT, and a Prolog provider is a set of multifile clauses with no
%   object to pass, so the conformance kit covered the seam's convenient tier
%   and not the one EXTENDING.md recommends for speed: the tier whose authors
%   are, by construction, the ones optimising rather than following the
%   default path.
%
%   The checks are the Python kit's, asked of a SPACE NAME instead of an
%   object, so a provider written in either language is held to one contract.
% Assumes:
%   - the provider is registered and metta_foreign_space/1 answers for it;
%     an unregistered name is a refusal rather than a pass
%     [tested: conformance_refuses_a_space_that_is_not_foreign]
%   - enumeration is the oracle. A provider that does not enumerate cannot be
%     checked this way and says so, which is the same limit the Python kit has
% Guarantees:
%   - a provider that under-approximates its match is refused, naming the atom
%     [tested: conformance_catches_an_under_approximating_matcher]
%   - a capability declared with no hook clause behind it is refused, which is
%     a registration-time mistake that otherwise surfaces inside a callback
%     [tested: conformance_catches_a_capability_with_no_hook]
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
%type a message has.
metta_check_space_provider(Space, Checks) :-
    must_be(atom, Space),
    refuse_unforeign_space(Space),
    conformance_capabilities(Space, CapabilityChecks),
    conformance_atoms(Space, Atoms),
    conformance_match(Space, Atoms, MatchCheck),
    conformance_pushdown(Space, Atoms, PushdownCheck),
    conformance_plan(Space, Atoms, PlanCheck),
    append(CapabilityChecks, [MatchCheck, PushdownCheck, PlanCheck], Checks).

refuse_unforeign_space(Space) :-
    (   metta_foreign_space(Space)
    ->  true
    ;   throw(error(petta_conformance_not_foreign(Space), none))
    ).

%Every capability the space declares has a hook with a clause behind it. A
%declaration with nothing behind it is the Prolog shape of the Python kit's
%"can_run says yes and the method is not there": it surfaces as a silent
%failure inside a callback rather than as a mistake at registration.
conformance_capabilities(Space, Checks) :-
    findall(Check, conformance_capability(Space, Check), Checks).

conformance_capability(Space, Check) :-
    member(Capability, [match, enumerate, add, remove, clear]),
    foreign_provides(Space, Capability),
    capability_hook(Capability, Name/Arity),
    (   conformance_hook_defined(Name, Arity)
    ->  format(string(Check), '~w: declared, ~w/~w has clauses',
               [Capability, Name, Arity])
    ;   throw(error(petta_conformance_no_hook(Space, Capability, Name/Arity),
                    none))
    ).

capability_hook(match, metta_foreign_match/3).
capability_hook(enumerate, metta_foreign_atoms/2).
capability_hook(add, metta_foreign_add/2).
capability_hook(remove, metta_foreign_remove/3).
capability_hook(clear, metta_foreign_clear/1).

%number_of_clauses rather than clause/2: the hooks are static multifile
%predicates, and asking a static predicate for its clauses is a permission
%error on a system built with protect_static_code.
conformance_hook_defined(Name, Arity) :-
    functor(Head, Name, Arity),
    petta_engine_module(Engine),
    catch(predicate_property(Engine:Head, number_of_clauses(Count)), _, fail),
    Count > 0.

conformance_atoms(Space, Atoms) :-
    (   foreign_provides(Space, enumerate)
    ->  findall(Atom, metta_foreign_atoms(Space, Atom), Atoms)
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
    length(Atoms, Count),
    format(string(Check), 'match: over-approximation holds over ~w atoms',
           [Count]).

conformance_answers_itself(Space, Atom) :-
    (   \+ \+ match_foreign(Space, Atom, answered, answered)
    ->  true
    ;   throw(error(petta_conformance_under_approximates(Space, Atom), none))
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
    forall(metta_foreign_match(Space, Candidate, []),
           conformance_candidate_matches(Space, Atom, Candidate)).

conformance_candidate_matches(Space, Atom, Candidate) :-
    (   \+ \+ Atom = Candidate
    ->  true
    ;   throw(error(petta_conformance_false_exact(Space, Atom, Candidate), none))
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
    ;   throw(error(petta_conformance_claim_differs(Space, Claimed, Split), none))
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
    gensym('&petta-conformance-', Native),
    forall(member(Atom, Atoms), 'add-atom'(Native, Atom, _)).

conformance_drop_copy(Native, Atoms) :-
    forall(member(Atom, Atoms), 'remove-atom'(Native, Atom, _)).

prolog:error_message(petta_conformance_claim_differs(Space, Claimed, Split)) -->
    [ '~w claims conjunctions and answered ~w where the engine\'s own split \c
       over the same atoms answered ~w. A claim is EXACT: a provider that \c
       cannot answer a conjunction exactly must decline it, because the engine \c
       plans only what you leave and never re-checks a row.'
      -[Space, Claimed, Split] ].
prolog:error_message(petta_conformance_not_foreign(Space)) -->
    [ '~w is not a registered foreign space, so there is no provider to \c
       check. Register it first.'-[Space] ].
prolog:error_message(petta_conformance_no_hook(Space, Capability, PI)) -->
    [ '~w declares the ~w capability and ~w has no clauses. Implement the \c
       hook, or drop the capability from metta_foreign_capability/2.'
      -[Space, Capability, PI] ].
prolog:error_message(petta_conformance_under_approximates(Space, Atom)) -->
    [ '~w holds ~w and matching it answered nothing. A provider may \c
       over-approximate and may never under-approximate: yielding every atom \c
       is always correct, yielding fewer than match is never allowed to be.'
      -[Space, Atom] ].
prolog:error_message(petta_conformance_false_exact(Space, Atom, Candidate)) -->
    [ '~w claims exact filtering for ~w and yielded ~w, which does not match \c
       it. exact means every candidate you yield for this pattern unifies \c
       with it, so the caller may stop at its bound; a claim that is wrong \c
       loses answers.'-[Space, Atom, Candidate] ].
