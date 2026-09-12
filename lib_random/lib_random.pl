% Purpose: select occurrences and stream samples from explicit distribution values.
% Assumes: math-float and Vector's dot provide the shared binary64 conversion.
% [source: lib/lib_math/lib_math.pl:'math-float'/2; commit=505b45e1d9184608c818a8a4fdba5cf6406bf3e7].
% Guarantees: parameter refusals consume no random state, positions preserve
% duplicate values, and with-seed restores the generator after completion or cut.
% [tested: lib_random; commit=505b45e1d9184608c818a8a4fdba5cf6406bf3e7].
% Owns resources: query-local population and numeric terms; the host thread owns
% its generator. The existing metta_with_seed/4 scope owns state restoration.
% [source: engine/metta/control.pl:metta_with_seed/4; commit=505b45e1d9184608c818a8a4fdba5cf6406bf3e7].
% Guarded by: the host generator is thread-local; this library stores no state.
% Decides: parameters use finite binary64; continuous samples use native floating
% precision and final IEEE saturation. These draws are for sampling, not secrets.

:- module(lib_random,
          [ 'random-choice!'/2, 'random-shuffle!'/2, 'random-sample!'/4,
            'random-draw!'/3, 'random-distributions'/1
          ]).
:- set_module(base(metta_engine)).
:- use_module(library(error), [must_be/2, domain_error/2, representation_error/1]).
:- use_module(library(random), [random/1, random_member/2, random_permutation/2,
                               random_between/3, randseq/3]).
:- use_module(library(apply), [maplist/2, maplist/3, foldl/4]).
:- use_module('../lib_math/lib_math', ['math-float'/2]).
:- use_module('../lib_vector/lib_vector', [dot/3]).
:- meta_predicate random_operation(+, 0).
:- multifile seam:seeded_operation/1.
seam:seeded_operation('random-choice!').
seam:seeded_operation('random-shuffle!').
seam:seeded_operation('random-sample!').
seam:seeded_operation('random-draw!').

%! 'random-choice!'(+Items:'Atom', -Item:any) is det.
%
% Choose one occurrence uniformly from a nonempty expression. Items are held,
% so runnable expressions remain data; bind a computed population with let first.
% Equal values at different positions remain separate choices. Empty input raises.
'random-choice!'(Items, Item) :-
    random_operation('random-choice!',
        (must_be(list,Items),
         (Items == [] -> domain_error(nonempty_population,Items) ; true),
         random_member(Item,Items))).

%! 'random-shuffle!'(+Items:'Atom', -Shuffled:list) is det.
%
% A new permutation of the held expression, preserving every occurrence and
% leaving the input unchanged. Empty input returns empty. Uses the host's
% random-key sort, O(n log n), and the same generator as with-seed.
'random-shuffle!'(Items, Shuffled) :-
    random_operation('random-shuffle!',
        (must_be(list,Items),random_permutation(Items,Shuffled))).

%! 'random-sample!'(+Items:'Atom', +Count:integer, +Replacement:boolean, -Sample:list) is det.
%
% Count ordered draws from held Items. Replacement True permits repeated
% positions; False chooses distinct positions, so Count cannot exceed the input
% length. Duplicate values can appear in either case. Count zero returns empty,
% even for an empty population. Validate every argument before drawing.
% Index the population once: O(n+k) with replacement; without replacement add
% the host's distinct-index selection and O(k log k) permutation.
'random-sample!'(Items, Count, Replacement, Sample) :-
    random_operation('random-sample!',
        (must_be(list,Items),must_be(nonneg,Count),must_be(boolean,Replacement),
         length(Items,Size),
         (Count > 0,Size =:= 0 -> domain_error(nonempty_population,Items) ; true),
         (Replacement == false,Count > Size
         -> domain_error(sample_size,Count-Size) ; true),
         Pool=..[population|Items],
         (Replacement == true
         -> length(Indices,Count),maplist(random_index(Size),Indices)
         ; randseq(Count,Size,Indices)),
         maplist(population_item(Pool),Indices,Sample))).

random_index(Size, Index) :- random_between(1,Size,Index).
population_item(Pool, Index, Item) :- arg(Index,Pool,Item).

%! 'random-distributions'(-Forms:list) is det.
%
% The accepted distribution values as (random-distribution Name Parameters)
% rows, with parameter names as Strings. Uniform requires Low=<High; triangular
% requires Low=<Mode=<High. Normal/lognormal take a mean and nonnegative standard
% deviation; exponential a positive rate; gamma a positive shape and scale;
% beta two positive shapes; bernoulli a probability in [0,1]; pareto a positive
% shape and minimum one; weibull a positive scale and shape.
'random-distributions'(Forms) :-
    findall(['random-distribution',Name,Parameters],distribution_form(Name,Parameters),Forms).

