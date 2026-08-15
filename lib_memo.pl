% Purpose: memoize MeTTa function calls with bounded LRU or WTinyLFU
%   eviction and dependency-based invalidation.
% Assumes:
%   - a named space compiles its equations into a module of its own and
%     inherits the rest from user, so a function name alone does not name
%     a function [source: src/spaces.pl:129, space_module/2]
%   - translated_from/2 is engine-wide, and a clause's module is what
%     places an equation in a space
%     [source: src/spaces.pl, metta_remove_atom/3]
% Guarantees:
%   - Routine cache eviction does not write diagnostics to user_error
%     [tested 2026-08-14: memo_eviction_output].
%   - Memoizing a function in one space leaves every other space's answers
%     unchanged [tested 2026-08-15: memo_space_isolation].
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
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- use_module(library(lists)).
:- use_module(library(solution_sequences)).
:- use_module(library(ugraphs)). %vertices_edges_to_ugraph/3, reachable/3

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
:- dynamic arity/2.

% Cached results: metta_memo_entry(Fun, Module, Arity, Gen, AVs, Results)
:- dynamic metta_memo_entry/6.

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

% Coarse function-level dependency graph: Caller -> Callee
:- dynamic metta_memo_dep/6.

% Lightweight runtime metrics
:- dynamic metta_memo_stat/2.

% Per-thread call context to build dependency graph cheaply
:- thread_local metta_memo_call_ctx/3.

% Module Resolution

%The module a call is dispatched in is not always the module holding the
%clauses: a named space compiles its own equations into its own module and
%inherits everything else from user. Cache under the module that defines
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
%the space defines the function, user's when it only inherits it. Used by
%the public API, where no arity is in hand and the equations answer.
memo_scope_module(Fun, Module) :-
    current_metta_module(CallModule),
    (   CallModule \== user,
        memo_equation(Fun, CallModule, any, _)
    ->  Module = CallModule
    ;   Module = user ).

%This module's equations for Fun, with a fixed input arity when one is
%asked for and every arity for `any`. The clause's module is the test:
%translated_from/2 is engine-wide, and the same equation imported into two
%spaces has one entry per module.
memo_equation(Fun, Module, Arities, Term) :-
    translated_from(Ref, Term),
    Term = [=, [Fun|Args], _],
    ( Arities == any -> true ; length(Args, Arities) ),
    clause_property(Ref, module(Module)).

%The space a module's equations belong to, inverting space_module/2.
memo_module_space(user, '&self') :- !.
memo_module_space(Module, Module).

% Runtime Hook Integration

:- multifile metta_memoized_dispatch_call/4.
metta_memoized_dispatch_call(Fun, Args, Out, Goal) :-
    memo_name_enabled(Fun),
    current_metta_module(CallModule),
    length(Args, CallArity),
    PredArity is CallArity + 1,
    memo_owner_module(Fun, CallModule, PredArity, Module),
    memoization_enabled_for_call(Fun, Module, CallArity),
    Goal = cache_call(Fun, CallModule, Args, Out).

%The guard that runs before anything else: this hook is consulted for every
%reduced call and every compiled call site, and reading the module, then
%resolving the owner, is work wasted whenever nothing by this name is
%memoized at all. memo_enabled/2 indexes on the name it is given
%[measured 2026-08-15: argument 1, 47x over sixty functions, jiti_list/1].
memo_name_enabled(Fun) :- memo_enabled(Fun, _), !.
memo_name_enabled(Fun) :- memo_enabled(Fun, _, _).

%The engine's change hook names a function, not a space. Every module
%holding state for that name is invalidated: over-invalidation costs one
%recomputation, under-invalidation answers from a stale cache.
:- multifile metta_on_function_changed/1.
metta_on_function_changed(Fun) :-
    memo_state_modules(Fun, Modules),
    forall(member(Module, Modules), cache_invalidate(Fun, Module)).

%The removal hook fires only once no space defines the name any more
%[source: src/spaces.pl, metta_remove_atom/3], so the disable is global.
:- multifile metta_on_function_removed/1.
metta_on_function_removed(Fun) :-
    memo_state_modules(Fun, Modules),
    forall(member(Module, Modules), cache_invalidate(Fun, Module)),
    disable_memoization(Fun).

memo_state_modules(Fun, Modules) :-
    findall(M,
        ( memo_enabled(Fun, M)
        ; memo_enabled(Fun, M, _)
        ; metta_memo_entry(Fun, M, _, _, _, _)
        ; metta_memo_generation(Fun, M, _, _)
        ; metta_memo_dep(Fun, M, _, _, _, _)
        ; metta_memo_dep(_, _, _, Fun, M, _)
        ),
        Raw),
    sort(Raw, Modules).

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
    memberchk(In, [wtinylfu, 'WTinyLFU', 'W-TinyLFU', 'wtinylfu', 'w-tinylfu']), !.
