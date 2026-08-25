% Purpose: memoize MeTTa function calls with C-trie exact bags or bounded
%   LRU/WTinyLFU storage and dependency-based invalidation.
% Assumes:
%   - every space, &self included, compiles its equations into a module of
%     its own and inherits the rest through that module's base chain, so a
%     function name alone does not name a function
%     [source: engine/spaces.pl, space_module/2]
%   - translated_from/2 is engine-wide, and a clause's module is what
%     places an equation in a space
%     [source: engine/spaces.pl, metta_remove_atom/3]
% Guarantees:
%   - Routine cache eviction does not write diagnostics to user_error
%     [tested 2026-08-14: memo_eviction_output].
%   - Memo aggregation values come from the memo-aggregate catalog
%     vocabulary; spelling aliases for eviction strategies remain only as
%     documented input collisions [tested:
%     test_a_planted_closed_policy_list_is_reported_by_the_inventory_lane;
%     commit=42b5d28232e75c32b20a1d5bf1f740fec134938d].
%   - Memoizing a function in one space leaves every other space's answers
%     unchanged [tested 2026-08-15: memo_space_isolation].
%   - The bespoke memo dependency graph has been replaced by the engine support
%     graph; transitive caller caches still invalidate under autoload=false
%     [tested: memo_support_graph:a_leaf_change_invalidates_transitive_callers_only,
%     support_graph:test_a_derived_fact_is_invalidated_forward_from_what_it_supports;
%     commit=7ade2b90e2631451fd6ffc23d22dd8c2d4a7a7aa].
%   - A pure recursive SCC is enabled automatically only when one retained RHS
%     calls that SCC at least twice; force/refuse catalog declarations override
%     profitability without weakening purity [tested:
%     test_a_doubly_branching_recursion_is_tabled_automatically_and_a_tail_recursion_is_not,
%     test_an_impure_function_is_never_cached_automatically,
%     test_automatic_cache_force_and_refuse_overrides; commit=9e7d5dc2cad810940e5386d52636ac6946df279d].
%   - Automatic caching preserves answer bags beyond memo_answer_limit/1,
%     ignores manual aggregation and keys floats exactly; bounded search is a
%     hard safety refusal because eager bag collection would change its
%     left-recursive control; an explicit SWI table takes precedence rather
%     than stacking both cache substrates [tested:
%     test_automatic_caching_preserves_multiplicity_and_answer_limit,
%     test_bounded_left_recursive_search_is_not_cached_automatically,
%     test_explicit_tabling_takes_precedence_over_automatic_memoization;
%     commit=9e7d5dc2cad810940e5386d52636ac6946df279d].
%   - get-memoize-stats/2 reports one function's live entry and answer counts,
%     preserving duplicate answer occurrences in the latter [tested:
%     lib_memo_stats:a_function_report_counts_answer_occurrences;
%     commit=04b794b718563ebb114800abebfc6f1200d7b835].
%   - Exact memoization stores each distinct solved answer in SWI's C answer
%     trie with a summed occurrence count, then expands that count on replay;
%     equal answers therefore remain equal bag occurrences [tested:
%     test_exact_cache_matches_uncached_answer_bags;
%     commit=04b794b718563ebb114800abebfc6f1200d7b835].
% Decides: cache state is keyed by the module that holds the function's
%   clauses, the way lib_tabling.pl keys its declarations. The function
%   name stays the first argument, which is where it earns its place on
%   the tables consulted with only a name bound: memo_enabled/2 and
%   metta_memo_generation/4 both index on argument 1 at 47x over sixty
%   functions in one module, and memo_enabled/2 is what the dispatch
%   hook's fast-fail guard reads. metta_memo_entry/6 does NOT depend on
%   the ordering: SWI assesses every instantiated argument and picks the
%   canonicalized key, deep-indexing into it at 19.8x over 1,200 entries
%   [measured 2026-08-15 with library(prolog_jiti), jiti_list/1]
%   [source: SWI-Prolog 10.1 Reference Manual 2.17, index selection].
% Owns resources: exact_memo_specialization/5 owns one generated replay
%   predicate, mode-directed table predicate and its answer tries per cached
%   function arity. Invalidation abolishes its answers; function removal
%   untables and abolishes both generated predicates.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- use_module(library(lists)).
:- use_module(library(ordsets)).
:- use_module(library(solution_sequences)).
:- use_module(library(tables)).
:- use_module(library(terms)). %term_size/2, for eviction cost accounting

% State Declarations
%
% Every table is keyed by (Fun, Module): the module is the one whose
% clauses answer the call. Keyed by name alone, enabling memoization in
% one space enabled it in all of them, one cache served every space, and
% two spaces defining the same name answered with each other's equations.

% Tracks functions currently enabled for memoization.
% memo_enabled/2 means all arities for Fun in Module are memoized.
% memo_enabled/3 means only a specific call arity (input-argument count).
:- dynamic memo_enabled/2.
:- dynamic memo_enabled/3.
:- dynamic memo_automatic_enabled/2.
:- dynamic memo_automatic_decision/4.
:- dynamic memo_automatic_dirty/1.
:- dynamic arity/2.

% Cached results: metta_memo_entry(Fun, Module, Arity, Gen, AVs, Results).
% Exact decorator tables: exact_memo_specialization(ReplayName, TableName,
% Fun, Module, Arity).
:- dynamic metta_memo_entry/6.
:- dynamic exact_memo_specialization/5.

% Generation counter per (Fun, Module, Arity) for invalidation
:- dynamic metta_memo_generation/4.

% Queue state for LRU/WTinyLFU eviction
:- dynamic metta_memo_count/4.
:- dynamic metta_memo_head/4.
:- dynamic metta_memo_tail/4.
:- dynamic metta_memo_q/5.

% Global memory tracking
:- dynamic metta_memo_total_bytes/1.

% Tracks keys currently being computed (avoids duplicate recursive probes)
:- dynamic metta_memo_in_progress/5.

% Lightweight runtime metrics
:- dynamic metta_memo_stat/2.

% Per-thread call context to build dependency graph cheaply
:- thread_local metta_memo_call_ctx/3.

% Module Resolution

%The module a call is dispatched in is not always the module holding the
%clauses: a space compiles its own equations into its own module and
%inherits everything else through it. Cache under the module that defines
%the predicate, or one shared function reached from two spaces gets two
%caches and neither invalidates the other. imported_from/1 is the
%documented way to ask
%[source: SWI-Prolog 10.1 Reference Manual 4.15, predicate_property/2].
memo_owner_module(Fun, CallModule, PredArity, Module) :-
    functor(Head, Fun, PredArity),
    (   predicate_property(CallModule:Head, imported_from(From))
    ->  Module = From
    ;   Module = CallModule ).

%Which module a call from the running space is asking about: its own when
%the space defines the function, &self's when it only inherits it. Used by
%the public API, where no arity is in hand and the equations answer.
memo_scope_module(Fun, Module) :-
    current_metta_module(CallModule),
    metta_self_module(Self),
    (   CallModule \== Self,
        memo_equation(Fun, CallModule, any, _)
    ->  Module = CallModule
    ;   Module = Self ).

%This module's equations for Fun, with a fixed input arity when one is
%asked for and every arity for `any`. The clause's module is the test:
%translated_from/2 is engine-wide, and the same equation imported into two
%spaces has one entry per module.
%
%The SHAPE is built before the store is asked, because every caller binds Fun
%and the head sits inside the second argument. Asking translated_from/2 for an
%unbound term first and destructuring after walked every equation in the
%engine on each lookup; the pattern gives SWI's deep index at 2/2/1 a position
%to discriminate on and the walk becomes one probe. A fixed arity narrows the
%pattern further, which is why length/2 also moves ahead of the store
%[measured 2026-08-23: 20,000 lookups against a module of M equations cost
%0.140s at M=200, 0.515 at 800, 2.037 at 3,200 and 8.628 at 12,800, exactly
%4.0x per 4x module, and cost 0.0086, 0.0088, 0.0090 and 0.0155; tested:
%memo_equation_lookup:one_head_is_found_without_walking_the_other_equations].
%
%That walk was invisible to the inference counter, which is why it stood.
%Failing a clause head sends the VM to shallow_backtrack, whose CHP_CLAUSE
%branch asks nextClause/4 for the next candidate and resumes at
%NEXT_INSTRUCTION; the counter is only ever raised on the call and depart path
%[source: SWI-Prolog src/pl-vmi.c, VMH(shallow_backtrack) against
%VMH(depart_or_retry_continue), which holds the one
%LD->statistics.inferences++ of the two; V10.1.13, upstream commit
%fc7ef84b949378b729052c3ade79c90ce5416abb, the version this engine runs on].
%So a candidate rejected by head unification costs instructions and no
%inference, and statistics/2 reports THREE for this lookup whether the walk
%crosses 20 clauses or 20,000 [measured 2026-08-23 at 20, 200, 2,000 and
%20,000]. The tracer does see it, because the same branch keeps a CHP_DEBUG
%choice point while the debugger is on: at 20 clauses it reports one call of
%translated_from/2, 19 redos and 20 exits in the old order against one call,
%no redo and one exit in this one [measured 2026-08-23 through
%prolog_trace_interception/4]. plunit meta-calls its test bodies and cannot
%trace them, so the test that pins this is TIMED, the only one in the tree
%that has to be.
memo_equation(Fun, Module, Arities, Term) :-
    Term = [=, [Fun|Args], _],
    ( Arities == any -> true ; length(Args, Arities) ),
    translated_from(Ref, Term),
    clause_property(Ref, module(Module)).


% Runtime Hook Integration

