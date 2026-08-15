% Purpose: the runtime control plane for tabling MeTTa functions. Every
%   declaration is a constructed, module-qualified table/1 goal, never
%   interpolated source text, so hyphenated and uppercase names survive,
%   named spaces instrument their own implementation module, repeated
%   declarations are cumulative and idempotent, and every operation
%   verifies its effect and throws loudly when the engine disagrees.
%   Live declarations reflect into &petta as (tabled space name arity)
%   facts, input arity, asserted on declare and retracted on undeclare.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

%A MeTTa call form arrives as a list, possibly under one quote; the
%function name is its head atom and the compiled arity is the input
%arity plus the output argument the translator appends.
metta_tabling_target(Call0, Module, Name, CompiledArity) :-
    ( Call0 = [quote, Call] -> true ; Call = Call0 ),
    ( is_list(Call), Call = [Name|Args], atom(Name)
      -> true
    ; throw(error(type_error(metta_function_call, Call0), none)) ),
    length(Args, InputArity),
    CompiledArity is InputArity + 1,
    metta_tabling_module(Name, CompiledArity, Module).

%The function's clauses live in its space's module; a shared function
%lives in user. The first module that actually defines the predicate
%wins, and none defining it is a loud refusal: declare after defining,
%because tabling a name that does not exist yet tables nothing.
metta_tabling_module(Name, CompiledArity, Module) :-
    findall(Candidate, metta_tabling_candidate(Candidate), Candidates),
    ( member(Module, Candidates),
      current_predicate(Module:Name/CompiledArity)
      -> true
    ; throw(error(existence_error(metta_function, Name/CompiledArity), none)) ).

metta_tabling_candidate(Module) :-
    current_metta_space(Space),
    space_module(Space, Module).
metta_tabling_candidate(user).

metta_tabled_decl(Call, true) :-
    metta_tabling_target(Call, Module, Name, CompiledArity),
    table(Module:Name/CompiledArity),
    functor(Head, Name, CompiledArity),
    ( predicate_property(Module:Head, tabled) -> true
    ; throw(error(petta_tabling_failed(Module:Name/CompiledArity), none)) ),
    metta_tabling_reflect(Module, Name, CompiledArity, Fact),
    'remove-atom'('&petta', Fact, _),
    'add-atom'('&petta', Fact, _).

metta_untabled_decl(Call, true) :-
    metta_tabling_target(Call, Module, Name, CompiledArity),
    untable(Module:Name/CompiledArity),
    functor(Head, Name, CompiledArity),
    ( predicate_property(Module:Head, tabled)
      -> throw(error(petta_untabling_failed(Module:Name/CompiledArity), none))
    ; true ),
    metta_tabling_reflect(Module, Name, CompiledArity, Fact),
    'remove-atom'('&petta', Fact, _).

%The live-declaration record in &petta: the space whose module holds the
%predicate (user's functions belong to '&self'), the function name, and
%its INPUT arity, the arity a MeTTa caller sees. Declaring removes any
%previous record before adding, so repetition never duplicates.
metta_tabling_reflect(Module, Name, CompiledArity, [tabled, Space, Name, InputArity]) :-
    ( Module == user -> Space = '&self' ; Space = Module ),
    InputArity is CompiledArity - 1.

%Clear answers, keep the declaration: unifying subgoal tables of this
%predicate are abolished and every other table stands.
metta_table_clear(Call, true) :-
    metta_tabling_target(Call, Module, Name, CompiledArity),
    functor(Head, Name, CompiledArity),
    abolish_table_subgoals(Module:Head).

metta_table_clear_all(true) :-
    abolish_all_tables.

%A table answers from the equations that were compiled when it was built,
%so changing any equation makes every table that could have read it stale.
%Measured before this, in the workspace review's P07: tabling a one-clause
%function, adding a second equation, then calling it answered only the
%cached first answer, and only an explicit abolish exposed both.
%
%Every table goes, not the changed function's alone. Deciding which tables
%could have read a given equation needs a call graph over compiled clauses
%that the engine does not keep, and answering that question wrongly is a
%stale answer with no symptom. Definition changes are rare beside calls,
%tables rebuild lazily on the next call, and this is the same funnel that
%already invalidates the specializer and the memo cache
%[tested: tabling_equation_change_drops_tables].
:- multifile metta_on_function_changed/1.
metta_on_function_changed(_) :-
    metta_tabling_declared, !,
    abolish_all_tables.
metta_on_function_changed(_).

:- multifile metta_on_function_removed/1.
metta_on_function_removed(_) :-
    metta_tabling_declared, !,
    abolish_all_tables.
metta_on_function_removed(_).

%Nothing is tabled in the overwhelming majority of programs, and this hook
%runs on every equation the loader compiles, so the test that decides it is
%one indexed lookup on a predicate that is usually empty.
metta_tabling_declared :- 'get-atoms'('&petta', [tabled|_]), !.
