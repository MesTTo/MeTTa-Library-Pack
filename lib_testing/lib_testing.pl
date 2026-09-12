% Purpose: generate finite input families and check quantified answer bags.
% Assumes: generators and function answer streams are finite when exhausted.
% Guarantees: choices retain occurrences and literal values; properties use
% the core bag comparison and report the first failing input through
% assert-answers. A universal check returns its executed case count.
% [tested: lib_testing; commit=WORKTREE].
% Decides: integer and length bounds are inclusive; reversed intervals are
% empty. List positions copy variables independently; sharing within a chosen
% value survives. Generator/function/expectation variables are copied together.
% [tested: lib_testing; commit=WORKTREE].

:- module(lib_testing,
          ['test-integers'/3,'test-choices'/2,'test-lists'/4,
           'test-forall'/4,'test-witness'/4]).
:- set_module(base(metta_engine)).
:- use_module(library(error), [must_be/2]).
:- use_module(library(lists), [member/2]).
:- use_module(library(apply), [maplist/3]).
:- use_module(library(aggregate), [aggregate_all/3]).
:- use_module('../lib_combinatorics/lib_combinatorics', ['cartesian-power'/3]).

%! 'test-integers'(+Low:integer, +High:integer, -Value:integer) is nondet.
%
% Every integer from Low through High, in ascending order. Equal bounds give
% one value; reversed bounds give no answers. Both bounds must be finite
% integers. Arbitrarily large integers use the native between generator.
'test-integers'(Low,High,Value) :-
    must_be(integer,Low),must_be(integer,High),between(Low,High,Value).

%! 'test-choices'(+Choices:'Atom', -Value:any) is nondet.
%
% One fresh copy of each occurrence in a held expression, in order. Empty
% choices give no answers and duplicates remain distinct cases. Runnable
% expressions remain data. Variables shared inside one choice stay shared;
% choices do not bind the original template. Bind computed choices with let.
'test-choices'(Choices,Value) :-
    must_be(acyclic,Choices),must_be(list,Choices),
    member(Choice,Choices),copy_term(Choice,Value).

%! 'test-lists'(+Generator:'Atom', +Minimum:integer, +Maximum:integer, -Values:list) is nondet.
%
% All lists whose lengths lie in the inclusive interval, shortest first and
% with the last position varying fastest. Snapshot the finite held element
% generator once in the calling module, then use its answer occurrences as
% the population. Each position copies its choice independently. Variables
% shared within a choice stay shared. Nested generators build nested lists.
% Both lengths must be nonnegative integers. Reversed bounds yield nothing;
% maximum zero yields one empty list without running the element generator.
% An empty population yields only the empty list when Minimum is zero.
% Working storage is the population plus one list; the complete output has
% the sum of n^k lists over the requested lengths for n population entries.
'test-lists'(Generator,Minimum,Maximum,Values) :-
    must_be(acyclic,Generator),must_be(nonneg,Minimum),must_be(nonneg,Maximum),
    Minimum=<Maximum,
    ( Maximum=:=0 -> Values=[]
    ; current_metta_module(Module),
      findall(Value,(eval_metta_in_module(Module,Generator,Value),
                     must_be(acyclic,Value)),Population),
      ( Population==[] -> Minimum=:=0,Values=[]
      ; between(Minimum,Maximum,Length),
        'cartesian-power'(Population,Length,Template),
        maplist(copy_term,Template,Values) ) ).

%! 'test-forall'(+Generator:'Atom', +Function:'Atom', +Expected:'Atom', -Count:integer) is det.
%
% For every answer of the finite held Generator, apply held Function to that
% input as literal data and compare its complete answer bag with held Expected.
% Return the number of cases checked. Zero reports an empty domain explicitly.
% For a Boolean property, Expected is (True), requiring exactly one True answer.
% Expected () instead asserts that every application has no answers. Reordered
% answers agree and duplicates count, using assertEqualToResult's equality.
% Use an =alpha property when separately copied variables should match.
% The first mismatch raises the engine's assertion failure with the generated
% call, missing answers and excess answers. Generator/function errors propagate.
% Lambdas, names and partial applications resolve in the calling module.
'test-forall'(Generator,Function,Expected,Count) :-
    testing_arguments(Generator,Function,Expected,G,F,E),
    current_metta_module(Module),
    aggregate_all(count,
        ( testing_case(Module,G,F,E,Value,Actual,Same),
          'assert-answers'(Same,['test-forall',G,[F,[quote,Value]],E],Actual,E,_) ),
        Count).

%! 'test-witness'(+Generator:'Atom', +Function:'Atom', +Expected:'Atom', -Value:any) is semidet.
%
% The first generated input whose complete function answer bag equals Expected,
% using the same comparison and literal input application as test-forall.
% Return no answer when the finite domain contains no witness, including an
% empty domain. Stop the generator after the first witness; skipped mismatches
% print nothing. Exceptions propagate. Use core test or bag assertions to
% state whether a witness must exist or what it must be.
'test-witness'(Generator,Function,Expected,Value) :-
    testing_arguments(Generator,Function,Expected,G,F,E),
    current_metta_module(Module),
    once((testing_case(Module,G,F,E,Value,_,Same),Same==true)).

testing_arguments(Generator,Function,Expected,G,F,E) :-
    must_be(acyclic,Generator-Function-Expected),must_be(list,Expected),
    copy_term(Generator-Function-Expected,G-F-E).

% Use the same three core operations as prelude:assertEqualToResult/3.
% Generation and assertion remain separate, as in SmallCheck's over/forAll:
% https://github.com/Bodigrim/smallcheck/blob/433ada587bf4ff898031aaa5530c0b7aaab10e3a/Test/SmallCheck/Property.hs#L128-L143
testing_case(Module,Generator,Function,Expected,Value,Actual,Same) :-
    eval_metta_in_module(Module,Generator,Value),must_be(acyclic,Value),
    findall(Answer,eval_metta_in_module(Module,[Function,[quote,Value]],Answer),Actual),
    'subtraction-atom'(Expected,Actual,Missing),
    'subtraction-atom'(Actual,Expected,Excess),
    '=alpha'([Missing,Excess],[[],[]],Same).

:- det('test-forall'/4).
