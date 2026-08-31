% Purpose: the runtime control plane for tabling MeTTa functions. Every
%   declaration is a constructed, module-qualified table/1 goal, never
%   interpolated source text, so hyphenated and uppercase names survive,
%   named spaces instrument their own implementation module, repeated
%   declarations are cumulative and idempotent, and every operation
%   verifies its effect and throws loudly when the engine disagrees.
%   Live declarations reflect into &metta as (tabled space name arity)
%   facts, input arity, asserted on declare and retracted on undeclare. The
%   tables are shared between SWI engines, so a Python Answers cursor and the
%   term runner reach one answer trie and report one set of statistics.
% Guarantees:
%   - a function change invalidates the tables MeTTa DECLARED and walks no
%     further: one equation change after a table of N answers was built and
%     dropped costs the same 377 inferences at N of 5,000, 20,000 and 80,000,
%     where abolish_all_tables/0 cost 2N [tested:
%     test_an_equation_change_does_not_pay_for_a_dropped_table; commit=WORKTREE]
%   - A declared table survives a write to a space it reads, and a change
%     to any equation drops it [tested: tabling_equation_change_drops_tables,
%     and end to end by examples/ch18-performance/18-02-memoisation-and-tabling/10-tabling_equation_change.metta and
%     examples/ch18-performance/18-02-memoisation-and-tabling/11-tabling_space_write.metta].
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
%     examples/ch18-performance/18-02-memoisation-and-tabling/12-tabling_statistics.metta].
%   - A read that cannot be resolved to one space predicate, or that names
%     a foreign space, is refused rather than tabled without the guarantee
%     [tested: tabling_refuses_unresolvable_reads].
%   - Reads of a parametric native space resolve to its reserved predicate in
%     its canonical storage module [tested:
%     test_two_instances_of_a_parametric_space_answer_independently;
%     commit=3c7bcde6a0670ec5c563584b26977b41cc727580].
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
%     (tabled Space Name Arity) facts this reflects into &metta are what
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

%A tabled call is another owner of the universal call-dispatch seam. Like
%lib_memo, install one indexed handler only for names that are enabled: an
%ordinary program that imports this library and tables nothing pays nothing at
%a call site.
:- multifile seam:dispatch_call/4.
:- dynamic seam:dispatch_call/4.
:- dynamic metta_tabling_dispatch_installed/1.
:- dynamic metta_tabling_registration/3.

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

%The function's clauses live in the module that owns the predicate visible at
%the call site. A named space may import a function from its parent; tabling
%the call-site module in that case wraps a shadow the executable call does not
%enter. imported_from/1 is SWI's published ownership question and is the same
%late-bound resolution pattern used by lib_memo's dispatch owner.
%
%A definition that has arrived but not been translated has no predicate to
%find yet, and asking current_predicate/1 is not a call, so the engine's
%undefined-predicate net does not fire for it. None visible is a loud refusal:
%declare after defining, because tabling a name that does not exist yet tables
%nothing.
metta_tabling_module(Name, CompiledArity, Module) :-
    metta_ensure_compiled(Name),
    current_metta_module(CallModule),
    (   metta_tabling_visible_owner(Name, CompiledArity, CallModule, Module)
    ->  true
    ;   metta_self_module(Self),
        Self \== CallModule,
        metta_tabling_visible_owner(Name, CompiledArity, Self, Module)
    ->  true
    ;   throw(error(existence_error(metta_function, Name/CompiledArity), none))
    ).

metta_tabling_visible_owner(Name, CompiledArity, CallModule, Module) :-
    current_predicate(CallModule:Name/CompiledArity),
    functor(Head, Name, CompiledArity),
    (   predicate_property(CallModule:Head, imported_from(From))
    ->  Module = From
    ;   Module = CallModule
    ).

