% Purpose: compute exact mass and all posterior marginals for independent
%   Bernoulli candidates conditioned on a nonnegative integer additive target.
% Assumes:
%   - each candidate is (candidate ID LOSS (ratio NUMERATOR DENOMINATOR)); ID
%     is a distinct ground acyclic term, LOSS is a nonnegative integer, and the
%     ratio is an exact probability
%   - callers with fixed-point losses choose one shared integer scale before
%     calling; floating sums are deliberately outside this operation
% Guarantees:
%   - outputs preserve input order and contain only reduced exact ratios with
%     positive denominators [tested: test_weighted_subset_matches_exhaustive,
%     weighted_subset:equivalent_input_ratios_are_canonical;
%     commit=6471fbad35eced5ed6440ebf2c25a053b20221f3]
%   - equal partial sums are merged at every prefix and suffix layer, and all
%     marginals are recovered by a forward/backward join rather than by
%     enumerating subsets [tested:
%     weighted_subset:repeated_unit_losses_have_target_bounded_rows;
%     commit=6471fbad35eced5ed6440ebf2c25a053b20221f3]
% Fails when:
%   - an input violates the identity, integer-lattice, or exact-ratio contract
%   - posterior conditioning has zero mass; the refusal names
%     weighted-subset-mass-independent as the operation that still reports
%     reachability
% Decides:
%   - exact term identity (==), not unification or numeric equality, identifies
%     candidates; 1 and 1.0 are therefore different IDs
%   - the row state is private and target-truncated; exhaustive configurations
%     remain the separate chooseK family in lib_combinatorics.metta


:- module(lib_combinatorics,
          [ 'weighted-subset-mass-independent'/3,
            'weighted-subset-posterior-independent'/3
          ]).

