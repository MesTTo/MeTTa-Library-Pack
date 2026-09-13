% Purpose: compute numeric vectors and share their exact fractional square root.
% Assumes: SWI-Prolog has unbounded integers and rational arithmetic.
% [source: lib/lib_vector/lib_vector.pl:require_exact_runtime/0; commit=615e8a68dce996a0c05b3ddddc71b80bc598442d].
% Guarantees: complete numeric inputs are validated, finite reductions round
% only their final result, and named errors retain their formal terms.
% [tested: lib_vector_surface, test_vector_exact_reductions; commit=615e8a68dce996a0c05b3ddddc71b80bc598442d].
% Owns resources: random construction consumes the caller thread's existing
% generator; numeric results and temporaries require no explicit release.
% [tested: lib_vector_surface:random_draw_order_and_state; commit=615e8a68dce996a0c05b3ddddc71b80bc598442d].
% Decides: exact scalar inputs stay exact, floating scalar inputs round once,
% zero directions retain IEEE NaNs, and negative random counts draw nothing.
% [tested: lib_vector_surface, test_vector_ieee_arithmetic; commit=615e8a68dce996a0c05b3ddddc71b80bc598442d].
% Guarantees: native effect declarations describe numeric kernels as structural;
% random-normal-vector alone consumes the seed-controlled generator.
% [tested: test_sample_program_recordings_replay_through_the_core_seed; commit=WORKTREE].

:- module(lib_vector,
          [dot/3, norm/2, cosine/3, 'cosine-of-normalized'/3,
           'random-normal-vector'/2, 'random-normal-vector'/3,
           'vector-add'/3, 'vector-subtract'/3, 'vector-multiply'/3,
           'vector-divide'/3, 'vector-scale'/3, 'vector-normalize'/2,
           'vector-distance'/3, 'vector-fill'/3, fraction_sqrt/2]).
:- set_module(base(metta_engine)).
:- use_module(library(error), [must_be/2, domain_error/2, representation_error/1]).
:- use_module(library(apply), [maplist/2, maplist/3, maplist/4, foldl/4, foldl/5]).
:- use_module(library(random), [random/1]).
:- meta_predicate operation(+, 0).

:- multifile seam:extension_builtin/2, seam:seeded_operation/1.
seam:extension_builtin(dot, pureStructural).
seam:extension_builtin(norm, pureStructural).
seam:extension_builtin(cosine, pureStructural).
seam:extension_builtin('cosine-of-normalized', pureStructural).
seam:extension_builtin('vector-add', pureStructural).
seam:extension_builtin('vector-subtract', pureStructural).
seam:extension_builtin('vector-multiply', pureStructural).
seam:extension_builtin('vector-divide', pureStructural).
seam:extension_builtin('vector-scale', pureStructural).
seam:extension_builtin('vector-normalize', pureStructural).
seam:extension_builtin('vector-distance', pureStructural).
seam:extension_builtin('vector-fill', pureStructural).
seam:extension_builtin('random-normal-vector', oracleIO).
seam:seeded_operation('random-normal-vector').

require_exact_runtime :-
    ( current_prolog_flag(bounded, false), current_prolog_flag(rationals, true)
    -> true
    ; throw(error(vector_exact_arithmetic_unavailable,
                  context(lib_vector, 'install SWI-Prolog built with GMP rational arithmetic'))) ).

%! dot(+Left:list(number), +Right:list(number), -Product:number) is det.
%
% Return the dot product as a float. Accumulate exact finite products before
% one rounding; preserve IEEE infinities and NaNs. Empty inputs return 0.0.
% Both complete numeric expressions must have the same dimension.
dot(Left, Right, Product) :- operation(dot, dot_value(Left, Right, Product)).

%! norm(+Vector:list(number), -Length:number) is det.
%
% Return the correctly rounded Euclidean length of a numeric expression.
% Exact squared sums avoid intermediate overflow and underflow. Empty inputs
% return 0.0; NaN propagates and infinity without NaN returns infinity.
norm(Vector, Length) :-
    operation(norm, (vector_input(Vector), squared_sum(Vector, Sum), root(Sum, Length))).

%! cosine(+Left:list(number), +Right:list(number), -Similarity:number) is det.
%
% Return the cosine similarity of equal-dimensional numeric expressions.
% Compute the exact finite ratio before rounding, even if a norm would
% overflow or underflow. Zero or nonfinite vectors produce NaN.
cosine(Left, Right, Similarity) :-
    operation(cosine,
        ( vector_pair(Left, Right),
          foldl(moments, Left, Right, moments(0,0,0), moments(Dot,A2,B2)),
          cosine_value(Dot, A2, B2, Similarity) )).