%The same ownership decision drives execution. A ground-headed seam clause
%claims only a name with at least one live declaration, resolves the owner from
%the current call-site module at call time, and returns that exact qualified
%predicate. Late imports and two spaces defining the same name therefore keep
%their own tables.
metta_tabling_dispatch_call(Name, Args, Out, Goal) :-
    current_metta_module(CallModule),
    length(Args, InputArity),
    CompiledArity is InputArity + 1,
    metta_tabling_visible_owner(Name, CompiledArity, CallModule, Module),
    metta_tabling_registration(Name, Module, CompiledArity),
    functor(Head, Name, CompiledArity),
    predicate_property(Module:Head, tabled),
    append(Args, [Out], FullArgs),
    Direct =.. [Name|FullArgs],
    Goal = Module:Direct.

metta_tabling_register(Name, Module, CompiledArity) :-
    (   metta_tabling_registration(Name, Module, CompiledArity)
    ->  true
    ;   assertz(metta_tabling_registration(Name, Module, CompiledArity))
    ),
    metta_tabling_install_dispatch_handler(Name).

metta_tabling_install_dispatch_handler(Name) :-
    metta_tabling_dispatch_installed(Name),
    !.
metta_tabling_install_dispatch_handler(Name) :-
    assertz(seam:(dispatch_call(Name, Args, Out, Goal) :-
                      lib_tabling:metta_tabling_dispatch_call(Name, Args, Out,
                                                              Goal))),
    assertz(metta_tabling_dispatch_installed(Name)).

metta_tabling_unregister(Name, Module, CompiledArity) :-
    retractall(metta_tabling_registration(Name, Module, CompiledArity)),
    (   metta_tabling_registration(Name, _, _)
    ->  true
    ;   retractall(seam:(dispatch_call(Name, Args, Out, Goal) :-
                            lib_tabling:metta_tabling_dispatch_call(Name, Args,
                                                                    Out, Goal))),
        retractall(metta_tabling_dispatch_installed(Name))
    ).

%A table over a space also has to survive writes to that space, and SWI
%does that when both the table and the dynamic predicates it reads carry
%the incremental property [source: SWI-Prolog 10.1 Reference Manual 7.7].
%The predicates it reads are recoverable exactly: a match compiles to
%match(Space, Pattern, _, _) with a literal space identifier and list pattern.
%An atomic space uses its name as the storage functor; a parametric space uses
%the reserved functor in its canonical module. The walk follows the calls the
%body makes. Deriving them costs nothing per write,
%where a flag consulted on the write path measured two inferences of
%every five that add_sexp/3 spends [measured 2026-08-15].
%
%A read this cannot resolve is refused rather than tabled without the
%guarantee: a computed space or pattern, or a foreign space, whose atoms
%do not live in an SWI dynamic predicate at all.
%A DECLARATION MAY PRECEDE ITS DEFINITION. `!(tabled (fib $N))` written above
%`(= (fib $N) ...)` is the reading order upstream's own
%examples/tabling_fib.metta uses, and refusing it there refused a name the
%very next form defines. The declaration is HELD and installed when the
%function's clauses arrive, which is exactly what
%seam:function_clauses_changed/1 announces: "a handler that acts on the
%compiled predicate ... listens here instead, because at definition time there
%may be nothing to wrap and at materialisation time nothing else fires"
%[source: engine/ext_points.pl]. A name that is never defined never tables,
%and its held row is visible to the same (match &metta (tabled ...)) question
%the installed ones are [tested:
%examples/ch18-performance/18-02-memoisation-and-tabling/09-tabling_fib.metta].
%
%The handler clause is GROUND-HEADED and installed per held name, the shape
%lib_memo uses for seam:function_removed/1, because a resident handler costs
%four inferences on every compiled equation in the process
%[source: engine/ext_points.pl, measured 2026-08-15].
:- dynamic metta_tabling_held/1.

metta_tabled_decl(Call, true) :-
    \+ metta_tabling_resolvable(Call),
    !,
    metta_tabling_hold(Call).