:- multifile seam:dispatch_call/4.
:- dynamic seam:dispatch_call/4.
:- dynamic memo_dispatch_installed/1.

memo_dispatch_call(Fun, Args, Out, Goal) :-
    memo_name_enabled(Fun),
    current_metta_module(CallModule),
    length(Args, CallArity),
    PredArity is CallArity + 1,
    memo_owner_module(Fun, CallModule, PredArity, Module),
    memoization_enabled_for_call(Fun, Module, CallArity),
    ( memo_exact_for_predicate(Fun, Module, PredArity),
      exact_memo_specialization(ReplayName, _TableName,
                                Fun, Module, PredArity)
    -> append(Args, [Out], ReplayArgs),
       ReplayGoal =.. [ReplayName | ReplayArgs],
       Goal = Module:ReplayGoal
    ;  Goal = cache_call(Fun, CallModule, Args, Out)
    ).

%Tell the shared effect walk which source call this transparent dispatcher
%executes. Reconciliation can then re-check a function after it has been
%compiled through the cache without mistaking cache_call/4 for a user effect.
:- multifile seam:effect_operation_name/3.
seam:effect_operation_name(cache_call(Fun, _, Args, _), Fun, Arity) :-
    length(Args, InputArity),
    Arity is InputArity + 1.
seam:effect_operation_name(Module:Goal, Fun, Arity) :-
    callable(Goal),
    functor(Goal, ReplayName, Arity),
    exact_memo_specialization(ReplayName, _TableName,
                              Fun, Module, Arity).
seam:effect_operation_name(Goal, Fun, Arity) :-
    callable(Goal),
    functor(Goal, ReplayName, Arity),
    exact_memo_specialization(ReplayName, _TableName,
                              Fun, _Module, Arity).