distribution_form(uniform,["low","high"]).
distribution_form(normal,["mean","standard-deviation"]).
distribution_form(lognormal,["mean-of-log","standard-deviation-of-log"]).
distribution_form(exponential,["rate"]).
distribution_form(triangular,["low","high","mode"]).
distribution_form(gamma,["shape","scale"]).
distribution_form(beta,["alpha","beta"]).
distribution_form(bernoulli,["probability"]).
distribution_form(pareto,["shape"]).
distribution_form(weibull,["scale","shape"]).

%! 'random-draw!'(+Distribution:'Atom', +Count:integer, -Value:any) is nondet.
%
% Stream Count samples of a held value such as (normal 0 1) or (gamma 2 3).
% Count is nonnegative; zero validates the distribution but yields no answers.
% Collapse collects the stream, while once/cut consumes only the demanded prefix.
% Bind computed parameters before building the held distribution value.
% Every parameter converts to finite binary64. Continuous results are floats;
% bernoulli returns Bool. Degenerate valid bounds or deviation and probabilities
% zero/one consume no random state. Use with-seed to replay and restore state.
% Numerical algorithms use native floating precision: results may round to an
% endpoint, underflow to zero or overflow to infinity. No cached normal spare or
% library generator exists; secure bytes remain lib_crypto's separate operation.
'random-draw!'(Distribution, Count, Value) :-
    random_operation('random-draw!',
        (must_be(nonneg,Count),distribution_spec(Distribution,Prepared),
         between(1,Count,_),draw(Prepared,Value))).

distribution_spec(Spec, Prepared) :-
    (is_list(Spec),Spec=[Name|Values],atom(Name),distribution_form(Name,Parameters),
     length(Values,Arity),length(Parameters,Arity)
    -> true
    ; 'random-distributions'(Forms),
      throw(error(domain_error(random_distribution,Spec),
                  context('random-draw!',choose_one_of(Forms))))),
    maplist(finite_float,Values,Floats),Prepared=..[Name|Floats],
    (valid_distribution(Prepared) -> true
    ; domain_error(random_distribution_parameters,Spec)).

finite_float(Value, Float) :-
    'math-float'(Value,Float),float_class(Float,Class),
    ((Class == infinite ; Class == nan)
    -> domain_error(finite_random_parameter,Value) ; true).

valid_distribution(uniform(Low,High)) :- Low =< High.
valid_distribution(normal(_,Deviation)) :- Deviation >= 0.
valid_distribution(lognormal(_,Deviation)) :- Deviation >= 0.
valid_distribution(exponential(Rate)) :- Rate > 0.
valid_distribution(triangular(Low,High,Mode)) :- Low =< Mode,Mode =< High.
valid_distribution(gamma(Shape,Scale)) :- Shape > 0,Scale > 0.
valid_distribution(beta(Alpha,Beta)) :- Alpha > 0,Beta > 0.
valid_distribution(bernoulli(P)) :- P >= 0,P =< 1.
valid_distribution(pareto(Shape)) :- Shape > 0.
valid_distribution(weibull(Scale,Shape)) :- Scale > 0,Shape > 0.

draw(uniform(Low,High), Value) :-
    (Low =:= High -> Value=Low ; random(U),interpolate(U,Low,High,Value)).
draw(normal(Mean,Deviation), Value) :- normal_value(Mean,Deviation,Value).
draw(lognormal(Mean,Deviation), Value) :-
    normal_value(Mean,Deviation,Log),exponential_value(Log,Value).
draw(exponential(Rate), Value) :-
    random(U),exact(rational(-log(U)) rdiv rational(Rate),Ratio),'math-float'(Ratio,Value).
draw(triangular(Low,High,Mode), Value) :-
    (Low =:= High -> Value=Low
    ; exact((rational(Mode)-rational(Low)) rdiv (rational(High)-rational(Low)),Ratio),
      'math-float'(Ratio,C),random(U),
      (U =< C -> Position is sqrt(U*C)
      ; Position is 1.0-sqrt((1.0-U)*(1.0-C))),
      interpolate(Position,Low,High,Value)).
draw(gamma(Shape,Scale), Value) :-
    gamma_parts(Shape,Factors,Correction),positive_value([Scale|Factors],Correction,Value).
draw(beta(Alpha,Beta), Value) :- beta_value(Alpha,Beta,Value).
draw(bernoulli(P), Value) :-
    (P =:= 0 -> Value=false ; P =:= 1 -> Value=true
    ; random(U),(U < P -> Value=true ; Value=false)).