normalize_memo_strategy(In, lru) :-
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
    memberchk(Mode, [none, min, max, sum, count]), !,
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

'clear-memoize-stats'(true) :-
    retractall(metta_memo_stat(_, _)).

% Lifecycle, Dependencies, and Invalidation

enable_memoization(Fun, Module) :-
    ( memo_enabled(Fun, Module) -> true ; assertz(memo_enabled(Fun, Module)) ).

enable_memoization(Fun, Module, CallArity) :-
    ( memo_enabled(Fun, Module, CallArity) -> true
    ; assertz(memo_enabled(Fun, Module, CallArity)) ).

disable_memoization(Fun) :-
    retractall(memo_enabled(Fun, _)),
    retractall(memo_enabled(Fun, _, _)).

memo_current_generation(Fun, Module, Arity, Gen) :-
    ( metta_memo_generation(Fun, Module, Arity, Found) -> Gen = Found ; Gen = 0 ).

bump_metta_memo_generation(Fun, Module, Arity) :-
    memo_current_generation(Fun, Module, Arity, Prev),
    Next is Prev + 1,
    retractall(metta_memo_generation(Fun, Module, Arity, _)),
    assertz(metta_memo_generation(Fun, Module, Arity, Next)).

%Which functions an invalidation has to reach: this one, and every caller
%that reaches it through any chain. The dependency facts are caller to
%callee, so the graph is built with the edges reversed and reachability
%answers the closure, seed included and in standard order
%[source: SWI-Prolog 10.1 Reference Manual A.63, library(ugraphs)].
impacted_functions(SeedFun, SeedModule, Impacted) :-
    findall((Callee-CalleeModule)-(Caller-CallerModule),
            metta_memo_dep(Caller, CallerModule, _, Callee, CalleeModule, _),
            Edges),
    vertices_edges_to_ugraph([SeedFun-SeedModule], Edges, Graph),
    reachable(SeedFun-SeedModule, Graph, Impacted).

cache_invalidate_single(Fun, Module) :-
    findall(Arity,
        ( arity(Fun, Arity)
        ; metta_memo_generation(Fun, Module, Arity, _)
        ; metta_memo_entry(Fun, Module, Arity, _, _, _)
        ; metta_memo_count(Fun, Module, Arity, _)
        ; metta_memo_head(Fun, Module, Arity, _)
        ; metta_memo_tail(Fun, Module, Arity, _)
        ; metta_memo_q(Fun, Module, Arity, _, _)
        ; current_predicate(Module:Fun/Arity)
        ),
        RawArities),
    sort(RawArities, Arities),
    ( Arities == []
    -> true
    ; forall(member(Arity, Arities),
        with_cache_fun_mutex(Fun, Module, Arity,
            ( bump_metta_memo_generation(Fun, Module, Arity),
              invalidate_entries_for_fun_arity(Fun, Module, Arity, FreedBytes),
              update_total_bytes_subtract(FreedBytes),
              retractall(metta_memo_count(Fun, Module, Arity, _)),
              retractall(metta_memo_head(Fun, Module, Arity, _)),
              retractall(metta_memo_tail(Fun, Module, Arity, _)),
              retractall(metta_memo_q(Fun, Module, Arity, _, _)),
              retractall(metta_memo_in_progress(Fun, Module, Arity, _, _))
            )))
    ),
    retractall(metta_memo_dep(Fun, Module, _, _, _, _)),
    retractall(metta_memo_dep(_, _, _, Fun, Module, _)).

cache_invalidate(Fun, Module) :-
    impacted_functions(Fun, Module, Impacted),
    forall(member(F-M, Impacted), cache_invalidate_single(F, M)).

cache_clear :-
    retractall(metta_memo_entry(_, _, _, _, _, _)),
    retractall(metta_memo_generation(_, _, _, _)),
    retractall(metta_memo_count(_, _, _, _)),
    retractall(metta_memo_head(_, _, _, _)),
    retractall(metta_memo_tail(_, _, _, _)),
    retractall(metta_memo_q(_, _, _, _, _)),
    retractall(metta_memo_in_progress(_, _, _, _, _)),
    retractall(metta_memo_dep(_, _, _, _, _, _)),
    retractall(metta_memo_total_bytes(_)),
    asserta(metta_memo_total_bytes(0)),
    retractall(metta_memo_stat(_, _)),
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

'is-memoized'(Fun, true) :-
    memo_scope_module(Fun, Module),
    ( memo_enabled(Fun, Module)
    ; memo_enabled(Fun, Module, _)
    ), !.
'is-memoized'(_, false).

