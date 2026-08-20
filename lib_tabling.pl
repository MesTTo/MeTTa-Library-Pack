% Purpose: the runtime control plane for tabling MeTTa functions. Every
%   declaration is a constructed, module-qualified table/1 goal, never
%   interpolated source text, so hyphenated and uppercase names survive,
%   named spaces instrument their own implementation module, repeated
%   declarations are cumulative and idempotent, and every operation
%   verifies its effect and throws loudly when the engine disagrees.
%   Live declarations reflect into &petta as (tabled space name arity)
%   facts, input arity, asserted on declare and retracted on undeclare.
% Guarantees:
%   - A declared table survives a write to a space it reads, and a change
%     to any equation drops it [tested: tabling_equation_change_drops_tables,
%     and end to end by examples/libraries/tabling_equation_change.metta and
%     examples/libraries/tabling_space_write.metta].
%   - A write the table's own subgoal does not read leaves it VALID, not
%     merely leaves its answers unchanged, so tabling over a space that is
%     written to often is worth having. This is finer than the manual's own
%     summary, which says invalidation "is done at the level of tables.
%     Notably asserting a clause invalidates all affected tables" and closes
%     with "Future versions may implement a more fine grained approach"
%     [source: SWI-Prolog 10.1 Reference Manual, 7.7]. Measured 2026-08-16 on
%     SWI 10 against a table for (reach a $y) over (edge a b): adding
%     (edge b d) and (unrelated x y) each left invalidated at 0, read BEFORE
%     the next call so re-evaluation cannot be what hides it, while adding
%     (edge a c) took it to 1 immediately
%     [tested: tabling_statistics_count_invalidations, and end to end by
%     examples/libraries/tabling_statistics.metta].
%   - A read that cannot be resolved to one space predicate, or that names
%     a foreign space, is refused rather than tabled without the guarantee
%     [tested: tabling_refuses_unresolvable_reads].
% Fails when:
%   - the caller depends on the ORDER of a function's answers. Tabling
%     changes it. An untabled MeTTa function answers in clause order, and a
%     tabled one answers from its trie: SWI puts it plainly, "Tabling
%     effectively inverts the execution order for this case" [source:
%     SWI-Prolog 10.1 Reference Manual, section 7.1]. Which order comes out
%     depends on the trie's layout, so it moves when something unrelated
%     moves. Measured 2026-08-15: (collapse (pick a)) over two equations
%     answered (one two), and adding three facts that NOTHING CALLS to
%     engine/translator.pl flipped it to (two one); removing them flipped it
%     back, deterministically, seven runs each way. Adding only comments
%     changed nothing, so it tracks new atoms rather than new lines.
%
%     So tabling preserves the answer SET, not the answer sequence. A
%     program that reads a collapse positionally, with car-atom or
%     index-atom, is not safe to table. sort-atom over the collapse is, and
%     is what the examples do.
%
%     Which is now DETECTED rather than only written down here. The live
%     (tabled Space Name Arity) facts this reflects into &petta are what
%     space.lint() reads to find a car-atom, cdr-atom or index-atom picking
%     out of a collapse of a tabled function, reported as
%     tabled-answer-order-read [tested:
%     test_a_positional_read_of_a_tabled_functions_answers]. A finding and
%     not a refusal, because a positional read is right whenever the
%     function is deterministic and nothing here knows whether it is; a
%     collapse that goes through sort-atom or unique-atom first is not
%     reported [tested:
%     test_a_canonicalised_read_of_a_tabled_function_is_not_a_finding].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- multifile prolog:error_message//1.

%table_statistics/3 is tableutil's, and it is not autoloaded.
:- use_module(library(tableutil)).


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
metta_tabling_candidate(Module) :- metta_self_module(Module).