%! 'cosine-of-normalized'(+Left:list(number), +Right:list(number), -Product:number) is det.
%
% Return dot without checking normalization. This is cosine only when both
% inputs are unit vectors; for example (3 4) with itself still returns 25.0.
'cosine-of-normalized'(Left, Right, Product) :-
    operation('cosine-of-normalized', dot_value(Left, Right, Product)).

%! 'vector-add'(+Left:list(number), +Right:list(number), -Vector:list(number)) is det.
%
% Add equal-dimensional numeric expressions component by component. Exact
% operands stay exact; a floating operand makes that result a float rounded
% once. Preserve IEEE signed zeros, infinities and NaNs.
'vector-add'(Left, Right, Vector) :-
    operation('vector-add', elementwise(+, Left, Right, Vector)).

%! 'vector-subtract'(+Left:list(number), +Right:list(number), -Vector:list(number)) is det.
%
% Subtract Right from Left component by component, with vector-add's exact,
% floating and dimension rules.
'vector-subtract'(Left, Right, Vector) :-
    operation('vector-subtract', elementwise(-, Left, Right, Vector)).

%! 'vector-multiply'(+Left:list(number), +Right:list(number), -Vector:list(number)) is det.
%
% Multiply corresponding components, with vector-add's exact, floating and
% dimension rules. Use dot to sum the exact products before rounding.
'vector-multiply'(Left, Right, Vector) :-
    operation('vector-multiply', elementwise(*, Left, Right, Vector)).

%! 'vector-divide'(+Left:list(number), +Right:list(number), -Vector:list(number)) is det.
%
% Divide corresponding components. Exact operands return exact rationals;
% an exact zero divisor raises for the whole operation. A floating operand
% selects rounded floating results and IEEE zero division. Dimensions match.
'vector-divide'(Left, Right, Vector) :-
    operation('vector-divide', elementwise(/, Left, Right, Vector)).

%! 'vector-scale'(+Vector:list(number), +Factor:number, -Scaled:list(number)) is det.
%
% Multiply every component by Factor, with vector-multiply's number rules.
% Validate Factor even when the vector is empty.
'vector-scale'(Vector, Factor, Scaled) :-
    operation('vector-scale',
        ( vector_input(Vector), must_be(number, Factor),
          maplist(scalar(*, Factor), Vector, Scaled) )).

%! 'vector-normalize'(+Vector:list(number), -Unit:list(number)) is det.
%
% Return floating coordinates in the same direction with unit length,
% rounding each exact finite ratio once. Keep direction when a rounded norm
% would overflow or underflow. Empty stays empty; zero vectors yield NaNs.
% An infinite norm maps finite coordinates to signed zero and infinities to
% NaN; a NaN norm yields NaNs. Signed zero coordinates keep their signs.
'vector-normalize'(Vector, Unit) :-
    operation('vector-normalize', (vector_input(Vector), normalize(Vector, Unit))).

%! 'vector-distance'(+Left:list(number), +Right:list(number), -Distance:number) is det.
%
% Return the correctly rounded Euclidean distance of equal-dimensional
% numeric expressions. Subtract and sum squared differences exactly before
% the final root; preserve IEEE infinity and NaN behavior. Empty returns 0.0.
'vector-distance'(Left, Right, Distance) :-
    operation('vector-distance',
        ( vector_pair(Left, Right), foldl(distance_step, Left, Right, 0, Sum),
          root(Sum, Distance) )).

%! 'vector-fill'(+Count:integer, +Value:number, -Vector:list(number)) is det.
%
% Construct Count copies of Value. Count must be a nonnegative integer and
% Value a Number, including when Count is zero. Preserve its numeric type.
'vector-fill'(Count, Value, Vector) :-
    operation('vector-fill',
        ( must_be(nonneg, Count), must_be(number, Value),
          length(Vector, Count), maplist(=(Value), Vector) )).

%! 'random-normal-vector'(+Count:integer, -Vector:list(number)) is det.
%! 'random-normal-vector'(+Count:integer, +Accumulator:list(number), -Vector:list(number)) is det.
%
% Prepend Count independent uniform draws in (0,1) to Accumulator, then
% normalize the whole expression. The default accumulator is empty; negative
% integer counts draw nothing. Validate before drawing. Use the caller
% thread's generator, including with-seed. With no accumulator this projects
% the positive cube: it is neither Gaussian nor a uniform spherical direction.
'random-normal-vector'(Count, Vector) :- 'random-normal-vector'(Count, [], Vector).
'random-normal-vector'(Count, Accumulator, Vector) :-
    operation('random-normal-vector',
        ( must_be(integer, Count), vector_input(Accumulator),
          random_prepend(Count, Accumulator, Values), normalize(Values, Vector) )).

