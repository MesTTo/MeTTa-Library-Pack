% Purpose: compute finite descriptive statistics from exact stored observations.
% Assumes: math-float rounds exact results; fraction_sqrt accepts a nonnegative
% rational and rounds its root, including final IEEE saturation.
% [source: lib/lib_vector/lib_vector.pl:fraction_sqrt/2; commit=84824f5cf870f5cd7ac89d6580093d0459d91a9b].
% Guarantees: algebraic reductions stay exact until final floating conversion,
% and invalid domains raise with the operation's name.
% [tested: lib_statistics, test_statistics_exact_reductions; commit=84824f5cf870f5cd7ac89d6580093d0459d91a9b].
% Owns resources: immutable query-local terms; no streams or mutable state.
% Decides: numeric observations are finite; degrees of freedom is explicit;
% modes use term identity; geometric mean retains native log/exp precision.

:- module(lib_statistics,
          ['stats-sum'/2, 'stats-mean'/2, 'stats-geometric-mean'/2,
           'stats-harmonic-mean'/2, 'stats-median'/2, 'stats-quantile'/4,
           'stats-quantiles'/4, 'stats-mode'/2, 'stats-variance'/3,
           'stats-stdev'/3, 'stats-covariance'/4, 'stats-correlation'/3,
           'stats-ranks'/2, 'stats-regression'/4]).
:- set_module(base(metta_engine)).
:- use_module(library(error), [must_be/2, domain_error/2, representation_error/1]).
:- use_module(library(apply), [maplist/2, maplist/3, foldl/4, foldl/5]).
:- use_module(library(lists), [member/2, memberchk/2, min_list/2, max_list/2]).
:- use_module(library(pairs), [group_pairs_by_key/2, pairs_values/2]).
:- use_module('../lib_math/lib_math', ['math-float'/2]).
:- use_module('../lib_vector/lib_vector', [fraction_sqrt/2]).
:- meta_predicate statistics_operation(+, 0).

%! 'stats-sum'(+Data:list(number), -Total:number) is det.
%
% Sum finite observations exactly before any rounding. Empty input returns 0.
% All integer/rational observations produce an exact result; any float makes
% the result a float rounded once. Every numeric head refuses NaN and infinity.
'stats-sum'(Data, Total) :-
    statistics_operation('stats-sum',
        (numeric_data(Data,Values,Kind),foldl(add,Values,0,Sum),result(Kind,Sum,Total))).

%! 'stats-mean'(+Data:list(number), -Mean:number) is det.
%
% Arithmetic mean of a nonempty finite expression, with stats-sum's exact
% accumulation and result type. A sum may exceed binary64 while its mean fits.
'stats-mean'(Data, Mean) :-
    statistics_operation('stats-mean',
        (numeric_data(Data,Values,Kind),sample_size(Values,0,N),
         foldl(add,Values,0,Sum),exact(Sum rdiv N,Ratio),result(Kind,Ratio,Mean))).

%! 'stats-harmonic-mean'(+Data:list(number), -Mean:number) is det.
%
% N divided by the sum of reciprocals, for nonnegative finite observations.
% A zero makes the mean zero after every observation is validated. Empty or
% negative input raises. Exact inputs retain an exact result.
'stats-harmonic-mean'(Data, Mean) :-
    statistics_operation('stats-harmonic-mean',
        (numeric_data(Data,Values,Kind),sample_size(Values,0,N),
         maplist(nonnegative,Values),
         (memberchk(0,Values) -> Ratio=0
         ; foldl(reciprocal_add,Values,0,Sum),exact(N rdiv Sum,Ratio)),
         result(Kind,Ratio,Mean))).

%! 'stats-geometric-mean'(+Data:list(number), -Mean:number) is det.
%
% Floating geometric mean of nonnegative finite observations. Validate the
% whole expression before returning zero for a zero observation. Empty or
% negative input raises. Sum binary exponents separately from mantissa logs,
% so huge and tiny exact observations can cancel without an overflowing product.
% Native log/exp precision applies; bound the approximation by the observed
% minimum and maximum before final rounding. Equal observations retain their
% rounded value. A result outside binary64 rounds to zero or infinity.
'stats-geometric-mean'(Data, Mean) :-
    statistics_operation('stats-geometric-mean',
        (numeric_data(Data,Values,_),sample_size(Values,0,N),
         maplist(nonnegative,Values),
         (memberchk(0,Values) -> Mean=0.0
         ; geometric_mean(Values,N,Mean)))).

%! 'stats-median'(+Data:list(number), -Median:number) is det.
%
% Middle observation, or the exact mean of the two middle observations. Empty
% input raises. Numeric result types follow stats-sum, including mixed inputs.
'stats-median'(Data, Median) :-
    statistics_operation('stats-median',
        (sorted_data(Data,Pool,N,Kind),Half is 1 rdiv 2,
         quantile(Pool,N,Half,inclusive,Value),result(Kind,Value,Median))).

