% Purpose: implement the assumption-explicit Beta, STV/moment, and
%   support-checked independent-product formulas exported by lib_pln2.
% Assumes:
%   - confidence c and an explicit positive scale k mean evidence count
%     n = k*c/(1-c); k is caller policy, never a hidden engine constant
%   - (supported (moments MEAN VARIANCE) IDS) carries stable ground acyclic
%     evidence identities supplied by the caller
% Guarantees:
%   - confidence/count conversion is reciprocal over its finite domain, Beta
%     moments use the standard mean and variance, and Beta-Binomial updates add
%     observed success and failure counts [tested:
%     test_confidence_count_round_trip, test_beta_moments_match_definition,
%     test_beta_update_adds_observations; commit=afc4024cef7d4b7bcdd194bb030a112187b676d0]
%   - independent product and conditional total-probability variance are the
%     exact second moments under the stated mutual-independence assumption
%     [tested: test_supported_product_matches_the_formula,
%     test_supported_total_probability_matches_the_formula;
%     commit=afc4024cef7d4b7bcdd194bb030a112187b676d0]
% Fails when:
%   - values are non-finite or outside their mathematical domains
%   - support overlaps; the refusal requires a reasoner to factor shared
%     support with stable signed identities before this library combines it
% Decides:
%   - variance zero and endpoint means do not invent a finite confidence;
%     callers retain moments or supply a finite identifiable variance
%   - no clipping, delta-method inversion, or confidence discount is applied


:- module(lib_pln2,
          [ 'pln2-beta-moments'/2,
            'pln2-beta-update'/4,
            'pln2-confidence-count'/3,
            'pln2-count-confidence'/3,
            'pln2-moments-stv'/3,
            'pln2-product-independent'/3,
            'pln2-require-independent-supports'/2,
            'pln2-stv-moments'/3,
            'pln2-total-probability-independent'/4
          ]).

% Guarantees: private helpers and autoload declarations belong to this module.
% [tested: engine_modules; commit=WORKTREE]
% Assumes: engine operations resolve through metta_engine's published exports.
% [source: engine/metta.pl:metta_engine_reexport/2; commit=WORKTREE]
:- set_module(base(metta_engine)).

% The standard Beta mean and variance fix the parameterization used below.
% [source: https://www.itl.nist.gov/div898/handbook/eda/section3/eda366h.htm;
% commit=afc4024cef7d4b7bcdd194bb030a112187b676d0]
'pln2-beta-moments'(RawBeta, [moments, Mean, Variance]) :-
    Operation = 'pln2-beta-moments'/1,
    pln2_beta(Operation, RawBeta, Alpha, Beta),
    Total is Alpha + Beta,
    Mean is Alpha / Total,
    Variance is Alpha * Beta / (Total * Total * (Total + 1)),
    !.

% A Beta prior followed by binomial observations has posterior shapes
% alpha+successes and beta+failures.
% [source: https://mc-stan.org/docs/2_22/stan-users-guide/exploiting-conjugacy.html;
% commit=afc4024cef7d4b7bcdd194bb030a112187b676d0]
'pln2-beta-update'(RawBeta, Successes, Failures,
                   [beta, UpdatedAlpha, UpdatedBeta]) :-
    Operation = 'pln2-beta-update'/3,
    pln2_beta(Operation, RawBeta, Alpha, Beta),
    pln2_nonnegative(Operation, successes, Successes),
    pln2_nonnegative(Operation, failures, Failures),
    UpdatedAlpha is Alpha + Successes,
    UpdatedBeta is Beta + Failures,
    !.

'pln2-confidence-count'(Confidence, Scale, Count) :-
    Operation = 'pln2-confidence-count'/2,
    pln2_confidence(Operation, Confidence),
    pln2_positive(Operation, evidence_scale, Scale),
    Count is Scale * Confidence / (1 - Confidence),
    !.

'pln2-count-confidence'(Count, Scale, Confidence) :-
    Operation = 'pln2-count-confidence'/2,
    pln2_nonnegative(Operation, evidence_count, Count),
    pln2_positive(Operation, evidence_scale, Scale),
    Confidence is Count / (Count + Scale),
    !.

'pln2-stv-moments'(RawStv, Scale, [moments, Strength, Variance]) :-
    Operation = 'pln2-stv-moments'/2,
    pln2_stv(Operation, RawStv, Strength, Confidence),
    pln2_positive(Operation, evidence_scale, Scale),
    Count is Scale * Confidence / (1 - Confidence),
    Variance is Strength * (1 - Strength) / (Count + 1),
    !.

