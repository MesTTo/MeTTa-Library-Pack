% Purpose: bridge exact numeric representations and host arithmetic kernels.
% Assumes: Vector owns scalar rounding and the licensed fraction_sqrt/2 kernel.
% [source: lib/lib_vector/lib_vector.pl:scalar/4, fraction_sqrt/2; commit=WORKTREE].
% Guarantees: exact constructors refuse approximation, roots precede binary64
% rounding, and conversion preserves signed zeros and subnormals.
% [tested: lib_math, test_statistics_exact_reductions; commit=WORKTREE].
% Owns resources: numeric temporaries belong to the query; no stored state.
% Decides: conversion rounds to nearest with ties to even and signed IEEE
% saturation, as Vector does. Native floating functions retain the host's
% arithmetic error policy; rationalization is an explicit approximation.
% [source: lib/lib_vector/lib_vector.pl:positive_float/3; commit=4d17f1af15fe125e3b8cd488502ba1e0e688fb3e].

:- module(lib_math,
          [ 'math-rational'/3, 'math-ratio'/2,
            'math-rationalize'/2, 'math-integer-root'/3, 'math-power-mod'/4,
            'math-sqrt'/2, 'math-float'/2, 'math-class'/2,
            'math-real'/3, 'math-real-functions'/1
          ]).
:- set_module(base(metta_engine)).
:- use_module(library(error), [must_be/2, domain_error/2, representation_error/1]).
:- use_module(library(apply), [maplist/3]).
:- use_module('../lib_vector/lib_vector', ['vector-scale'/3, fraction_sqrt/2]).
:- meta_predicate math_operation(+, 0).

%! 'math-rational'(+Numerator:integer, +Denominator:integer, -Value:number) is det.
%
% Construct an exact reduced Number with a positive denominator. Whole results
% are integers. A zero denominator or host policy that approximates the exact
% result raises. The unary MeTTa form converts a finite Number to its exact
% binary rational value through math-ratio; rationalize is the approximation.
% Use math-ratio to recover the parts; rationals have no signed zero.
'math-rational'(Numerator, Denominator, Value) :-
    math_operation('math-rational',
        (must_be(integer,Numerator),must_be(integer,Denominator),
         (Denominator =:= 0 -> domain_error(nonzero_denominator,Denominator) ; true),
         Value is Numerator rdiv Denominator,
         (rational(Value) -> true ; representation_error(exact_math_arithmetic)))).

%! 'math-ratio'(+Value:number, -Parts:list(integer)) is det.
%
% The exact (Numerator Denominator) of a finite Number. For a float these
% represent its binary value, so 0.1 has a larger denominator than 1/10.
% Both floating zeros give (0 1). NaN and infinities raise.
'math-ratio'(Value, [Numerator,Denominator]) :-
    math_operation('math-ratio',
        (finite_number(Value),Exact is rational(Value),
         Numerator is numerator(Exact),Denominator is denominator(Exact))).

%! 'math-rationalize'(+Value:number, -Rational:number) is det.
%
% Preserve exact numbers and approximate finite floats within the host's
% floating rounding error, often with a much smaller denominator. Thus 0.1
% becomes exactly 1/10. math-ratio instead preserves the exact binary value.
% Both zeros become integer zero; NaN and infinities raise.
'math-rationalize'(Value, Rational) :-
    math_operation('math-rationalize',
        (finite_number(Value),Rational is rationalize(Value))).

finite_number(Value) :-
    must_be(number,Value),
    ( float(Value),float_class(Value,Class),(Class == infinite ; Class == nan)
    -> domain_error(finite_number,Value)
    ; true ).

%! 'math-integer-root'(+Degree:integer, +Value:integer, -RootAndRemainder:list(integer)) is det.
%
% Exact (Root Remainder) with Root^Degree+Remainder=Value. Degree is positive.
% For nonnegative Value, Root is the floor of the real root. A negative Value
% requires odd Degree and gives negative Root and Remainder, toward zero.
% The host degree parameter must fit its native signed long; Value is unbounded.
'math-integer-root'(Degree, Value, [Root,Remainder]) :-
    math_operation('math-integer-root',
        (must_be(positive_integer,Degree),must_be(integer,Value),
         (Value < 0,0 is Degree mod 2
         -> domain_error(odd_degree_for_negative_integer,Degree) ; true),
         nth_integer_root_and_remainder(Degree,Value,Root,Remainder))).