metta_tabled_decl(Call, true) :-
    metta_tabling_target(Call, Module, Name, CompiledArity),
    functor(Head, Name, CompiledArity),
    ( predicate_property(Module:Head, tabled) -> WasTabled = true
                                               ; WasTabled = false ),
    catch(metta_tabling_declare(Module, Name, CompiledArity, Head),
          Error,
          ( metta_tabling_rollback_new_table(WasTabled, Module, Name,
                                             CompiledArity),
            throw(Error) )).

metta_tabling_resolvable(Call) :-
    catch(metta_tabling_target(Call, _, _, _),
          error(existence_error(metta_function, _), _),
          fail).

metta_tabling_hold(Call) :-
    metta_tabling_call_name(Call, Name),
    (   metta_tabling_held(Call)
    ->  true
    ;   assertz(metta_tabling_held(Call)),
        assertz(seam:(function_clauses_changed(Name) :-
                          lib_tabling:metta_tabling_release(Name)))
    ).

metta_tabling_call_name(Call0, Name) :-
    ( Call0 = [quote, Call] -> true ; Call = Call0 ),
    ( is_list(Call), Call = [Name|_], atom(Name)
      -> true
    ; throw(error(type_error(metta_function_call, Call0), none)) ).

%Every held declaration for this name, tried once its clauses exist. A
%declaration that still cannot resolve stays held: a function may be defined
%at one arity and declared at another, and the later definition is what
%decides.
metta_tabling_release(Name) :-
    forall(( metta_tabling_held(Call),
             metta_tabling_call_name(Call, Name) ),
           (   metta_tabling_resolvable(Call)
           ->  retract(metta_tabling_held(Call)),
               retractall(seam:(function_clauses_changed(Name) :-
                                    lib_tabling:metta_tabling_release(Name))),
               metta_tabled_decl(Call, _)
           ;   true
           )).

metta_tabling_declare(Module, Name, CompiledArity, Head) :-
    metta_tabling_install_table(Module, Name, CompiledArity),
    ( predicate_property(Module:Head, tabled),
      predicate_property(Module:Head, tabled(shared))
      -> true
    ; throw(error(metta_tabling_failed(Module:Name/CompiledArity), none)) ),
    metta_tabling_reflect(Module, Name, CompiledArity, Fact),
    metta_tabling_reflection_ensure(Fact),
    metta_tabling_register(Name, Module, CompiledArity).

metta_tabling_install_table(Module, Name, CompiledArity) :-
    (   metta_cache_unchecked(Name)
    ->  %The caller accepted staleness by declaration, so the purity walk is
        %skipped and the table is PLAIN: with reads unresolved there is
        %nothing sound to hang the incremental property on, and a stale
        %answer is exactly what (cache Name unchecked) accepts
        %[tested: an_unchecked_declaration_tables_an_impure_body].
        table(Module:Name/CompiledArity as shared)
    ;   metta_tabling_reads(Module, Name, CompiledArity, Reads),
        forall(member(Storage:Predicate, Reads),
               dynamic(Storage:Predicate as incremental)),
        table(Module:Name/CompiledArity as (incremental, shared))
    ).

metta_tabling_rollback_new_table(true, _, _, _) :- !.
metta_tabling_rollback_new_table(false, Module, Name, CompiledArity) :-
    catch(untable(Module:Name/CompiledArity), _, true).

metta_untabled_decl(Call, true) :-
    metta_tabling_target(Call, Module, Name, CompiledArity),
    untable(Module:Name/CompiledArity),
    functor(Head, Name, CompiledArity),
    ( predicate_property(Module:Head, tabled)
      -> throw(error(metta_untabling_failed(Module:Name/CompiledArity), none))
    ; true ),
    metta_tabling_reflect(Module, Name, CompiledArity, Fact),
    catch(metta_tabling_reflection_write(remove, Fact),
          Error,
          ( metta_tabling_install_table(Module, Name, CompiledArity),
            throw(Error) )),
    metta_tabling_unregister(Name, Module, CompiledArity).

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
    ( metta_space_name(Space) -> true
    ; throw(error(metta_tabling_unresolved_read(Operation, Space), none)) ),
    ( seam:foreign_space(Space)
      -> throw(error(metta_tabling_foreign_space(Operation, Space), none))
    ; true ),
    native_storage_module(Space, Storage),
    native_storage_functor(Space, Functor),
    metta_tabling_patterns(Operation, Pattern, Shapes),
    findall(Storage:Functor/Arity,
            ( member(Shape, Shapes),
              length(Shape, Count),
              Arity is Count + 1 ),
            Reads).