'pln2-moments-stv'(RawMoments, Scale, [stv, Mean, Confidence]) :-
    Operation = 'pln2-moments-stv'/2,
    pln2_moments(Operation, RawMoments, Mean, Variance),
    pln2_positive(Operation, evidence_scale, Scale),
    (   Mean > 0, Mean < 1
    ->  true
    ;   pln2_refuse(
            Operation,
            pln2_unidentifiable_concentration(endpoint_mean, Mean),
            "a mean of 0 or 1 does not identify finite Beta concentration; retain (moments MEAN VARIANCE) instead")
    ),
    (   Variance > 0
    ->  Maximum is Mean * (1 - Mean),
        Count is Maximum / Variance - 1,
        Confidence is Count / (Count + Scale)
    ;   pln2_refuse(
            Operation,
            pln2_unidentifiable_concentration(zero_variance, Variance),
            "zero variance denotes unbounded concentration; retain moments or supply a positive finite variance")
    ),
    !.

% Polynomial provenance keeps joint use distinct from alternative use. The
% supported operations below enforce the corresponding minimum contract: a
% source identity may occur in only one independent operand. They refuse
% overlap rather than pretending to perform reasoner-owned proof factoring.
% [source: https://doi.org/10.1145/1265530.1265535; commit=afc4024cef7d4b7bcdd194bb030a112187b676d0]
'pln2-require-independent-supports'(Supports, true) :-
    pln2_validate_support_groups('pln2-require-independent-supports'/1,
                                  Supports, _),
    !.

'pln2-product-independent'(RawLeft, RawRight,
                           [supported, [moments, Mean, Variance], Support]) :-
    Operation = 'pln2-product-independent'/2,
    pln2_supported_moments(Operation, RawLeft, LeftMean, LeftVariance,
                           LeftSupport),
    pln2_supported_moments(Operation, RawRight, RightMean, RightVariance,
                           RightSupport),
    pln2_validate_support_groups(Operation, [LeftSupport, RightSupport],
                                  Support),
    Mean is LeftMean * RightMean,
    Variance is LeftVariance * RightVariance
               + LeftVariance * RightMean * RightMean
               + RightVariance * LeftMean * LeftMean,
    !.

'pln2-total-probability-independent'(
        RawIfTrue, RawIfFalse, RawCondition,
        [supported, [moments, Mean, Variance], Support]) :-
    Operation = 'pln2-total-probability-independent'/3,
    pln2_supported_moments(Operation, RawIfTrue, TrueMean, TrueVariance,
                           TrueSupport),
    pln2_supported_moments(Operation, RawIfFalse, FalseMean, FalseVariance,
                           FalseSupport),
    pln2_supported_moments(Operation, RawCondition,
                           ConditionMean, ConditionVariance,
                           ConditionSupport),
    pln2_validate_support_groups(
        Operation, [TrueSupport, FalseSupport, ConditionSupport], Support),
    Complement is 1 - ConditionMean,
    Difference is TrueMean - FalseMean,
    Mean is TrueMean * ConditionMean + FalseMean * Complement,
    Variance is ConditionMean * ConditionMean * TrueVariance
               + Complement * Complement * FalseVariance
               + Difference * Difference * ConditionVariance
               + ConditionVariance * (TrueVariance + FalseVariance),
    !.

pln2_beta(Operation, [beta, Alpha, Beta], Alpha, Beta) :-
    !,
    (   pln2_finite_number(Alpha), Alpha > 0,
        pln2_finite_number(Beta), Beta > 0
    ->  true
    ;   pln2_refuse(
            Operation,
            pln2_invalid_beta([beta, Alpha, Beta]),
            "use (beta ALPHA BETA) with finite positive shape parameters")
    ).
pln2_beta(Operation, Raw, _, _) :-
    pln2_refuse(Operation, pln2_invalid_beta(Raw),
                "use (beta ALPHA BETA) with finite positive shape parameters").

pln2_stv(Operation, [stv, Strength, Confidence], Strength, Confidence) :-
    !,
    pln2_probability(Operation, strength, Strength),
    pln2_confidence(Operation, Confidence).
pln2_stv(Operation, Raw, _, _) :-
    pln2_refuse(Operation, pln2_invalid_stv(Raw),
                "use (stv STRENGTH CONFIDENCE) with 0 <= STRENGTH <= 1 and 0 <= CONFIDENCE < 1").

pln2_moments(Operation, [moments, Mean, Variance], Mean, Variance) :-
    !,
    pln2_probability(Operation, mean, Mean),
    pln2_nonnegative(Operation, variance, Variance),
    Maximum is Mean * (1 - Mean),
    (   Variance =< Maximum
    ->  true
    ;   pln2_refuse(
            Operation,
            pln2_invalid_variance(Mean, Variance),
            "a probability-valued random variable requires 0 <= VARIANCE <= MEAN*(1-MEAN)")
    ).
pln2_moments(Operation, Raw, _, _) :-
    pln2_refuse(Operation, pln2_invalid_moments(Raw),
                "use (moments MEAN VARIANCE) for a probability-valued random variable").

pln2_supported_moments(Operation, [supported, RawMoments, Support],
                       Mean, Variance, Support) :-
    !,
    pln2_moments(Operation, RawMoments, Mean, Variance),
    (   is_list(Support)
    ->  true
    ;   pln2_refuse(
            Operation,
            pln2_invalid_support(Support),
            "use a proper list of stable ground acyclic evidence IDs")
    ).
pln2_supported_moments(Operation, Raw, _, _, _) :-
    pln2_refuse(
        Operation,
        pln2_invalid_supported_moments(Raw),
        "use (supported (moments MEAN VARIANCE) (ID ...)) with caller-stable evidence IDs").

pln2_validate_support_groups(Operation, Supports, Union) :-
    (   is_list(Supports)
    ->  pln2_support_groups(Supports, Operation, [], Reversed),
        reverse(Reversed, Union)
    ;   pln2_refuse(
            Operation,
            pln2_invalid_support_groups(Supports),
            "use a proper list of support-ID lists")
    ).

pln2_support_groups([], _, Seen, Seen).
pln2_support_groups([Support|Supports], Operation, Seen, Union) :-
    (   is_list(Support)
    ->  pln2_support_ids(Support, Operation, [], Seen, After)
    ;   pln2_refuse(
            Operation,
            pln2_invalid_support(Support),
            "use a proper list of stable ground acyclic evidence IDs for each operand")
    ),
    pln2_support_groups(Supports, Operation, After, Union).

pln2_support_ids([], _, _, Seen, Seen).
pln2_support_ids([Id|Ids], Operation, Local, Seen, Union) :-
    (   ground(Id), acyclic_term(Id)
    ->  true
    ;   pln2_refuse(
            Operation,
            pln2_invalid_support_identity(Id),
            "assign every source a stable ground acyclic evidence ID before combining truth values")
    ),
    (   pln2_same_id(Id, Local)
    ->  pln2_refuse(
            Operation,
            pln2_duplicate_support_identity(Id),
            "list each evidence ID once within an operand support")
    ;   pln2_same_id(Id, Seen)
    ->  pln2_refuse(
            Operation,
            pln2_dependent_supports(Id),
            "factor shared support in an owned reasoner with stable signed evidence IDs, then combine only disjoint residual supports")
    ;   pln2_support_ids(Ids, Operation, [Id|Local], [Id|Seen], Union)
    ).

pln2_same_id(Id, [Seen|_]) :-
    Id == Seen,
    !.
pln2_same_id(Id, [_|Seen]) :-
    pln2_same_id(Id, Seen).

pln2_probability(Operation, Role, Value) :-
    (   pln2_finite_number(Value), Value >= 0, Value =< 1
    ->  true
    ;   pln2_refuse(
            Operation,
            pln2_invalid_probability(Role, Value),
            "use a finite probability between 0 and 1 inclusive")
    ).

pln2_confidence(Operation, Value) :-
    (   pln2_finite_number(Value), Value >= 0, Value < 1
    ->  true
    ;   pln2_refuse(
            Operation,
            pln2_invalid_confidence(Value),
            "use finite 0 <= CONFIDENCE < 1; confidence 1 would require an infinite evidence count")
    ).

pln2_positive(Operation, Role, Value) :-
    (   pln2_finite_number(Value), Value > 0
    ->  true
    ;   pln2_refuse(
            Operation,
            pln2_invalid_positive(Role, Value),
            "use a finite value greater than zero")
    ).

pln2_nonnegative(Operation, Role, Value) :-
    (   pln2_finite_number(Value), Value >= 0
    ->  true
    ;   pln2_refuse(
            Operation,
            pln2_invalid_nonnegative(Role, Value),
            "use a finite value greater than or equal to zero")
    ).

pln2_finite_number(Value) :-
    number(Value),
    (   float(Value)
    ->  float_class(Value, Class),
        Class \== infinite,
        Class \== nan
    ;   true
    ).

pln2_refuse(Operation, Problem, Remedy) :-
    throw(error(Problem, context(Operation, Remedy))).

% Every refusal above carries a remedy, and SWI prints the context half that
% holds it. The FORMAL half needs a clause of its own or SWI answers "Unknown
% error term: pln2_invalid_probability(mean,170)", which shows the caller the
% shape of the complaint instead of the complaint
% [measured 2026-09-05: !(pln2-moments-stv (moments 170 25) 100) answered
% "'pln2-moments-stv'/2: Unknown error term: pln2_invalid_probability(mean,170)"
% through the library's public door].
%
% error_message//1 rather than message//1: SWI dispatches the formal half of an
% error(Formal, Context) pair through this hook, and a message//1 clause for the
% formal is never reached [source: extensions/cmetta/bridge.pl records the same
% measurement for cmetta_operation_failed/2;
% commit=e34e8e386772b582ba24828138056c5d26be28f8].
%
% Each sentence names what was WRONG and leaves what to DO to the remedy the
% throw already carries, so the two halves do not repeat each other.
:- multifile prolog:error_message//1.

prolog:error_message(pln2_invalid_probability(Role, Value)) -->
    [ 'the ~w is ~p, which is not a probability'-[Role, Value] ].
prolog:error_message(pln2_invalid_confidence(Value)) -->
    [ 'the confidence is ~p'-[Value] ].
prolog:error_message(pln2_invalid_positive(Role, Value)) -->
    [ 'the ~w is ~p, which is not a finite positive number'-[Role, Value] ].
prolog:error_message(pln2_invalid_nonnegative(Role, Value)) -->
    [ 'the ~w is ~p, which is not a finite non-negative number'-[Role, Value] ].
prolog:error_message(pln2_invalid_variance(Mean, Variance)) -->
    [ 'a variance of ~p is larger than a mean of ~p allows'-[Variance, Mean] ].
prolog:error_message(pln2_invalid_stv(Raw)) -->
    [ '~p is not a truth value'-[Raw] ].
prolog:error_message(pln2_invalid_beta(Raw)) -->
    [ '~p is not a Beta distribution'-[Raw] ].
prolog:error_message(pln2_invalid_moments(Raw)) -->
    [ '~p is not the moments of a probability-valued random variable'-[Raw] ].
prolog:error_message(pln2_invalid_supported_moments(Raw)) -->
    [ '~p does not carry moments together with the support they rest on'-[Raw] ].
prolog:error_message(pln2_invalid_support(Support)) -->
    [ '~p is not a support list'-[Support] ].
prolog:error_message(pln2_invalid_support_groups(Supports)) -->
    [ '~p is not one support list per operand'-[Supports] ].
prolog:error_message(pln2_invalid_support_identity(Id)) -->
    [ '~p cannot identify a source, because an evidence ID must be ground \c
       and acyclic'-[Id] ].
prolog:error_message(pln2_duplicate_support_identity(Id)) -->
    [ 'the evidence ID ~p appears twice in one operand support'-[Id] ].
prolog:error_message(pln2_dependent_supports(Id)) -->
    [ 'the evidence ID ~p supports more than one operand, so the operands \c
       are not independent and the formula does not apply'-[Id] ].
prolog:error_message(pln2_unidentifiable_concentration(endpoint_mean, Mean)) -->
    [ 'a mean of ~p sits at the end of the range, where no finite Beta \c
       concentration fits'-[Mean] ].
prolog:error_message(pln2_unidentifiable_concentration(zero_variance, Variance)) -->
    [ 'a variance of ~p leaves the Beta concentration unbounded'-[Variance] ].

:- det('pln2-beta-moments'/2).
:- det('pln2-beta-update'/4).
:- det('pln2-confidence-count'/3).
:- det('pln2-count-confidence'/3).
:- det('pln2-stv-moments'/3).
:- det('pln2-moments-stv'/3).
:- det('pln2-require-independent-supports'/2).
:- det('pln2-product-independent'/3).
:- det('pln2-total-probability-independent'/4).