operation(Name, Goal) :-
    catch((require_exact_runtime, Goal), Error, rethrow_metta_operation_error(Name, Error)).

vector_input(Vector) :- must_be(list(number), Vector).
vector_pair(Left, Right) :-
    vector_input(Left), vector_input(Right), length(Left, A), length(Right, B),
    ( A =:= B -> true ; domain_error(vector_dimensions, [A,B]) ).

elementwise(Op, Left, Right, Vector) :-
    vector_pair(Left, Right), maplist(scalar(Op), Left, Right, Vector).

exact_result(Result) :-
    ( rational(Result) -> true ; representation_error(exact_vector_arithmetic) ).

exact(Value, Exact) :-
    ( rational(Value) -> Exact = Value
    ; float_class(Value, Class),
      ( (Class == infinite ; Class == nan) -> Exact = Value
      ; Exact is rational(Value), exact_result(Exact) ) ).

% Finite magnitudes do not affect an IEEE operation with a nonfinite input.
% Keep their sign and distinguish zero; huge exact values must stay finite.
proxy_value(Value, Proxy) :-
    ( float(Value), float_class(Value, Class),
      (Class == infinite ; Class == nan ; Class == zero)
    -> Proxy = Value
    ; Value =:= 0 -> Proxy = 0.0
    ; Proxy is copysign(1.0, Value) ).

proxy(Op, Left, Right, Out) :-
    proxy_value(Left, A), proxy_value(Right, B),
    % Workaround: swi-infinite-division-zero-sign - multiply by the exact proxy reciprocal.
    % This domain contains only signed units, zeros, infinities and NaNs.
    ( Op == (/) -> Expression = A*(1.0/B)
    ; Expression =.. [Op,A,B] ),
    ieee(Op, Expression, Out).

ieee(Op, Expression, Out) :-
    catch(Out is Expression, Error, metta_saturating_recover(Op, Expression, Out, Error)).

exact_binary(Op, Left, Right, Out) :-
    exact(Left, A), exact(Right, B),
    ( rational(A), rational(B), (Op \== (/) ; B =\= 0)
    -> (Op == (/) -> Functor = rdiv ; Functor = Op),
       Expression =.. [Functor,A,B], Out is Expression, exact_result(Out)
    ; proxy(Op, Left, Right, Out) ).

scalar(Op, Left, Right, Out) :-
    ( Op == (/), rational(Left), rational(Right), Right =:= 0
    -> throw(error(evaluation_error(zero_divisor), _))
    ; true ),
    exact_binary(Op, Left, Right, Exact),
    ( rational(Exact), (float(Left) ; float(Right))
    -> ( Exact =:= 0 -> proxy(Op, Left, Right, Out) ; rounded(Exact, Out) )
    ; Out = Exact ).

dot_value(Left, Right, Product) :-
    vector_pair(Left, Right), foldl(dot_step, Left, Right, 0, Sum), round_result(Sum, Product).

dot_step(Left, Right, Acc, Out) :-
    exact(Left, A), exact(Right, B), product_add(A, B, Acc, Out).

product_add(A, B, Acc, Out) :-
    ( rational(A), rational(B), rational(Acc)
    -> Out is Acc+A*B, exact_result(Out)
    ; proxy_value(Acc, S), proxy_value(A, X), proxy_value(B, Y),
      ieee(dot, S+X*Y, Out) ).

squared_sum(Vector, Sum) :- foldl(square_step, Vector, 0, Sum).
square_step(Value, Acc, Out) :- exact(Value, X), product_add(X, X, Acc, Out).

moments(Left, Right, moments(D0,A0,B0), moments(D,A2,B2)) :-
    exact(Left, A), exact(Right, B),
    product_add(A, B, D0, D), product_add(A, A, A0, A2), product_add(B, B, B0, B2).

distance_step(Left, Right, Acc, Out) :-
    exact_binary(-, Left, Right, Delta), product_add(Delta, Delta, Acc, Out).

cosine_value(Dot, A2, B2, Similarity) :-
    ( rational(Dot), rational(A2), rational(B2), A2 > 0, B2 > 0
    -> Numerator is Dot*Dot, exact_result(Numerator),
       Denominator is A2*B2, exact_result(Denominator),
       Ratio is Numerator rdiv Denominator, exact_result(Ratio),
       fraction_sqrt(Ratio, Magnitude), Similarity is copysign(Magnitude, Dot)
    ; Similarity = 1.5NaN ).