%A table over a space also has to survive writes to that space, and SWI
%does that when both the table and the dynamic predicates it reads carry
%the incremental property [source: SWI-Prolog 10.1 Reference Manual 7.7].
%The predicates it reads are recoverable exactly: a match compiles to
%match(Space, Pattern, _, _) with the space an atom and the pattern a
%list, so the storage predicate is Space/(1 + arguments), and the walk
%follows the calls the body makes. Deriving them costs nothing per write,
%where a flag consulted on the write path measured two inferences of
%every five that add_sexp/3 spends [measured 2026-08-15].
%
%A read this cannot resolve is refused rather than tabled without the
%guarantee: a computed space or pattern, or a foreign space, whose atoms
%do not live in an SWI dynamic predicate at all.
metta_tabled_decl(Call, true) :-
    metta_tabling_target(Call, Module, Name, CompiledArity),
    (   metta_cache_unchecked(Name)
    ->  %The caller accepted staleness by declaration, so the purity walk is
        %skipped and the table is PLAIN: with reads unresolved there is
        %nothing sound to hang the incremental property on, and a stale
        %answer is exactly what (cache Name unchecked) accepts
        %[tested: an_unchecked_declaration_tables_an_impure_body].
        table(Module:Name/CompiledArity)
    ;   metta_tabling_reads(Module, Name, CompiledArity, Reads),
        forall(member(Storage:Predicate, Reads),
               dynamic(Storage:Predicate as incremental)),
        table(Module:Name/CompiledArity as incremental)
    ),
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

%Every space storage predicate this function can read, following the calls
%its clauses make. The walk carries a seen-set over predicate indicators
%and collects as it goes: what is wanted is the reads gathered along the
%way, not the set of reachable predicates.
metta_tabling_reads(Module, Name, CompiledArity, Reads) :-
    metta_effect_walk(Module, [Name/CompiledArity], Found),
    foldl(metta_tabling_resolve, Found, [], Raw),
    sort(Raw, Reads).

%The walk is the ENGINE's, metta_effect_walk/3, and so is the refusal for a
%goal nothing declares pure. What stays here is what tabling does with the
%reads it reports, which is the half that is genuinely tabling's: resolve each
%to the storage predicates that answer it, so the table can carry the
%incremental property against them. Memoization calls the same walk and does
%the opposite with the same reads, because it has no invalidation to hang on
%them [source: engine/metta.pl, metta_effect_walk/3].
metta_tabling_resolve(read(Operation, Space, Pattern), Reads0, Reads) :-
    metta_tabling_read(Operation, Space, Pattern, Found),
    append(Found, Reads0, Reads).

%One space read, resolved to the dynamic predicates that answer it: one
%per conjunct, since a conjunction reads each of its patterns.
metta_tabling_read(Operation, Space, Pattern, Reads) :-
    ( atom(Space) -> true
    ; throw(error(petta_tabling_unresolved_read(Operation, Space), none)) ),
    ( metta_foreign_space(Space)
      -> throw(error(petta_tabling_foreign_space(Operation, Space), none))
    ; true ),
    native_storage_module(Space, Storage),
    metta_tabling_patterns(Operation, Pattern, Shapes),
    findall(Storage:Space/Arity,
            ( member(Shape, Shapes),
              length(Shape, Count),
              Arity is Count + 1 ),
            Reads).

%The argument lists a pattern reads. A conjunction contributes one per
%conjunct; anything whose shape is not fixed cannot be resolved.
metta_tabling_patterns(Operation, Pattern, _) :-
    \+ is_list(Pattern), !,
    throw(error(petta_tabling_unresolved_read(Operation, Pattern), none)).
metta_tabling_patterns(Operation, [Comma|Conjuncts], Shapes) :-
    nonvar(Comma), Comma == ',', !,
    foldl(metta_tabling_conjunct(Operation), Conjuncts, [], Shapes).
metta_tabling_patterns(Operation, [Head|Arguments], [Arguments]) :-
    ( nonvar(Head) -> true
    ; throw(error(petta_tabling_unresolved_read(Operation, [Head|Arguments]), none)) ).

metta_tabling_conjunct(Operation, Conjunct, Shapes0, Shapes) :-
    metta_tabling_patterns(Operation, Conjunct, Found),
    append(Found, Shapes0, Shapes).