% Guarantees: private helpers and autoload declarations belong to this module.
% [tested: engine_modules; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
% Assumes: engine operations resolve through metta_engine's published exports.
% [source: engine/metta.pl:metta_engine_reexport/2; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
:- set_module(base(metta_engine)).

:- use_module(library(lists), [reverse/2, append/3]).

%! 'weighted-subset-mass-independent'(+Candidates:list, +Target:integer, -Ratio:list) is det.
%
% The exact probability that the losses of the independently chosen candidates
% add up to Target, as the reduced (ratio Numerator Denominator). Each candidate
% is (candidate Id Loss (ratio Numerator Denominator)) with a nonnegative
% integer loss, and equal partial sums are merged at every layer rather than
% enumerated, so the work is bounded by the target and not by 2^n. A target that
% cannot be reached has mass (ratio 0 1).
'weighted-subset-mass-independent'(RawCandidates, Target, Ratio) :-
    weighted_subset_validate('weighted-subset-mass-independent'/2,
                             RawCandidates, Target, Candidates, Denominator),
    weighted_subset_final_row(Candidates, Target, Row),
    weighted_subset_row_weight(Row, Target, Weight),
    weighted_subset_ratio(Weight, Denominator, Ratio),
    !.

%! 'weighted-subset-posterior-independent'(+Candidates:list, +Target:integer, -Posterior:list) is det.
%
% The observation's own mass and every candidate's posterior probability of
% having been chosen given that the losses add up to Target, as
% (subset-posterior Mass ((candidate-posterior Id Ratio) ...)) in the candidates'
% own order. The marginals come from one forward and one backward pass rather
% than from enumerating subsets. Conditioning on a target of zero mass refuses
% and names weighted-subset-mass-independent as the operation that still reports
% reachability.
'weighted-subset-posterior-independent'(RawCandidates, Target, Result) :-
    Operation = 'weighted-subset-posterior-independent'/2,
    weighted_subset_validate(Operation, RawCandidates, Target,
                             Candidates, Denominator),
    weighted_subset_prefix_rows(Candidates, Target, PrefixRows),
    reverse(Candidates, ReversedCandidates),
    weighted_subset_prefix_rows(ReversedCandidates, Target,
                                ReversedSuffixRows),
    append(PrefixBefore, [FinalRow], PrefixRows),
    append(SuffixRowsReversed, [_AllCandidates], ReversedSuffixRows),
    reverse(SuffixRowsReversed, SuffixAfter),
    weighted_subset_row_weight(FinalRow, Target, ObservationWeight),
    (   ObservationWeight =:= 0
    ->  weighted_subset_refuse(
            Operation,
            weighted_subset_zero_mass(Target),
            "conditioning on a zero-mass observation is undefined; use weighted-subset-mass-independent to inspect reachability")
    ;   weighted_subset_ratio(ObservationWeight, Denominator, Mass),
        weighted_subset_marginals(Candidates, PrefixBefore, SuffixAfter,
                                  Target, ObservationWeight, Marginals),
        Result = ['subset-posterior', Mass, Marginals]
    ),
    !.

weighted_subset_validate(Operation, RawCandidates, Target,
                         Candidates, Denominator) :-
    (   integer(Target), Target >= 0
    ->  true
    ;   weighted_subset_refuse(
            Operation,
            weighted_subset_invalid_target(Target),
            "use a nonnegative integer target; fixed-point callers must choose one shared integer scale")
    ),
    (   is_list(RawCandidates)
    ->  weighted_subset_candidates(RawCandidates, Operation, [], Candidates,
                                   Denominator)
    ;   weighted_subset_refuse(
            Operation,
            weighted_subset_invalid_candidates(RawCandidates),
            "use a proper list of (candidate ID LOSS (ratio NUMERATOR DENOMINATOR)) rows")
    ).

weighted_subset_candidates([], _, _, [], 1).
weighted_subset_candidates([Raw|Raws], Operation, Seen,
                           [Candidate|Candidates], Denominator) :-
    weighted_subset_candidate(Raw, Operation, Seen, Candidate, Id,
                              CandidateDenominator),
    weighted_subset_candidates(Raws, Operation, [Id|Seen], Candidates,
                               RestDenominator),
    Denominator is CandidateDenominator * RestDenominator.

weighted_subset_candidate([candidate, Id, Loss, [ratio, Numerator, Denominator]],
                          Operation, Seen,
                          ws_candidate(Id, Loss, CanonicalNumerator,
                                       CanonicalDenominator),
                          Id, CanonicalDenominator) :-
    !,
    (   ground(Id), acyclic_term(Id)
    ->  true
    ;   weighted_subset_refuse(
            Operation,
            weighted_subset_invalid_identity(Id),
            "assign each independent Bernoulli event a distinct ground acyclic ID")
    ),
    (   weighted_subset_same_id(Id, Seen)
    ->  weighted_subset_refuse(
            Operation,
            weighted_subset_duplicate_identity(Id),
            "assign each independent Bernoulli event a distinct ground ID")
    ;   true
    ),
    (   integer(Loss), Loss >= 0
    ->  true
    ;   weighted_subset_refuse(
            Operation,
            weighted_subset_invalid_loss(Id, Loss),
            "use a nonnegative integer loss; fixed-point callers must choose one shared integer scale")
    ),
    (   integer(Numerator), integer(Denominator),
        Denominator > 0, Numerator >= 0, Numerator =< Denominator
    ->  Divisor is gcd(Numerator, Denominator),
        CanonicalNumerator is Numerator // Divisor,
        CanonicalDenominator is Denominator // Divisor
    ;   weighted_subset_refuse(
            Operation,
            weighted_subset_invalid_prior(Id, [ratio, Numerator, Denominator]),
            "use an exact (ratio NUMERATOR DENOMINATOR) with integer 0 <= NUMERATOR <= DENOMINATOR and DENOMINATOR > 0")
    ).
weighted_subset_candidate(Raw, Operation, _, _, _, _) :-
    weighted_subset_refuse(
        Operation,
        weighted_subset_invalid_candidate(Raw),
        "use (candidate ID LOSS (ratio NUMERATOR DENOMINATOR)) for every row").

weighted_subset_same_id(Id, [Seen|_]) :-
    Id == Seen,
    !.
weighted_subset_same_id(Id, [_|Seen]) :-
    weighted_subset_same_id(Id, Seen).

weighted_subset_final_row(Candidates, Target, Row) :-
    weighted_subset_final_row(Candidates, Target, [cell(0, 1)], Row).

weighted_subset_final_row([], _, Row, Row).
weighted_subset_final_row([Candidate|Candidates], Target, Before, Row) :-
    weighted_subset_step(Target, Candidate, Before, After),
    weighted_subset_final_row(Candidates, Target, After, Row).

weighted_subset_prefix_rows(Candidates, Target, Rows) :-
    weighted_subset_prefix_rows(Candidates, Target, [cell(0, 1)], Rows).

weighted_subset_prefix_rows([], _, Row, [Row]).
weighted_subset_prefix_rows([Candidate|Candidates], Target, Before,
                            [Before|Rows]) :-
    weighted_subset_step(Target, Candidate, Before, After),
    weighted_subset_prefix_rows(Candidates, Target, After, Rows).

weighted_subset_step(Target, ws_candidate(_, Loss, Selected, Denominator),
                     Before, After) :-
    Unselected is Denominator - Selected,
    weighted_subset_scale_shift(Before, Unselected, 0, Target, AbsentRow),
    weighted_subset_scale_shift(Before, Selected, Loss, Target, PresentRow),
    weighted_subset_merge_rows(AbsentRow, PresentRow, After).

weighted_subset_scale_shift(_, 0, _, _, []) :-
    !.
weighted_subset_scale_shift([], _, _, _, []).
weighted_subset_scale_shift([cell(Sum, Weight)|Cells], Factor, Shift, Target,
                            Shifted) :-
    ShiftedSum is Sum + Shift,
    (   ShiftedSum > Target
    ->  Shifted = []
    ;   ShiftedWeight is Weight * Factor,
        Shifted = [cell(ShiftedSum, ShiftedWeight)|Rest],
        weighted_subset_scale_shift(Cells, Factor, Shift, Target, Rest)
    ).

weighted_subset_merge_rows([], Right, Right) :-
    !.
weighted_subset_merge_rows(Left, [], Left) :-
    !.
weighted_subset_merge_rows([cell(LeftSum, LeftWeight)|Left],
                           [cell(RightSum, RightWeight)|Right], Merged) :-
    compare(Order, LeftSum, RightSum),
    weighted_subset_merge_order(Order,
                                cell(LeftSum, LeftWeight), Left,
                                cell(RightSum, RightWeight), Right, Merged).

weighted_subset_merge_order(<, LeftCell, Left, RightCell, Right,
                            [LeftCell|Merged]) :-
    weighted_subset_merge_rows(Left, [RightCell|Right], Merged).
weighted_subset_merge_order(>, LeftCell, Left, RightCell, Right,
                            [RightCell|Merged]) :-
    weighted_subset_merge_rows([LeftCell|Left], Right, Merged).
weighted_subset_merge_order(=, cell(Sum, LeftWeight), Left,
                            cell(Sum, RightWeight), Right,
                            [cell(Sum, Weight)|Merged]) :-
    Weight is LeftWeight + RightWeight,
    weighted_subset_merge_rows(Left, Right, Merged).

weighted_subset_row_weight([], _, 0).
weighted_subset_row_weight([cell(Sum, Weight)|Cells], Target, Found) :-
    compare(Order, Sum, Target),
    weighted_subset_row_weight_order(Order, Weight, Cells, Target, Found).

weighted_subset_row_weight_order(=, Weight, _, _, Weight).
weighted_subset_row_weight_order(>, _, _, _, 0).
weighted_subset_row_weight_order(<, _, Cells, Target, Weight) :-
    weighted_subset_row_weight(Cells, Target, Weight).

weighted_subset_marginals([], [], [], _, _, []).
weighted_subset_marginals([ws_candidate(Id, Loss, Selected, _)|Candidates],
                          [Prefix|Prefixes], [Suffix|Suffixes], Target,
                          ObservationWeight,
                          [['candidate-posterior', Id, Ratio]|Marginals]) :-
    RemainingTarget is Target - Loss,
    (   RemainingTarget < 0
    ->  JointWeight = 0
    ;   weighted_subset_convolution_at(Prefix, Suffix, RemainingTarget,
                                       OtherWeight),
        JointWeight is Selected * OtherWeight
    ),
    weighted_subset_ratio(JointWeight, ObservationWeight, Ratio),
    weighted_subset_marginals(Candidates, Prefixes, Suffixes, Target,
                              ObservationWeight, Marginals).

weighted_subset_convolution_at(LeftAscending, RightAscending, Target, Weight) :-
    reverse(RightAscending, RightDescending),
    weighted_subset_convolution(LeftAscending, RightDescending, Target, 0,
                                Weight).

weighted_subset_convolution([], _, _, Weight, Weight) :-
    !.
weighted_subset_convolution(_, [], _, Weight, Weight) :-
    !.
weighted_subset_convolution([cell(LeftSum, LeftWeight)|Left],
                            [cell(RightSum, RightWeight)|Right], Target,
                            Accumulator, Weight) :-
    Sum is LeftSum + RightSum,
    compare(Order, Sum, Target),
    weighted_subset_convolution_order(
        Order, LeftSum, LeftWeight, Left, RightSum, RightWeight, Right, Target,
        Accumulator, Weight).

weighted_subset_convolution_order(<, _, _, Left, RightSum, RightWeight, Right,
                                  Target, Accumulator, Weight) :-
    weighted_subset_convolution(Left, [cell(RightSum, RightWeight)|Right],
                                Target, Accumulator, Weight).
weighted_subset_convolution_order(>, LeftSum, LeftWeight, Left, _, _, Right,
                                  Target, Accumulator, Weight) :-
    weighted_subset_convolution([cell(LeftSum, LeftWeight)|Left], Right,
                                Target, Accumulator, Weight).
weighted_subset_convolution_order(=, _, LeftWeight, Left, _, RightWeight,
                                  Right, Target, Accumulator, Weight) :-
    Next is Accumulator + LeftWeight * RightWeight,
    weighted_subset_convolution(Left, Right, Target, Next, Weight).

weighted_subset_ratio(0, _, [ratio, 0, 1]) :-
    !.
weighted_subset_ratio(Numerator, Denominator,
                      [ratio, ReducedNumerator, ReducedDenominator]) :-
    Divisor is gcd(Numerator, Denominator),
    ReducedNumerator is Numerator // Divisor,
    ReducedDenominator is Denominator // Divisor.

weighted_subset_refuse(Operation, Problem, Remedy) :-
    throw(error(Problem, context(Operation, Remedy))).

:- det('weighted-subset-mass-independent'/3).
:- det('weighted-subset-posterior-independent'/3).