'is-memoized'(Fun, CallArity, true) :-
    memo_scope_module(Fun, Module),
    ( memo_enabled(Fun, Module)
    ; memo_enabled(Fun, Module, CallArity)
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

memoization_enabled_for_call(Fun, Module, CallArity) :-
    memo_enabled(Fun, Module)
    ; memo_enabled(Fun, Module, CallArity).

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

% Canonical cache key: quantize floats, then normalize variable identities.
canonicalize_args_key(AVs, KeyAVs) :-
    quantize_term(AVs, Quantized),
    copy_term(Quantized, KeyAVs),
    numbervars(KeyAVs, 0, _).

with_memo_call_context(Fun, Module, Arity, Goal) :-
    ( metta_memo_call_ctx(ParentFun, ParentModule, ParentArity)
    -> ( ParentFun == Fun, ParentModule == Module, ParentArity == Arity
       -> true
       ; ( metta_memo_dep(ParentFun, ParentModule, ParentArity, Fun, Module, Arity)
         -> true
         ; asserta(metta_memo_dep(ParentFun, ParentModule, ParentArity, Fun, Module, Arity))
         ))
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

memo_probe_results(Fun, Module, AVs, ProbeResults) :-
    memo_answer_limit(Limit),
    append(AVs, [Result], RawArgs),
    RawGoal =.. [Fun | RawArgs],
    findnsols(Limit, answer(SolvedAVs, SolvedResult),
        ( call(Module:RawGoal),
          copy_term((AVs, Result), (SolvedAVs, SolvedResult))
        ),
        ProbeResults).

% Ground calls should not re-unify raw input args on replay, because
% float quantization intentionally maps slightly different inputs to one key.
memo_probe_ground_results(Fun, Module, AVs, ProbeResults) :-
    memo_answer_limit(Limit),
    append(AVs, [Result], RawArgs),
    RawGoal =.. [Fun | RawArgs],
    findnsols(Limit, answer(SolvedResult),
        ( call(Module:RawGoal),
          copy_term(Result, SolvedResult)
        ),
        ProbeResults).

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
    truncate_answers(ProbeResults, LimitedResults),
    ( LimitedResults == ProbeResults -> true ; memo_stat_inc(answer_limit_truncated) ),
    store_if_current_generation(Fun, Module, Arity, CurGen, KeyAVs, LimitedResults),
    record_miss(Fun, Module, Arity, KeyAVs).

cache_probe_and_store_variant(Fun, Module, Arity, CurGen, KeyAVs, AVs, ProbeResults) :-
    setup_call_cleanup(
        true,
        memo_probe_results(Fun, Module, AVs, ProbeResults),
        finish_in_progress(Fun, Module, Arity, CurGen, KeyAVs)),
    cache_store(Fun, Module, Arity, CurGen, KeyAVs, ProbeResults).

cache_call_store_ground(Fun, Module, Arity, CurGen, KeyAVs, AVs, Goal, Out) :-
    _ = Goal,
    % For ground+quantized keys, collisions are intentional. Guarding "in-progress"
    % entries here can cause large duplicate recomputation in recursive workloads
    % Keep the ground path as direct probe/store.
    memo_probe_ground_results(Fun, Module, AVs, ProbeResults),
    apply_aggregate_mode(ProbeResults, FinalResults),
    cache_store(Fun, Module, Arity, CurGen, KeyAVs, FinalResults),
    memo_stat_inc(cache_miss),
    member(Answer, FinalResults),
    replay_ground_answer(Out, Answer).

cache_call_store_variant(Fun, Module, Arity, CurGen, KeyAVs, AVs, Goal, Out) :-
    start_in_progress(Fun, Module, Arity, CurGen, KeyAVs, Started),
    ( Started == true
    -> cache_probe_and_store_variant(Fun, Module, Arity, CurGen, KeyAVs, AVs, ProbeResults),
       memo_stat_inc(cache_miss),
       member(Answer, ProbeResults),
       replay_variant_answer(AVs, Out, Answer)
    ; ( wait_for_cached_variant(Fun, Module, Arity, CurGen, KeyAVs, AVs, Out)
      -> memo_stat_inc(waited_on_in_progress)
      ; memo_stat_inc(in_progress_fallback),
        call(Module:Goal)
      )
    ).

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
    -> canonicalize_args_key(AVs, KeyAVs),
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

%The space that asks owns the equations, unless it only inherits them from
%&self. Recompiling in the wrong space is how memoizing in one space used
%to rewrite every other space's equations into it.
memo_target(Fun, Arities, Context, Space, Module, Terms) :-
    ( atom(Fun), fun(Fun)
    -> true
    ; throw(error(domain_error(function_symbol, Fun), Context))
    ),
    memo_scope_module(Fun, Module),
    memo_module_space(Module, Space),
    findall(Term, memo_equation(Fun, Module, Arities, Term), RawTerms),
    sort(RawTerms, Terms).

%Recompiling is what makes memoization take effect: the translator bakes
%the dispatch into every compiled call site, so equations already compiled
%go through the compiler again with the flag set.
memo_recompile(Space, Terms, Enable) :-
    forall(member(Term, Terms), 'remove-atom'(Space, Term, _)),
    call(Enable),
    forall(member(Term, Terms), 'add-atom'(Space, Term, _)).
