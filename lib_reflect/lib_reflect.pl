% Purpose: the engine's own surface, as data. What builtins exist, what
%   special forms the translator knows, what arities are registered, what the
%   current space defines.
%
%   The point is not introspection for its own sake. Two consumers want this
%   and both currently guess: metta-lsp computes diagnostics against
%   MeTTaScript's builtin list rather than this engine's, and the documentation
%   surface has no way to enumerate what it ought to document. A list
%   maintained in two places drifts; a list the engine answers cannot.
% Assumes:
%   - builtin_fun/1, fun/1 and arity/2 are the engine's own registries
%     [source: engine/metta.pl:1136, 1306, 1312]
%   - every translator special form is a clause of translate_special_dl/5
%     [source: engine/translator.pl, 40 clauses as of 2026-08-15]
% Guarantees:
%   - every predicate here is a pure reader; nothing it answers changes what
%     the engine does [assumed 2026-08-16: nothing checks the surface is unchanged after a read]
%   - the accessors are nondeterministic, one answer per solution, because an
%     answer set is the MeTTa reading of "all of them"; collapse for a tuple [tested: lib_reflect:every_registered_builtin_is_reported, special_forms_are_reported]
% Fails when:
%   - asked about a name that does not exist. That is no answer rather than an
%     error, because "is this a builtin" is a question, not an assertion.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: the JSON export metta-lsp would consume is built in
%     the .metta half out of these plus lib_json, so nothing here needs to know
%     about JSON.

:- use_module(library(lists)).

%One builtin name per solution. Indexed on the name, so asking about a
%specific one is a lookup rather than a scan.
'engine-builtin'(Name) :-
    builtin_fun(Name).

%The translator's special forms, which are NOT builtins and do not appear in
%any registry: they are clause heads. A form like hyperpose or timeout is
%compiled rather than called, which is exactly why a tool that only knows the
%builtin list gets them wrong.
%Asking about ONE name is a lookup, not a scan: clause/2 with the head bound
%is first-argument indexed, so the enumeration is only built when the caller
%actually wants every form. Computing the setof either way would make
%(knows? hyperpose) walk forty clauses to answer one question.
'engine-special-form'(Name) :-
    (   nonvar(Name)
    ->  once(special_form_head(Name))
    ;   setof(Head, special_form_head(Head), Heads),
        member(Name, Heads)
    ).

special_form_head(Head) :- metta_special_form_head(Head).

'engine-arity'(Name, Arity) :-
    arity(Name, Arity).

%Everything the engine knows as a function, builtin or not.
'engine-function'(Name) :-
    fun(Name).

%The functions this space defines itself, which is the useful half for a tool:
%builtins are the same everywhere, user code is not.
'engine-user-function'(Name) :-
    fun(Name),
    \+ builtin_fun(Name).

%Whether a name is known at all, as a boolean, so it guards a query.
'engine-knows'(Name, Answer) :-
    (   fun(Name)
    ->  Answer = true
    ;   special_form_head(Name)
    ->  Answer = true
    ;   Answer = false
    ).

%Where a function came from, which is the question a name collision raises and
%the one this library could not answer. fun/1 is a flat list in which an
%equation, a compiled Python function, a registered Python operation and a
%library's Prolog predicate look identical, so metta-lsp could not show an
%author where a name comes from and a library could not verify its own
%installation.
%
%The tiers answer in order of how firmly each is known:
%
%  builtin           the engine's own, from builtin_fun/1
%  special-form      compiled by the translator rather than called
%  prolog / python   the tier that CLAIMED the name, from
%                    metta_function_origin/3, which the same registration
%                    refuses a second claim on
%  specialization    the ENGINE wrote this equation, not the program: the
%                    specializer stores a generated clause under a name like
%                    twice_Spec_[inc], and those atoms save and digest like
%                    any other, so a tool showing a program what it holds was
%                    presenting engine bookkeeping as source. 19 of the 238
%                    example programs hold them, 40 of ch08/15-roman.metta's
%                    85 atoms among them. Above `equation` because a
%                    specialization IS one and the tier says who authored it
%  equation          everything else that is a function: its clauses live in
%                    a space's module, which fun_in/2 already records, so no
%                    fact has to be asserted per compiled equation for this
%
%The detail is the source file for a Prolog registration, the dispatch kind
%for a Python one, and the name it specializes for a specialization, which is
%what a reader wants next [tested: lib_reflect_origin].
'engine-origin'(Name, Origin) :-
    (   builtin_fun(Name)
    ->  Origin = [builtin]
    ;   metta_function_origin(Name, Tier, Detail)
    ->  Origin = [Tier, Detail]
    ;   specializer:ho_specialization(_, Base, Name)
    ->  Origin = [specialization, Base]
    ;   fun(Name)
    ->  ( fun_in(Module, Name) -> Origin = [equation, Module] ; Origin = [equation] )
    ;   special_form_head(Name)
    ->  Origin = ['special-form']
    ;   fail
    ).

%Every extension point the engine declares, as [Name, Arity, Kind].
%
%The kind is the fact a handler author needs and the one that used to be
%readable only by a person, in a comment at the top of engine/ext_points.pl. An
%event or declaration seam has every clause read, so a cut in one silently
%disables every clause after it; an ownership seam is claimed by the first
%handler that succeeds, and a cut after a guard proving the request is yours
%is correct and fast there. Restating that list by hand is what put
%seam:backend_selftest/0 outside the check that enforces it, so it is data in
%seam:kind/2 now and this reads it rather than keeping a copy
%[tested: lib_reflect:extension_points_are_reported].
%
%A SERVICE runs the other way: the engine writes those clauses and an
%extension calls them, so none of the cut reasoning above applies to one.
%Both directions are reported, because a tool asking what the contract is
%wants the whole of it, and seam:clauses_from/2 says which way a kind
%runs [tested: lib_reflect:both_directions_of_the_contract_are_reported].
'engine-extension-point'(Point) :-
    seam:kind(Name/Arity, Kind),
    Point = [Name, Arity, Kind].

%How many of each, which is the cheap health check a tool wants first.
'engine-surface-counts'(Counts) :-
    aggregate_all(count, builtin_fun(_), Builtins),
    aggregate_all(count, fun(_), Functions),
    findall(Head, special_form_head(Head), Heads0),
    sort(Heads0, Heads),
    length(Heads, SpecialForms),
    UserFunctions is Functions - Builtins,
    Counts = [[builtins, Builtins],
              ['special-forms', SpecialForms],
              [functions, Functions],
              ['user-functions', UserFunctions]].