%! 'stats-quantile'(+Data:list(number), +Probability:number, +Method:atom, -Value:number) is det.
%
% Linearly interpolate sorted observations at Probability in [0,1]. Inclusive
% places the minimum at 0 and maximum at 1. Exclusive places sorted observation i
% at i/(N+1), extrapolating with the nearest endpoint pair outside those positions.
% A singleton returns its observation. Empty input or an unknown method raises.
% Exact observations retain exact interpolation; a float observation rounds once.
'stats-quantile'(Data, Probability, Method, Value) :-
    statistics_operation('stats-quantile',
        (quantile_method(Method),finite_number(Probability,P),
         (P >= 0,P =< 1 -> true ; domain_error(probability,Probability)),
         sorted_data(Data,Pool,N,Kind),quantile(Pool,N,P,Method,Exact),
         result(Kind,Exact,Value))).

%! 'stats-quantiles'(+Data:list(number), +Partitions:integer, +Method:atom, -Cuts:list(number)) is det.
%
% The Partitions-1 cut points at i/Partitions, using stats-quantile's inclusive
% or exclusive interpolation. Partitions must be positive. One partition gives
% empty cuts after validating the nonempty data and method. Sort once, then
% index each pair: O(n log n+k) arithmetic/index operations for k cuts.
'stats-quantiles'(Data, Partitions, Method, Cuts) :-
    statistics_operation('stats-quantiles',
        (must_be(positive_integer,Partitions),quantile_method(Method),
         sorted_data(Data,Pool,N,Kind),Last is Partitions-1,
         findall(Value,
                 (between(1,Last,I),exact(I rdiv Partitions,P),
                  quantile(Pool,N,P,Method,Exact),result(Kind,Exact,Value)),Cuts))).

%! 'stats-mode'(+Data:'Atom', -Mode:any) is nondet.
%
% Every most frequent held term, once, in first-occurrence order. Terms compare
% by identity, so 1 and 1.0 count separately and runnable expressions stay data.
% Collapse collects ties; once selects the first mode. Empty and cyclic data
% raise. Native stable sorting counts occurrences in O(n log n).
'stats-mode'(Data, Mode) :-
    statistics_operation('stats-mode',
        (must_be(list,Data),
         (acyclic_term(Data) -> true ; representation_error(cyclic_statistical_data)),
         sample_size(Data,0,_),indexed(Data,0,Indexed),keysort(Indexed,Sorted),
         group_pairs_by_key(Sorted,Groups),maplist(mode_count,Groups,Counts),
         keysort(Counts,Ordered),Ordered=[key(Maximum,_)-_|_],
         member(key(Maximum,_)-Mode,Ordered))).

%! 'stats-variance'(+Data:list(number), +DegreesOfFreedom:integer, -Variance:number) is det.
%
% Sum of squared deviations divided by N-DegreesOfFreedom. Use 0 for a whole
% population and 1 for the usual sample estimate. DegreesOfFreedom is a
% nonnegative integer and N must exceed it. Exact moments prevent cancellation;
% result types follow stats-sum, with only the final result rounded.
'stats-variance'(Data, DegreesOfFreedom, Variance) :-
    statistics_operation('stats-variance',
        (variance(Data,DegreesOfFreedom,Kind,Exact),result(Kind,Exact,Variance))).

%! 'stats-stdev'(+Data:list(number), +DegreesOfFreedom:integer, -Deviation:number) is det.
%
% Correctly rounded floating square root of the exact variance. The same
% sample-size rules as stats-variance apply. Take the root before rounding,
% so a representable deviation survives an unrepresentable floating variance.
'stats-stdev'(Data, DegreesOfFreedom, Deviation) :-
    statistics_operation('stats-stdev',
        (variance(Data,DegreesOfFreedom,_,Exact),fraction_sqrt(Exact,Deviation))).

%! 'stats-covariance'(+Left:list(number), +Right:list(number), +DegreesOfFreedom:integer, -Covariance:number) is det.
%
% Paired covariance, dividing the sum of centered products by N-DegreesOfFreedom.
% The finite expressions have equal lengths and N must exceed the nonnegative
% integer DegreesOfFreedom. Exact paired moments and final rounding follow
% stats-variance; choose 0 for population covariance or 1 for a sample estimate.
'stats-covariance'(Left, Right, DegreesOfFreedom, Covariance) :-
    statistics_operation('stats-covariance',
        (must_be(nonneg,DegreesOfFreedom),paired_data(Left,Right,A,B,N,Kind),
         enough(N,DegreesOfFreedom),paired_moments(A,B,moments(SX,SY,_,_,XY)),
         exact((N*XY-SX*SY) rdiv (N*(N-DegreesOfFreedom)),Exact),
         result(Kind,Exact,Covariance))).