draw(pareto(Shape), Value) :-
    random(U),exact(rational(-log(U)) rdiv rational(Shape),Correction),
    positive_value([],Correction,Value).
draw(weibull(Scale,Shape), Value) :-
    random(U),exact(rational(log(-log(U))) rdiv rational(Shape),Correction),
    positive_value([Scale],Correction,Value).

interpolate(Position, Low, High, Value) :-
    R is rational(Position),exact(1-R,L),dot([L,R],[Low,High],Value).

normal_value(Mean, Deviation, Value) :-
    (Deviation =:= 0 -> Value=Mean
    ; standard_normal(Z),dot([1,Z],[Mean,Deviation],Value)).

% Box-Muller, with no cached spare: the host generator is the complete state.
% https://github.com/python/cpython/blob/ebf955df7a89ed0c7968f79faec1de49f61ed7cb/Lib/random.py#L557-L592
standard_normal(Z) :- random(U),random(V),Z is cos(2*pi*U)*sqrt(-2*log(V)).

% Marsaglia/Tsang and its shape-boosting identity, with multiplication delayed.
% The Rand translation and license are recorded under vendor/.
% https://github.com/rust-random/rand_distr/blob/d65b9bbf991e56d8a097a35d934e6f93d9194ac0/src/gamma.rs#L203-L287
gamma_parts(Shape, Factors, Correction) :-
    (Shape < 1.0
    -> Boost is Shape+1.0,gamma_factors(Boost,Factors),random(U),
       exact(rational(log(U)) rdiv rational(Shape),Correction)
    ; gamma_factors(Shape,Factors),Correction=0).

gamma_factors(Shape, Factors) :-
    (Shape =:= 1.0 -> random(U),E is -log(U),Factors=[E]
    ; D is Shape-1.0/3.0,C is (1.0/3.0)/sqrt(D),
      gamma_accept(D,C,V),Factors=[D,V]).

gamma_accept(D, C, V) :-
    standard_normal(Z),Root is 1.0+C*Z,
    (Root > 0.0,Candidate is Root*Root*Root,random(U),Z2 is Z*Z,
     (U < 1.0-0.0331*Z2*Z2 ; log(U) < 0.5*Z2+D*(1.0-Candidate+log(Candidate)))
    -> V=Candidate
    ; gamma_accept(D,C,V)).

% Keep ordinary products exact. Combine logarithms only when a power would
% lose range before a later factor can bring the final value back into range.
positive_value(Factors, Correction, Value) :-
    exponential_value(Correction,Power),
    (float_class(Power,normal)
    -> foldl(exact_product,[Power|Factors],1,Product),'math-float'(Product,Value)
    ; foldl(log_product,Factors,Correction,Log),exponential_value(Log,Value)).

% NumPy's beta sampler retains underflowed powers through their log ratio.
% Here rational log differences also preserve subnormal shape parameters.
% https://github.com/numpy/numpy/blob/2f7fe64b8b6d7591dd208942f1cc74473d5db4cb/numpy/random/src/distributions/distributions.c#L429-L459
beta_value(Alpha, Beta, Value) :-
    gamma_parts(Alpha,AF,AC),gamma_parts(Beta,BF,BC),
    (AC =:= BC
    -> foldl(exact_product,AF,1,X),foldl(exact_product,BF,1,Y),
       exact(X rdiv (X+Y),Ratio),'math-float'(Ratio,Value)
    ; foldl(log_product,AF,AC,X),foldl(log_product,BF,BC,Y),exact(X-Y,Delta),
      Negative is -abs(Delta),exponential_value(Negative,Tail),
      (Delta >= 0 -> Value is 1.0/(1.0+Tail) ; Value is Tail/(1.0+Tail))).

exact_product(Factor, Acc, Product) :- exact(Acc*rational(Factor),Product).
log_product(Factor, Acc, Log) :- exact(Acc+rational(log(Factor)),Log).

exact(Expression, Value) :-
    Value is Expression,
    (rational(Value) -> true ; representation_error(exact_random_transform)).

exponential_value(Log, Value) :-
    'math-float'(Log,F),
    catch(Value is exp(F),Error,metta_saturating_recover(exp,exp(F),Value,Error)).

random_operation(Name, Goal) :-
    catch(Goal,Error,rethrow_metta_operation_error(Name,Error)).

:- det('random-choice!'/2).
:- det('random-shuffle!'/2).
:- det('random-sample!'/4).
:- det('random-distributions'/1).