prolog:error_message(petta_tabling_unresolved_read(Operation, Culprit)) -->
    { swrite(Culprit, Text) },
    [ 'a tabled function reads ~w with ~w, which cannot be resolved to one \c
       space predicate, so writes to it could not invalidate the table. \c
       Name the space and the pattern shape, or do not table this \c
       function.'-[Operation, Text] ].
prolog:error_message(petta_tabling_foreign_space(Operation, Space)) -->
    [ 'a tabled function reads the foreign space ~w with ~w. Its atoms do \c
       not live in this engine, so a write there cannot invalidate the \c
       table. Do not table a function that reads a foreign space.'-[Space, Operation] ].

%The live-declaration record in &petta: the space whose module holds the
%predicate, the function name, and its INPUT arity, the arity a MeTTa caller
%sees. Declaring removes any previous record before adding, so repetition
%never duplicates.
metta_tabling_reflect(Module, Name, CompiledArity, [tabled, Space, Name, InputArity]) :-
    metta_module_space(Module, Space),
    InputArity is CompiledArity - 1.

%Clear answers, keep the declaration: unifying subgoal tables of this
%predicate are abolished and every other table stands.
metta_table_clear(Call, true) :-
    metta_tabling_target(Call, Module, Name, CompiledArity),
    functor(Head, Name, CompiledArity),
    abolish_table_subgoals(Module:Head).

metta_table_clear_all(true) :-
    abolish_all_tables.

%What the incremental machinery actually did, rather than what it is
%supposed to do. A table over a space is invalidated by a write and
%re-evaluated on the next call, and until now nothing could see either
%happen: the guarantee was tested by its EFFECT, a fresh answer, which is
%also what an accidentally-rebuilt-from-scratch table produces.
%
%library(tableutil) already counts both, per subgoal variant, and its
%wording is the definition: invalidated is "Number of times an incremental
%table was invalidated", reevaluated is "Number of times an invalidated
%table was reevaluated. If lower than invalidated this implies that
%dependent nodes of the IDG were reevaluated to the same answer set"
%[source: SWI-Prolog 10.1 Reference Manual, A.59 library(tableutil)].
%That last sentence is the one worth surfacing: a gap between the two is
%SWI deciding a dependency changed without changing this table's answers,
%which is the incremental win being visible rather than assumed.
%
%The stat list is fixed rather than open. table_statistics/3 enumerates
%whatever it has, and answering all of it would publish trie-internal
%numbers that move with SWI's implementation; these five are the ones a
%caller can act on [tested: tabling_statistics_count_invalidations].
metta_table_statistics(Call, Stats) :-
    metta_tabling_target(Call, Module, Name, CompiledArity),
    functor(Head, Name, CompiledArity),
    findall([Reported, Value],
            reportable_table_statistic(Module:Head, Reported, Value),
            Stats).

%SWI's own spelling on the left, MeTTa's on the right: complete_call reads
%as complete-call beside every other name a MeTTa program sees.
reportable_table_statistic(Variant, Reported, Value) :-
    member(Stat-Reported, [tables-tables, answers-answers,
                           complete_call-'complete-call',
                           invalidated-invalidated, reevaluated-reevaluated]),
    ( catch(table_statistics(Variant, Stat, Value), _, fail) -> true ; Value = 0 ).

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
%If-then-else, not a cut. Every caller of this hook enumerates the whole
%predicate with forall/2, so a cut in one clause's body cuts THAT predicate's
%clause choice points and no handler ordered after this one runs. Clause order
%among multifile contributors is load order, and engine/duals.pl installs its
%handler with assertz, which appends: with tabling declared, a changed
%function abolished the tables and never dropped the stale dual, so
%(not-provable (pq 2)) answered both False from the recompiled path and True
%from the dual that was never dropped [tested: duals_survive_tabling].
metta_on_function_changed(_) :-
    ( metta_tabling_declared -> abolish_all_tables ; true ).

:- multifile metta_on_function_removed/1.
metta_on_function_removed(_) :-
    ( metta_tabling_declared -> abolish_all_tables ; true ).

%Nothing is tabled in the overwhelming majority of programs, and this hook
%runs on every equation the loader compiles, so the test that decides it is
%one indexed lookup on a predicate that is usually empty.
metta_tabling_declared :- 'get-atoms'('&petta', [tabled|_]), !.