normalize(Vector, Unit) :-
    squared_sum(Vector, Sum),
    ( rational(Sum), Sum > 0 -> maplist(normal_coordinate(Sum), Vector, Unit)
    ; root(Sum, Length), maplist(divide_by(Length), Vector, Unit) ).

normal_coordinate(Sum, Value, Unit) :-
    exact(Value, X), Square is X*X, exact_result(Square),
    Ratio is Square rdiv Sum, exact_result(Ratio),
    fraction_sqrt(Ratio, Magnitude), Unit is copysign(Magnitude, Value).

divide_by(Length, Value, Out) :- scalar(/, Value, Length, Out).

random_prepend(Count, Acc, Values) :-
    ( Count > 0 -> random(Sample), Next is Count-1, random_prepend(Next, [Sample|Acc], Values)
    ; Values = Acc ).

round_result(Value, Out) :- ( rational(Value) -> rounded(Value, Out) ; Out = Value ).
root(Value, Out) :- ( rational(Value) -> fraction_sqrt(Value, Out) ; Out = Value ).

scale_ratio(N, D, Shift, A, B) :-
    ( Shift >= 0 -> A is N << Shift, B = D ; A = N, B is D << -Shift ).

rounded(Value, Out) :-
    ( Value =:= 0 -> Out = 0.0
    ; N is abs(numerator(Value)), D is denominator(Value), positive_float(N, D, Float),
      ( Value >= 0 -> Out = Float
      ; Float == 1.0Inf -> Out = -1.0Inf
      ; Out is -Float ) ).

% Workaround: swi-rational-subnormal-rounding - round at the final binary64 quantum.
% SWI's intermediate significand rounding followed by ldexp can round twice.
% Integer scaling and ties-to-even follow CPython long_true_divide's method:
% https://github.com/python/cpython/blob/ebf955df7a89ed0c7968f79faec1de49f61ed7cb/Objects/longobject.c#L4508
positive_float(N, D, Out) :-
    Difference is msb(N)-msb(D), scale_ratio(N, D, -Difference, A, B),
    ( A < B -> Exponent is Difference-1 ; Exponent = Difference ),
    ( Exponent > 1023 -> Out = 1.0Inf
    ; Exponent < -1075 -> Out = 0.0
    ; Shift is max(Exponent-52, -1074),
      scale_ratio(N, D, -Shift, Dividend, Divisor),
      divmod(Dividend, Divisor, Quotient, Remainder), Twice is 2*Remainder,
      ( (Twice > Divisor ; Twice =:= Divisor, Quotient /\ 1 =:= 1)
      -> Rounded is Quotient+1 ; Rounded = Quotient ),
      ( Rounded =:= 0 -> Out = 0.0
      ; msb(Rounded)+Shift > 1023 -> Out = 1.0Inf
      ; scale_ratio(Rounded, 1, Shift, ResultN, ResultD),
        Dyadic is ResultN rdiv ResultD, exact_result(Dyadic), Out is float(Dyadic) ) ).

%! fraction_sqrt(+Value:rational, -Out:float) is det.
%
% Native numeric service: callers supply a nonnegative exact rational. Return
% its correctly rounded binary64 root, including final IEEE overflow/underflow.
% [tested: lib_vector_surface, lib_statistics; commit=84824f5cf870f5cd7ac89d6580093d0459d91a9b].
% Translate CPython's fraction square root with a 109-bit round-to-odd
% intermediate; vendor/ records the license. No MeTTa head is registered.
% https://github.com/python/cpython/blob/ebf955df7a89ed0c7968f79faec1de49f61ed7cb/Lib/statistics.py#L1695-L1721
% @private
fraction_sqrt(Value, Out) :-
    ( Value =:= 0 -> Out = 0.0
    ; N is numerator(Value), D is denominator(Value),
      Shift is (msb(N)-msb(D)-109) div 2, scale_ratio(N, D, -2*Shift, A, B),
      Integer is A div B, nth_integer_root_and_remainder(2, Integer, Root, _),
      ( Root*Root*B =:= A -> Odd = Root ; Odd is Root \/ 1 ),
      scale_ratio(Odd, 1, Shift, ResultN, ResultD), positive_float(ResultN, ResultD, Out) ).

:- multifile prolog:error_message//1.
prolog:error_message(vector_exact_arithmetic_unavailable) -->
    ['vector_exact_arithmetic_unavailable: install SWI-Prolog built with GMP integer and rational arithmetic'-[]].