%The argument lists a pattern reads. A conjunction contributes one per
%conjunct; anything whose shape is not fixed cannot be resolved.
metta_tabling_patterns(Operation, Pattern, _) :-
    \+ is_list(Pattern), !,
    throw(error(metta_tabling_unresolved_read(Operation, Pattern), none)).
metta_tabling_patterns(Operation, [Comma|Conjuncts], Shapes) :-
    nonvar(Comma), Comma == ',', !,
    foldl(metta_tabling_conjunct(Operation), Conjuncts, [], Shapes).
metta_tabling_patterns(Operation, [Head|Arguments], [Arguments]) :-
    ( nonvar(Head) -> true
    ; throw(error(metta_tabling_unresolved_read(Operation, [Head|Arguments]), none)) ).

metta_tabling_conjunct(Operation, Conjunct, Shapes0, Shapes) :-
    metta_tabling_patterns(Operation, Conjunct, Found),
    append(Found, Shapes0, Shapes).

prolog:error_message(metta_tabling_unresolved_read(Operation, Culprit)) -->
    { swrite(Culprit, Text) },
    [ 'a tabled function reads ~w with ~w, which cannot be resolved to one \c
       space predicate, so writes to it could not invalidate the table. \c
       Name the space and the pattern shape, or do not table this \c
       function.'-[Operation, Text] ].
prolog:error_message(metta_tabling_foreign_space(Operation, Space)) -->
    [ 'a tabled function reads the foreign space ~w with ~w. Its atoms do \c
       not live in this engine, so a write there cannot invalidate the \c
       table. Do not table a function that reads a foreign space.'-[Space, Operation] ].

%The live-declaration record in &metta: the space whose module holds the
%predicate, the function name, and its INPUT arity, the arity a MeTTa caller
%sees. A standing exact record is the idempotent case, so repetition never
%writes or duplicates it.
metta_tabling_reflect(Module, Name, CompiledArity, [tabled, Space, Name, InputArity]) :-
    metta_module_space(Module, Space),
    InputArity is CompiledArity - 1.

%A reflection fact already standing is the idempotent case and needs no write.
%Every actual write must answer `true`, the answer this engine's effectful
%operations give (engine/metta/runtime.pl's note above 'println!'/2 carries the
%family). Failure, an error answer, or an exception is rethrown under one named
%tabling error so a caller cannot receive True from a declaration whose catalog
%state did not land.
metta_tabling_reflection_ensure(Fact) :-
    (   once('get-atoms'('&metta', Fact))
    ->  true
    ;   metta_tabling_reflection_write(add, Fact)
    ).

metta_tabling_reflection_write(Operation, Fact) :-
    catch((   metta_tabling_reflection_goal(Operation, Fact, Result)
          ->  Outcome = result(Result)
          ;   Outcome = failed
          ),
          Error,
          Outcome = exception(Error)),
    (   Outcome == result(true)
    ->  true
    ;   throw(error(metta_tabling_reflection_write_failed(Operation, Fact,
                                                          Outcome), none))
    ).

metta_tabling_reflection_goal(add, Fact, Result) :-
    'add-atom'('&metta', Fact, Result).
metta_tabling_reflection_goal(remove, Fact, Result) :-
    'remove-atom'('&metta', Fact, Result).

prolog:error_message(metta_tabling_reflection_write_failed(Operation, Fact,
                                                            Outcome)) -->
    { swrite(Fact, Text) },
    [ 'tabling could not ~w its reflection row ~w: the &metta write answered \c
       ~w. The table declaration and its catalog row must change together.'-
      [Operation, Text, Outcome] ].

%The engine's ordinary atom-removed event also covers pooled-space cleanup,
%which removes every (tabled Space ...) row after untabling its predicates. It
%therefore retires the indexed dispatch handler without a tabling-specific
%lifecycle callback or an engine edit.
:- multifile seam:atom_removed/2.
seam:atom_removed('&metta', Fact) :-
    (   Fact = [tabled, Space, Name, InputArity],
        atom(Name),
        integer(InputArity),
        space_module(Space, Module)
    ->  CompiledArity is InputArity + 1,
        metta_tabling_unregister(Name, Module, CompiledArity)
    ;   true
    ).

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
    % policy-inventory-exempt: documented-collision-decision; reason=the pairs pin the documented SWI statistic names to their public MeTTa spellings including complete_call to complete-call; evidence=lib/lib_tabling/lib_tabling.pl:reportable_table_statistic/3
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
:- multifile seam:function_changed/1.
%If-then-else, not a cut. Every caller of this hook enumerates the whole
%predicate with forall/2, so a cut in one clause's body cuts THAT predicate's
%clause choice points and no handler ordered after this one runs. Clause order
%among multifile contributors is load order, and engine/duals.pl installs its
%handler with assertz, which appends: with tabling declared, a changed
%function abolished the tables and never dropped the stale dual, so
%(not-provable (pq 2)) answered both False from the recompiled path and True
%from the dual that was never dropped [tested: duals_survive_tabling].
seam:function_changed(_) :-
    ( metta_tabling_declared -> metta_tabling_abolish_declared ; true ).

:- multifile seam:function_removed/1.
seam:function_removed(_) :-
    ( metta_tabling_declared -> metta_tabling_abolish_declared ; true ).

%Every table a MeTTa declaration made, and nothing else.
%
%abolish_all_tables/0 walks the WHOLE variant trie, which keeps a variant for
%every table the process has ever built. After one space tabled a
%200,000-answer recursion and was dropped, each call still cost 73ms with no
%live table left anywhere, and these two hooks fire once per compiled
%equation: one library import paid 13 walks and 0.9 seconds, and the 60-cycle
%drop test above spent 156 seconds
%[measured 2026-08-31: 5,266,337 inferences for one import, 2,600,026
%'$tbl_destroy_table'/1 calls under 13 abolish_all_tables/0 walks].
%
%abolish_table_subgoals/1 walks the same trie indexed by the predicate, so the
%cost is the tables a declared function actually has and a dropped space's
%variants are never walked again. abolish_module_tables/1 is NOT the
%narrowing: it misses `as shared` tables entirely, which is what every MeTTa
%table is [measured 2026-08-31: 50 tables before it and 50 after,
%0 after abolish_table_subgoals/1].
%
%The scope this drops is the tables of OTHER libraries, which own their own
%invalidation: lib_memo carries a generation argument rather than abolishing
%(its own comment says a private table cannot be selectively abolished across
%carriers), and engine/parser.pl abolishes metta_symbol_writable/1 itself.
metta_tabling_abolish_declared :-
    forall(metta_tabling_declared_table(Module, Head),
           abolish_table_subgoals(Module:Head)).

%metta_exec_module_known/2 rather than space_module/2: this is a READ, and
%space_module/2 would ENSURE a module for a space that has none, which is a
%space with no table to abolish.
metta_tabling_declared_table(Module, Head) :-
    'get-atoms'('&metta', [tabled, Space, Name, InputArity]),
    atom(Name),
    integer(InputArity),
    metta_exec_module_known(Space, Module),
    CompiledArity is InputArity + 1,
    functor(Head, Name, CompiledArity).

%Nothing is tabled in the overwhelming majority of programs, and this hook
%runs on every equation the loader compiles, so the test that decides it is
%one indexed lookup on a predicate that is usually empty.
metta_tabling_declared :- 'get-atoms'('&metta', [tabled|_]), !.
