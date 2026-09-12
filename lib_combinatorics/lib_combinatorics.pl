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
%     commit=afc4024cef7d4b7bcdd194bb030a112187b676d0]
%   - equal partial sums are merged at every prefix and suffix layer, and all
%     marginals are recovered by a forward/backward join rather than by
%     enumerating subsets [tested:
%     weighted_subset:repeated_unit_losses_have_target_bounded_rows;
%     commit=afc4024cef7d4b7bcdd194bb030a112187b676d0]
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
            'weighted-subset-posterior-independent'/3,
            permutations/2,
            subsets/2,
            tuples/2,
            'cartesian-power'/3,
            'range-step'/4,
            factorial/2,
            binomial/3,
            'permutation-count'/3
          ]).

% Guarantees: private helpers and autoload declarations belong to this module.
% [tested: engine_modules; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
% Assumes: engine operations resolve through metta_engine's published exports.
% [source: engine/metta.pl:metta_engine_reexport/2; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
:- set_module(base(metta_engine)).

:- use_module(library(lists), [reverse/2, permutation/2, append/3, nth0/3]).
:- use_module(library(error), [must_be/2, domain_error/2]).

%! permutations(+Items:list, -Permutation:list) is nondet.
%
% Every ordering of the items, one per answer, in the host's own order: the
% items as given first, then the orderings that swap the latest elements. A
% repeated item makes repeated answers, because a permutation counts positions
% and not values. Empty items have exactly one permutation, the empty one.
permutations(Items, Permutation) :-
    must_be(list, Items),
    permutation(Items, Permutation).

%! subsets(+Items:list, -Subset:list) is nondet.
%
% Every subset, one per answer, each keeping the items' own order: the powerset,
% so n items give 2^n answers, starting with the whole set and ending with the
% empty one. A repeated item is a distinct position, so (a a) has four subsets.
subsets([], []).
subsets([Item|Items], Subset) :-
    subsets(Items, Rest),
    ( Subset = [Item|Rest] ; Subset = Rest ).

%! tuples(+Sets:list, -Tuple:list) is nondet.
%
% One element chosen from each set, one tuple per answer: the Cartesian product,
% in the order that varies the LAST set fastest. Any empty set means no answers,
% and no sets at all mean one answer, the empty tuple.
tuples(Sets, Tuple) :-
    must_be(list, Sets),
    tuples_(Sets, Tuple).

tuples_([], []).
tuples_([Set|Sets], [Item|Items]) :-
    must_be(list, Set),
    member(Item, Set),
    tuples_(Sets, Items).

%! 'cartesian-power'(+Items:list, +Length:integer, -Tuple:list) is nondet.
%
% Every tuple of that length over the items, repetition allowed, one per answer:
% the Cartesian power, so k from n items gives n^k answers. Length zero gives
% one answer, the empty tuple, whatever the items are.
'cartesian-power'(Items, Length, Tuple) :-
    must_be(list, Items),
    must_be(nonneg, Length),
    length(Tuple, Length),
    tuples_power(Tuple, Items).

tuples_power([], _).
tuples_power([Item|More], Items) :-
    member(Item, Items),
    tuples_power(More, Items).

%! 'range-step'(+From:number, +To:number, +Step:integer, -Value:number) is nondet.
%
% The numbers from From towards To, one per answer, moving by Step and stopping
% before To, which is excluded as it is in range. A negative step counts down; a
% zero step raises, because it would never arrive. A step that already points
% away from To has no answers.
'range-step'(From, To, Step, Value) :-
    must_be(number, From),
    must_be(number, To),
    must_be(integer, Step),
    (   Step =:= 0
    ->  domain_error(nonzero_step, Step)
    ;   true
    ),
    range_step_(From, To, Step, Value).

range_step_(From, To, Step, Value) :-
    (   Step > 0
    ->  From < To
    ;   From > To
    ),
    (   Value = From
    ;   Next is From + Step,
        range_step_(Next, To, Step, Value)
    ).

%! factorial(+Number:integer, -Result:integer) is det.
%
% The product of 1 through Number, exactly, with 0 giving 1. A negative number
% raises, because the factorial of one is not a whole number.
factorial(Number, Result) :-
    must_be(nonneg, Number),
    factorial_(Number, 1, Result).

factorial_(0, Result, Result) :- !.
factorial_(Number, Accumulator, Result) :-
    Next is Accumulator * Number,
    Smaller is Number - 1,
    factorial_(Smaller, Next, Result).

%! binomial(+Count:integer, +Chosen:integer, -Result:integer) is det.
%
% How many unordered choices of Chosen items there are among Count of them,
% exactly. Choosing more than there are is 0, and choosing none is 1. The
% multiplication runs over the smaller side and divides as it goes, so the
% intermediate values stay near the answer rather than reaching Count factorial.
binomial(Count, Chosen, Result) :-
    must_be(nonneg, Count),
    must_be(integer, Chosen),
    (   ( Chosen < 0 ; Chosen > Count )
    ->  Result = 0
    ;   Other is Count - Chosen,
        ( Chosen =< Other -> Smaller = Chosen ; Smaller = Other ),
        binomial_(1, Smaller, Count, 1, Result)
    ).

binomial_(Step, Smaller, _, Result, Result) :- Step > Smaller, !.
binomial_(Step, Smaller, Count, Accumulator, Result) :-
    Numerator is Count - Smaller + Step,
    Next is Accumulator * Numerator // Step,
    Following is Step + 1,
    binomial_(Following, Smaller, Count, Next, Result).

%! 'permutation-count'(+Count:integer, +Chosen:integer, -Result:integer) is det.
%
% How many ordered choices of Chosen items there are among Count of them,
% exactly: Count falling by one, Chosen times. Choosing more than there are is
% 0, and choosing none is 1.
'permutation-count'(Count, Chosen, Result) :-
    must_be(nonneg, Count),
    must_be(integer, Chosen),
    (   ( Chosen < 0 ; Chosen > Count )
    ->  Result = 0
    ;   falling(Count, Chosen, 1, Result)
    ).

falling(_, 0, Result, Result) :- !.
falling(Count, Chosen, Accumulator, Result) :-
    Next is Accumulator * Count,
    Smaller is Count - 1,
    Fewer is Chosen - 1,
    falling(Smaller, Fewer, Next, Result).

% A probabilistic adder can merge power-set paths reaching the same sum and
% recover marginals with forward/backward passes. This implementation derives
% that recurrence independently and uses sparse exact-integer rows rather than
% the paper's dense floating convolutions.
% [source: https://doi.org/10.1371/journal.pone.0091507; commit=afc4024cef7d4b7bcdd194bb030a112187b676d0]

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