%! 'math-power-mod'(+Base:integer, +Exponent:integer, +Modulus:integer, -Result:integer) is det.
%
% Compute Base^Exponent modulo a positive Modulus using native modular
% exponentiation, without constructing the full power. Exponent is nonnegative;
% any signed integer Base is reduced modulo Modulus before the host call.
'math-power-mod'(Base, Exponent, Modulus, Result) :-
    math_operation('math-power-mod',
        (must_be(integer,Base),must_be(nonneg,Exponent),must_be(positive_integer,Modulus),
         Reduced is Base mod Modulus,Result is powm(Reduced,Exponent,Modulus))).

%! 'math-sqrt'(+Value:number, -Root:float) is det.
%
% Correctly rounded floating square root of a nonnegative finite Number.
% Take the root before rounding, so huge or tiny exact inputs can still have
% representable roots. Reuse Vector's fractional-root kernel and final IEEE
% saturation. Preserve the sign of floating zero. A negative or nonfinite
% input raises.
'math-sqrt'(Value, Root) :-
    math_operation('math-sqrt',
        (float(Value),Value =:= 0 -> Root=Value
        ; 'math-ratio'(Value,[Numerator,Denominator]),
          (Numerator >= 0 -> true ; domain_error(nonnegative_number,Value)),
          'math-rational'(Numerator,Denominator,Exact),
          fraction_sqrt(Exact,Root))).

%! 'math-float'(+Value:number, -Float:float) is det.
%
% @private
% Native consumers use this Vector bridge. The public MeTTa equation composes
% vector-scale directly and does not register this native predicate.
%
% Convert a Number to binary64 through multiplication by the floating unit.
% Round once to nearest with ties to even, preserving negative zero, subnormal
% values, infinities and NaNs. Overflow saturates to signed infinity; underflow
% preserves the sign. The rounding policy is shared with vector-scale.
'math-float'(Value, Float) :-
    % Workaround: swi-rational-subnormal-rounding - reuse Vector's final-quantum rounding.
    math_operation('math-float','vector-scale'([Value],1.0,[Float])).

%! 'math-class'(+Value:number, -Class:atom) is det.
%
% The numeric species: integer, rational, or a host float class of zero,
% subnormal, normal, infinite or nan. Both signs of zero have class zero.
'math-class'(Value, Class) :-
    math_operation('math-class',
        (must_be(number,Value),
         (integer(Value) -> Class=integer
         ; rational(Value) -> Class=rational
         ; float_class(Value,Class)))).

%! 'math-real-functions'(-Functions:list) is det.
%
% The native floating functions provided here as (math-function Name Arity)
% rows. Each row describes one accepted math-real call. Existing core trig,
% arithmetic and bit heads keep their names; factorial and binomial come from
% the imported combinatorics face.
'math-real-functions'(Functions) :-
    findall(['math-function',Name,Arity],real_function(Name,Arity),Functions).

%! 'math-real'(+Function:atom, +Arguments:list(number), -Result:float) is det.
%
% Apply one function listed by math-real-functions to its numeric arguments.
% Each argument first passes through math-float; the native function then uses
% the host arithmetic error policy. Empty arguments select a constant. Unknown
% names, wrong arities, nonnumbers and native domain errors raise.
'math-real'(Function, Arguments, Result) :-
    math_operation('math-real',
        ((atom(Function),real_function(Function,Arity)
         -> true ; domain_error(math_real_function,Function)),
         must_be(list(number),Arguments),length(Arguments,Count),
         (Count =:= Arity -> true
         ; throw(error(domain_error(math_real_arguments,Arguments),
                       context('math-real',expected_arity(Function,Arity))))),
         maplist('math-float',Arguments,Floats),
         Expression=..[Function|Floats],Result is Expression)).

real_function(sinh,1).
real_function(cosh,1).
real_function(tanh,1).
real_function(asinh,1).
real_function(acosh,1).
real_function(atanh,1).
real_function(log10,1).
real_function(erf,1).
real_function(erfc,1).
real_function(lgamma,1).
real_function(atan2,2).
real_function(copysign,2).
real_function(nexttoward,2).
real_function(float_integer_part,1).
real_function(float_fractional_part,1).
real_function(pi,0).
real_function(e,0).
real_function(epsilon,0).
real_function(inf,0).
real_function(nan,0).

math_operation(Name, Goal) :-
    catch(Goal,Error,rethrow_metta_operation_error(Name,Error)).

:- det('math-rational'/3).
:- det('math-ratio'/2).
:- det('math-rationalize'/2).
:- det('math-integer-root'/3).
:- det('math-power-mod'/4).
:- det('math-sqrt'/2).
:- det('math-float'/2).
:- det('math-class'/2).
:- det('math-real'/3).
:- det('math-real-functions'/1).