:- multifile prolog:error_message//1.
prolog:error_message(permission_error(memoize, volatile_function, Name)) -->
    [ '~w is declared volatile, so its answers are not reproducible and a \c
       cache would skip whatever the call does. Ask the library that \c
       registered it, or memoize a wrapper whose answers are.'-[Name] ].

%The guard that runs before anything else: this hook is consulted for every
%reduced call and every compiled call site, and reading the module, then
%resolving the owner, is work wasted whenever nothing by this name is
%memoized at all. memo_enabled/2 indexes on the name it is given
%[measured 2026-08-15: argument 1, 47x over sixty functions, jiti_list/1].
memo_name_enabled(Fun) :- memo_enabled(Fun, _), !.
memo_name_enabled(Fun) :- memo_enabled(Fun, _, _), !.
memo_name_enabled(Fun) :- memo_automatic_enabled(Fun, _), !.

memo_enabled_name(Fun) :- memo_enabled(Fun, _).
memo_enabled_name(Fun) :- memo_enabled(Fun, _, _).
memo_enabled_name(Fun) :- memo_automatic_enabled(Fun, _).

%The dispatch seam is a compile-path hook, so merely having a resident clause
%prices every ordinary call site. Install it only while at least one manual or
%automatic cache is live, matching the extension seam's zero-cost-until-used
%contract. Ground handler heads let SWI's first-argument index skip every
%unrelated function even while another function is cached.
memo_refresh_dispatch_handler :-
    findall(Fun, memo_enabled_name(Fun), Needed0),
    sort(Needed0, Needed),
    findall(Fun, memo_dispatch_installed(Fun), Installed0),
    sort(Installed0, Installed),
    ord_subtract(Needed, Installed, Add),
    ord_subtract(Installed, Needed, Remove),
    maplist(memo_install_dispatch_handler, Add),
    maplist(memo_remove_dispatch_handler, Remove).

memo_install_dispatch_handler(Fun) :- memo_dispatch_installed(Fun), !.
memo_install_dispatch_handler(Fun) :-
    assertz(seam:(dispatch_call(Fun, Args, Out, Goal) :-
                      lib_memo:memo_dispatch_call(Fun, Args, Out, Goal))),
    assertz(memo_dispatch_installed(Fun)).

memo_remove_dispatch_handler(Fun) :-
    retractall(seam:(dispatch_call(Fun, Args, Out, Goal) :-
                         lib_memo:memo_dispatch_call(Fun, Args, Out, Goal))),
    retractall(memo_dispatch_installed(Fun)).

%Only a changed source-call graph can move an SCC decision. The support graph
%filters unrelated equations before announcing this event; source batches run
%Tarjan once at their boundary, while an isolated mutation drains immediately.
:- multifile seam:function_call_graph_changed/2.
seam:function_call_graph_changed(_, Module) :-
    memo_automatic_mark_dirty(Module),
    ( active_source_program(_) -> true ; memo_automatic_reconcile_dirty ).

:- multifile seam:source_program_compiled/0.
seam:source_program_compiled :-
    memo_automatic_reconcile_dirty.

:- multifile seam:cache_policy_changed/1.
seam:cache_policy_changed(Fun) :-
    memo_automatic_mark_policy_changed(Fun),
    memo_automatic_reconcile_dirty.

:- multifile seam:automatic_cache_explanation/3.
seam:automatic_cache_explanation(Fun, Choice, Reason) :-
    %An explanation is an inspection: a deferred definition has no memo rules
    %and no equations to read yet, and nothing here CALLS Fun, so the
    %undefined-procedure net cannot force it. Without the force the explain
    %report simply carried no cache row for a function that was defined and
    %never called [measured 2026-08-24: tests/test_automatic_tabling.py].
    metta_ensure_compiled(Fun),
    memo_scope_module(Fun, Module),
    (   memo_manual_enabled(Fun, Module)
    ->  Choice = manual,
        Reason = declaration
    ;   memo_automatic_decision(Fun, Module, Choice, Reason)
    ->  true
    ;   once(memo_equation(Fun, Module, any, _)),
        Choice = declined,
        Reason = 'not-recursive'
    ).

%The removal hook fires only once no space defines the name any more
%[source: engine/spaces.pl, metta_remove_atom/3], so the disable is global.
:- multifile seam:function_removed/1.
:- dynamic seam:function_removed/1.
:- dynamic memo_function_removed_installed/1.

memo_function_removed(Fun) :-
    memo_state_modules(Fun, Modules),
    forall(member(Module, Modules),
           ( forget_memo_supports(Fun, Module),
             remove_exact_memo_specializations(Fun, Module) )),
    disable_memoization(Fun),
    retractall(memo_automatic_enabled(Fun, _)),
    retractall(memo_automatic_decision(Fun, _, _, _)),
    memo_refresh_dispatch_handler,
    memo_refresh_function_removed_handler.

memo_refresh_function_removed_handler :-
    findall(Fun, memo_lifecycle_state(Fun), Needed0),
    sort(Needed0, Needed),
    findall(Fun, memo_function_removed_installed(Fun), Installed0),
    sort(Installed0, Installed),
    ord_subtract(Needed, Installed, Add),
    ord_subtract(Installed, Needed, Remove),
    maplist(memo_install_function_removed_handler, Add),
    maplist(memo_remove_function_removed_handler, Remove).

memo_lifecycle_state(Fun) :- memo_enabled(Fun, _).
memo_lifecycle_state(Fun) :- memo_enabled(Fun, _, _).
memo_lifecycle_state(Fun) :- memo_automatic_enabled(Fun, _).
memo_lifecycle_state(Fun) :- memo_automatic_decision(Fun, _, _, _).

memo_install_function_removed_handler(Fun) :-
    memo_function_removed_installed(Fun),
    !.
memo_install_function_removed_handler(Fun) :-
    assertz(seam:(function_removed(Fun) :-
                      lib_memo:memo_function_removed(Fun))),
    assertz(memo_function_removed_installed(Fun)).

memo_remove_function_removed_handler(Fun) :-
    retractall(seam:(function_removed(Fun) :-
                         lib_memo:memo_function_removed(Fun))),
    retractall(memo_function_removed_installed(Fun)).

memo_state_modules(Fun, Modules) :-
    findall(M,
        ( memo_enabled(Fun, M)
        ; memo_enabled(Fun, M, _)
        ; memo_automatic_enabled(Fun, M)
        ; memo_automatic_decision(Fun, M, _, _)
        ; metta_memo_entry(Fun, M, _, _, _, _)
        ; metta_memo_generation(Fun, M, _, _)
        ; exact_memo_specialization(_, _, Fun, M, _)
        ),
        Raw),
    sort(Raw, Modules).

:- thread_local memo_automatic_reconciling/0.

%A policy write is rare and may force a non-recursive function, so it takes
%the wider function-view lookup. Equation changes stay on the candidate index
%above, keeping unrelated source definitions off the decision path.
memo_automatic_mark_policy_changed(Fun) :-
    findall(Module,
            ( support_view_module(Fun, Module)
            ; memo_automatic_enabled(Fun, Module)
            ; memo_automatic_decision(Fun, Module, _, _) ),
            Modules0),
    sort(Modules0, Modules),
    forall(member(Module, Modules), memo_automatic_mark_dirty(Module)).

memo_automatic_mark_dirty(Module) :-
    ( memo_automatic_dirty(Module) -> true
    ; assertz(memo_automatic_dirty(Module)) ).

memo_automatic_reconcile_dirty :- memo_automatic_reconciling, !.
memo_automatic_reconcile_dirty :-
    findall(Module, retract(memo_automatic_dirty(Module)), Modules0),
    sort(Modules0, Modules),
    (   Modules == []
    ->  true
    ;   setup_call_cleanup(
            asserta(memo_automatic_reconciling, Ref),
            memo_automatic_reconcile_modules(Modules),
            erase(Ref))
    ).

%Compute every dirty module before changing any dispatch. Then publish the
%whole new state before recompiling a name, so mutually recursive members see
%one another enabled whichever component order Tarjan returned.
memo_automatic_reconcile_modules(Modules) :-
    maplist(memo_automatic_module_plan, Modules, Plans),
    maplist(memo_automatic_apply_plan, Plans, ChangedLists),
    append(ChangedLists, Changed0),
    sort(Changed0, Changed),
    memo_refresh_dispatch_handler,
    memo_refresh_function_removed_handler,
    forall(member(Fun, Changed),
           ( recompile_function_impl(Fun),
             forall(support_memo_take_change(_, Fun), true) )).

memo_automatic_module_plan(Module, plan(Module, Decisions)) :-
    support_memo_sccs(Module, Components),
    findall(Fun,
            ( member(memo_scc(Members, _, _), Components),
              member(Fun, Members) ),
            RecursiveFuns0),
    sort(RecursiveFuns0, RecursiveFuns),
    %The declarations drive, not the equations. Asking every equation in the
    %module whether its name carried a cache declaration made this reconciliation
    %linear in the module, and it runs once per source whose call graph changed,
    %so a program built by loading K sources paid it K times over a module that
    %grew each time [measured 2026-08-23: compiling a two-form source with one
    %source call into a space already holding M equations cost 4,831 inferences
    %at M=200 and 37,831 at M=3,200, exactly 11.0 an equation; it is 2,615 at
    %both now and unchanged at M=25,600; tested:
    %memo_cache_override:reconciling_a_source_costs_nothing_that_grows_with_the_module].
    %(cache F ...) rows are a first-argument lookup in the catalog and there are
    %normally none, so the probe that confirms F has an equation HERE runs at
    %most once a declaration.
    findall(Fun,
            ( memo_cache_override(Fun, _),
              \+ memberchk(Fun, RecursiveFuns),
              once(memo_equation(Fun, Module, any, _)) ),
            OverrideFuns0),
    sort(OverrideFuns0, OverrideFuns),
    findall(Decision,
            ( member(Component, Components),
              Component = memo_scc(Members, _, _),
              member(Fun, Members),
              memo_automatic_function_decision(Module, Fun, Component,
                                                Decision) ),
            RecursiveDecisions),
    findall(Decision,
            ( member(Fun, OverrideFuns),
              memo_automatic_function_decision(
                  Module, Fun, memo_scc([Fun], false, 0), Decision) ),
            OverrideDecisions),
    append(RecursiveDecisions, OverrideDecisions, Decisions).

memo_automatic_function_decision(_, Fun, _,
                                 decision(Fun, false, refused, declaration)) :-
    memo_cache_override(Fun, refuse),
    !.
memo_automatic_function_decision(Module, Fun, Component,
                                 decision(Fun, false, declined, Reason)) :-
    memo_automatic_candidate(Fun, Component),
    memo_automatic_unsafe_reason(Fun, Module, Reason),
    !.
memo_automatic_function_decision(_, Fun, _,
                                 decision(Fun, true, forced, declaration)) :-
    memo_cache_override(Fun, force),
    !.
memo_automatic_function_decision(_, Fun,
                                 memo_scc(Members, true, MaxCalls),
                                 decision(Fun, true, automatic,
                                          ['recursive-scc', Members,
                                           'body-call-count', MaxCalls])) :-
    MaxCalls >= 2,
    !.
memo_automatic_function_decision(_, Fun, memo_scc(_, true, _),
                                 decision(Fun, false, declined,
                                          'single-recursive-call')) :- !.
memo_automatic_function_decision(_, Fun, _,
                                 decision(Fun, false, declined,
                                          'not-recursive')).

%Purity is the expensive half of admission and is needed only when the
%profitability rule or a force declaration could enable the function. Ordinary
%non-recursive definitions pay the one batched graph walk, not one effect walk
%per definition.
memo_automatic_candidate(Fun, _) :- memo_cache_override(Fun, force), !.
memo_automatic_candidate(_, memo_scc(_, true, MaxCalls)) :- MaxCalls >= 2.

memo_cache_override(Fun, Mode) :-
    petta_contract_fact([cache, Fun, Mode]).

memo_automatic_unsafe_reason(Fun, _, [volatile, Fun]) :-
    \+ metta_function_cacheable(Fun),
    !.
memo_automatic_unsafe_reason(Fun, Module, 'explicit-tabling') :-
    current_predicate(Module:Fun/Arity),
    functor(Head, Fun, Arity),
    predicate_property(Module:Head, tabled),
    !.
memo_automatic_unsafe_reason(Fun, Module, ['bounded-search', Control]) :-
    memo_equation(Fun, Module, any, [=, _, Body]),
    sub_term(Form, Body),
    nonvar(Form),
    Form = [Control|_],
    atom(Control),
    % policy-inventory-exempt: mechanism-internal; reason=once take and top are the fixed bounded-search controls whose branch pruning conflicts with eager answer-bag collection; evidence=lib/lib_memo.pl:memo_automatic_unsafe_reason/3
    memberchk(Control, [once, take, top]),
    !.
memo_automatic_unsafe_reason(Fun, Module, Reason) :-
    findall(Arity,
            ( memo_equation(Fun, Module, any, [=, [_|Args], _]),
              length(Args, InputArity),
              Arity is InputArity + 1 ),
            Arities0),
    sort(Arities0, Arities),
    member(Arity, Arities),
    memo_automatic_arity_unsafe(Fun, Module, Arity, Reason),
    !.

memo_automatic_arity_unsafe(Fun, Module, Arity, Reason) :-
    catch(( metta_effect_walk(Module, [Fun/Arity], Reads),
            Result = reads(Reads) ),
          Error,
          Result = error(Error)),
    (   Result = error(error(metta_impure_goal(Goal), _))
    ->  Reason = [impure, Goal]
    ;   Result = error(Error)
    ->  Reason = [impure, Error]
    ;   Result = reads(Reads),
        Reads \== [],
        Reason = ['space-read', Reads]
    ).

memo_automatic_apply_plan(plan(Module, Decisions), Changed) :-
    findall(Fun, memo_automatic_enabled(Fun, Module), OldEnabled0),
    sort(OldEnabled0, OldEnabled),
    findall(Fun, member(decision(Fun, true, _, _), Decisions), NewEnabled0),
    sort(NewEnabled0, NewEnabled),
    ord_symdiff(OldEnabled, NewEnabled, Changed),
    transaction(
        ( retractall(memo_automatic_enabled(_, Module)),
          retractall(memo_automatic_decision(_, Module, _, _)),
          forall(member(decision(Fun, Enabled, Choice, Reason), Decisions),
                 ( assertz(memo_automatic_decision(Fun, Module,
                                                   Choice, Reason)),
                   ( Enabled == true
                   -> assertz(memo_automatic_enabled(Fun, Module))
                   ;  true ) )) )),
    forall(member(Fun, NewEnabled),
           memo_automatic_record_sources(Fun, Module)),
    forall(( member(Fun, Changed),
             \+ memberchk(Fun, NewEnabled),
             \+ memo_manual_enabled(Fun, Module) ),
           ( cache_invalidate(Fun, Module),
             forget_memo_supports(Fun, Module) )).

memo_automatic_record_sources(Fun, Module) :-
    memo_state_arities(Fun, Module, Arities),
    forall(member(Arity, Arities), record_memo_source(Fun, Module, Arity)).

memo_manual_enabled(Fun, Module) :- memo_enabled(Fun, Module), !.
memo_manual_enabled(Fun, Module) :- memo_enabled(Fun, Module, _).

% Configuration API

:- dynamic memo_strategy/1.
:- dynamic memo_unique_limit/1.
:- dynamic memo_size_limit/1.
:- dynamic memo_float_precision/1.
:- dynamic memo_answer_limit/1.
:- dynamic memo_aggregate_mode/1.

% Defaults
memo_unique_limit(100).
memo_strategy(wtinylfu).
memo_float_precision(12).
memo_size_limit(5368709120).  % ~5GB (global limit)
memo_answer_limit(2048).      % Cap stored answers per key
memo_aggregate_mode(none).    % none|min|max|sum|count (ground path)
metta_memo_total_bytes(0).    % Global bytes tracker

normalize_memo_strategy(In, wtinylfu) :-
    % policy-inventory-exempt: documented-collision-decision; reason=legacy spellings intentionally normalize to the one wtinylfu strategy; evidence=lib/lib_memo.pl:normalize_memo_strategy/2
    memberchk(In, [wtinylfu, 'WTinyLFU', 'W-TinyLFU', 'wtinylfu', 'w-tinylfu']), !.
normalize_memo_strategy(In, lru) :-
    % policy-inventory-exempt: documented-collision-decision; reason=case variants intentionally normalize to the one lru strategy; evidence=lib/lib_memo.pl:normalize_memo_strategy/2
    memberchk(In, [lru, 'LRU']), !.
normalize_memo_strategy(In, Out) :-
    atom(In),
    downcase_atom(In, D),
    normalize_memo_strategy(D, Out).

apply_memo_option([strategy, Raw]) :-
    normalize_memo_strategy(Raw, S), !,
    retractall(memo_strategy(_)),
    assertz(memo_strategy(S)).
apply_memo_option(['unique-limit', N]) :-
    integer(N), N > 0, !,
    retractall(memo_unique_limit(_)),
    assertz(memo_unique_limit(N)).
apply_memo_option(['size-limit', N]) :-
    (integer(N) ; float(N)), N > 0, !,
    retractall(memo_size_limit(_)),
    Bytes is round(N * 1073741824),  % Convert GB to bytes
    assertz(memo_size_limit(Bytes)).
apply_memo_option([float, N]) :-
    integer(N), N >= 0, !,
    retractall(memo_float_precision(_)),
    assertz(memo_float_precision(N)).
apply_memo_option(['answer-limit', N]) :-
    integer(N), N > 0, !,
    retractall(memo_answer_limit(_)),
    assertz(memo_answer_limit(N)).
apply_memo_option([aggregate, Mode]) :-
    petta_vocabulary_value('memo-aggregate', Mode), !,
    retractall(memo_aggregate_mode(_)),
    assertz(memo_aggregate_mode(Mode)).
apply_memo_option(Opt) :-
    throw(error(domain_error(memoize_option, Opt), 'config-memoize/2')).

'config-memoize'(Opt1, true) :-
    apply_memo_option(Opt1).
'config-memoize'(Opt1, Opt2, true) :-
    apply_memo_option(Opt1),
    apply_memo_option(Opt2).
'config-memoize'(Opt1, Opt2, Opt3, true) :-
    apply_memo_option(Opt1),
    apply_memo_option(Opt2),
    apply_memo_option(Opt3).

'get-memoize-config'(Config) :-
    memo_strategy(S),
    memo_unique_limit(UniqueLimit),
    memo_size_limit(SizeLimit),
    memo_float_precision(Prec),
    memo_answer_limit(AnswerLimit),
    memo_aggregate_mode(AggMode),
    Config = [[strategy, S], ['unique-limit', UniqueLimit], ['size-limit', SizeLimit], [float, Prec], ['answer-limit', AnswerLimit], [aggregate, AggMode]].

% Stats API

memo_stat_inc(Key) :-
    ( retract(metta_memo_stat(Key, N0)) -> N is N0 + 1 ; N = 1 ),
    asserta(metta_memo_stat(Key, N)).

memo_stats_snapshot(Stats) :-
    findall([K, V], metta_memo_stat(K, V), Stats).

'get-memoize-stats'(Stats) :-
    memo_stats_snapshot(Stats).

'get-memoize-stats'(Fun, [[entries, EntryCount], [answers, AnswerCount]]) :-
    memo_scope_module(Fun, Module),
    findall(Results,
            metta_memo_entry(Fun, Module, _, _, _, Results),
            Bags),
    length(Bags, PrologEntryCount),
    maplist(length, Bags, AnswerCounts),
    sum_list(AnswerCounts, PrologAnswerCount),
    exact_memo_table_stats(Fun, Module, TrieEntryCount, TrieAnswerCount),
    EntryCount is PrologEntryCount + TrieEntryCount,
    AnswerCount is PrologAnswerCount + TrieAnswerCount.

exact_memo_table_stats(Fun, Module, EntryCount, AnswerCount) :-
    findall(Trie,
            current_exact_memo_table(Fun, Module, Trie),
            Tries),
    length(Tries, EntryCount),
    findall(Multiplicity,
            ( member(Trie, Tries),
              get_returns(Trie, Return),
              exact_memo_return_multiplicity(Return, Multiplicity) ),
            Multiplicities),
    sum_list(Multiplicities, AnswerCount).

current_exact_memo_table(Fun, Module, Trie) :-
    exact_memo_specialization(_ReplayName, TableName,
                              Fun, Module, Arity),
    TableArity is Arity + 1,
    functor(TableGoal, TableName, TableArity),
    get_calls(Module:TableGoal, Trie, _Return).

exact_memo_return_multiplicity(Return, Multiplicity) :-
    compound_name_arguments(Return, ret, ReturnArgs),
    last(ReturnArgs, Multiplicity).

'clear-memoize-stats'(true) :-
    retractall(metta_memo_stat(_, _)).

% Lifecycle, Dependencies, and Invalidation

enable_memoization(Fun, Module) :-
    ( memo_enabled(Fun, Module) -> true ; assertz(memo_enabled(Fun, Module)) ),
    memo_install_dispatch_handler(Fun),
    memo_install_function_removed_handler(Fun),
    memo_state_arities(Fun, Module, Arities),
    forall(member(Arity, Arities), record_memo_source(Fun, Module, Arity)).

enable_memoization(Fun, Module, CallArity) :-
    ( memo_enabled(Fun, Module, CallArity) -> true
    ; assertz(memo_enabled(Fun, Module, CallArity)) ),
    memo_install_dispatch_handler(Fun),
    memo_install_function_removed_handler(Fun),
    PredArity is CallArity + 1,
    record_memo_source(Fun, Module, PredArity).

enable_exact_memoization(Fun, Module, Arities) :-
    ( memo_enabled(Fun, Module, exact) -> true
    ; assertz(memo_enabled(Fun, Module, exact)) ),
    memo_install_dispatch_handler(Fun),
    memo_install_function_removed_handler(Fun),
    forall(member(Arity, Arities),
           ( ensure_exact_memo_specialization(Fun, Module, Arity),
             record_memo_source(Fun, Module, Arity) )).

ensure_exact_memo_specialization(Fun, Module, Arity) :-
    exact_memo_specialization(_, _, Fun, Module, Arity),
    !.
ensure_exact_memo_specialization(Fun, Module, Arity) :-
    atomic_list_concat(['$petta_exact_replay$', Fun, '$', Arity], ReplayName),
    atomic_list_concat(['$petta_exact_table$', Fun, '$', Arity], TableName),
    length(RawArgs, Arity),
    ReplayHead =.. [ReplayName | RawArgs],
    append(RawArgs, [Multiplicity], TableArgs),
    TableHead =.. [TableName | TableArgs],
    append(RawArgs, [1], ProducerArgs),
    ProducerHead =.. [TableName | ProducerArgs],
    RawGoal =.. [Fun | RawArgs],
    SameContextBody =
        ( lib_memo:metta_memo_call_ctx(Fun, Module, Arity),
          !,
          TableHead,
          between(1, Multiplicity, _Occurrence) ),
    RootBody = lib_memo:exact_specialized_root(
                   Fun, Module, Arity, Module:TableHead, Multiplicity),
    assertz(Module:(ProducerHead :- RawGoal)),
    declare_exact_memo_table(Module, TableName, Arity),
    assertz(Module:(ReplayHead :- SameContextBody)),
    assertz(Module:(ReplayHead :- RootBody)),
    assertz(exact_memo_specialization(ReplayName, TableName,
                                      Fun, Module, Arity)).

% A normal argument is answer identity; sum is its coefficient. Every raw
% proof contributes one in ProducerHead above, so equal solved answers occupy
% one C-trie answer whose coefficient is their exact multiplicity. SWI uses
% this mode to count tabled proof alternatives in test_wfs.pl.
% Source: SWI-Prolog/swipl-devel f49d28558b5f1ade8348f254b5583117e773b2bb,
% boot/tabling.pl and tests/tabling/test_wfs.pl.
exact_memo_mode_head(TableName, Arity, ModeHead) :-
    TableArity is Arity + 1,
    functor(ModeHead, TableName, TableArity),
    arg(TableArity, ModeHead, sum).

declare_exact_memo_table(Module, TableName, Arity) :-
    exact_memo_mode_head(TableName, Arity, ModeHead),
    table(Module:ModeHead).

disable_memoization(Fun) :-
    findall(Module,
            exact_memo_specialization(_, _, Fun, Module, _),
            ExactModules0),
    sort(ExactModules0, ExactModules),
    forall(member(Module, ExactModules),
           remove_exact_memo_specializations(Fun, Module)),
    retractall(memo_enabled(Fun, _)),
    retractall(memo_enabled(Fun, _, _)).

memo_current_generation(Fun, Module, Arity, Gen) :-
    ( metta_memo_generation(Fun, Module, Arity, Found) -> Gen = Found ; Gen = 0 ).

bump_metta_memo_generation(Fun, Module, Arity) :-
    memo_current_generation(Fun, Module, Arity, Prev),
    Next is Prev + 1,
    retractall(metta_memo_generation(Fun, Module, Arity, _)),
    assertz(metta_memo_generation(Fun, Module, Arity, Next)).

memo_state_arities(Fun, Module, Arities) :-
    findall(Arity,
        ( arity(Fun, Arity)
        ; metta_memo_generation(Fun, Module, Arity, _)
        ; metta_memo_entry(Fun, Module, Arity, _, _, _)
        ; metta_memo_count(Fun, Module, Arity, _)
        ; metta_memo_head(Fun, Module, Arity, _)
        ; metta_memo_tail(Fun, Module, Arity, _)
        ; metta_memo_q(Fun, Module, Arity, _, _)
        ; exact_memo_specialization(_, _, Fun, Module, Arity)
        ; current_predicate(Module:Fun/Arity)
        ),
        RawArities),
    sort(RawArities, Arities).

record_memo_source(Fun, Module, Arity) :-
    support_record(memo(Module, Fun, Arity), function(Module, Fun)).

cache_invalidate_node(Fun, Module, Arity) :-
    with_cache_fun_mutex(Fun, Module, Arity,
        ( bump_metta_memo_generation(Fun, Module, Arity),
          abolish_exact_memo_tables(Fun, Module, Arity),
          invalidate_entries_for_fun_arity(Fun, Module, Arity, FreedBytes),
          update_total_bytes_subtract(FreedBytes),
          retractall(metta_memo_count(Fun, Module, Arity, _)),
          retractall(metta_memo_head(Fun, Module, Arity, _)),
          retractall(metta_memo_tail(Fun, Module, Arity, _)),
          retractall(metta_memo_q(Fun, Module, Arity, _, _)),
          retractall(metta_memo_in_progress(Fun, Module, Arity, _, _))
        )).

:- multifile support_graph:support_invalidation_action/1.
support_graph:support_invalidation_action(memo(Module, Fun, Arity)) :-
    cache_invalidate_node(Fun, Module, Arity).

cache_invalidate(Fun, Module) :-
    memo_state_arities(Fun, Module, Arities),
    forall(member(Arity, Arities),
           ( record_memo_source(Fun, Module, Arity),
             support_invalidate(memo(Module, Fun, Arity)) )).

forget_memo_supports(Fun, Module) :-
    memo_state_arities(Fun, Module, Arities),
    forall(member(Arity, Arities),
           support_forget(memo(Module, Fun, Arity))).

% abolish_table_subgoals/1 does not translate a mode-directed wrapper to its
% generated table head. get_calls/3 in SWI's library(tables) performs this
% same two-hook translation before inspecting answers. Using the derived head
% clears only this cache and keeps unrelated application tables alive.
% Source: SWI-Prolog/swipl-devel f49d28558b5f1ade8348f254b5583117e773b2bb,
% library/tables.pl:get_calls/3.
reset_exact_memo_table(Module, TableName, Arity) :-
    TableArity is Arity + 1,
    functor(ModeGoal, TableName, TableArity),
    '$tbl_implementation'(Module:ModeGoal,
                          TableModule:Implementation),
    TableModule:'$table_mode'(Implementation, TableGoal, _Moded),
    abolish_table_subgoals(TableModule:TableGoal).

abolish_exact_memo_tables(Fun, Module, Arity) :-
    forall(exact_memo_specialization(_ReplayName, TableName,
                                     Fun, Module, Arity),
           reset_exact_memo_table(Module, TableName, Arity)).

remove_exact_memo_specializations(Fun, Module) :-
    findall(specialization(ReplayName, TableName, Arity),
            exact_memo_specialization(ReplayName, TableName,
                                      Fun, Module, Arity),
            Specializations),
    forall(member(specialization(ReplayName, TableName, Arity),
                  Specializations),
           ( TableArity is Arity + 1,
             reset_exact_memo_table(Module, TableName, Arity),
             untable(Module:TableName/TableArity),
             abolish(Module:ReplayName/Arity),
             abolish(Module:TableName/TableArity) )),
    retractall(exact_memo_specialization(_, _, Fun, Module, _)).

cache_clear :-
    findall(memo(Module, Fun, Arity),
            ( supports(_, memo(Module, Fun, Arity))
            ; supports(memo(Module, Fun, Arity), _) ),
            MemoNodes0),
    sort(MemoNodes0, MemoNodes),
    abolish_exact_memo_tables(_Fun, _Module, _Arity),
    retractall(metta_memo_entry(_, _, _, _, _, _)),
    retractall(metta_memo_generation(_, _, _, _)),
    retractall(metta_memo_count(_, _, _, _)),
    retractall(metta_memo_head(_, _, _, _)),
    retractall(metta_memo_tail(_, _, _, _)),
    retractall(metta_memo_q(_, _, _, _, _)),
    retractall(metta_memo_in_progress(_, _, _, _, _)),
    retractall(metta_memo_total_bytes(_)),
    asserta(metta_memo_total_bytes(0)),
    retractall(metta_memo_stat(_, _)),
    forall(member(Node, MemoNodes), support_forget(Node)),
    ( catch(nb_current('$petta_memo_cms', _), _, fail) -> nb_delete('$petta_memo_cms') ; true ),
    ( catch(nb_current('$petta_memo_cms_size', _), _, fail) -> nb_delete('$petta_memo_cms_size') ; true ),
    ( catch(nb_current('$petta_memo_accesses', _), _, fail) -> nb_delete('$petta_memo_accesses') ; true ).

%Every space's cache, because the memory budget it resets is one global
%budget. Use invalidate-memoize to drop one function in one space.
'clear-memoize'(true) :-
    cache_clear.

'invalidate-memoize'(Fun, true) :-
    memo_scope_module(Fun, Module),
    cache_invalidate(Fun, Module).

%The force ahead of every read, because the automatic decision is DERIVED
%from the compiled call graph: an equation that arrived and was not needed
%yet has no graph, so asking is-memoized before the first call answered
%False for a function the reconciliation memoizes the moment it compiles.
%Nothing here calls Fun, so the undefined-procedure net never fires.
'is-memoized'(Fun, true) :-
    metta_ensure_compiled(Fun),
    memo_scope_module(Fun, Module),
    ( memo_enabled(Fun, Module)
    ; memo_enabled(Fun, Module, _)
    ; memo_automatic_enabled(Fun, Module)
    ), !.
'is-memoized'(_, false).

'is-memoized'(Fun, CallArity, true) :-
    metta_ensure_compiled(Fun),
    memo_scope_module(Fun, Module),
    ( memo_enabled(Fun, Module)
    ; memo_enabled(Fun, Module, CallArity)
    ; memo_enabled(Fun, Module, exact)
    ; memo_automatic_enabled(Fun, Module)
    ), !.
'is-memoized'(_, _, false).

% Synchronization Helpers

cache_fun_mutex_id(Fun, Module, Arity, Mutex) :-
    atomic_list_concat(['metta_cache_fun_', Module, '_', Fun, '_', Arity], Mutex).

with_cache_fun_mutex(Fun, Module, Arity, Goal) :-
    cache_fun_mutex_id(Fun, Module, Arity, Mutex),
    with_mutex(Mutex, Goal).

with_cms_mutex(Goal) :-
    with_mutex(metta_cache_cms, Goal).

% Frequency Sketch (WTinyLFU)

ensure_cms :-
    ( catch(nb_current('$petta_memo_cms', _), _, fail),
      catch(nb_current('$petta_memo_cms_size', _), _, fail)
    -> true
    ; current_prolog_flag(max_arity, MaxArity0),
      ( integer(MaxArity0), MaxArity0 > 0 -> MaxArity = MaxArity0 ; MaxArity = 1024 ),
      SketchSize is min(8192, MaxArity),
      functor(CMS, v, SketchSize),
      forall(between(1, SketchSize, I), nb_setarg(I, CMS, 0)),
      nb_setval('$petta_memo_cms', CMS),
      nb_setval('$petta_memo_cms_size', SketchSize),
      nb_setval('$petta_memo_accesses', 0)
    ).

get_freq(Fun, Module, Arity, AVs, Freq) :-
    with_cms_mutex(
        ( catch(nb_current('$petta_memo_cms', CMS), _, fail)
        -> ( catch(nb_current('$petta_memo_cms_size', SketchSize), _, fail)
            -> true
            ; functor(CMS, _, SketchSize) ),
            term_hash((Fun, Module, Arity, AVs), HashRaw),
            Hash is (abs(HashRaw) mod SketchSize) + 1,
            arg(Hash, CMS, Val),
            ( integer(Val) -> Freq = Val ; Freq = 0 )
        ; Freq = 0 )
        ).

record_hit(Fun, Module, Arity, AVs) :-
    with_cms_mutex(
        ( catch(nb_current('$petta_memo_cms', CMS), _, fail)
        -> ( catch(nb_current('$petta_memo_cms_size', SketchSize), _, fail)
            -> true
            ; functor(CMS, _, SketchSize) ),
            term_hash((Fun, Module, Arity, AVs), HashRaw),
            Hash is (abs(HashRaw) mod SketchSize) + 1,
            arg(Hash, CMS, Val),
            ( integer(Val) -> NextVal is Val + 1 ; NextVal = 1 ),
            nb_setarg(Hash, CMS, NextVal)
        ; true )
        ).

record_miss(Fun, Module, Arity, AVs) :-
    with_cms_mutex(
        ( ensure_cms,
          nb_getval('$petta_memo_cms_size', SketchSize),
          term_hash((Fun, Module, Arity, AVs), HashRaw),
          Hash is (abs(HashRaw) mod SketchSize) + 1,
          nb_getval('$petta_memo_cms', CMS),
          arg(Hash, CMS, Val),
          ( integer(Val) -> NextVal is Val + 1 ; NextVal = 1 ),
          nb_setarg(Hash, CMS, NextVal),
          nb_getval('$petta_memo_accesses', Acc),
          NextAcc is Acc + 1,
          nb_setval('$petta_memo_accesses', NextAcc),
          ( NextAcc > SketchSize -> halve_cms ; true )
        )).

halve_cms :-
    nb_setval('$petta_memo_accesses', 0),
    nb_getval('$petta_memo_cms_size', SketchSize),
    nb_getval('$petta_memo_cms', CMS),
    forall(between(1, SketchSize, I),
        ( arg(I, CMS, Val),
          ( integer(Val) -> NewVal is Val // 2 ; NewVal = 0 ),
          nb_setarg(I, CMS, NewVal)
        )).

% Storage and Eviction

get_memo_queue_state(Fun, Module, Arity, Count, Head, Tail) :-
    ( metta_memo_count(Fun, Module, Arity, C) -> Count = C ; Count = 0 ),
    ( metta_memo_head(Fun, Module, Arity, H) -> Head = H ; Head = 0 ),
    ( metta_memo_tail(Fun, Module, Arity, T) -> Tail = T ; Tail = 0 ).

set_memo_queue_state(Fun, Module, Arity, Count, Head, Tail) :-
    retractall(metta_memo_count(Fun, Module, Arity, _)),
    retractall(metta_memo_head(Fun, Module, Arity, _)),
    retractall(metta_memo_tail(Fun, Module, Arity, _)),
    asserta(metta_memo_count(Fun, Module, Arity, Count)),
    asserta(metta_memo_head(Fun, Module, Arity, Head)),
    asserta(metta_memo_tail(Fun, Module, Arity, Tail)).

% Storage - Eviction Policies (LRU and WTinyLFU)

% Calculate estimated size of a cache entry (AVs + Results)
entry_size(AVs, Results, Bytes) :-
    term_size(AVs, S1),
    term_size(Results, S2),
    Bytes is (S1 + S2) * 8.

% Find oldest entry globally (across all functions/entries)
% Returns Fun, Module, Arity, and AVs of the oldest entry
find_global_oldest(Fun, Module, Arity, AVs) :-
    findall((HeadVal, F, M, A),
        metta_memo_head(F, M, A, HeadVal),
        Heads),
    Heads = [_|_],
    sort(Heads, Sorted),
    Sorted = [(MinHead, Fun, Module, Arity)|_],
    Next is MinHead + 1,
    metta_memo_q(Fun, Module, Arity, Next, AVs).

% Maximum eviction attempts to prevent infinite recursion
max_eviction_attempts(1000).

% Evict entries globally until space is available
% Includes safeguards against infinite recursion
evict_global_space(NeededBytes) :-
    evict_global_space(NeededBytes, 0).

evict_global_space(NeededBytes, Attempts) :-
    max_eviction_attempts(MaxAttempts),
    ( Attempts >= MaxAttempts
    -> format(user_error, 'WARNING: Memoization eviction limit exceeded (~d attempts).~n', [MaxAttempts]),
       true  % Stop trying, but don't fail
    ; memo_size_limit(Limit),
      metta_memo_total_bytes(Current),
      NewTotal is Current + NeededBytes,
      ( NewTotal =< Limit
      -> true  % Space available now
      ; % Need to evict
        ( find_global_oldest(Fun, Module, Arity, VictimAVs)
        -> evict_entry(Fun, Module, Arity, VictimAVs),
           NewAttempts is Attempts + 1,
           evict_global_space(NeededBytes, NewAttempts)
        ; format(user_error, 'WARNING: No entries to evict, but global limit exceeded.~n', []),
          true
        )
      )
    ).

% Evict a specific entry and update size tracking
evict_entry(Fun, Module, Arity, AVs) :-
    ( metta_memo_entry(Fun, Module, Arity, _, AVs, CachedResults)
    -> entry_size(AVs, CachedResults, Bytes),
       retractall(metta_memo_entry(Fun, Module, Arity, _, AVs, _)),
       ( metta_memo_q(Fun, Module, Arity, _, AVs)
       -> ( metta_memo_head(Fun, Module, Arity, Head)
          -> Head1 is Head + 1,
             retractall(metta_memo_head(Fun, Module, Arity, _)),
             asserta(metta_memo_head(Fun, Module, Arity, Head1))
          ; true
          ),
          retractall(metta_memo_q(Fun, Module, Arity, _, AVs)),
          ( metta_memo_count(Fun, Module, Arity, Count)
          -> Count1 is Count - 1,
             retractall(metta_memo_count(Fun, Module, Arity, _)),
             asserta(metta_memo_count(Fun, Module, Arity, Count1))
          ; true
          )
       ; true
       ),
       ( metta_memo_total_bytes(Total)
       -> NewTotal is max(0, Total - Bytes),
          retractall(metta_memo_total_bytes(_)),
          asserta(metta_memo_total_bytes(NewTotal))
       ; asserta(metta_memo_total_bytes(0))
       )
    ; true
    ).

% Update total bytes when adding entry
invalidate_entries_for_fun_arity(Fun, Module, Arity, FreedBytes) :-
    findall(Bytes,
        ( metta_memo_entry(Fun, Module, Arity, _, AVs, CachedResults),
          entry_size(AVs, CachedResults, Bytes)
        ),
        Sizes),
    sum_list(Sizes, FreedBytes),
    retractall(metta_memo_entry(Fun, Module, Arity, _, _, _)).

update_total_bytes_subtract(Bytes) :-
    ( retract(metta_memo_total_bytes(Current))
    -> true
    ; Current = 0
    ),
    New is max(0, Current - Bytes),
    retractall(metta_memo_total_bytes(_)),
    asserta(metta_memo_total_bytes(New)).

update_total_bytes_add(Bytes) :-
    ( retract(metta_memo_total_bytes(Current))
    -> New is Current + Bytes
    ; New is Bytes
    ),
    asserta(metta_memo_total_bytes(New)).

memo_store(Fun, Module, Arity, Gen, AVs, CachedResults) :-
    memo_unique_limit(Max),
    get_memo_queue_state(Fun, Module, Arity, Count, Head, Tail),
    % Check global size limit first
    entry_size(AVs, CachedResults, NewBytes),
    evict_global_space(NewBytes),
    memo_strategy(Strategy),
    ( Count < Max
    -> Count1 is Count + 1,
        Tail1 is Tail + 1,
        assertz(metta_memo_q(Fun, Module, Arity, Tail1, AVs)),
        assertz(metta_memo_entry(Fun, Module, Arity, Gen, AVs, CachedResults)),
        update_total_bytes_add(NewBytes),
        set_memo_queue_state(Fun, Module, Arity, Count1, Head, Tail1)
    ; Head1 is Head + 1,
        ( retract(metta_memo_q(Fun, Module, Arity, Head1, VictimAVs))
        -> ( Strategy == lru
            -> % Evict victim and add new - update global size
                ( metta_memo_entry(Fun, Module, Arity, _, VictimAVs, VictimResults)
                -> entry_size(VictimAVs, VictimResults, VictimBytes),
                   retractall(metta_memo_entry(Fun, Module, Arity, _, VictimAVs, _)),
                   % Subtract victim size, add new size
                   ( retract(metta_memo_total_bytes(CurrentTotal))
                   -> NewTotal is CurrentTotal - VictimBytes + NewBytes
                   ; NewTotal is NewBytes
                   ),
                   asserta(metta_memo_total_bytes(NewTotal))
                ; true
                ),
                Tail1 is Tail + 1,
                assertz(metta_memo_q(Fun, Module, Arity, Tail1, AVs)),
                assertz(metta_memo_entry(Fun, Module, Arity, Gen, AVs, CachedResults)),
                set_memo_queue_state(Fun, Module, Arity, Count, Head1, Tail1)
            ; get_freq(Fun, Module, Arity, VictimAVs, VictimFreq),
                get_freq(Fun, Module, Arity, AVs, NewFreq),
                ( NewFreq >= VictimFreq
                -> % Admit new entry - evict victim
                    ( metta_memo_entry(Fun, Module, Arity, _, VictimAVs, VictimResults)
                    -> entry_size(VictimAVs, VictimResults, VictimBytes),
                       retractall(metta_memo_entry(Fun, Module, Arity, _, VictimAVs, _)),
                       ( retract(metta_memo_total_bytes(CurrentTotal))
                       -> NewTotal is CurrentTotal - VictimBytes + NewBytes
                       ; NewTotal is NewBytes
                       ),
                       asserta(metta_memo_total_bytes(NewTotal))
                    ; true
                    ),
                    Tail1 is Tail + 1,
                    assertz(metta_memo_q(Fun, Module, Arity, Tail1, AVs)),
                    assertz(metta_memo_entry(Fun, Module, Arity, Gen, AVs, CachedResults)),
                    set_memo_queue_state(Fun, Module, Arity, Count, Head1, Tail1)
                ; % Reject new entry, keep victim
                    _ = Gen,
                    Tail1 is Tail + 1,
                    assertz(metta_memo_q(Fun, Module, Arity, Tail1, VictimAVs)),
                    set_memo_queue_state(Fun, Module, Arity, Count, Head1, Tail1)
                )
            )
        ; Tail1 is Tail + 1,
            assertz(metta_memo_q(Fun, Module, Arity, Tail1, AVs)),
            assertz(metta_memo_entry(Fun, Module, Arity, Gen, AVs, CachedResults)),
            update_total_bytes_add(NewBytes),
            Count1 is min(Max, Count + 1),
            set_memo_queue_state(Fun, Module, Arity, Count1, Head1, Tail1)
        )
    ).

store_if_current_generation(Fun, Module, Arity, ExpectedGen, AVs, CachedResults) :-
    with_cache_fun_mutex(Fun, Module, Arity,
        ( memo_current_generation(Fun, Module, Arity, CurGen),
          ( CurGen =:= ExpectedGen
          -> memo_store(Fun, Module, Arity, CurGen, AVs, CachedResults)
          ; true )
        )).

% Key Canonicalization and Replay

memoization_enabled_for_call(Fun, Module, _) :-
    memo_enabled(Fun, Module), !.
memoization_enabled_for_call(Fun, Module, CallArity) :-
    memo_enabled(Fun, Module, Mode),
    ( Mode == CallArity ; Mode == exact ),
    !.
memoization_enabled_for_call(Fun, Module, _) :-
    memo_automatic_enabled(Fun, Module), !.

memo_manual_enabled_for_call(Fun, Module, _) :-
    memo_enabled(Fun, Module), !.
memo_manual_enabled_for_call(Fun, Module, CallArity) :-
    memo_enabled(Fun, Module, Mode),
    ( Mode == CallArity ; Mode == exact ),
    !.

memo_exact_for_predicate(Fun, Module, _) :-
    memo_enabled(Fun, Module, exact).

memo_automatic_only_for_call(Fun, Module, CallArity) :-
    once(memo_automatic_enabled(Fun, Module)),
    \+ memo_manual_enabled_for_call(Fun, Module, CallArity).

memo_automatic_only_for_predicate(Fun, Module, PredArity) :-
    CallArity is PredArity - 1,
    memo_automatic_only_for_call(Fun, Module, CallArity).

memoization_enabled_for_predicate_arity(Fun, Module, PredArity) :-
    integer(PredArity),
    PredArity >= 1,
    CallArity is PredArity - 1,
    memoization_enabled_for_call(Fun, Module, CallArity).

memoizable_fun(Fun, Module, Arity) :-
    current_predicate(Module:Fun/Arity),
    memoization_enabled_for_predicate_arity(Fun, Module, Arity),
    integer(Arity),
    Arity >= 1,
    length(HeadArgs, Arity),
    Head =.. [Fun | HeadArgs],
    \+ predicate_property(Module:Head, built_in).

quantize_float(V, Q) :-
    memo_float_precision(Prec),
    Scale is 10.0 ** Prec,
    Q is round(V * Scale) / Scale.

quantize_term(T, T) :- var(T), !.
quantize_term(T, Q) :- float(T), !, quantize_float(T, Q).
quantize_term(T, T) :- atomic(T), !.
quantize_term(T, Q) :-
    T =.. [F|Args],
    maplist(quantize_term, Args, QArgs),
    Q =.. [F|QArgs].

args_too_complex(AVs) :-
    memo_size_limit(Limit),
    term_size(AVs, S),
    EstimatedBytes is S * 8,
    EstimatedBytes > Limit.

args_worth_caching(AVs) :-
    \+ args_too_complex(AVs).

%Automatic keys are exact. Float quantization remains the explicit manual
%API's configured behaviour, but applying it silently would merge distinct
%program calls merely because the compiler selected their function.
canonicalize_args_key(Fun, Module, Arity, AVs, KeyAVs) :-
    memo_automatic_only_for_predicate(Fun, Module, Arity),
    !,
    copy_term(AVs, KeyAVs),
    numbervars(KeyAVs, 0, _).
canonicalize_args_key(Fun, Module, Arity, AVs, KeyAVs) :-
    memo_exact_for_predicate(Fun, Module, Arity),
    !,
    copy_term(AVs, KeyAVs),
    numbervars(KeyAVs, 0, _).
canonicalize_args_key(_, _, _, AVs, KeyAVs) :-
    quantize_term(AVs, Quantized),
    copy_term(Quantized, KeyAVs),
    numbervars(KeyAVs, 0, _).

with_memo_call_context(Fun, Module, Arity, Goal) :-
    Node = memo(Module, Fun, Arity),
    record_memo_source(Fun, Module, Arity),
    ( metta_memo_call_ctx(ParentFun, ParentModule, ParentArity)
    -> ( ParentFun == Fun, ParentModule == Module, ParentArity == Arity
       -> true
       ; Parent = memo(ParentModule, ParentFun, ParentArity),
         support_record(Parent, Node)
       )
    ; true ),
    setup_call_cleanup(
        asserta(metta_memo_call_ctx(Fun, Module, Arity)),
        Goal,
        retract(metta_memo_call_ctx(Fun, Module, Arity))).

replay_variant_answer(AVs, Out, answer(CachedAVs, CachedOut)) :-
    AVs = CachedAVs,
    Out = CachedOut.

replay_ground_answer(Out, answer(CachedOut)) :-
    Out = CachedOut.

start_in_progress(Fun, Module, Arity, Gen, KeyAVs, Started) :-
    with_cache_fun_mutex(Fun, Module, Arity,
        ( metta_memo_in_progress(Fun, Module, Arity, Gen, KeyAVs)
        -> Started = false
        ; asserta(metta_memo_in_progress(Fun, Module, Arity, Gen, KeyAVs)),
          Started = true
        )).

finish_in_progress(Fun, Module, Arity, Gen, KeyAVs) :-
    with_cache_fun_mutex(Fun, Module, Arity,
        retractall(metta_memo_in_progress(Fun, Module, Arity, Gen, KeyAVs))).

wait_for_cached_variant(Fun, Module, Arity, CurGen, KeyAVs, AVs, Out) :-
    wait_for_cached_variant(Fun, Module, Arity, CurGen, KeyAVs, AVs, Out, 25).

wait_for_cached_variant(_, _, _, _, _, _, _, 0) :- fail.
wait_for_cached_variant(Fun, Module, Arity, CurGen, KeyAVs, AVs, Out, Attempts) :-
    ( cache_lookup(Fun, Module, Arity, CurGen, KeyAVs, CachedResults),
      member(Answer, CachedResults),
      replay_variant_answer(AVs, Out, Answer)
    -> true
    ; sleep(0.001),
      Next is Attempts - 1,
      wait_for_cached_variant(Fun, Module, Arity, CurGen, KeyAVs, AVs, Out, Next)
    ).

% Probe and Aggregation

apply_aggregate_mode(ProbeResults, FinalResults) :-
    memo_aggregate_mode(Mode),
    apply_aggregate_mode(Mode, ProbeResults, FinalResults).

apply_aggregate_mode(none, ProbeResults, ProbeResults).
apply_aggregate_mode(count, ProbeResults, [answer(Count)]) :-
    length(ProbeResults, Count).
apply_aggregate_mode(sum, ProbeResults, [answer(Sum)]) :-
    findall(V, member(answer(V), ProbeResults), Values),
    sum_list(Values, Sum).
apply_aggregate_mode(min, ProbeResults, [answer(Min)]) :-
    findall(V, member(answer(V), ProbeResults), Values),
    min_list(Values, Min).
apply_aggregate_mode(max, ProbeResults, [answer(Max)]) :-
    findall(V, member(answer(V), ProbeResults), Values),
    max_list(Values, Max).

truncate_answers(Answers, Limited) :-
    memo_answer_limit(Limit),
    length(Prefix, Limit),
    append(Prefix, _, Answers), !,
    Limited = Prefix.
truncate_answers(Answers, Answers).

% Runtime Dispatch

memo_probe_limit(Fun, Module, Arity, Limit) :-
    memo_answer_limit(Configured),
    ( memo_automatic_only_for_predicate(Fun, Module, Arity)
    -> Limit is Configured + 1
    ;  Limit = Configured ).

memo_probe_results(Fun, Module, Arity, AVs, ProbeResults) :-
    append(AVs, [Result], RawArgs),
    RawGoal =.. [Fun | RawArgs],
    (   memo_exact_for_predicate(Fun, Module, Arity)
    ->  findall(answer(SolvedAVs, SolvedResult),
                ( call(Module:RawGoal),
                  copy_term((AVs, Result), (SolvedAVs, SolvedResult)) ),
                ProbeResults)
    ;   memo_probe_limit(Fun, Module, Arity, Limit),
        once(findnsols(Limit, answer(SolvedAVs, SolvedResult),
            ( call(Module:RawGoal),
              copy_term((AVs, Result), (SolvedAVs, SolvedResult))
            ),
            ProbeResults))
    ).

% Ground calls should not re-unify raw input args on replay, because
% float quantization intentionally maps slightly different inputs to one key.
memo_probe_ground_results(Fun, Module, Arity, AVs, ProbeResults) :-
    append(AVs, [Result], RawArgs),
    RawGoal =.. [Fun | RawArgs],
    (   memo_exact_for_predicate(Fun, Module, Arity)
    ->  findall(answer(SolvedResult),
                ( call(Module:RawGoal),
                  copy_term(Result, SolvedResult) ),
                ProbeResults)
    ;   memo_probe_limit(Fun, Module, Arity, Limit),
        once(findnsols(Limit, answer(SolvedResult),
            ( call(Module:RawGoal),
              copy_term(Result, SolvedResult)
            ),
            ProbeResults))
    ).

cache_lookup(Fun, Module, Arity, CurGen, KeyAVs, CachedResults) :-
    metta_memo_entry(Fun, Module, Arity, CurGen, KeyAVs, CachedResults).

cache_replay_hit_ground(Fun, Module, Arity, KeyAVs, CachedResults, Out) :-
    memo_stat_inc(cache_hit),
    record_hit(Fun, Module, Arity, KeyAVs),
    member(Answer, CachedResults),
    replay_ground_answer(Out, Answer).

cache_replay_hit_variant(Fun, Module, Arity, KeyAVs, CachedResults, AVs, Out) :-
    memo_stat_inc(cache_hit),
    record_hit(Fun, Module, Arity, KeyAVs),
    member(Answer, CachedResults),
    replay_variant_answer(AVs, Out, Answer).

cache_store(Fun, Module, Arity, CurGen, KeyAVs, ProbeResults) :-
    ( memo_exact_for_predicate(Fun, Module, Arity)
    -> LimitedResults = ProbeResults
    ; truncate_answers(ProbeResults, LimitedResults) ),
    ( LimitedResults == ProbeResults -> true ; memo_stat_inc(answer_limit_truncated) ),
    store_if_current_generation(Fun, Module, Arity, CurGen, KeyAVs, LimitedResults),
    record_miss(Fun, Module, Arity, KeyAVs).

cache_probe_variant(Fun, Module, Arity, CurGen, KeyAVs, AVs, ProbeResults) :-
    setup_call_cleanup(
        true,
        memo_probe_results(Fun, Module, Arity, AVs, ProbeResults),
        finish_in_progress(Fun, Module, Arity, CurGen, KeyAVs)).

memo_automatic_probe_overflow(Fun, Module, Arity, ProbeResults) :-
    memo_automatic_only_for_predicate(Fun, Module, Arity),
    memo_answer_limit(Limit),
    length(ProbeResults, Count),
    Count > Limit.

memo_ground_final_results(Fun, Module, Arity, ProbeResults, ProbeResults) :-
    memo_automatic_only_for_predicate(Fun, Module, Arity),
    !.
memo_ground_final_results(Fun, Module, Arity, ProbeResults, ProbeResults) :-
    memo_exact_for_predicate(Fun, Module, Arity),
    !.
memo_ground_final_results(_, _, _, ProbeResults, FinalResults) :-
    apply_aggregate_mode(ProbeResults, FinalResults).

cache_call_store_ground(Fun, Module, Arity, CurGen, KeyAVs, AVs, Goal, Out) :-
    % For ground+quantized keys, collisions are intentional. Guarding "in-progress"
    % entries here can cause large duplicate recomputation in recursive workloads
    % Keep the ground path as direct probe/store.
    memo_probe_ground_results(Fun, Module, Arity, AVs, ProbeResults),
    (   memo_automatic_probe_overflow(Fun, Module, Arity, ProbeResults)
    ->  memo_stat_inc(automatic_answer_limit_bypass),
        call(Module:Goal)
    ;   memo_ground_final_results(Fun, Module, Arity,
                                  ProbeResults, FinalResults),
        cache_store(Fun, Module, Arity, CurGen, KeyAVs, FinalResults),
        memo_stat_inc(cache_miss),
        member(Answer, FinalResults),
        replay_ground_answer(Out, Answer)
    ).

cache_call_store_variant(Fun, Module, Arity, CurGen, KeyAVs, AVs, Goal, Out) :-
    start_in_progress(Fun, Module, Arity, CurGen, KeyAVs, Started),
    ( Started == true
    -> cache_probe_variant(Fun, Module, Arity, CurGen, KeyAVs, AVs, ProbeResults),
       (   memo_automatic_probe_overflow(Fun, Module, Arity, ProbeResults)
       ->  memo_stat_inc(automatic_answer_limit_bypass),
           call(Module:Goal)
       ;   cache_store(Fun, Module, Arity, CurGen, KeyAVs, ProbeResults),
           memo_stat_inc(cache_miss),
           member(Answer, ProbeResults),
           replay_variant_answer(AVs, Out, Answer)
       )
    ; ( wait_for_cached_variant(Fun, Module, Arity, CurGen, KeyAVs, AVs, Out)
      -> memo_stat_inc(waited_on_in_progress)
      ; memo_stat_inc(in_progress_fallback),
        call(Module:Goal)
      )
    ).

exact_specialized_root(Fun, Module, Arity, TableGoal, Multiplicity) :-
    with_memo_call_context(Fun, Module, Arity,
    ( ( get_call(TableGoal, _Trie, _Return)
      -> memo_stat_inc(cache_hit)
      ;  memo_stat_inc(cache_miss) ),
      call(TableGoal),
      between(1, Multiplicity, _Occurrence)
    )).

%CallModule is the module the compiled call site lives in, fixed when the
%clause was translated; the module that owns the clauses is resolved here,
%on every call, so a space defining the function after the caller was
%compiled is still cached under itself.
cache_call(Fun, CallModule, AVs, Out) :-
    length(AVs, NArgs),
    Arity is NArgs + 1,
    memo_owner_module(Fun, CallModule, Arity, Module),
    append(AVs, [Out], GoalArgs),
    Goal =.. [Fun | GoalArgs],
    with_memo_call_context(Fun, Module, Arity,
    ( args_worth_caching(AVs),
      memoizable_fun(Fun, Module, Arity)
    -> canonicalize_args_key(Fun, Module, Arity, AVs, KeyAVs),
        memo_current_generation(Fun, Module, Arity, CurGen),
        ( ground(AVs)
        -> ( cache_lookup(Fun, Module, Arity, CurGen, KeyAVs, CachedResults)
           -> cache_replay_hit_ground(Fun, Module, Arity, KeyAVs, CachedResults, Out)
           ; cache_call_store_ground(Fun, Module, Arity, CurGen, KeyAVs, AVs, Goal, Out)
           )
        ; ( cache_lookup(Fun, Module, Arity, CurGen, KeyAVs, CachedResults)
          -> cache_replay_hit_variant(Fun, Module, Arity, KeyAVs, CachedResults, AVs, Out)
          ; cache_call_store_variant(Fun, Module, Arity, CurGen, KeyAVs, AVs, Goal, Out)
          )
        )
    ; memo_stat_inc(cache_bypass),
      call(Module:Goal)
    )).

% Public API

'memoize'(Fun, true) :-
    memo_target(Fun, any, 'memoize!/2', Space, Module, Terms),
    memo_recompile(Space, Terms, enable_memoization(Fun, Module)).

'memoize'(Fun, CallArity, true) :-
    ( integer(CallArity), CallArity >= 0
    -> true
    ; throw(error(domain_error(nonneg_integer, CallArity), 'memoize!/3'))
    ),
    memo_target(Fun, CallArity, 'memoize!/3', Space, Module, Terms),
    memo_recompile(Space, Terms, enable_memoization(Fun, Module, CallArity)).

%The Python @cache contract is an exact answer bag. This is an internal bridge
%service rather than another MeTTa declaration spelling: unlike configurable
%manual memoize, it never quantizes keys, aggregates answers or applies
%answer-limit, because those policies would change the decorated function.
memoize_exact(Fun) :-
    memo_target(Fun, any, 'memoize-exact!/2', Space, Module, Terms),
    findall(Arity,
            ( member([=, [Fun | Args], _Body], Terms),
              length(Args, InputArity),
              Arity is InputArity + 1 ),
            RawArities),
    sort(RawArities, Arities),
    memo_recompile(Space, Terms,
                   enable_exact_memoization(Fun, Module, Arities)).

%The space that asks owns the equations, unless it only inherits them from
%&self. Recompiling in the wrong space is how memoizing in one space used
%to rewrite every other space's equations into it.
memo_target(Fun, Arities, Context, Space, Module, Terms) :-
    ( atom(Fun), fun(Fun)
    -> true
    ; throw(error(domain_error(function_symbol, Fun), Context))
    ),
    %Every declaration door resolves its target here, and each of them reads
    %the COMPILED state: the purity walk that refuses an impure body walks
    %compiled clauses, so a deferred definition read as pure and (memoize f)
    %accepted a function it must refuse
    %[measured 2026-08-24: tests/test_contract.py, an unchecked declaration].
    metta_ensure_compiled(Fun),
    %A library may declare that its function must not be cached, with
    %(volatility name volatile) in its export block. Caching a function whose
    %answers are not reproducible skips its effect on the second call, and
    %before this nothing recorded whether that was sound: the review's own
    %probe cached a side-effecting registered predicate and watched the effect
    %disappear. An undeclared function is still cacheable, because
    %memoization is opt-in by the caller and refusing silence would break
    %every existing (memoize f).
    ( metta_function_cacheable(Fun)
    -> true
    ; throw(error(permission_error(memoize, volatile_function, Fun),
                  context(Context,
                          'the library that registered this declared it volatile')))
    ),
    memo_scope_module(Fun, Module),
    memo_refuse_uncacheable(Fun, Module, Context),
    metta_module_space(Module, Space),
    findall(Term, memo_equation(Fun, Module, Arities, Term), RawTerms),
    sort(RawTerms, Terms).

%The BODY, not only the declaration above it. Opting in is the CALLER saying
%they want the cache; it is not the caller establishing that the function is
%safe to cache, and nothing was establishing that: `(memoize viapy)` was
%accepted, `is-memoized` answered true, and mutating the data the Python
%operation reads left the cache answering the old value
%[source: ai-metta-python-seams.md item 1].
%
%The walk is the engine's, the same one tabling uses, so one judgement covers
%both. The criterion here is STRICTER, and the reason is what each does after
%caching: tabling resolves every space read to its storage predicate and
%carries the incremental property against it, so a read is something it can
%invalidate on. Memoization invalidates on an equation change and on nothing
%else, so a read it cannot see change is a cache that goes stale in silence.
memo_refuse_uncacheable(Fun, Module, Context) :-
    findall(Arity, current_predicate(Module:Fun/Arity), Arities),
    forall(member(Arity, Arities),
           memo_refuse_uncacheable_arity(Fun, Module, Arity, Context)).

%(cache Fun unchecked) in &petta is the caller's declared acceptance of
%staleness, so the walk is skipped for this function. The volatility gate is
%NOT skipped: it runs before this predicate is reached, and a library's
%explicit volatile keeps refusing whatever the caller declares
%[tested: an_unchecked_declaration_memoizes_an_impure_body].
memo_refuse_uncacheable_arity(Fun, _Module, _Arity, _Context) :-
    metta_cache_unchecked(Fun),
    !.
memo_refuse_uncacheable_arity(Fun, Module, Arity, Context) :-
    catch(metta_effect_walk(Module, [Fun/Arity], Reads),
          error(metta_impure_goal(Goal), _),
          throw(error(permission_error(memoize, impure_function, Fun),
                      context(Context, Goal)))),
    (   Reads == []
    ->  true
    ;   throw(error(permission_error(memoize, space_reading_function, Fun),
                    context(Context, Reads)))
    ).

:- multifile prolog:error_message//1.
prolog:error_message(permission_error(memoize, impure_function, Name)) -->
    [ '~w calls an operation that is not classified pureStructural, so a \c
       cached answer would hide its effect. Declare that operation with \c
       (effect <operation> pureStructural) only when it inspects its \c
       arguments without observing mutable state'-[Name] ].
prolog:error_message(permission_error(memoize, space_reading_function, Name)) -->
    [ '~w reads a space, and memoization invalidates on an equation change \c
       and on nothing else, so the cache would outlive the atoms it was \c
       computed from. Table it instead: tabling resolves the read and \c
       invalidates on it'-[Name] ].

%Recompiling is what makes memoization take effect: the translator bakes
%the dispatch into every compiled call site, so equations already compiled
%go through the compiler again with the flag set.
memo_recompile(Space, Terms, Enable) :-
    forall(member(Term, Terms), 'remove-atom'(Space, Term, _)),
    call(Enable),
    forall(member(Term, Terms), 'add-atom'(Space, Term, _)).