%! 'stats-correlation'(+Left:list(number), +Right:list(number), -Correlation:number) is det.
%
% Pearson correlation, correctly rounded into [-1,1] from exact paired moments.
% Both finite expressions need equal lengths, at least two observations and
% nonzero variance. Constant input raises. Compose stats-ranks on both inputs
% to obtain Spearman correlation with averaged ties.
'stats-correlation'(Left, Right, Correlation) :-
    statistics_operation('stats-correlation',
        (paired_data(Left,Right,A,B,N,_),enough(N,1),
         paired_moments(A,B,Moments),centered(N,Moments,XX,YY,XY),
         (XX > 0,YY > 0 -> true ; domain_error(nonconstant_observations,Left-Right)),
         exact((XY*XY) rdiv (XX*YY),Ratio),fraction_sqrt(Ratio,Magnitude),
         (XY < 0 -> Correlation is -Magnitude ; Correlation=Magnitude))).

%! 'stats-ranks'(+Data:list(number), -Ranks:list(number)) is det.
%
% One-based numeric ranks in input order. Tied numeric values receive their
% exact mean rank, so 1 and 1.0 tie. Empty input returns empty. Sort/group once,
% then restore original positions in O(n log n); no observation is dropped.
'stats-ranks'(Data, Ranks) :-
    statistics_operation('stats-ranks',
        (numeric_data(Data,Values,_),indexed(Values,0,Indexed),keysort(Indexed,Sorted),
         group_pairs_by_key(Sorted,Groups),rank_groups(Groups,0,Ranked,[]),
         keysort(Ranked,Ordered),pairs_values(Ordered,Ranks))).

%! 'stats-regression'(+Independent:list(number), +Dependent:list(number), +Proportional:boolean, -Fit:list) is det.
%
% Least-squares (linear-fit Slope Intercept) from finite paired observations.
% False fits an affine line and needs at least two observations with nonconstant
% x. True fits through the origin and needs at least one observation with nonzero
% sum of squared x values. Lengths match. Coefficients use exact moments and
% retain exact results unless either expression contains a float.
'stats-regression'(Independent, Dependent, Proportional, Fit) :-
    statistics_operation('stats-regression',
        (must_be(boolean,Proportional),
         paired_data(Independent,Dependent,A,B,N,Kind),
         (Proportional == true -> enough(N,0) ; enough(N,1)),
         paired_moments(A,B,Moments),Moments=moments(SX,SY,QX,_,QXY),
         (Proportional == true -> XX=QX,XY=QXY
         ; centered(N,Moments,XX,_,XY)),
         (XX > 0 -> true ; domain_error(identifiable_regression,Independent)),
         exact(XY rdiv XX,Slope),
         (Proportional == true -> Intercept=0
         ; exact((SY-Slope*SX) rdiv N,Intercept)),
         result(Kind,Slope,RS),result(Kind,Intercept,RI),Fit=['linear-fit',RS,RI])).

numeric_data(Data, Values, Kind) :-
    must_be(list(number),Data),maplist(finite_number,Data,Values),
    (member(Value,Data),float(Value) -> Kind=float ; Kind=exact).

finite_number(Value, Exact) :-
    must_be(number,Value),
    (rational(Value) -> Exact=Value
    ; float_class(Value,Class),
      ((Class == infinite ; Class == nan) -> domain_error(finite_observation,Value)
      ; exact(rational(Value),Exact))).

exact(Expression, Value) :-
    Value is Expression,
    (rational(Value) -> true ; representation_error(exact_statistics_arithmetic)).

result(Kind, Exact, Value) :-
    (Kind == float -> 'math-float'(Exact,Value) ; Value=Exact).
nonnegative(Value) :- (Value >= 0 -> true ; domain_error(nonnegative_observation,Value)).
add(Value, Acc, Sum) :- exact(Acc+Value,Sum).
reciprocal_add(Value, Acc, Sum) :- exact(Acc+(1 rdiv Value),Sum).
sample_size(Values, D, N) :- length(Values,N),enough(N,D).
enough(N, D) :- (N > D -> true ; domain_error(statistical_sample_size,N-D)).

% CPython's exact moment reduction, extended to paired cross products below.
% https://github.com/python/cpython/blob/ebf955df7a89ed0c7968f79faec1de49f61ed7cb/Lib/statistics.py#L1501-L1545
variance(Data, D, Kind, Variance) :-
    must_be(nonneg,D),numeric_data(Data,Values,Kind),sample_size(Values,D,N),
    foldl(moment,Values,0-0,Sum-Squares),
    exact((N*Squares-Sum*Sum) rdiv (N*(N-D)),Variance).
moment(X, S-Q, Sum-Squares) :- exact(S+X,Sum),exact(Q+X*X,Squares).

paired_data(Left, Right, A, B, N, Kind) :-
    numeric_data(Left,A,AK),numeric_data(Right,B,BK),length(A,N),length(B,M),
    (N =:= M -> true ; domain_error(paired_observation_lengths,N-M)),
    ((AK == float ; BK == float) -> Kind=float ; Kind=exact).
paired_moments(A, B, Moments) :- foldl(paired_moment,A,B,moments(0,0,0,0,0),Moments).
paired_moment(X, Y, moments(A,B,C,D,E), moments(SX,SY,XX,YY,XY)) :-
    exact(A+X,SX),exact(B+Y,SY),exact(C+X*X,XX),exact(D+Y*Y,YY),exact(E+X*Y,XY).
centered(N, moments(SX,SY,QX,QY,QXY), XX, YY, XY) :-
    exact(N*QX-SX*SX,XX),exact(N*QY-SY*SY,YY),exact(N*QXY-SX*SY,XY).

% Interpolation follows CPython quantiles, retaining exact stored observations.
% https://github.com/python/cpython/blob/ebf955df7a89ed0c7968f79faec1de49f61ed7cb/Lib/statistics.py#L1165-L1218
quantile_method(Method) :-
    must_be(atom,Method),
    (memberchk(Method,[inclusive,exclusive]) -> true
    ; domain_error(quantile_method,Method)).
sorted_data(Data, Pool, N, Kind) :-
    numeric_data(Data,Values,Kind),sample_size(Values,0,N),msort(Values,Sorted),
    Pool=..[observations|Sorted].
quantile(Pool, N, P, Method, Value) :-
    (N =:= 1 -> arg(1,Pool,Value)
    ; (Method == inclusive -> exact(P*(N-1),Position),J is min(floor(Position),N-2)
      ; exact(P*(N+1)-1,Position),J is max(0,min(floor(Position),N-2))),
      exact(Position-J,Delta),AIndex is J+1,BIndex is J+2,
      arg(AIndex,Pool,A),arg(BIndex,Pool,B),exact(A*(1-Delta)+B*Delta,Value)).

indexed([], _, []).
indexed([Value|Rest], I, [Value-I|Indexed]) :- J is I+1,indexed(Rest,J,Indexed).
mode_count(Value-[First|Rest], key(Negative,First)-Value) :-
    length(Rest,N),Negative is -N-1.
rank_groups([], _, Tail, Tail).
rank_groups([_-Positions|Rest], Before, Ranked, Tail) :-
    length(Positions,Count),exact((2*Before+Count+1) rdiv 2,Rank),
    rank_positions(Positions,Rank,Ranked,More),After is Before+Count,
    rank_groups(Rest,After,More,Tail).
rank_positions([], _, Tail, Tail).
rank_positions([I|Rest], Rank, [I-Rank|Pairs], Tail) :- rank_positions(Rest,Rank,Pairs,Tail).

% Average logarithms as in CPython geometric_mean; separate binary exponents
% before log/exp so exponent cancellation remains exact over all magnitudes.
% https://github.com/python/cpython/blob/ebf955df7a89ed0c7968f79faec1de49f61ed7cb/Lib/statistics.py#L224-L261
geometric_mean(Values, N, Mean) :-
    foldl(log_parts,Values,0-0,Exponent-Logs),
    Q is Exponent div N,R is Exponent-Q*N,
    exact((Logs+R*rational(log(2))) rdiv N,Log),
    'math-float'(Log,L),Power is rational(exp(L)),scale_binary(Power,Q,Approx),
    min_list(Values,Low),max_list(Values,High),Bound is max(Low,min(High,Approx)),
    'math-float'(Bound,Mean).
log_parts(Value, E0-L0, E-L) :-
    Shift is msb(numerator(Value))-msb(denominator(Value)),Inverse is -Shift,
    scale_binary(Value,Inverse,M),'math-float'(M,F),E is E0+Shift,
    exact(L0+rational(log(F)),L).
scale_binary(Value, Exponent, Scaled) :-
    (Exponent >= 0 -> exact(Value*(1<<Exponent),Scaled)
    ; exact(Value rdiv (1<< -Exponent),Scaled)).

statistics_operation(Name, Goal) :-
    catch(Goal,Error,rethrow_metta_operation_error(Name,Error)).

:- det('stats-sum'/2).
:- det('stats-mean'/2).
:- det('stats-harmonic-mean'/2).
:- det('stats-geometric-mean'/2).
:- det('stats-median'/2).
:- det('stats-quantile'/4).
:- det('stats-quantiles'/4).
:- det('stats-variance'/3).
:- det('stats-stdev'/3).
:- det('stats-covariance'/4).
:- det('stats-correlation'/3).
:- det('stats-ranks'/2).
:- det('stats-regression'/4).
