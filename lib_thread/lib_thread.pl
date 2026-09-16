% Purpose: concurrency for MeTTa over SWI's own primitives. Futures are
%   suspended SWI engines multiplexed over one bounded carrier pool; waits,
%   channel backpressure and blocking host calls release those carriers.
%   Every predicate follows the compiled convention, inputs then one output.
% Guarantees: deferred native expressions follow owned values through Scope
%   transfer; rolled-back descriptors perform no cleanup
%   [tested: lib_thread_scope_deferred; commit=9b0a084e534ddf7dd67980ad84c27c8279b877f1].
% Guarantees: scope_keep/3 records roots, and close follows current native
%   dependencies after children join. Failed dependency queries retain the
%   scope for retry [tested: lib_thread_scope_deferred; commit=bc30fbd0bbcbf535de217d5a9efad2910002f343].
% Assumes: scope_defer/4 dependency expressions terminate without side effects.
% Assumes:
%   - user:metta_py_dispatch/4 identifies the loaded Python seat for context
%     capture [tested:
%     test_context_snapshot_crosses_every_spawn_door_including_thread_workers;
%     commit=8358dfc233bf299bb23eceddd94593a62372fe4b].
%   - eval_metta_in_module/3 in engine/translator.pl evaluates one MeTTa
%     expression under a named space's module, which is what a worker thread
%     needs because SWI global variables are thread-local [source:
%     engine/translator.pl, eval_metta_in_module/3]
%   - concurrent_maplist/3 already sizes its pool to min(cpu_count, length)
%     and calls each goal once [source 2026-08-15:
%     /usr/lib/swi-prolog/library/thread.pl, workers/2 and once_in_module/5]
% Guarantees:
%   - await joins a native worker even when its result was published before
%     the wait began or another awaiter owns the native join; interruption
%     propagates and a later await can take over; pool_stats/2 reads one manager
%     snapshot [tested:
%     lib_thread_completion; commit=8ca8a387fc61d0918484b19a1a3baf85b6523043].
%   - scope_body/2 and scope_close/4 join their child tree, cancel siblings on
%     failure, transfer explicitly kept spaces and revoke every released alias
%     [tested: lib_thread_scope,
%     extensions/python/tests/ch17_concurrency_and_the_loop/test_scopes.py;
%     commit=c6e1198c490a824b96f6fc6e1c0622a542917024].
%   - spawned computations are SWI engines stepped over a bounded carrier
%     pool, and a space write wakes rather than parks a carrier [tested:
%     lib_thread:spawned_engines_multiplex_over_bounded_carriers,
%     lib_thread:a_suspended_engine_resumes_when_its_space_waker_fires,
%     lib_thread:cancelling_a_suspended_engine_releases_it_without_an_answer;
%     commit=39092863ae34184a9f955f185ff57c1ff177ec40]
%   - oracleIO host operations detach onto transient offload threads before
%     entering foreign code, so even more blocked calls than normal carriers
%     cannot consume scheduler capacity; cancellation signals the engine and
%     waits for acknowledgement. A foreign call must return before its engine
%     can acknowledge cancellation [tested: lib_thread_cancellation;
%     commit=c6e1198c490a824b96f6fc6e1c0622a542917024]
%   - future await, empty channel receive and full channel send suspend their
%     engines and wake from completion or mailbox state instead of blocking
%     all carriers [tested:
%     lib_thread:awaiting_futures_suspends_engines_instead_of_all_carriers,
%     lib_thread:empty_channel_receives_suspend_engines_instead_of_all_carriers,
%     lib_thread:full_channel_sends_suspend_engines_instead_of_all_carriers;
%     commit=39092863ae34184a9f955f185ff57c1ff177ec40]
%   - channel_close/2 refuses a closed or unknown channel with
%     existence_error(metta_channel, Id), as recv and send do, while a scope
%     releasing a channel already gone is not an error [tested:
%     lib_thread:closing_a_closed_channel_is_an_existence_error,
%     examples/ch17-concurrency-and-the-loop/05-channels_pools_and_the_machine.metta;
%     commit=f75df8e1c17a6c700e8d3700e440fe1ee535ea9f]
%   - future completion is single-assignment, settled pool work cannot be
%     reported as cancelled, timer dispatch cannot cross a successful
%     cancellation, a failed async landing publication records a terminal
%     error without overwriting an outcome already committed, and a repeating
%     timer coalesces ticks while its prior invocation is still running [tested:
%     lib_thread:a_future_terminal_outcome_is_single_assignment,
%     lib_thread:cancelling_a_completed_unawaited_pool_future_is_false,
%     lib_thread:timer_fire_and_cancel_have_one_atomic_transition,
%     lib_thread:a_repeating_timer_never_overlaps_its_own_invocations,
%     test_a_failed_landing_publication_settles_the_future_as_an_error;
%     commit=2f562bc5c051ee373cb7ab27ea6cae641f1df094]
%   - a thread worker settles its future exactly once whatever a cancellation
%     signal interrupted, including the window before its evaluation catch is
%     installed and the one after it exits, because the settlement runs in a
%     cleanup handler with thread signals blocked; and cancelling waits for
%     the worker thread to end rather than for its settlement, settling a
%     worker that ended unsettled as cancelled, so no canceller waits forever
%     [tested:
%     lib_thread:a_signal_before_the_worker_installs_its_catch_still_settles,
%     lib_thread:cancelling_a_worker_that_ended_unsettled_answers_cancelled;
%     commit=50e34286f66c938d89d5d367c6370ad44164c97f]
%   - a blocking take parks until a matching atom arrives, removes exactly
%     one, and two takers never claim the same atom: eight takers over four
%     atoms claim four distinct ones and the space is left empty [tested:
%     lib_thread:test_a_blocking_take_waits_for_a_matching_atom_and_removes_exactly_one,
%     lib_thread:a_blocking_peek_parks_without_removing; commit=c05f93baf8c6ecd483487efb72d7f8eb92c97809]
%   - a wait answers an atom the space holds even when no wake-up ever
%     reached it, because it re-reads the store on slices that back off from
%     50ms to a second rather than trusting the hint; that covers the write
%     door's own publisher being installed only while a handler exists, which
%     leaves a writer already inside it writing silently [tested:
%     lib_thread:a_wait_finds_an_atom_whose_hint_was_never_published,
%     lib_thread:a_scheduled_wait_finds_an_atom_whose_hint_was_never_published;
%     commit=5f92ecfb105f7a11d8f3b1a4c0a7e3b6d4b656a6]
%   - par-map answers one result per element, in the input list's order,
%     because concurrent_maplist/3 preserves position [tested: lib_thread:par_map_answers_one_result_per_element_in_order]
%   - par-race releases every worker from one start barrier and ignores Empty
%     answers, so source order cannot buy a branch thread-creation time and a
%     pruned branch cannot win [tested: lib_thread:race_survives_a_failing_branch;
%     commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87]
%   - a future holds its expression's whole ANSWER SET, because it is a space
%     the evaluating engine adds every answer to; awaiting twice answers the
%     same set without blocking a second time [tested: lib_thread:a_future_holds_the_whole_answer_set]
%   - future answer writes and iteration snapshots share a dedicated mutex and
%     a monotone publication position, so a snapshot plus later changes emits
%     every duplicate occurrence exactly once [tested:
%     test_future_iteration_watermark_separates_snapshot_from_later_events;
%     commit=1877bec75a9a22265c9222f0c0c538c8f65a983f]
%   - channels use one recorded FIFO as their foreign-space provider; space
%     operations and mailbox operations share its bag, and reads copy terms
%     [tested: lib_thread:a_channel_round_trips_a_term,
%     test_channel_space_and_mailbox_share_a_randomized_bag_and_fifo;
%     commit=c6e1198c490a824b96f6fc6e1c0622a542917024].
%   - timers cost no per-timer threads: one timer thread and one bounded pool serve every
%     timer in the process [assumed 2026-08-16: no test counts threads around an armed timer]
% Fails when:
%   - the work per element is small. A parallel map over cheap elements pays
%     thread creation for nothing; measure before reaching for it.
%   - many callers park on ONE space. A waiting space_await or space_take
%     costs the space a seam:atom_added/2 clause, so every write into
%     that space, including writes that match no waiter, runs one guard per
%     waiter: writes are O(waiters) and one arriving atom wakes all of them
%     to race for it, the thundering herd a hand-off queue would avoid and
%     this seam cannot, because an EVENT seam runs every handler by
%     construction. Exactly-one still holds, and the wasted work is one
%     failed removal per loser per atom. Channel notifications also wake
%     every registered waiter; their FIFO selects one receiver per message
%     [source: lib/lib_thread/lib_thread.pl:metta_channel_wake/2; commit=c6e1198c490a824b96f6fc6e1c0622a542917024].
%   - a branch needs the caller's variable bindings back. Threads copy terms,
%     so bindings made inside a branch do not escape it.
% Owns:
%   - recorded scope rows, host cleanup references and progress queues until
%     scope_close/4 succeeds; a failed cleanup retains its resources for retry.
%     Revocation markers retain only names [tested:
%     test_cleanup_failure_revokes_aliases_attempts_all_and_can_retry;
%     commit=c6e1198c490a824b96f6fc6e1c0622a542917024].
%   - one seam:atom_added/2 clause and one message queue per live
%     space_await/space_take call, both released when the call leaves
%   - one SWI engine and one completion queue per live spawned future; one
%     bounded normal carrier pool for the process; one transient offload
%     thread per currently blocking oracleIO step; one message queue per live
%     channel and one notification queue per blocked host channel call;
%     and, once any timer has been used, one timer thread plus one
%     bounded timer pool for the process.
% Guarded by:
%   - '$metta_scopes' protects scope state and ownership; each channel's name
%     protects its FIFO; recorded database operations publish waiters before
%     their first probe. Signals, callbacks and joins leave these
%     mutexes before running user work [source: lib/lib_thread/lib_thread.pl,
%     scope_cancel/2, scope_join_engines_/1, channel_try_/3; commit=c6e1198c490a824b96f6fc6e1c0622a542917024].
%   - '$metta_engine_scheduler' protects task state and carrier creation;
%     '$metta_timers' serialises starting the timer service; one outcome mutex
%     per future claims its terminal value, one answer mutex serialises
%     publication with iteration snapshots, and one await mutex serialises
%     waiter registration and mailbox consumption;
%     '$metta_timer_lifecycle' serialises timer dispatch and cancellation;
%     '$metta_scheduler_deadlines' serialises finite wake tokens.
% Decides:
%   - a future IS a space, so it carries an answer SET rather than one value.
%     A MeTTa expression has an answer set, and a future answering only the
%     first would discard the evaluation model at the concurrency boundary.
%   - a timer is a future that starts later, so setTimeout and clearTimeout are
%     spawn-with-a-delay and thread-cancel rather than a separate handle type.
%   - a saturated timer pool never blocks the one timer service: a one-shot
%     retries after 10ms and a repeating timer retries at its next period, so
%     scheduler deadlines remain independent of timer-body capacity [tested:
%     lib_thread:a_saturated_timer_pool_does_not_block_scheduler_deadlines;
%     commit=39092863ae34184a9f955f185ff57c1ff177ec40].
%   - oracleIO follows Go's blocking-syscall handoff: normal scheduler
%     carriers never enter potentially blocking foreign code; the engine
%     detaches onto a transient thread until that call returns [source:
%     https://github.com/golang/go/blob/c19862e5f8415b4f24b189d065ed739517c548ba/src/runtime/proc.go#L4781-L4831,
%     Go 1.26.5 entersyscallblock; source:
%     https://github.com/SWI-Prolog/swipl-devel/blob/fc7ef84b949378b729052c3ade79c90ce5416abb/man/engines.plx#L13-L21,
%     SWI-Prolog 10.1.13 engine_next/2 attachment semantics].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: latches and barriers over spaces, and supervision.
%     The choose/par handler follow-up is specified in
%     docs/journal/2026-09-08-a-scope-owns-its-children.md.


:- module(lib_thread,
          [ channel_close/2,
            channel_new/1,
            channel_new/2,
            channel_recv/2,
            channel_recv/3,
            channel_send/3,
            channel_size/2,
            channel_try_recv/2,
            cpu_count/1,
            future_add_atom/2,
            metta_async_future/4,
            metta_async_future_abandon/2,
            metta_async_future_bind/4,
            metta_async_future_discard/1,
            metta_async_future_discard/3,
            metta_async_future_fail/2,
            metta_async_future_new/2,
            metta_async_future_settle/4,
            metta_future_snapshot/3,
            par_any/3,
            par_filter/3,
            par_forall/3,
            par_map/3,
            par_race/2,
            pool_create/3,
            pool_destroy/2,
            pool_stats/2,
            pool_submit/3,
            scope_open/4,
            scope_current/1,
            scope_close/4,
            scope_call/2,
            scope_apply/4,
            scope_do/3,
            scope_keep/3,
            scope_cancel/2,
            scope_attach_space/3,
            scope_space_live/1,
            scope_space_dead/1,
            scope_engine_released/1,
            scope_forget_space/1,
            scope_drop_space/1,
            scope_cleanup/0,
            scope_publish/2,
            scope_host_resource/4,
            scope_host_done/2,
            scope_body/2,
            scope_defer/3,
            scope_defer/4,
            space_drop/2,
            capture/2,
            space_await/3,
            space_await/4,
            space_await_where/4,
            space_await_where/5,
            space_take/3,
            space_take/4,
            space_take_where/4,
            space_take_where/5,
            thread_await/2,
            thread_cancel/2,
            thread_count/1,
            thread_settled/2,
            thread_spawn/2,
            timer_after/3,
            timer_every/3,
            with_lock/3
          ]).

% Guarantees: private helpers and autoload declarations belong to this module.
% [tested: engine_modules; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
% Assumes: engine operations resolve through metta_engine's published exports.
% [source: engine/metta.pl:metta_engine_reexport/2; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
:- set_module(base(metta_engine)).

%Nothing below this line works without threads, so the file says so where the
%engine's pre-load scan can read it. An import on a build without
%library(thread) then refuses naming the capability and what it costs, and
%this file never loads; before it, the two imports failed one after the other
%and the MeTTa caller got a wrapped transcript of SWI's own source_sink errors
%[tested: platform_capabilities_reduced:a_library_that_declares_an_absent_capability_never_loads].
:- metta_requires(concurrency).
:- use_module(library(thread)).
:- use_module(library(thread_pool)).
:- use_module(library(error)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(aggregate)).
:- use_module(library(heaps)).
:- use_module(library(pairs)).

:- dynamic metta_future/3.          % Space, Worker, DoneQueue
:- dynamic metta_future_result/2.   % Space, done | cancelled | error(Error)
:- dynamic metta_scheduler_task/6.  % Id, Engine, Space, Done, Context, State
:- dynamic metta_scheduler_lane/3.  % Lane, runnable queue, carrier threads
:- dynamic metta_future_waiter/2.   % Future space, suspended scheduler task
:- dynamic metta_timer_context/3.   % Future space, repeat policy, Python Context
:- dynamic metta_scheduler_deadline/2. % Token, suspended scheduler task
:- dynamic metta_async_future/4.    % Token, operation name, space, DoneQueue

%THE ONLY WAY THIS LIBRARY JOINS A THREAD. thread_join/2 on its own is unsafe
%against any thread that can be inside engine_create/3 or engine_destroy/1,
%which every thread that runs MeTTa can be.
%
%PL_set_engine's detach_engine() memsets the CALLING thread's own
%PL_thread_info_t.tid to zero and restores it on the way out, and thread_join/2
%reads that field once, with no has_tid test, and hands it to
%pthread_timedjoin_np. A join landing in that window calls
%pthread_timedjoin_np(0, ...) and glibc dereferences a null struct pthread
%[source: SWI-Prolog 10.1.13 src/pl-thread.c:7038 detach_engine, :7056
%PL_set_engine by its line :7077, :4083 '$engine_create'/3 whose PL_set_engine
%pair is :4134 and :4148, :4164 destroy_interactor whose pair is :4168 and
%:4170, :2898 thread_join reading .tid at :2927;
%commit=2421d06e697daffb0797c307a798131616ebdd8e].
%
%The window is not this library's to avoid at the other end. A merged match
%opens one engine per space and destroys them all when it is done
%[source: engine/spaces/bounded_matching.pl, metta_match_engine/4 and
%metta_engine_done/1; commit=2421d06e697daffb0797c307a798131616ebdd8e], so any
%worker evaluating an ordinary
%query passes through it, and race_stop_/1 and cancel_future_worker_/4 join
%exactly such workers, straight after a thread_signal(_, abort) that a thread
%inside engine_create/3 does not survive cleanly either.
%
%A thread whose status has left `running` has finished its body. Waiting for
%that excludes the body's engine-switch window. SWI still runs its exit hooks:
%start_thread publishes completion before freePrologThread calls them. The
%default pool hook reports exit to the manager, then calls true; it does not
%switch engines. This wait does not establish safety for a caller exit hook
%that itself switches engines [source:
%https://github.com/SWI-Prolog/swipl-devel/blob/V10.1.13/src/pl-thread.c:start_thread,freePrologThread
%and library/thread_pool.pl:worker_exitted/3; commit=8ca8a387fc61d0918484b19a1a3baf85b6523043].
%
%The wait POLLS, because SWI publishes thread completion only through
%thread_property/2 and the blocking wait for it IS thread_join/2, the call that
%is unsafe. It backs off from half a millisecond to 32, so a worker that was
%just aborted is joined inside a millisecond and one that runs for minutes
%costs about thirty wakeups a second; SWI's own thread_join/2 polls at 250ms
%for its signal handling [source: SWI-Prolog 10.1.13 src/pl-thread.c:2873
%pthread_join_interruptible; commit=2421d06e697daffb0797c307a798131616ebdd8e].
%[tested: lib_thread:a_joined_worker_survives_engine_churn_on_its_thread,
%lib_thread:a_joined_worker_survives_a_merged_match_on_its_thread;
%commit=2421d06e697daffb0797c307a798131616ebdd8e]
metta_thread_join_settled(Thread, Status) :-
    metta_thread_settled_(Thread, 0.0005),
    thread_join(Thread, Status).

%A thread that has gone entirely counts as settled: thread_join/2 then reports
%the existence error, which is what every caller here already catches.
metta_thread_settled_(Thread, Delay) :-
    (   catch(thread_property(Thread, status(Status)),
              error(existence_error(thread, Thread), _), Status = gone),
        Status \== running
    ->  true
    ;   sleep(Delay),
        Next is min(Delay * 2, 0.032),
        metta_thread_settled_(Thread, Next)
    ).

%Handles are small integers rather than blobs so they print, compare and
%cross the Python boundary as ordinary MeTTa values.
%The counter is a FLAG rather than a dynamic fact, and the difference is a
%WRONG ANSWER rather than a style. A fact is source, and importing this
%library into a SECOND space consults the file again, which put the counter
%back to zero and made the next mint hand out a name that was already in use:
%`(dict-space ((a 1) (b 2)))` in a second space answered a size of four,
%because it had added its two entries on top of the first dict's two in
%`&json-1` [tested: test_a_dict_is_a_space_a_comprehension_can_build;
%commit=657ae9672c07b628f8a20c7fe39aa43e58b0014f]. A flag lives outside the source, so re-loading cannot
%reset it, and its update is atomic, which is the whole of what the mutex was
%for [source: SWI-Prolog 10.1 Reference Manual, flag/3, "The update is
%atomic. This predicate can be used to create a shared global counter"].
next_metta_handle(Id) :-
    flag('$metta_thread_handle', Previous, Previous + 1),
    Id is Previous + 1.

% --------------------------------------------------------- lifetime scopes

% A nursery joins before releasing inputs. The recorded database is deliberate:
% SWI transactions must not roll back ownership of a still-running computation.
% Python carries these handles; it owns no parallel lifetime registry.
% [tested: lib_thread_scope; commit=c6e1198c490a824b96f6fc6e1c0622a542917024]
:- meta_predicate scope_call(+, 0).
:- meta_predicate scope_publish(+, 0).
:- dynamic scope_deferred_/6.
:- multifile seam:engine_context/1, seam:space_created/1,
             seam:space_access/1, seam:space_releasing/1,
             seam:host_engine_created/1, seam:host_engine_released/1,
             seam:foreign_refuse/2.

scope_current_(Scope) :-
    ( nb_current('$metta_scope', Current) -> Scope = Current ; Scope = none ).

scope_current(Scope) :- scope_current_(Scope).

scope_id_(Prefix, Id) :-
    next_metta_handle(Number), atom_concat(Prefix, Number, Id).

scope_state_(Id, Parent, Owner, State, Reason) :-
    with_mutex('$metta_scopes',
               recorded(Id, state(Parent, Owner, State, Reason), _)).

scope_open(Parent, Owner, Seconds, Id) :-
    scope_outside_transaction_,
    ( Seconds == infinite -> true
    ; must_be(number, Seconds),
      ( Seconds >= 0 -> true ; domain_error(not_less_than_zero, Seconds) ) ),
    scope_id_('$metta_scope_', Id),
    message_queue_create(Progress, [max_size(1)]),
    catch(( with_mutex('$metta_scopes', sig_atomic((
                scope_checkpoint_(Parent),
                recorda(Id, state(Parent, Owner, open, none), _),
                recordz(Id, progress(Progress), _),
                ( Parent == none -> true ; recordz(Parent, child(scope, Id), _) ) ))),
            scope_deadline_(Seconds, Id) ), Error,
          ( message_queue_destroy(Progress), scope_erase_(Id),
            scope_unlink_(Parent, scope, Id), throw(Error) )).

scope_deadline_(infinite, _) :- !.
scope_deadline_(Seconds, Id) :-
    ensure_timer_service, get_time(Now), Deadline is Now + Seconds,
    metta_timer_queue(Queue),
    thread_send_message(Queue, schedule(Deadline, scope_deadline(Id))).

scope_outside_transaction_ :-
    ( current_transaction(_)
    -> permission_error(start, scope_in_transaction, transaction)
    ; true ).

scope_checkpoint_(none) :- !.
scope_checkpoint_(Id) :-
    ( scope_state_(Id, Parent, _, State, _)
    -> ( State == cancelled -> scope_throw_(Id)
       ; State == closing -> permission_error(enter, closed_scope, Id)
       ; scope_checkpoint_(Parent) )
    ; existence_error(metta_scope, Id) ).

scope_throw_(Id) :-
    throw(error(metta_control_signal(interrupted, [scope, Id]),
                context(metta, scope(Id)))).

scope_call(none, Goal) :- !, call(Goal).
scope_call(Id, Goal) :-
    scope_current_(Previous),
    ( Previous \== none, scope_descendant_(Previous, Id)
    -> Effective = Previous ; Effective = Id ),
    setup_call_cleanup(
        scope_enter_(Effective, Registration),
        ( b_setval('$metta_scope', Effective),
          scope_checkpoint_(Effective), call(Goal), scope_checkpoint_(Effective) ),
        ( b_setval('$metta_scope', Previous), scope_leave_(Effective, Registration) )).

scope_descendant_(Id, Id) :- !.
scope_descendant_(Id, Ancestor) :-
    scope_state_(Id, Parent, _, _, _), Parent \== none,
    scope_descendant_(Parent, Ancestor).

scope_enter_(Id, Registration) :-
    thread_self(Engine),
    with_mutex('$metta_scopes', sig_atomic((
        scope_checkpoint_(Id),
        ( recorded(Id, active(_, Engine), _)
        -> Registration = none
        ; scope_id_('$metta_scope_call_', Token),
          recordz(Id, active(Token, Engine), Ref), Registration = ref(Ref) ) ))).

scope_leave_(_, none).
scope_leave_(Id, ref(Ref)) :-
    with_mutex('$metta_scopes', (erase(Ref), scope_progress_(Id))).

scope_progress_(Id) :-
    ( recorded(Id, progress(Queue), _), message_queue_property(Queue, size(0))
    -> thread_send_message(Queue, changed) ; true ).

% A completion publishes terminal state before its observers finish. Retain
% that producer until publication leaves, including when cancellation won.
scope_publish(Space, Goal) :-
    ( scope_space_owner_(Space, Id, _), scope_state_(Id, _, _, _, _)
    -> scope_current_(Previous),
       setup_call_cleanup(
           with_mutex('$metta_scopes', recordz(Id, publishing, Ref)),
           ( b_setval('$metta_scope', Id), call(Goal) ),
           ( b_setval('$metta_scope', Previous), scope_leave_(Id, ref(Ref)) ) )
    ; call(Goal) ).

scope_apply(Id, Predicate, Inputs, Out) :-
    append(Inputs, [Out], Arguments), Goal =.. [Predicate|Arguments],
    scope_call(Id, user:Goal).
scope_do(Id, Predicate, Inputs) :-
    Goal =.. [Predicate|Inputs], scope_call(Id, user:Goal).

seam:engine_context(lib_thread:scope_call(Id)) :-
    scope_current_(Id), Id \== none.

seam:host_engine_created(Engine) :-
    scope_current_(Id),
    ( Id == none -> true
    ; with_mutex('$metta_scopes', sig_atomic((
          scope_checkpoint_(Id), recordz(Id, child(engine, Engine), _),
          scope_engine_key_(Engine, Key), recorda(Key, owner(Id), _) ))) ).
seam:host_engine_released(Engine) :-
    with_mutex('$metta_scopes',
        ( scope_engine_key_(Engine, Key),
          forall(recorded(Key, owner(Id), Ref),
                 ( erase(Ref), scope_unlink_(Id, engine, Engine), scope_progress_(Id) )) )).

scope_engine_key_(Engine, Key) :-
    term_to_atom(Engine, Atom), atom_concat('$metta_scope_engine:', Atom, Key).

scope_owner_(Id, Owner) :-
    ( scope_state_(Id, _, Actual, _, _)
    -> ( Actual == Owner -> true ; permission_error(close, scope_owner, Id) )
    ; existence_error(metta_scope, Id) ).

scope_cancel(Id, Reason) :-
    with_mutex('$metta_scopes', sig_atomic((
        ( recorded(Id, state(Parent, Owner, State, Prior), Ref), State \== closing
        -> ( Prior == none -> Cause = Reason ; Cause = Prior ),
           erase(Ref), recorda(Id, state(Parent, Owner, cancelled, Cause), _),
           findall(Kind-Value, recorded(Id, child(Kind, Value), _), Resources),
           findall(active-(Token-Engine), recorded(Id, active(Token, Engine), _), Active),
           append(Resources, Active, Requests)
        ; Requests = [] ) ))),
    % A refused signal must not prevent the remaining siblings from stopping.
    findall(Error,
        ( member(Request, Requests),
          catch(( scope_request_stop_(Id, Reason, Request)
                -> fail
                ; throw(error(scope_cancel_failed(Request), context(scope_cancel/2, Id))) ),
                Error, true) ), Errors),
    ( Errors == [] -> true
    ; Errors = [Error] -> throw(Error)
    ; throw(error(scope_cancellation(Errors), context(scope_cancel/2, Id))) ).

% An automatic request has no caller to receive refusal. Retain it for close;
% completion publication and the shared timer service must still finish.
scope_cancel_automatic_(Id, Reason) :-
    catch(scope_cancel(Id, Reason), Error,
          ( message_to_string(Error, Text), scope_fault_(Id, [prolog, Text]) )).

scope_signal_active_(Id, Token-Engine) :-
    ( metta_scheduler_task(_, Engine, Space, _, _, _),
      scope_space_owner_(Space, Id, _)
    -> true
    ; catch(thread_signal(Engine, lib_thread:scope_deliver_(Id, Token)),
            error(existence_error(thread, _), _), true) ).

scope_deliver_(Id, Token) :-
    ( recorded(Id, active(Token, _), _),
      scope_state_(Id, _, _, cancelled, _)
    -> scope_throw_(Id)
    ; true ).

scope_request_stop_(_, Reason, scope-Child) :- !, scope_cancel(Child, Reason).
scope_request_stop_(Id, _, active-Active) :- !, scope_signal_active_(Id, Active).
scope_request_stop_(_, _, space-Space) :- !,
    ( metta_future_result(Space, _) -> true
    ; metta_future(Space, scheduler(Task), _)
    -> metta_scheduler_request_cancel(Task, _)
    ; metta_future(Space, async(Token), _)
    -> metta_async_cancel(Token, _)
    ; metta_future(Space, none, _)
    -> thread_cancel(Space, _)
    ; metta_future(Space, Worker, _)
    -> catch(thread_signal(Worker, lib_thread:future_cancel_signal_(Space, Worker)),
             error(existence_error(thread, _), _), true)
    ; true ).
scope_request_stop_(Id, _, host-Token) :- !,
    ( recorded(Token, host(_, future, Object), _)
    -> user:py_call(Object:'__call__'(Id))
    ; true ).
scope_request_stop_(_, _, _).

scope_space_key_(Space, Key) :-
    term_to_atom(Space, Atom), atom_concat('$metta_scope_space:', Atom, Key).

scope_space_owner_(Space, Owner, Host) :-
    ground(Space), scope_space_key_(Space, Key),
    with_mutex('$metta_scopes', recorded(Key, lifetime(Owner, Host), _)).

scope_space_live(Space) :-
    ( nb_current('$metta_scope_cleanup', true) -> true
    ; scope_revoked_(Space)
    -> permission_error(access, released_scope_space, Space)
    ; true ).

seam:space_access(Space) :- scope_space_live(Space).
seam:space_created(Space) :-
    scope_current_(Id),
    ( Id == none -> true
    ; with_mutex('$metta_scopes', sig_atomic((
          % Allocation has already happened. Enrol it even if cancellation won;
          % the active call keeps its scope open until the next checkpoint.
          scope_space_live(Space),
          ( scope_space_owner_(Space, _, _) -> true
          ; scope_space_key_(Space, Key),
            recorda(Key, lifetime(Id, none), _),
            recordz(Id, child(space, Space), _) ) ))) ).

scope_attach_space(Space, Host, Scoped) :-
    with_mutex('$metta_scopes', sig_atomic((
        ( scope_space_key_(Space, Key), recorded(Key, lifetime(Owner, Existing), Ref)
        -> Scoped = true,
           ( Owner == dead -> true
           ; recorded(Key, retired, _) -> true
           ; nb_current('$metta_scope_cleanup', true) -> true
           ; Existing == none, Host \== none
           -> erase(Ref), recorda(Key, lifetime(Owner, Host), _)
           ; true )
        ; Scoped = false ) ))).

scope_forget_space(Space) :-
    with_mutex('$metta_scopes', sig_atomic((
        ( scope_space_key_(Space, Key), recorded(Key, lifetime(Owner, _), Ref)
        -> erase(Ref), forall(recorded(Key, retired, Retired), erase(Retired)),
           recorda(Key, lifetime(dead, none), _),
           scope_unlink_(Owner, space, Space)
        ; true ) ))).

seam:space_releasing(Space) :-
    ( metta_future(Space, _, _)
    -> thread_cancel(Space, _), future_settle_(Space, _)
    ; true ).
seam:space_released(Space) :-
    forall(retract(metta_future(Space, _, Done)),
           message_queue_destroy(Done)),
    retractall(metta_future_result(Space, _)),
    with_mutex('$metta_scopes', sig_atomic((
        ( scope_space_key_(Space, Key), recorded(Key, lifetime(Owner, Host), Ref)
        -> ( Host == none
           -> erase(Ref), recorda(Key, lifetime(dead, none), _),
              scope_unlink_(Owner, space, Space)
           ; ( recorded(Key, retired, _) -> true ; recordz(Key, retired, _) ) )
        ; true ) ))).

scope_cleanup :- nb_current('$metta_scope_cleanup', true).

scope_engine_released(Space) :-
    scope_space_key_(Space, Key), recorded(Key, retired, _).

scope_drop_space(Space) :-
    scope_space_owner_(Space, dead, _), !.
scope_drop_space(Space) :-
    setup_call_cleanup(
        ( ( nb_current('$metta_scope_cleanup', Previous) -> true ; Previous = false ),
          b_setval('$metta_scope_cleanup', true) ),
        scope_release_(none, none, cleanup, space-Space),
        b_setval('$metta_scope_cleanup', Previous)).

% A revoked raw name must refuse reads as well as creation. Enumeration omits
% tombstones: a revocation is not a registered live space.
scope_revoked_(Space) :-
    ground(Space),
    with_mutex('$metta_scopes',
        ( scope_space_owner_(Space, Owner, _),
          ( Owner == dead -> true ; scope_engine_released(Space) ) )).
scope_space_dead(Space) :- scope_revoked_(Space).
seam:foreign_space(Space) :- scope_revoked_(Space).
seam:foreign_refuse(Space, _) :- scope_revoked_(Space), scope_space_live(Space).
seam:foreign_atoms(Space, _) :-
    scope_revoked_(Space), !, scope_space_live(Space).
seam:foreign_match(Space, _, _) :-
    scope_revoked_(Space), !, scope_space_live(Space).
seam:foreign_add(Space, _) :-
    scope_revoked_(Space), !, scope_space_live(Space).
seam:foreign_remove(Space, _, _) :-
    scope_revoked_(Space), !, scope_space_live(Space).
seam:foreign_clear(Space) :-
    scope_revoked_(Space), !, scope_space_live(Space).

scope_host_resource(Id, Kind, Object, Token) :-
    scope_outside_transaction_,
    must_be(oneof([future, cleanup]), Kind),
    scope_id_('$metta_scope_host_', Token),
    ( Kind == future -> message_queue_create(Queue, [max_size(1)]) ; Queue = none ),
    catch(with_mutex('$metta_scopes', sig_atomic((
              scope_checkpoint_(Id), recorda(Token, host(Id, Kind, Object), _),
              recordz(Id, child(host, Token), _),
              ( Queue == none -> true ; recordz(Token, queue(Queue), _) ) ))),
          Error,
          ( ( Queue == none -> true ; message_queue_destroy(Queue) ),
            scope_erase_(Token), scope_unlink_(Id, host, Token), throw(Error) )).

scope_host_done(Token, Error) :-
    ( recorded(Token, host(Id, future, _), _)
    -> ( Error == none -> true
       ; scope_fault_(Id, [python, Error]), scope_cancel_automatic_(Id, child_failure) ),
       recorded(Token, queue(Queue), _), thread_send_message(Queue, done)
    ; true ).

% This is the native counterpart of a host cleanup callback. The descriptor
% belongs to the database transaction; its child entry belongs to Scope.
% Rollback can remove the former without orphaning a host resource because
% the held expression owns database facts, not a running computation.
scope_defer(Value, Expr, Out) :- scope_defer(Value, Expr, [], Out).

scope_defer(Value, Expr, Dependencies, true) :-
    scope_current_(Id),
    ( Id == none -> true
    ; must_be(ground, Value),
      current_metta_module(Module),
      with_mutex('$metta_scopes', sig_atomic((
          scope_checkpoint_(Id), scope_id_('$metta_scope_deferred_', Token),
          assertz(scope_deferred_(Token, Id, Value, Module, Expr, Dependencies)),
          recordz(Id, child(deferred, Token), _) ))) ).

space_drop(Space, true) :- scope_drop_space(Space).

scope_fault_(Id, Error) :-
    with_mutex('$metta_scopes', recordz(Id, fault(Error), _)).

scope_future_done_(Space, Outcome) :-
    ( scope_space_owner_(Space, Id, _), scope_state_(Id, _, _, _, _),
      Outcome = error(Error)
    -> message_to_string(Error, Text),
       with_mutex('$metta_scopes', sig_atomic((
           recordz(Id, fault([prolog, Text]), _),
           recorded(Id, state(Parent, Owner, State, Prior), Ref),
           ( State == closing -> true
           ; ( Prior == none -> Reason = child_failure ; Reason = Prior ),
             erase(Ref), recorda(Id, state(Parent, Owner, cancelled, Reason), _) ) )))
    ; true ).

scope_keep(Id, Owner, Value) :-
    scope_owner_(Id, Owner), scope_checkpoint_(Id),
    forall(scope_value_resource_(Id, Value, Resource),
           ( recorded(Id, root(Resource), _) -> true
           ; recordz(Id, root(Resource), _) )).

scope_value_resource_(Id, Value, Resource) :-
    sub_term(Part, Value), ground(Part),
    ( scope_space_owner_(Part, Owner, _), Resource = space-Part
    ; scope_deferred_(Token, Owner, Part, _, _, _), Resource = deferred-Token ),
    scope_descendant_(Id, Owner).

scope_keep_value_(Id, Value) :-
    forall(scope_value_resource_(Id, Value, Resource), scope_keep_resource_(Id, Resource)).

scope_keep_resource_(Id, space-Space) :- scope_keep_space_(Id, Space).
scope_keep_resource_(Id, deferred-Token) :- scope_keep_deferred_(Id, Token).

% Like a container's tp_traverse, the held query describes current edges;
% cleanup remains separate. See CPython v3.14.4 Doc/c-api/gcsupport.rst:223-237.
% Mark before following edges so mutually referring owned values terminate.
scope_keep_deferred_(Id, Token) :-
    ( recorded(Id, keep_deferred(Token), _) -> true
    ; recordz(Id, keep_deferred(Token), _),
      ( scope_deferred_(Token, _, Value, Module, Expr, Dependencies)
      -> scope_keep_value_(Id, [Value, Expr, Dependencies]),
         forall(spaces:metta_module_space(Module, Home), scope_keep_value_(Id, Home)),
         forall(eval_metta_in_module(Module, Dependencies, Child),
                ( scope_expression_answer_(dependencies, Child),
                  scope_keep_value_(Id, Child) ))
      ; true ) ).

scope_keep_space_(Id, Space) :-
    ( recorded(Id, keep(Space), _) -> true
    ; recordz(Id, keep(Space), _),
      forall(( seam:space_dependency(Space, Parent),
               scope_space_owner_(Parent, Owner, _), scope_descendant_(Id, Owner) ),
             scope_keep_space_(Id, Parent)),
      ( metta_future(Space, _, _)
      -> forall('get-atoms'(Space, Answer), scope_keep_value_(Id, Answer))
      ; true ) ).

scope_refresh_kept_(Id, Reason, Errors) :-
    forall(( recorded(Id, keep(_), Ref) ; recorded(Id, keep_deferred(_), Ref) ),
           erase(Ref)),
    ( Reason \== none -> Errors = []
    ; findall([prolog, Text],
          ( recorded(Id, root(Resource), _),
            catch(( scope_keep_resource_(Id, Resource) -> fail
                  ; throw(error(scope_retention_failed(Resource), context(scope, Id))) ),
                  Error, message_to_string(Error, Text)) ), Errors) ).

scope_close(Id, Owner, Disposition, [Reason, Errors, Released]) :-
    scope_owner_(Id, Owner),
    thread_self(Current),
    ( recorded(Id, active(_, Current), _)
    -> permission_error(close, active_scope_body, Id) ; true ),
    ( Disposition == success -> true ; scope_cancel(Id, body_failure) ),
    setup_call_cleanup(
        ( ( nb_current('$metta_scope_cleanup', Previous) -> true ; Previous = false ),
          b_setval('$metta_scope_cleanup', true) ),
        ( scope_finish_(Id, Disposition, Reason, Errors),
          ( scope_state_(Id, _, _, _, _) -> Released = false ; Released = true ) ),
        b_setval('$metta_scope_cleanup', Previous)).

scope_finish_(Id, Disposition, Reason, Errors) :-
    ( scope_state_(Id, _, _, cancelled, _)
    -> scope_cancel(Id, cancelled) ; true ),
    forall(( recorded(Id, child(space, Timer), _),
             metta_timer_context(Timer, every(_), _) ), thread_cancel(Timer, _)),
    scope_join_(Id),
    scope_join_engines_(Id),
    scope_state_(Id, _, _, _, PriorReason),
    ( Disposition \== success, PriorReason == none -> Reason = body_failure
    ; Reason = PriorReason ),
    scope_refresh_kept_(Id, Reason, RetentionErrors),
    ( RetentionErrors == [] -> scope_dispose_(Id, Reason, Errors)
    ; Errors = RetentionErrors ).

scope_dispose_(Id, Reason, Errors) :-
    with_mutex('$metta_scopes', sig_atomic((
        recorded(Id, state(Parent, Owner, _, _), Ref), erase(Ref),
        recorda(Id, state(Parent, Owner, closing, Reason), _),
        findall(Kind-Value, recorded(Id, child(Kind, Value), _), Resources) ))),
    reverse(Resources, Reverse),
    partition(scope_returning_(Id, Reason), Reverse, Returning, Releasing),
    scope_release_all_(Id, Parent, cleanup, Releasing, FirstErrors),
    ( FirstErrors == [] -> Transfer = Reason ; Transfer = cleanup ),
    % Adoption preserves acquisition order in the parent's child list, so its
    % eventual cleanup follows the same reverse order as the child's cleanup.
    ( Transfer == none -> reverse(Returning, Transferring)
    ; Transferring = Returning ),
    scope_release_all_(Id, Parent, Transfer, Transferring, LastErrors),
    append(FirstErrors, LastErrors, CleanupErrors),
    findall(Error, recorded(Id, fault(Error), _), Faults),
    append(Faults, CleanupErrors, Errors),
    ( is_message_queue(metta_timer_requests)
    -> thread_send_message(metta_timer_requests, cancel(scope_deadline(Id)))
    ; true ),
    ( CleanupErrors == []
    -> with_mutex('$metta_scopes',
           ( recorded(Id, progress(Progress), _), message_queue_destroy(Progress),
             scope_erase_(Id), scope_unlink_(Parent, scope, Id) ))
    ; true ).

scope_returning_(Id, none, space-Space) :- recorded(Id, keep(Space), _).
scope_returning_(Id, none, deferred-Token) :- recorded(Id, keep_deferred(Token), _).

scope_release_all_(Id, Parent, Reason, Resources, Errors) :-
    findall([prolog, Text],
        ( member(Resource, Resources),
          catch(( ( scope_release_(Id, Parent, Reason, Resource) -> true
                  ; throw(error(scope_cleanup_failed(Resource), context(scope, Id))) ),
                  fail ), Error, message_to_string(Error, Text)) ), Errors).

scope_join_(Id) :-
    ( recorded(Id, child(space, Space), _),
      metta_future(Space, _, _), \+ metta_future_result(Space, _)
    -> ( scope_state_(Id, _, _, cancelled, _)
       -> thread_cancel(Space, _) ; true ),
       future_settle_(Space, _), scope_join_(Id)
    ; recorded(Id, child(host, Token), _),
      recorded(Token, host(_, future, _), _),
      \+ recorded(Token, joined, _)
    -> recorded(Token, queue(Queue), _), thread_get_message(Queue, done),
       recordz(Token, joined, _), scope_join_(Id)
    ; true ).

scope_join_engines_(Id) :-
    scope_join_(Id),
    forall(recorded(Id, child(engine, Engine), _), metta_host_hold_close(Engine)),
    with_mutex('$metta_scopes',
        ( ( (recorded(Id, active(_, _), _) ; recorded(Id, publishing, _))
          -> Waiting = true
          ; ( recorded(Id, child(space, Space), _), metta_future(Space, _, _),
              \+ metta_future_result(Space, _)
            ; recorded(Id, child(host, Token), _), recorded(Token, host(_, future, _), _),
              \+ recorded(Token, joined, _) )
          -> Waiting = again
          ; recorded(Id, child(scope, Child), _),
            scope_state_(Child, _, _, ChildState, _), ChildState \== closing
          -> Waiting = child(Child)
          ; recorded(Id, state(Parent, Owner, _, Reason), Ref), erase(Ref),
            recorda(Id, state(Parent, Owner, closing, Reason), _), Waiting = false ),
          recorded(Id, progress(Progress), _) )),
    ( Waiting == true
    -> thread_get_message(Progress, changed), scope_join_(Id), scope_join_engines_(Id)
    ; Waiting == again -> scope_join_engines_(Id)
    ; Waiting = child(Child)
    -> scope_state_(Child, _, ChildOwner, _, _),
       scope_close(Child, ChildOwner, success, [_, ChildErrors, _]),
       maplist(scope_fault_(Id), ChildErrors),
       ( ChildErrors == [] -> true ; scope_cancel(Id, child_failure) ),
       scope_join_engines_(Id)
    ; true ).

scope_release_(_, _, _, space-Space) :-
    scope_space_owner_(Space, dead, _), !.
scope_release_(Id, Parent, none, space-Space) :-
    recorded(Id, keep(Space), _), !,
    with_mutex('$metta_scopes', sig_atomic((
        scope_space_key_(Space, Key), recorded(Key, lifetime(_, Host), Ref),
        erase(Ref), recorda(Key, lifetime(Parent, Host), _),
        scope_unlink_(Id, space, Space),
        ( Parent == none -> true ; recordz(Parent, child(space, Space), _) ) ))).
% The host's drop retires the space inside the current transaction and
% forgets this record from its own completion after the outer outcome, so an
% abort keeps the lifetime; seam:space_released/1 below marks the engine's half.
scope_release_(_, _, _, space-Space) :-
    ( scope_space_owner_(Space, _, Host), Host \== none
    -> user:py_call(Host:'__call__'(), _)
    ; metta_release_space(Space) ).
scope_release_(_, _, _, host-Token) :-
    ( recorded(Token, host(_, Kind, Object), _)
    -> scope_host_release_(Kind, Object),
       forall(recorded(Token, queue(Queue), _), message_queue_destroy(Queue)),
       scope_erase_(Token)
    ; true ).
scope_release_(Id, Parent, none, deferred-Token) :-
    recorded(Id, keep_deferred(Token), _), !,
    with_mutex('$metta_scopes', sig_atomic((
        scope_unlink_(Id, deferred, Token),
        ( retract(scope_deferred_(Token, Id, Value, Module, Expr, Dependencies))
        -> ( Parent == none -> true
           ; assertz(scope_deferred_(Token, Parent, Value, Module, Expr, Dependencies)),
             recordz(Parent, child(deferred, Token), _) )
        ; true ) ))).
scope_release_(_, _, _, deferred-Token) :-
    ( scope_deferred_(Token, _, _, Module, Expr, _)
    -> findall(Answer, eval_metta_in_module(Module, Expr, Answer), Answers),
       Answers \== [],
       forall(member(Answer, Answers), scope_expression_answer_(cleanup, Answer)),
       retractall(scope_deferred_(Token, _, _, _, _, _))
    ; true ).
scope_release_(_, _, _, pool-Name) :- pool_destroy(Name, _).
scope_release_(_, _, _, engine-Engine) :- metta_host_hold_close(Engine).
scope_release_(_, _, _, scope-Id) :-
    ( scope_state_(Id, _, Owner, _, _)
    -> scope_close(Id, Owner, failure, [_, Errors, _]),
       ( Errors == [] -> true ; throw(error(scope_cleanup(Errors), _)) )
    ; true ).

scope_host_release_(future, _).
scope_host_release_(cleanup, Object) :- user:py_call(Object:'__call__'()).

scope_expression_answer_(Stage, Answer) :-
    ( nonvar(Answer), Answer = [Head|Tail], Head == 'Error', nonvar(Tail)
    -> throw(error(scope_expression_answer(Stage, Answer), none))
    ; true ).

scope_unlink_(Id, Kind, Value) :-
    forall(recorded(Id, child(Kind, Value), Ref), erase(Ref)).
scope_erase_(Id) :- forall(recorded(Id, _, Ref), erase(Ref)).

scope_body(Expr, Out) :-
    scope_current_(Parent), thread_self(Owner),
    scope_open(Parent, Owner, infinite, Id), current_metta_module(Module),
    catch(( findall(Value, scope_call(Id, eval_metta_in_module(Module, Expr, Value)), Values),
            scope_keep(Id, Owner, Values), Disposition = success ),
          Error, Disposition = error(Error)),
    scope_close(Id, Owner, Disposition, [Reason, Errors, _]),
    ( Disposition = error(Error), Reason \== child_failure -> throw(Error)
    ; Errors \== [] -> throw(error(scope_children(Errors), context(scope_body/2, Reason)))
    ; Disposition = error(Error) -> throw(Error)
    ; member(Out, Values) ).

capture(Expr, [evalc, Expr, Space]) :- current_metta_space(Space).

% ------------------------------------------------------- parallel over data

%Evaluate (F Element) for each element, one answer each, positions preserved.
par_map(F, List, Out) :-
    must_be(list, List),
    current_metta_module(Module),
    length(List, Count),
    setup_call_cleanup(
        metta_capture_python_contexts(Count, Contexts),
        concurrent_maplist(par_apply_(Module, F), Contexts, List, Out),
        metta_release_python_contexts(Contexts)).

par_apply_(Module, F, Context, Element, Result) :-
    metta_in_python_context(
        Context,
        eval_metta_in_module(Module, [F, Element], Result)).

%Keep the elements for which (F Element) answers True.
par_filter(F, List, Out) :-
    must_be(list, List),
    current_metta_module(Module),
    length(List, Count),
    setup_call_cleanup(
        metta_capture_python_contexts(Count, Contexts),
        concurrent_maplist(par_true_(Module, F), Contexts, List, Flags),
        metta_release_python_contexts(Contexts)),
    keep_flagged_(List, Flags, Out).

par_true_(Module, F, Context, Element, Flag) :-
    metta_in_python_context(
        Context,
        (   eval_metta_in_module(Module, [F, Element], Answer),
            Answer == true
        ->  Flag = true
        ;   Flag = false
        )).

keep_flagged_([], [], []).
keep_flagged_([E|Es], [true|Fs], [E|Out]) :- !, keep_flagged_(Es, Fs, Out).
keep_flagged_([_|Es], [_|Fs], Out) :- keep_flagged_(Es, Fs, Out).

%True when (F Element) answers True for every element, False otherwise.
%concurrent_forall/2 stops the remaining workers as soon as one fails.
par_forall(F, List, Answer) :-
    must_be(list, List),
    current_metta_module(Module),
    length(List, Count),
    setup_call_cleanup(
        ( metta_capture_python_contexts(Count, Contexts),
          pairs_keys_values(Pairs, Contexts, List) ),
        (   concurrent_forall(member(Context-Element, Pairs),
                              par_true_checked_(Module, F, Context, Element))
        ->  Answer = true
        ;   Answer = false
        ),
        metta_release_python_contexts(Contexts)).

par_true_checked_(Module, F, Context, Element) :-
    metta_in_python_context(
        Context,
        ( eval_metta_in_module(Module, [F, Element], Answer),
          Answer == true )).

%True when (F Element) answers True for at least one element.
%
%Expressed as "not every element fails" so that concurrent_forall/2's early
%exit does the work. first_solution/3 is the obvious primitive and is the
%wrong one: it answers the first goal to COMPLETE, so a branch that finishes
%by failing makes the whole call fail [measured 2026-08-15:
%first_solution(found, [nope(_), fast(_)], []) fails].
par_any(F, List, Answer) :-
    must_be(list, List),
    current_metta_module(Module),
    length(List, Count),
    setup_call_cleanup(
        ( metta_capture_python_contexts(Count, Contexts),
          pairs_keys_values(Pairs, Contexts, List) ),
        (   List == []
        ->  Answer = false
        ;   concurrent_forall(member(Context-Element, Pairs),
                              \+ par_true_checked_(Module, F, Context, Element))
        ->  Answer = false
        ;   Answer = true
        ),
        metta_release_python_contexts(Contexts)).

%Evaluate every expression at once and answer the first to SUCCEED, then stop
%the rest. A branch that fails drops out without ending the race, which is why
%this collects through its own mailbox rather than calling first_solution/3.
%An exception in any branch is raised to the caller rather than counted as a
%loss, so a broken branch is never silently the reason another one won.
par_race(Exprs, Out) :-
    must_be(list, Exprs),
    Exprs \== [],
    current_metta_module(Module),
    length(Exprs, Count),
    setup_call_cleanup(
        race_resources_create(Count, Start, Results, Contexts),
        setup_call_cleanup(
            race_start_(Module, Exprs, Contexts, Start, Results, Threads),
            ( race_release_(Threads, Start),
              race_collect_(Results, Count, Out) ),
            race_stop_(Threads)),
        ( metta_release_python_contexts(Contexts),
          race_queues_destroy(Start, Results) )).

race_resources_create(Count, Start, Results, Contexts) :-
    race_queues_create(Start, Results),
    catch((   metta_capture_python_contexts(Count, Contexts)
          ->  true
          ;   race_queues_destroy(Start, Results),
              fail
          ),
          Error,
          ( race_queues_destroy(Start, Results), throw(Error) )).

race_queues_create(Start, Results) :-
    message_queue_create(Start),
    catch(message_queue_create(Results),
          Error,
          ( message_queue_destroy(Start), throw(Error) )).

race_start_(Module, Exprs, Contexts, Start, Results, Threads) :-
    pairs_keys_values(Pairs, Contexts, Exprs),
    race_start_pairs_(Pairs, Module, Start, Results, [], Outcome),
    (   Outcome = started(Reverse)
    ->  reverse(Reverse, Threads)
    ;   Outcome = error(Error, Started),
        race_stop_(Started),
        throw(Error)
    ).

race_start_pairs_([], _, _, _, Started, started(Started)).
race_start_pairs_([Context-Expr|Pairs], Module, Start, Results, Started,
                  Outcome) :-
    catch(( thread_create(race_body_(Module, Context, Expr, Start, Results),
                          Thread, []),
            Created = thread(Thread) ),
          Error,
          Created = error(Error)),
    (   Created = thread(Thread)
    ->  race_start_pairs_(Pairs, Module, Start, Results, [Thread|Started],
                          Outcome)
    ;   Created = error(Error),
        Outcome = error(Error, Started)
    ).

race_release_(Threads, Start) :-
    forall(member(_, Threads), thread_send_message(Start, go)).

race_body_(Module, Context, Expr, Start, Results) :-
    thread_get_message(Start, go),
    metta_in_python_context(
        Context,
        (   catch((   eval_metta_in_module(Module, Expr, Value),
                      Value \== 'Empty'
                  ->  Message = ok(Value)
                  ;   Message = lost
                  ),
                  Error,
                  Message = error(Error))
        ->  true
        ;   Message = lost
        )),
    thread_send_message(Results, Message).

race_collect_(Queue, Remaining, Out) :-
    Remaining > 0,
    thread_get_message(Queue, Message),
    (   Message = ok(Value)
    ->  Out = Value
    ;   Message = error(Error)
    ->  throw(Error)
    ;   Next is Remaining - 1,
        race_collect_(Queue, Next, Out)
    ).

race_stop_(Threads) :-
    forall(member(Thread, Threads),
           catch(thread_signal(Thread, abort), _, true)),
    forall(member(Thread, Threads),
           catch(metta_thread_join_settled(Thread, _), _, true)).

race_queues_destroy(Start, Results) :-
    catch(message_queue_destroy(Start), _, true),
    catch(message_queue_destroy(Results), _, true).

% ------------------------------------------------------------------ futures

%A future IS A SPACE. (spawn $expr) answers a space name, the evaluating
%thread adds every answer to it as it is found, and await reads them back.
%
%This is the point. A MeTTa expression does not have a value, it has an answer
%set, so a future that answers one value throws the evaluation model away at
%the concurrency boundary: (spawn (superpose (1 2 3))) has to be able to reach
%all three. Because the handle is an ordinary space, everything that already
%works on spaces works on a future: match it, get-atoms it, and await-atom on
%it to take answers as they land instead of waiting for the end.
%
%And it is one FROM THE MOMENT ITS NAME IS HANDED OUT, which is why the space
%is created here rather than by whoever writes to it first. All four callers
%mint a fresh handle and hand it straight to a caller; the storage used to
%appear only on the first answer, so in between the caller held a handle to
%nothing: metta_space_operand/1 was false for &future-1, metta_space_names/1
%omitted it, and a host codec asking the engine what species the atom is was
%told a symbol, so !(spawn (+ 1 2)) reached Python as a Symbol rather than a
%FutureSpace [measured 2026-08-27, when get-metatype still answered the
%species question too; it answers upstream PeTTa's name question since
%2026-09-05 and the codec asks metta_space_operand/1 directly]. The timer path below already said this in
%prose. ensure_native_storage_module/2 is idempotent, so the first write is a
%cache hit.
future_space_name(Number, Space) :-
    scope_current_(Id),
    ( Id == none -> true ; scope_outside_transaction_ ),
    atom_concat('&future-', Number, Space),
    ensure_native_storage_module(Space, _).

thread_spawn(Expr, Space) :-
    current_metta_module(Module),
    metta_capture_python_context(Context),
    catch(thread_spawn_context_(Context, Module, Expr, Space),
          Error,
          ( metta_release_python_context(Context), throw(Error) )).

thread_spawn_context_(Context, Module, Expr, Space) :-
    next_metta_handle(Number),
    future_space_name(Number, Space),
    message_queue_create(Done, [max_size(1)]),
    catch(metta_scheduler_spawn(Module, Expr, Space, Done, Context, _Task),
          Error,
          ( message_queue_destroy(Done), throw(Error) )).

%The scheduler is Go's G/P/M separation at this engine's scale: an engine is
%the resumable computation, a queue is the execution permission, and a fixed
%SWI worker is the carrier. Unlike a raw goal in thread_create/3, the engine
%detaches after each answer, explicit wait, or lane handoff and can resume on
%another worker. Each carrier is a long-lived queue loop, so resuming an engine
%does not create another OS thread.

metta_scheduler_ensure :-
    metta_scheduler_ensure_lane_ready(normal).

metta_scheduler_ensure_lane_ready(normal) :-
    with_mutex('$metta_engine_scheduler',
               metta_scheduler_ensure_lane_ready_locked(normal)).

metta_scheduler_ensure_lane_ready_locked(Lane) :-
    cpu_count(Cores),
    Workers is max(1, min(Cores, 4)),
    metta_scheduler_ensure_lane(Lane, Workers).

metta_scheduler_ensure_lane(Lane, Workers) :-
    (   metta_scheduler_lane(Lane, Queue, Carriers)
    ->  include(metta_scheduler_carrier_running, Carriers, Running),
        retract(metta_scheduler_lane(Lane, Queue, Carriers)),
        assertz(metta_scheduler_lane(Lane, Queue, Running))
    ;   message_queue_create(Queue),
        assertz(metta_scheduler_lane(Lane, Queue, [])),
        Running = []
    ),
    length(Running, Count),
    Missing is Workers - Count,
    metta_scheduler_start_carriers(Lane, Queue, Missing).

metta_scheduler_carrier_running(Thread) :-
    catch(thread_property(Thread, status(running)), _, fail).

metta_scheduler_start_carriers(_, _, Missing) :-
    Missing =< 0, !.
metta_scheduler_start_carriers(Lane, Queue, Missing) :-
    thread_create(metta_scheduler_carrier(Lane, Queue), Thread,
                  [detached(true)]),
    retract(metta_scheduler_lane(Lane, Queue, Carriers)),
    assertz(metta_scheduler_lane(Lane, Queue, [Thread|Carriers])),
    Remaining is Missing - 1,
    metta_scheduler_start_carriers(Lane, Queue, Remaining).

metta_scheduler_carrier(Lane, Queue) :-
    thread_get_message(Queue, Message),
    (   Message = run(Task)
    ->  catch(metta_scheduler_step(Task, Lane),
              Error,
              metta_scheduler_submission_failed(Task, Error)),
        metta_scheduler_carrier(Lane, Queue)
    ;   Message == stop
    ->  true
    ;   metta_scheduler_carrier(Lane, Queue)
    ).

metta_scheduler_lane_size(normal, Size) :-
    metta_scheduler_ensure_lane_ready(normal),
    metta_scheduler_lane(normal, _, Carriers),
    include(metta_scheduler_carrier_running, Carriers, Running),
    length(Running, Size).

metta_scheduler_lane_queue(Queue) :-
    (   metta_scheduler_lane(normal, Queue, _)
    ->  true
    ;   metta_scheduler_ensure_lane_ready(normal),
        metta_scheduler_lane(normal, Queue, _)
    ).

metta_scheduler_spawn(Module, Expr, Space, Done, Context, Task) :-
    metta_scheduler_ensure,
    next_metta_handle(Task),
    engine_create(Final,
                  metta_scheduler_body(Task, Context, Module, Expr, Final),
                  Engine),
    catch(( assertz(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                         queued(normal))),
            assertz(metta_future(Space, scheduler(Task), Done)),
            metta_scheduler_enqueue(Task, normal) ),
          Error,
          ( retractall(metta_scheduler_task(Task, _, _, _, _, _)),
            retractall(metta_future(Space, scheduler(Task), Done)),
            engine_destroy(Engine),
            throw(Error) )).

%forall/2 retains every answer. Each answer is yielded to the scheduler before
%the carrier writes it, so no engine is attached while an atom hook runs and a
%hook that wakes another task only queues that task.
metta_scheduler_body(Task, Context, Module, Expr, Outcome) :-
    catch(( b_setval('$metta_scheduler_task', Task),
            metta_in_python_context(Context,
                forall(eval_metta_in_module(Module, Expr, Value),
                       engine_yield('$metta_scheduler_answer'(Value)))),
            Outcome = done ),
          Error, future_caught_(Error, Outcome)).

%A carrier sends its successor step to an unbounded runnable queue, then
%returns to that queue before the engine may resume. Enqueue is non-blocking,
%so every carrier can hand off simultaneously without the all-workers-submit
%deadlock of thread_create_in_pool/4. The handoff is Go's blocking-syscall
%shape: release the execution permission before the foreign call proceeds.
%Go performs the corresponding handoff before a goroutine enters a blocking
%syscall, releasing its P so another M can run queued work [source:
%https://github.com/golang/go/blob/c19862e5f8415b4f24b189d065ed739517c548ba/src/runtime/proc.go#L4781-L4831,
%Go 1.26.5 entersyscallblock].
metta_scheduler_enqueue(Task, normal) :-
    catch(( metta_scheduler_lane_queue(Queue),
            thread_send_message(Queue, run(Task)) ),
          Error,
          metta_scheduler_submission_failed(Task, Error)).
metta_scheduler_enqueue(Task, dirty) :-
    catch(metta_scheduler_offload(Task),
          Error,
          metta_scheduler_submission_failed(Task, Error)).

%A blocking foreign call gets a transient M without keeping a scheduler P,
%which is Go's syscall handoff rather than a second bounded carrier pool. The
%SWI engine detaches at the lane yield; this worker attaches for exactly one
%foreign step and exits when the engine yields back to normal. An indefinitely
%blocked call therefore owns its offload thread, not one of the four carriers
%that make progress for every other runnable engine [source:
%https://github.com/golang/go/blob/c19862e5f8415b4f24b189d065ed739517c548ba/src/runtime/proc.go#L4781-L4831,
%Go 1.26.5 entersyscallblock].
metta_scheduler_offload(Task) :-
    thread_create(metta_scheduler_dirty_worker(Task), Thread,
                  [detached(true)]),
    with_mutex('$metta_engine_scheduler',
               metta_scheduler_bind_offload(Task, Thread, Message)),
    thread_send_message(Thread, Message).

metta_scheduler_bind_offload(Task, Thread, Message) :-
    (   retract(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                     queued(dirty)))
    ->  assertz(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                     offloaded(Thread))),
        Message = run
    ;   Message = stop
    ).

metta_scheduler_dirty_worker(Task) :-
    thread_get_message(Message),
    (   Message == run
    ->  catch(metta_scheduler_step(Task, dirty),
              Error,
              metta_scheduler_submission_failed(Task, Error))
    ;   true
    ).

metta_scheduler_submission_failed(Task, Error) :-
    metta_scheduler_finish(Task, error(Error)).

metta_scheduler_step(Task, Lane) :-
    (   with_mutex('$metta_engine_scheduler',
                   metta_scheduler_begin_step(Task, Lane, Engine))
    ->  catch(engine_next_reified(Engine, Event),
              Error,
              Event = throw(Error)),
        metta_scheduler_event(Task, Lane, Event)
    ;   true
    ).

metta_scheduler_begin_step(Task, Lane, Engine) :-
    thread_self(Thread),
    metta_scheduler_begin_state(Lane, Thread, Initial),
    retract(metta_scheduler_task(Task, Engine, Space, Done, Context, Initial)),
    assertz(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                 running(Lane, Thread))).

metta_scheduler_begin_state(normal, _, queued(normal)).
metta_scheduler_begin_state(dirty, Thread, offloaded(Thread)).

metta_scheduler_event(Task, Lane,
                      the('$metta_scheduler_answer'(Value))) :- !,
    catch(( metta_scheduler_write_answer(Task, Value), Outcome = ok ),
          Error,
          Outcome = error(Error)),
    (   Outcome == ok
    ->  metta_scheduler_continue(Task, Lane)
    ;   Outcome = error(WriteError),
        metta_scheduler_finish(Task, error(WriteError))
    ).
metta_scheduler_event(Task, Lane,
                      the('$metta_scheduler_suspend')) :- !,
    metta_scheduler_suspend(Task, Lane).
metta_scheduler_event(Task, _,
                      the('$metta_scheduler_lane'(Lane))) :- !,
    metta_scheduler_handoff(Task, Lane).
metta_scheduler_event(Task, _, the(done)) :- !,
    metta_scheduler_finish(Task, done).
metta_scheduler_event(Task, _, the(cancelled)) :- !,
    metta_scheduler_finish(Task, cancelled).
metta_scheduler_event(Task, _, the(error(Error))) :- !,
    metta_scheduler_finish(Task, error(Error)).
metta_scheduler_event(Task, _, no) :- !,
    metta_scheduler_finish(Task, done).
% A signal may arrive before the body's catch has been entered. The carrier's
% engine_next_reified guard owns that interval and classifies the same token.
metta_scheduler_event(Task, _,
        throw(error(metta_control_signal(interrupted, scheduler(Task)), _))) :- !,
    metta_scheduler_finish(Task, cancelled).
metta_scheduler_event(Task, _, throw(Error)) :- !,
    metta_scheduler_finish(Task, error(Error)).
metta_scheduler_event(Task, _, Unexpected) :-
    metta_scheduler_finish(
        Task,
        error(error(metta_scheduler_protocol(Unexpected),
                    context(metta_scheduler_step/2,
                            'a scheduled engine yielded an unknown event')))).

metta_scheduler_write_answer(Task, Value) :-
    with_mutex('$metta_engine_scheduler',
               ( metta_scheduler_task(Task, _, Space, _, _, State),
                 ( State = cancelling(_, _) -> Publish = false
                 ; Publish = true ) )),
    ( Publish == true -> future_add_atom(Space, Value) ; true ).

metta_scheduler_continue(Task, Lane) :-
    with_mutex('$metta_engine_scheduler',
               metta_scheduler_transition(Task, Lane, continue, Action)),
    metta_scheduler_action(Task, Action).

metta_scheduler_suspend(Task, Lane) :-
    with_mutex('$metta_engine_scheduler',
               metta_scheduler_transition(Task, Lane, suspend, Action)),
    metta_scheduler_action(Task, Action).

metta_scheduler_handoff(Task, Lane) :-
    must_be(oneof([normal, dirty]), Lane),
    with_mutex('$metta_engine_scheduler',
               metta_scheduler_transition(Task, _, handoff(Lane), Action)),
    metta_scheduler_action(Task, Action).

metta_scheduler_transition(Task, Lane, Operation, Action) :-
    (   retract(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                     cancelling(Lane, _)))
    ->  assertz(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                     finishing(cancelled))),
        Action = finish(cancelled)
    ;   retract(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                     wake_pending(Lane, _)))
    ->  metta_scheduler_next_state(Operation, Lane, NextLane, _),
        assertz(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                     queued(NextLane))),
        Action = enqueue(NextLane)
    ;   retract(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                     running(Lane, _)))
    ->  metta_scheduler_next_state(Operation, Lane, NextLane, NextState),
        assertz(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                     NextState)),
        ( NextState = queued(_) -> Action = enqueue(NextLane)
        ; Action = none )
    ;   Action = none
    ).

metta_scheduler_next_state(continue, Lane, Lane, queued(Lane)).
metta_scheduler_next_state(suspend, Lane, Lane, suspended(Lane)).
metta_scheduler_next_state(handoff(Target), _, Target, queued(Target)).

metta_scheduler_action(_, none).
metta_scheduler_action(Task, enqueue(Lane)) :-
    metta_scheduler_enqueue(Task, Lane).
metta_scheduler_action(Task, finish(Outcome)) :-
    metta_scheduler_finish(Task, Outcome).

%A wakeup is a hint and the store remains the truth. Running records remember
%one pending hint, closing the write-before-suspend race; multiple writes fold
%into that one bit and never enqueue the same engine twice.
metta_scheduler_wake(Task) :-
    with_mutex('$metta_engine_scheduler',
               metta_scheduler_wake_locked(Task, Action)),
    metta_scheduler_action(Task, Action).

metta_scheduler_wake_locked(Task, Action) :-
    (   retract(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                     suspended(Lane)))
    ->  assertz(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                     queued(Lane))),
        Action = enqueue(Lane)
    ;   retract(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                     running(Lane, Thread)))
    ->  assertz(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                     wake_pending(Lane, Thread))),
        Action = none
    ;   Action = none
    ).

metta_scheduler_finish(Task, Outcome) :-
    with_mutex('$metta_engine_scheduler',
               metta_scheduler_take_task(Task, Engine, Space, Done, Context)),
    (   nonvar(Engine)
    ->  catch(engine_destroy(Engine), _, true),
        retractall(metta_future_waiter(_, Task)),
        metta_release_python_context(Context),
        metta_future_complete(Space, Done, Outcome)
    ;   true
    ).

metta_scheduler_take_task(Task, Engine, Space, Done, Context) :-
    (   retract(metta_scheduler_task(Task, Engine, Space, Done, Context, _))
    ->  true
    ;   true
    ).

metta_scheduler_cancel(Task, Answer) :-
    metta_scheduler_request_cancel(Task, Wait),
    (   Wait = await(Space)
    ->  future_settle_(Space, Outcome),
        ( Outcome == cancelled -> Answer = true ; Answer = false )
    ;   Answer = false
    ).

% Request first, acknowledge separately: a scope signals every sibling before
% it waits for a foreign call. The engine handle is the signal target; its
% carrier has a different signal queue [tested: lib_thread_cancellation;
% commit=c6e1198c490a824b96f6fc6e1c0622a542917024]. The retained engine blob identifies this lifetime even if
% it finishes between selection and signalling. No signal runs under a mutex
% that the target may need to leave its guard.
metta_scheduler_request_cancel(Task, Wait) :-
    with_mutex('$metta_engine_scheduler',
               metta_scheduler_cancel_locked(Task, Action, Wait)),
    metta_scheduler_cancel_action(Action).

metta_scheduler_cancel_locked(Task, Action, Wait) :-
    (   retract(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                      queued(_)))
    ->  Action = dispose(Task, Engine, Space, Done, Context), Wait = await(Space)
    ;   retract(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                      offloaded(_)))
    ->  Action = dispose(Task, Engine, Space, Done, Context), Wait = await(Space)
    ;   retract(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                      suspended(_)))
    ->  Action = dispose(Task, Engine, Space, Done, Context), Wait = await(Space)
    ;   retract(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                     running(Lane, Thread)))
    ->  assertz(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                     cancelling(Lane, Thread))),
        Action = signal(Engine, Task), Wait = await(Space)
    ;   retract(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                     wake_pending(Lane, Thread)))
    ->  assertz(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                     cancelling(Lane, Thread))),
        Action = signal(Engine, Task), Wait = await(Space)
    ;   metta_scheduler_task(Task, _, Space, _, _, cancelling(_, _))
    ->  Action = none, Wait = await(Space)
    ;   Action = none, Wait = finished
    ).

metta_scheduler_signal(Engine, Task) :-
    catch(thread_signal(Engine,
              throw(error(metta_control_signal(interrupted, scheduler(Task)),
                          context(metta, scheduler(Task))))),
          error(existence_error(thread, _), _), true).

metta_scheduler_cancel_action(none).
metta_scheduler_cancel_action(signal(Engine, Task)) :- metta_scheduler_signal(Engine, Task).
metta_scheduler_cancel_action(dispose(Task, Engine, Space, Done, Context)) :-
    catch(engine_destroy(Engine), _, true),
    retractall(metta_future_waiter(_, Task)),
    metta_release_python_context(Context),
    metta_future_complete(Space, Done, cancelled).

%Async host operations use the same future-space lifecycle without owning an
%engine. The Python event loop produces one encoded answer and calls the shim's
%landing predicate; these helpers own the common future registry and mailbox.
metta_async_future_new(Space, Done) :-
    next_metta_handle(Number),
    future_space_name(Number, Space),
    message_queue_create(Done, [max_size(1)]),
    assertz(metta_future(Space, async(pending), Done)).

metta_async_future_bind(Token, Name, Space, Done) :-
    retract(metta_future(Space, async(pending), Done)),
    assertz(metta_future(Space, async(Token), Done)),
    assertz(metta_async_future(Token, Name, Space, Done)).

metta_async_future_abandon(Space, Done) :-
    retractall(metta_future(Space, async(pending), Done)),
    catch(message_queue_destroy(Done), _, true).

metta_async_future_settle(Token, Outcome, Name, Space) :-
    (   retract(metta_async_future(Token, Name, Space, Done))
    ->  metta_future_complete(Space, Done, Outcome)
    ;   existence_error(metta_async_future, Token)
    ).

%Recovery is keyed by the durable future record rather than the transient
%publisher record: ordinary settlement removes the latter before lifecycle
%notification, and a watcher can fail after that successful settlement.
metta_async_future_fail(Token, Outcome) :-
    (   metta_future(Space, async(Token), Done)
    ->  retractall(metta_async_future(Token, _, _, _)),
        metta_future_complete(Space, Done, Outcome)
    ;   existence_error(metta_async_future, Token)
    ).

metta_async_future_discard(Token) :-
    (   retract(metta_async_future(Token, _, Space, Done))
    ->  metta_async_future_discard(Token, Space, Done)
    ;   true
    ).

metta_async_future_discard(Token, Space, Done) :-
    retractall(metta_async_future(Token, _, Space, Done)),
    retractall(metta_future(Space, async(Token), Done)),
    retractall(metta_future(Space, async(pending), Done)),
    catch(message_queue_destroy(Done), _, true).

metta_async_cancel(Token, Answer) :-
    metta_async_cancel_request_(Token, @(false), Answer, _).

metta_async_cancel_request_(Token, Joining, Answer, Running) :-
    user:py_call(metta_ops:async_cancel(Token, Joining), Accepted-Active),
    janus_true_(Accepted, Answer),
    janus_true_(Active, Running).

janus_true_(Value, Truth) :-
    % policy-inventory-exempt: mechanism-internal; reason=the two spellings janus hands a Python True, the bare atom and the @-wrapped one, depending on the conversion the caller asked for; evidence=lib/lib_thread/lib_thread.pl:metta_async_cancel_request_/4
    ( memberchk(Value, [true, @(true)]) -> Truth = true ; Truth = false ).

%A nested spawn forks the scheduled engine's retained Context after any host
%callback mutations made by that engine. A top-level door snapshots the Python
%caller's ambient Context. Falling back to the carrier's ambient context here
%would lose nested changes because carriers deliberately do not inherit task
%state between engine steps.
metta_capture_python_context(Context) :-
    scope_current_(Scope),
    (   nb_current('$metta_python_context', Parent), integer(Parent)
    ->  user:py_call(metta_ops:fork_context(Parent), Python)
    ;   current_predicate(user:metta_py_dispatch/4)
    ->  user:py_call(metta_ops:capture_context(), Python)
    ;   Python = none
    ),
    scope_context_(Scope, Python, Context).

scope_context_(none, Python, Python) :- !.
scope_context_(Scope, Python, scoped(Scope, Python)).

metta_capture_python_contexts(Count, Contexts) :-
    scope_current_(Scope),
    (   nb_current('$metta_python_context', Parent), integer(Parent)
    ->  user:py_call(metta_ops:fork_contexts(Parent, Count), Pythons)
    ;   current_predicate(user:metta_py_dispatch/4)
    ->  user:py_call(metta_ops:capture_contexts(Count), Pythons)
    ;   length(Pythons, Count), maplist(=(none), Pythons)
    ),
    maplist(scope_context_(Scope), Pythons, Contexts).

metta_release_python_context(scoped(_, Context)) :- !,
    metta_release_python_context(Context).
metta_release_python_context(none) :- !.
metta_release_python_context(Context) :-
    (   current_predicate(user:py_call/2)
    ->  catch(user:py_call(metta_ops:release_context(Context), _), _, true)
    ;   true
    ).

metta_release_python_contexts(Contexts) :-
    maplist(metta_release_python_context, Contexts).

metta_in_python_context(scoped(Scope, Context), Goal) :- !,
    scope_call(Scope, metta_in_python_context(Context, Goal)).
metta_in_python_context(Context, Goal) :-
    setup_call_cleanup(
        metta_python_context_push(Context, Previous),
        call(Goal),
        metta_python_context_pop(Previous)).

metta_python_context_push(Context, Previous) :-
    (   nb_current('$metta_python_context', Existing)
    ->  Previous = value(Existing)
    ;   Previous = absent
    ),
    b_setval('$metta_python_context', Context).

metta_python_context_pop(value(Context)) :- !,
    b_setval('$metta_python_context', Context).
metta_python_context_pop(absent) :-
    nb_delete('$metta_python_context').

%Explicit user-created pools and timers promise parallel workers rather than
%scheduler multiplexing, and run their already-captured Context here.
future_body_context_(Context, Module, Expr, Space, Done) :-
    future_worker_(Space, Done,
                   future_body_outcome_(Context, Module, Expr, Space, Outcome),
                   Outcome,
                   metta_release_python_context(Context)).

%A thread worker settles its future from a cleanup handler, which SWI runs
%with thread signals blocked, so the settlement happens exactly once whatever
%the cancellation signal interrupted: the body's own catch answers the common
%case, and a signal that lands before that catch is installed or after it has
%exited leaves the outcome unbound, which the handler reads as cancelled. The
%canceller waits for that settlement under the await mutex, and a worker that
%died unsettled left it waiting forever
%[tested: lib_thread:a_signal_before_the_worker_installs_its_catch_still_settles;
%commit=50e34286f66c938d89d5d367c6370ad44164c97f].
future_worker_(Space, Done, Body, Outcome, Release) :-
    setup_call_catcher_cleanup(
        true,
        catch(Body, error(metta_control_signal(interrupted, _), _), true),
        Catcher,
        ( future_worker_outcome_(Catcher, Outcome, Settled),
          metta_future_complete(Space, Done, Settled),
          Release )).

future_worker_outcome_(exit, Outcome, Settled) :- !,
    ( var(Outcome) -> Settled = cancelled ; Settled = Outcome ).
future_worker_outcome_(exception(Error), _, Settled) :- !,
    future_caught_(Error, Settled).
future_worker_outcome_(Catcher, _, error(metta_future_worker_ended(Catcher))).

future_body_outcome_(Context, Module, Expr, Space, Outcome) :-
        (   catch(( metta_in_python_context(Context,
                        forall(eval_metta_in_module(Module, Expr, Value),
                               future_add_atom(Space, Value))),
                    Outcome = done ),
                  Error,
                  future_caught_(Error, Outcome))
        ->  true
        ;   Outcome = done
        ).

future_caught_(error(metta_control_signal(interrupted, Detail), _), cancelled) :-
    ( Detail = scheduler(_) ; Detail = future(_) ; Detail = [scope, _] ), !.
future_caught_(Error, error(Error)).

future_mutex_(Space, Mutex) :-
    atom_concat('$metta_future_', Space, Mutex).

future_answer_mutex_(Space, Mutex) :-
    atom_concat('$metta_future_answers_', Space, Mutex).

future_completion_mutex_(Space, Mutex) :-
    atom_concat('$metta_future_completion_', Space, Mutex).

%A future iterator needs the same relationship PostgreSQL gives an exported
%logical-decoding snapshot: the snapshot shows exactly the state after which
%the change stream starts. Each future answer receives one process-wide
%position while holding a dedicated answer mutex, which covers the write and
%its synchronous atom-added callback. A snapshot under the same mutex therefore
%has one exact watermark. Duplicate values need no identity
%guess: position, not equality, decides which side of the snapshot owns them.
%[source: PostgreSQL 15, Logical Decoding Concepts, Exported Snapshots,
%https://www.postgresql.org/docs/15/logicaldecoding-explanation.html#LOGICALDECODING-SNAPSHOTS;
%commit=1877bec75a9a22265c9222f0c0c538c8f65a983f].
future_add_atom(Space, Term) :-
    future_answer_mutex_(Space, Mutex),
    with_mutex(Mutex, future_add_atom_locked_(Space, Term)).

future_add_atom_locked_(Space, Term) :-
    flag('$metta_future_answer_position', Previous, Previous + 1),
    Sequence is Previous + 1,
    setup_call_cleanup(
        future_answer_sequence_push_(Space, Sequence, Prior),
        'add-atom'(Space, Term, _),
        future_answer_sequence_pop_(Prior)).

future_answer_sequence_push_(Space, Sequence, Prior) :-
    (   nb_current('$metta_future_answer_sequence', Existing)
    ->  Prior = value(Existing)
    ;   Prior = absent
    ),
    b_setval('$metta_future_answer_sequence', future(Space, Sequence)).

future_answer_sequence_pop_(value(Sequence)) :- !,
    b_setval('$metta_future_answer_sequence', Sequence).
future_answer_sequence_pop_(absent) :-
    nb_delete('$metta_future_answer_sequence').

metta_future_snapshot(Space, Atoms, Watermark) :-
    known_future_(Space, _, _),
    future_answer_mutex_(Space, Mutex),
    with_mutex(
        Mutex,
        (   findall(Atom, 'get-atoms'(Space, Atom), Atoms),
            flag('$metta_future_answer_position', Watermark, Watermark)
        )).

%Claim the terminal outcome before publishing it. The completion mutex is
%separate from the await mutex because an ordinary awaiter holds the latter
%while blocked on Done; sending while holding it would deadlock the producer
%against its consumer. Publishing first then taking the await mutex closes the
%lost-wakeup window: a scheduled waiter either registers before the drain or
%observes the already-recorded terminal outcome.
metta_future_complete(Space, Done, Outcome) :-
    future_completion_mutex_(Space, CompletionMutex),
    with_mutex(
        CompletionMutex,
        (   metta_future_result(Space, _)
        ->  Claimed = false
        ;   scope_future_done_(Space, Outcome),
            assertz(metta_future_result(Space, Outcome)),
            Claimed = true
        )),
    ( Claimed == true, Outcome = error(_), scope_space_owner_(Space, Id, _)
    -> scope_cancel_automatic_(Id, child_failure) ; true ),
    metta_future_publish_(Claimed, Space, Done, Outcome).

metta_future_publish_(false, _, _, _) :- !.
metta_future_publish_(true, Space, Done, Outcome) :-
    catch(thread_send_message(Done, Outcome, [timeout(0)]), _, true),
    future_mutex_(Space, Mutex),
    with_mutex(
        Mutex,
        findall(Task,
                retract(metta_future_waiter(Space, Task)),
                Waiters)),
    maplist(metta_scheduler_wake, Waiters).

%Wait for the future to finish, then answer every atom it produced, one per
%solution. Awaiting a second time answers the same set without blocking again,
%so a handle can be shared.
%A transaction reads the database as it was when it OPENED, so a write another
%thread makes while it runs stays invisible inside it for as long as it lasts.
%Every wait here waits for exactly such a write, which makes the condition
%unreachable rather than slow, and a caller has no way to learn that from a
%wait that simply never ends.
%
%Measured 2026-09-04: `(let $f (spawn (inc 41)) (await $f))` answers 42 in
%0.00s and never returns inside a transaction, with the future space still
%empty a second after the worker finished; a spawned write under
%`(space_await $s (job $x) 2)` answers `(job 1)` outside and `[]` after the
%full two seconds inside, which is a WRONG answer rather than a slow one.
%
%A channel is NOT guarded, because its queue is not database state and the
%hazard does not reach it: `(let $c (channel) (let $_ (send $c hello)
%(recv $c)))` answers hello inside a transaction and outside one alike.
metta_refuse_wait_in_transaction(Waiter) :-
    (   current_transaction(_)
    ->  throw(error(metta_wait_in_transaction(Waiter),
                    context(Waiter,
                            'a transaction cannot see another thread''s writes')))
    ;   true
    ).

:- multifile prolog:error_message//1.
prolog:error_message(metta_wait_in_transaction(Waiter)) -->
    { _ = Waiter },
    [ 'this waits for another thread, and a transaction reads the database as \c
       it was when it opened, so the write being waited for cannot become \c
       visible while the transaction lasts. Wait outside the transaction, or \c
       use a channel, whose queue is not database state.'-[] ].

thread_await(Space, Out) :-
    metta_refuse_wait_in_transaction(await),
    future_settle_(Space, Outcome),
    (   Outcome = error(Error)
    ->  throw(Error)
    ;   'get-atoms'(Space, Out)
    ).

future_settle_(Space, Outcome) :-
    (   nb_current('$metta_scheduler_task', Task)
    ->  scheduler_future_settle_(Task, Space, Outcome)
    ;   future_mutex_(Space, Mutex),
        with_mutex(Mutex, future_outcome_(Space, Outcome, Worker)),
        future_join_(Worker)
    ).

%Await inside a scheduled engine parks the engine and leaves its carrier free.
%The recorded terminal outcome remains the source of truth; the waiter fact is
%only a level-triggered waker and is installed before completion drains it
%under the same await mutex.
scheduler_future_settle_(Task, Space, Outcome) :-
    future_mutex_(Space, Mutex),
    with_mutex(Mutex,
               scheduler_future_probe_(Task, Space, Status)),
    (   Status = ready(Outcome, Worker)
    ->  future_join_(Worker)
    ;   engine_yield('$metta_scheduler_suspend'),
        scheduler_future_settle_(Task, Space, Outcome)
    ).

scheduler_future_probe_(_, Space, ready(Outcome, Worker)) :-
    metta_future_result(Space, Outcome), !,
    known_future_(Space, Worker, _).
scheduler_future_probe_(_, Space, ready(Outcome, Worker)) :-
    known_future_(Space, Worker, Done),
    message_queue_property(Done, size(Pending)),
    Pending > 0, !,
    thread_get_message(Done, Received),
    future_record_received_(Space, Received, Outcome).
scheduler_future_probe_(Task, Space, pending) :-
    known_future_(Space, _, _),
    (   metta_future_waiter(Space, Task)
    ->  true
    ;   assertz(metta_future_waiter(Space, Task))
    ).

future_outcome_(Space, Outcome, Worker) :-
    known_future_(Space, Worker, Done),
    (   metta_future_result(Space, Recorded)
    ->  Outcome = Recorded
    ;   thread_get_message(Done, Received),
        future_record_received_(Space, Received, Outcome)
    ).

future_record_received_(Space, Received, Outcome) :-
    (   metta_future_result(Space, Recorded)
    ->  Outcome = Recorded
    ;   assertz(metta_future_result(Space, Received)),
        Outcome = Received
    ).

future_join_(scheduler(_)) :- !.
future_join_(async(_)) :- !.
future_join_(none) :- !.
future_join_(ThreadId) :-
    catch(metta_thread_join_settled(ThreadId, _), Error,
          future_join_recover_(ThreadId, Error, 0.0005)).

% SWI admits one joiner; a losing awaiter must still wait for worker cleanup.
% Retry with metta_thread_settled_/2's backoff so an interrupted joiner can be
% replaced. Await has no deadline of its own; external timeout, cancellation
% and other exceptions propagate through both waits [tested:
% lib_thread_completion; commit=8ca8a387fc61d0918484b19a1a3baf85b6523043]. The worker is the unaliased thread
% blob retained by a known future, so disappearance means an earlier join
% finished, including a repeat await; a recycled integer id is never used
% [source: lib/lib_thread/lib_thread.pl, pool_submit_context_/5 and
% timer_dispatch_worker_/7; commit=8ca8a387fc61d0918484b19a1a3baf85b6523043]. The one-join rule is documented
% at https://www.swi-prolog.org/pldoc/man?predicate=thread_join/2.
future_join_recover_(Thread, error(existence_error(thread, Thread), _), _) :- !.
future_join_recover_(Thread, Error, Delay) :-
    Error = error(permission_error(join, thread, Thread), _), !,
    catch(( thread_property(Thread, detached(false)),
            thread_self(Self), Thread \== Self
          -> State = contended
          ; State = invalid ),
          error(existence_error(thread, Thread), _), State = joined),
    (   State == joined
    ->  true
    ;   State == contended
    ->  sleep(Delay),
        Next is min(Delay * 2, 0.032),
        catch(metta_thread_join_settled(Thread, _), RetryError,
              future_join_recover_(Thread, RetryError, Next))
    ;   throw(Error)
    ).
future_join_recover_(_, Error, _) :- throw(Error).

known_future_(Space, ThreadId, Done) :-
    (   metta_future(Space, ThreadId, Done)
    ->  true
    ;   existence_error(metta_future, Space)
    ).

%Whether the future has finished, without waiting for it.
thread_settled(Space, Answer) :-
    (   metta_future_result(Space, _)
    ->  Answer = true
    ;   known_future_(Space, _, Done),
        message_queue_property(Done, size(Pending)),
        Pending > 0
    ->  Answer = true
    ;   Answer = false
    ).

%Stop a future that has not finished, and say whether it actually stopped
%rather than reporting success either way. Cancelling a timer stops the timer;
%answers already in the space stay there, because they really were produced.
thread_cancel(Space, Answer) :-
    with_mutex('$metta_timer_lifecycle',
               timer_cancel_prepare_(Space, TimerAction)),
    timer_cancel_action_(TimerAction, Space, Answer).

timer_cancel_action_(not_timer, Space, Answer) :- !,
    cancel_future_(Space, Answer).
timer_cancel_action_(pending(Context, Done), Space, true) :- !,
    metta_release_python_context(Context),
    metta_future_complete(Space, Done, cancelled).
timer_cancel_action_(orphan(Context), _, true) :- !,
    metta_release_python_context(Context).
timer_cancel_action_(active(once, Context, _Done, _Worker), Space, Answer) :- !,
    %Its timer heap entry was already consumed before the worker became
    %visible, so there is no tombstone to retain once cancellation has won the
    %lifecycle mutex. The winner also owns the removed context token.
    call_cleanup(cancel_future_(Space, Answer),
                 metta_release_python_context(Context)).
timer_cancel_action_(active(every(_), Context, Done, Worker), Space, true) :- !,
    call_cleanup(cancel_repeating_worker_(Worker),
                 metta_release_python_context(Context)),
    metta_future_complete(Space, Done, cancelled).

cancel_future_(Space, Answer) :-
    % An awaiter holds the await mutex while sleeping. Cancellation must be
    % able to reach the producer while such an await is outstanding.
    future_completion_mutex_(Space, Mutex),
    with_mutex(Mutex, future_cancel_probe_(Space, Status)),
    cancel_future_status_(Status, Space, Answer).

future_cancel_probe_(Space, terminal(Worker)) :-
    metta_future_result(Space, _),
    ( metta_future(Space, Worker, _) -> true ; Worker = none ), !.
future_cancel_probe_(Space, terminal(Worker)) :-
    metta_future(Space, Worker, Done),
    message_queue_property(Done, size(Pending)),
    Pending > 0, !,
    thread_get_message(Done, Outcome),
    assertz(metta_future_result(Space, Outcome)).
future_cancel_probe_(Space, pending(Worker, Done)) :-
    metta_future(Space, Worker, Done), !.
future_cancel_probe_(_, missing).

cancel_future_status_(terminal(Worker), _, false) :- !,
    future_join_(Worker).
cancel_future_status_(missing, Space, _) :- !, existence_error(metta_future, Space).
cancel_future_status_(pending(Worker, Done), Space, Answer) :-
    cancel_future_worker_(Worker, Space, Done, Answer).

cancel_future_worker_(scheduler(Task), _, _, Answer) :- !,
    metta_scheduler_cancel(Task, Answer).
cancel_future_worker_(async(Token), Space, _, Answer) :- !,
    metta_async_cancel_request_(Token, @(true), Accepted, Running),
    ( Accepted == true, Running == true
    -> future_settle_(Space, Outcome),
       ( Outcome == cancelled -> Answer = true ; Answer = false )
    ; Answer = Accepted ).
cancel_future_worker_(none, _, _, false) :- !.
cancel_future_worker_(ThreadId, Space, Done, Answer) :-
    catch(thread_signal(ThreadId, lib_thread:future_cancel_signal_(Space, ThreadId)),
          error(existence_error(thread, _), _), true),
    %Wait for the thread itself rather than for its settlement: a worker that
    %met the signal at its first call port, before its cleanup handler was
    %installed, ended without settling and did no work, so once it is gone
    %its outcome is cancelled unless it settled itself, in which case the
    %claim below is refused and the recorded outcome answers.
    future_join_(ThreadId),
    metta_future_complete(Space, Done, cancelled),
    future_settle_(Space, Outcome),
    ( Outcome == cancelled -> Answer = true ; Answer = false ).

future_cancel_signal_(Space, Thread) :-
    ( metta_future(Space, Thread, _), \+ metta_future_result(Space, _)
    -> throw(error(metta_control_signal(interrupted, future(Space)),
                   context(metta, future(Space))))
    ; true ).

cancel_repeating_worker_(none) :- !.
cancel_repeating_worker_(ThreadId) :-
    catch(thread_signal(ThreadId, abort), _, true),
    catch(metta_thread_join_settled(ThreadId, _), _, true).

% ----------------------------------------------------------------- channels

% The FIFO is the space provider's only term store. Queue entries are capacity
% tokens. Recorded terms preserve copying and remain outside transactions,
% unlike dynamic clauses [source: SWI-Prolog V10.1.13, man/builtin.plx,
% "The recorded database"; commit=c6e1198c490a824b96f6fc6e1c0622a542917024].
channel_new(Id) :- channel_create_([], Id).
channel_new(MaxSize, Id) :-
    must_be(positive_integer, MaxSize),
    channel_create_([max_size(MaxSize)], Id).

channel_create_(Options, Id) :-
    next_metta_handle(Number),
    atom_concat('&channel-', Number, Id),
    message_queue_create(Queue, Options),
    channel_key_(Id, Key),
    catch(sig_atomic((
              recorda(Key, queue(Queue), _),
              recordz('$metta_channels', Id, _),
              metta_claim_space(Id, lib_thread),
              forall(seam:space_created(Id), true) )),
          Error,
          ( channel_release_(Id), throw(Error) )).

channel_key_(Id, Key) :- atom_concat('$metta_channel:', Id, Key).

metta_channel(Id, Queue) :-
    ( var(Id) -> recorded('$metta_channels', Id, _) ; atom(Id) ),
    channel_key_(Id, Key),
    recorded(Key, queue(Queue), _).

known_channel_(Id, Queue) :-
    ( metta_channel(Id, Queue) -> true ; existence_error(metta_channel, Id) ).

channel_send(Id, Term, true) :-
    channel_wait_(Id, send, infinite, Term),
    seam:observe(added, Id, Term).

channel_recv(Id, Term) :-
    channel_wait_(Id, recv, infinite, Term),
    seam:observe(removed, Id, Term).

channel_recv(Id, Timeout, Term) :-
    must_be(number, Timeout),
    ( Timeout >= 0 -> true ; domain_error(not_less_than_zero, Timeout) ),
    get_time(Now), Deadline is Now + Timeout,
    channel_wait_(Id, recv, Deadline, Term),
    seam:observe(removed, Id, Term).

channel_try_recv(Id, Term) :-
    channel_try_(Id, recv, Term),
    seam:observe(removed, Id, Term).

channel_size(Id, Size) :-
    known_channel_(Id, Queue),
    message_queue_property(Queue, size(Size)).

% The door refuses a channel that is gone, the way recv and send do; the
% scope's own release path (seam:space_released/1 below) tolerates one.
channel_close(Id, true) :-
    known_channel_(Id, _),
    metta_release_space(Id).

channel_try_(Id, Mode, Term) :-
    channel_key_(Id, Key),
    with_mutex(Key, sig_atomic((
        known_channel_(Id, Queue), channel_change_(Mode, Key, Queue, Term) ))),
    channel_counterpart_(Mode, Other),
    metta_channel_wake(Id, Other).

channel_change_(send, Key, Queue, Term) :-
    thread_send_message(Queue, slot, [timeout(0)]),
    catch(recordz(Key, message(Term), _), Error,
          ( thread_get_message(Queue, slot, [timeout(0)]), throw(Error) )).
channel_change_(recv, Key, Queue, Term) :-
    once(recorded(Key, message(Term), Reference)),
    erase(Reference),
    thread_get_message(Queue, slot, [timeout(0)]).

channel_counterpart_(send, recv).
channel_counterpart_(recv, send).

% Register before probing; every notification is a hint to re-read the FIFO.
% The same wait works on a carrier or on a host, including in a transaction.
channel_wait_(Id, Mode, Deadline, Term) :-
    known_channel_(Id, _),
    setup_call_cleanup(
        channel_waiter_open_(Id, Mode, Deadline, Waiter, Ref, Timer),
        channel_wait_loop_(Id, Mode, Deadline, Term, Waiter),
        ( erase(Ref), channel_waiter_close_(Waiter, Timer) )).

channel_waiter_open_(Id, Mode, Deadline, Waiter, Ref, Timer) :-
    channel_key_(Id, Key),
    ( nb_current('$metta_scheduler_task', Task)
    -> Waiter = scheduler(Task),
       scheduler_deadline_start_(Task, Deadline, Timer)
    ;  message_queue_create(Queue, [max_size(1)]),
       Waiter = host(Queue), Timer = none ),
    catch(recordz(Key, waiter(Mode, Waiter), Ref), Error,
          ( channel_waiter_close_(Waiter, Timer), throw(Error) )).

channel_waiter_close_(scheduler(_), Timer) :- scheduler_deadline_cancel_(Timer).
channel_waiter_close_(host(Queue), _) :- message_queue_destroy(Queue).

channel_wait_loop_(Id, Mode, Deadline, Term, Waiter) :-
    ( channel_try_(Id, Mode, Term) -> true
    ; scheduler_deadline_open_(Deadline)
    -> channel_waiter_pause_(Waiter, Deadline),
       channel_wait_loop_(Id, Mode, Deadline, Term, Waiter)
    ; fail ).

channel_waiter_pause_(scheduler(_), _) :- engine_yield('$metta_scheduler_suspend').
channel_waiter_pause_(host(Queue), infinite) :- !, thread_get_message(Queue, wake).
channel_waiter_pause_(host(Queue), Deadline) :-
    get_time(Now), Left is max(0, Deadline - Now),
    thread_get_message(Queue, wake, [timeout(Left)]).

metta_channel_waiter(Id, Mode, Waiter) :-
    ( var(Id) -> recorded('$metta_channels', Id, _) ; true ),
    channel_key_(Id, Key), recorded(Key, waiter(Mode, Waiter), _).

metta_channel_wake(Id, Mode) :-
    findall(Waiter, metta_channel_waiter(Id, Mode, Waiter), Waiters),
    maplist(channel_wake_, Waiters).

channel_wake_(scheduler(Task)) :- metta_scheduler_wake(Task).
channel_wake_(host(Queue)) :-
    catch(( thread_send_message(Queue, wake, [timeout(0)]) -> true ; true ),
          error(existence_error(message_queue, _), _), true).

channel_snapshot_(Id, Terms) :-
    channel_key_(Id, Key),
    with_mutex(Key, ( known_channel_(Id, _),
                     findall(Term, recorded(Key, message(Term), _), Terms) )).

channel_clear_(Id) :-
    channel_key_(Id, Key),
    with_mutex(Key, sig_atomic((
        known_channel_(Id, Queue),
        findall(Term, ( recorded(Key, message(Term), Ref), erase(Ref),
                       thread_get_message(Queue, slot, [timeout(0)]) ), Terms) ))),
    metta_channel_wake(Id, send),
    forall(member(Term, Terms), seam:observe(removed, Id, Term)).

channel_release_(Id) :-
    channel_key_(Id, Key),
    with_mutex(Key, sig_atomic((
        ( recorded(Key, queue(Queue), QueueRef)
        -> erase(QueueRef), message_queue_destroy(Queue) ; true ),
        forall(recorded(Key, message(_), MessageRef), erase(MessageRef)) ))),
    metta_channel_wake(Id, send),
    metta_channel_wake(Id, recv),
    forall(recorded('$metta_channels', Id, Ref), erase(Ref)),
    metta_disclaim_space(Id, lib_thread).

:- multifile seam:foreign_space/1, seam:foreign_capability/2,
             seam:foreign_atoms/2, seam:foreign_match/3,
             seam:foreign_add/2, seam:foreign_remove/3, seam:foreign_clear/1,
             seam:context_events/3, seam:space_released/1.
seam:foreign_space(Id) :- metta_channel(Id, _).
seam:foreign_capability(Id, Capability) :-
    metta_channel(Id, _),
    % policy-inventory-exempt: mechanism-internal; reason=a channel is a FIFO that adds by send, removes by receive, enumerates and matches by snapshot and clears, and the vocabulary's other words are not FIFO operations; evidence=lib/lib_thread/lib_thread.pl:channel_snapshot_/2
    member(Capability, [add, remove, enumerate, match, clear]).
seam:context_events(Id, 'per-write-exactly', unordered) :- metta_channel(Id, _).
seam:foreign_atoms(Id, Term) :-
    metta_channel(Id, _), !, channel_snapshot_(Id, Terms), member(Term, Terms).
seam:foreign_match(Id, Term, _) :-
    metta_channel(Id, _), !, channel_snapshot_(Id, Terms), member(Term, Terms).
seam:foreign_add(Id, Term) :-
    metta_channel(Id, _), !, channel_wait_(Id, send, infinite, Term).
seam:foreign_remove(Id, Term, Removed) :-
    metta_channel(Id, _), !,
    ( channel_try_(Id, recv, Term) -> Removed = true ; Removed = false ).
seam:foreign_clear(Id) :- metta_channel(Id, _), !, channel_clear_(Id).
seam:space_released(Id) :-
    ( metta_channel(Id, _) -> channel_release_(Id) ; true ).

% ------------------------------------------------------- bounded worker pools

%A named pool with a fixed number of workers. Submitting more work than the
%pool can run queues it rather than creating unbounded threads, which is the
%difference between a pool and par-map on a huge list.
pool_create(Name, Size, true) :-
    must_be(atom, Name),
    must_be(positive_integer, Size),
    (   current_thread_pool(Name)
    ->  true
    ;   thread_pool_create(Name, Size, []),
        scope_current_(Id),
        ( Id == none -> true ; recordz(Id, child(pool, Name), _) )
    ).

%Submit an expression and answer a future handle, the same handle thread-await
%and thread-settled take, so pooled and unpooled work compose.
pool_submit(Name, Expr, Space) :-
    (   current_thread_pool(Name)
    ->  true
    ;   existence_error(metta_thread_pool, Name)
    ),
    current_metta_module(Module),
    metta_capture_python_context(Context),
    catch(pool_submit_context_(Name, Context, Module, Expr, Space),
          Error,
          ( metta_release_python_context(Context), throw(Error) )).

pool_submit_context_(Name, Context, Module, Expr, Space) :-
    next_metta_handle(Number),
    future_space_name(Number, Space),
    message_queue_create(Done, [max_size(1)]),
    catch(( thread_create_in_pool(Name,
                                  future_body_context_(Context, Module, Expr,
                                                       Space, Done),
                                  ThreadId, []),
            assertz(metta_future(Space, ThreadId, Done)) ),
          Error,
          ( message_queue_destroy(Done), throw(Error) )).

pool_stats(Name, Stats) :-
    (   current_thread_pool(Name)
    ->  true
    ;   existence_error(metta_thread_pool, Name)
    ),
    % An unbound property request copies all properties from one manager
    % state. Separate requests can combine running and free from different
    % states: SWI-Prolog thread_pool.pl, pool_properties/3 and pool_property/2.
    % https://github.com/SWI-Prolog/swipl-devel/blob/fc7ef84b949378b729052c3ade79c90ce5416abb/library/thread_pool.pl
    findall(Property, thread_pool_property(Name, Property), Properties),
    findall([Key, Value],
            % policy-inventory-exempt: mechanism-internal; reason=these are the fixed SWI thread_pool_property keys exposed by the pool statistics adapter; evidence=lib/lib_thread/lib_thread.pl:pool_stats/2
            ( member(Key, [size, running, backlog, free]),
              Property =.. [Key, Value],
              memberchk(Property, Properties) ),
            Stats).

pool_destroy(Name, true) :-
    catch(thread_pool_destroy(Name), _, true).

% ------------------------------------------------------------------- timers

%Deferred evaluation, the setTimeout/clearTimeout job, read the MeTTa way: a
%timer is a FUTURE THAT STARTS LATER, so it answers a space like spawn does,
%its answers appear in that space when it fires, and thread-cancel stops it.
%There is no separate timer handle type and no callback registration, because
%a space and a standing query already are those things.
%
%Cost. One timer thread for the whole process and one bounded pool, whatever
%the number of timers: N timers cost no threads. The timer thread holds a heap
%keyed by deadline and waits with a timed message receive, which measured a
%constant 0.06ms drift from 1ms out to 500ms, and 20,000 timers went into the
%heap in 29ms [measured 2026-08-15].
%
%Not alarm/4, which is SWI's own timer wheel and would have been the obvious
%choice: its goal runs as a SIGNAL on whichever thread scheduled it, so a
%firing timer would interrupt unrelated evaluation. Running MeTTa evaluation
%from a signal handler is what took SIGSEGV when metta_timeout tried it
%[measured 2026-08-15].
:- dynamic metta_timer_cancelled/1.

metta_timer_queue(metta_timer_requests).
metta_timer_pool(metta_timer_workers).

%The timer thread and its pool start on first use and outlive every timer.
ensure_timer_service :-
    with_mutex('$metta_timers', ensure_timer_service_locked).

ensure_timer_service_locked :-
    metta_timer_queue(Queue),
    (   is_message_queue(Queue)
    ->  true
    ;   message_queue_create(_, [alias(Queue)])
    ),
    metta_timer_pool(Pool),
    (   current_thread_pool(Pool)
    ->  true
    ;   cpu_count(Cores),
        Workers is max(1, min(Cores, 8)),
        thread_pool_create(Pool, Workers, [])
    ),
    (   catch(thread_property(metta_timer, status(running)), _, fail)
    ->  true
    ;   thread_create(timer_loop, _, [alias(metta_timer), detached(true)])
    ).

timer_loop :-
    empty_heap(Heap),
    timer_loop_(Heap).

%Wait exactly until the earliest deadline, or indefinitely when nothing is
%scheduled. A request arriving early simply preempts the wait, so adding a
%sooner timer takes effect immediately instead of after the current sleep.
timer_loop_(Heap) :-
    metta_timer_queue(Queue),
    (   min_of_heap(Heap, Deadline, _)
    ->  get_time(Now),
        Wait is max(0, Deadline - Now),
        (   thread_get_message(Queue, Request, [timeout(Wait)])
        ->  timer_request_(Request, Heap, Next)
        ;   timer_fire_(Heap, Next)
        )
    ;   thread_get_message(Queue, Request),
        timer_request_(Request, Heap, Next)
    ),
    timer_loop_(Next).

timer_request_(schedule(Deadline, scheduler_wake(Task, Token)), Heap, Next) :- !,
    with_mutex('$metta_scheduler_deadlines',
               (   metta_scheduler_deadline(Token, Task)
               ->  Active = true
               ;   Active = false
               )),
    (   Active == true
    ->  add_to_heap(Heap, Deadline, scheduler_wake(Task, Token), Next)
    ;   Next = Heap
    ).
timer_request_(schedule(Deadline, Timer), Heap, Next) :-
    add_to_heap(Heap, Deadline, Timer, Next).

timer_request_(cancel(Timer), Heap, Next) :-
    (   delete_from_heap(Heap, _, Timer, Remaining)
    ->  Next = Remaining
    ;   Next = Heap
    ).

%Cancelled user timers are marked rather than deleted from the heap: deletion
%is O(n) in a pairing heap and the check at fire time is O(1). Finite scheduler
%waits use unique wake tokens and delete their heap records on early success,
%because retaining one record for every completed wait would retain task IDs.
timer_fire_(Heap, Next) :-
    get_from_heap(Heap, _Deadline, Timer, Rest),
    timer_fire_value_(Timer, Rest, Next).

timer_fire_value_(scheduler_wake(Task, Token), Rest, Rest) :- !,
    with_mutex('$metta_scheduler_deadlines',
               (   retract(metta_scheduler_deadline(Token, Task))
               ->  Wake = true
               ;   Wake = false
               )),
    ( Wake == true -> metta_scheduler_wake(Task) ; true ).
timer_fire_value_(scope_deadline(Id), Rest, Rest) :- !,
    scope_cancel_automatic_(Id, deadline).
timer_fire_value_(timer(Space, Module, Expr, Repeat, Context), Rest, Next) :-
    with_mutex('$metta_timer_lifecycle',
               timer_fire_value_locked_(Space, Module, Expr, Repeat, Context,
                                        Rest, Next, Action)),
    timer_fire_action_(Action).

timer_fire_value_locked_(Space, _, _, _, _, Rest, Rest, none) :-
    retract(metta_timer_cancelled(Space)), !.
timer_fire_value_locked_(Space, Module, Expr, Repeat, Context, Rest, Next,
                         Action) :-
    catch(( timer_dispatch_(Space, Module, Expr, Repeat, Context),
            Status = dispatched ),
          Error,
          Status = error(Error)),
    (   Status == dispatched,
        Repeat = every(Period)
    ->  get_time(Now),
        Again is Now + Period,
        add_to_heap(Rest, Again,
                    timer(Space, Module, Expr, Repeat, Context), Next),
        Action = none
    ;   Status == dispatched
    ->  Next = Rest,
        Action = none
    ;   Status = error(Error),
        timer_pool_saturated_(Error)
    ->  timer_retry_(Space, Module, Expr, Repeat, Context, Rest, Next),
        Action = none
    ;   Status = error(Error),
        Next = Rest,
        timer_dispatch_failed_locked_(Space, Repeat, Context, Error, Action)
    ).

timer_pool_saturated_(error(resource_error(threads_in_pool(Pool)), _)) :-
    metta_timer_pool(Pool).

timer_retry_(Space, Module, Expr, Repeat, Context, Rest, Next) :-
    timer_retry_delay_(Repeat, Delay),
    get_time(Now),
    Again is Now + Delay,
    add_to_heap(Rest, Again,
                timer(Space, Module, Expr, Repeat, Context), Next).

timer_retry_delay_(once, 0.01).
timer_retry_delay_(every(Period), Period).

timer_fire_action_(none).
timer_fire_action_(release(Context)) :-
    metta_release_python_context(Context).
timer_fire_action_(fail(Context, Space, Done, Error)) :-
    metta_release_python_context(Context),
    metta_future_complete(Space, Done, error(Error)).

%The work runs on the pool, never on the timer thread: one slow expression
%would otherwise delay every other timer behind it. A repeating timer keeps at
%most one invocation live. Periods that elapse during a slow invocation are
%coalesced rather than building an unbounded pool backlog or overwriting the
%only worker handle cancellation can reach.
timer_dispatch_(Space, Module, Expr, Repeat, Context) :-
    metta_timer_pool(Pool),
    (   metta_future(Space, Worker, Done)
    ->  true
    ;   existence_error(metta_future, Space)
    ),
    (   Repeat = every(_),
        Worker \== none
    ->  true
    ;   timer_dispatch_worker_(Pool, Space, Module, Expr, Repeat, Context,
                               Done)
    ).

timer_dispatch_worker_(Pool, Space, Module, Expr, Repeat, Context, Done) :-
    timer_dispatch_body_(Repeat, Context, Module, Expr, Space, Done,
                         Start, Body),
    catch(thread_create_in_pool(Pool, Body, ThreadId, [wait(false)]),
          Error,
          ( timer_dispatch_start_destroy_(Start),
            throw(Error) )),
    catch(( retractall(metta_future(Space, _, _)),
            assertz(metta_future(Space, ThreadId, Done)),
            timer_dispatch_start_(Start) ),
          Error,
          ( catch(thread_signal(ThreadId, abort), _, true),
            catch(metta_thread_join_settled(ThreadId, _), _, true),
            timer_dispatch_start_destroy_(Start),
            throw(Error) )).

timer_dispatch_body_(once, Context, Module, Expr, Space, Done, none,
                     timer_once_body_(Context, Module, Expr, Space, Done)).
timer_dispatch_body_(every(_), Context, Module, Expr, Space, _, queue(Start),
                     repeating_body_started_(Start, Context, Module, Expr,
                                             Space)) :-
    message_queue_create(Start, [max_size(1)]).

timer_dispatch_start_(none).
timer_dispatch_start_(queue(Start)) :-
    thread_send_message(Start, go).

timer_dispatch_start_destroy_(none).
timer_dispatch_start_destroy_(queue(Start)) :-
    catch(message_queue_destroy(Start), _, true).

timer_dispatch_failed_locked_(Space, Repeat, Context, Error, Action) :-
    (   retract(metta_timer_context(Space, Repeat, Context))
    ->  (   metta_future(Space, _, Done)
        ->  Action = fail(Context, Space, Done, Error)
        ;   Action = release(Context)
        )
    ;   Action = none
    ).

%A repeating timer never completes, so it must NOT post a completion: the
%mailbox holds one message and a second post would block a pool worker
%forever. Consume a repeating timer with await-atom on its space instead.
%
%An error has nowhere to be raised to, so it is written into the space as an
%(Error <expr> <message>) atom, HE's own error shape. The consumer sees it by
%matching, which is how it would see any other answer.
timer_once_body_(Context, Module, Expr, Space, Done) :-
    future_worker_(Space, Done,
                   future_body_outcome_(Context, Module, Expr, Space, Outcome),
                   Outcome,
                   timer_context_release_(Space, once, Context)).

timer_context_release_(Space, Repeat, Context) :-
    with_mutex('$metta_timer_lifecycle',
               (   retract(metta_timer_context(Space, Repeat, Context))
               ->  Release = true
               ;   Release = false
               )),
    ( Release == true -> metta_release_python_context(Context) ; true ).

repeating_body_started_(Start, Context, Module, Expr, Space) :-
    setup_call_cleanup(
        true,
        thread_get_message(Start, go),
        catch(message_queue_destroy(Start), _, true)),
    call_cleanup(
        ( future_body_outcome_(Context, Module, Expr, Space, Outcome),
          repeating_outcome_(Outcome, Context, Expr, Space) ),
        repeating_body_finished_(Space)).

repeating_outcome_(done, _, _, _) :- !.
repeating_outcome_(error(Error), Context, Expr, Space) :-
    Context \= scoped(_, _), !,
    term_to_atom(Error, Message), future_add_atom(Space, ['Error', Expr, Message]).
repeating_outcome_(Outcome, Context, _, Space) :-
    with_mutex('$metta_timer_lifecycle',
        ( ( metta_timer_cancelled(Space) -> true
          ; assertz(metta_timer_cancelled(Space)) ),
          ( retract(metta_timer_context(Space, _, Context)) -> Release = true
          ; Release = false ),
          metta_future(Space, _, Done) )),
    ( Release == true -> metta_release_python_context(Context) ; true ),
    metta_future_complete(Space, Done, Outcome).

repeating_body_finished_(Space) :-
    thread_self(Worker),
    with_mutex('$metta_timer_lifecycle',
               (   retract(metta_future(Space, Worker, Done))
               ->  assertz(metta_future(Space, none, Done))
               ;   true
               )).

timer_cancel_prepare_(Space, Action) :-
    (   retract(metta_timer_context(Space, Repeat, Context))
    ->  (   metta_timer_cancelled(Space)
        ->  true
        ;   assertz(metta_timer_cancelled(Space))
        ),
        (   metta_future(Space, Worker, Done)
        ->  (   Worker == none
            ->  Action = pending(Context, Done)
            ;   Repeat == once
            ->  retractall(metta_timer_cancelled(Space)),
                Action = active(once, Context, Done, Worker)
            ;   Action = active(Repeat, Context, Done, Worker)
            )
        ;   Action = orphan(Context)
        )
    ;   Action = not_timer
    ).

%Evaluate an expression once, after a delay. Answers the future space it will
%produce into, so you can await-atom on it before it has fired.
timer_after(Seconds, Expr, Space) :-
    must_be(number, Seconds),
    schedule_timer_(Seconds, Expr, once, Space).

%Evaluate it again every Seconds until cancelled. Consume it with await-atom
%rather than await: a repeating timer never finishes, so there is no complete
%answer set to wait for.
timer_every(Seconds, Expr, Space) :-
    must_be(number, Seconds),
    Seconds > 0,
    schedule_timer_(Seconds, Expr, every(Seconds), Space).

schedule_timer_(Seconds, Expr, Repeat, Space) :-
    ensure_timer_service,
    current_metta_module(Module),
    metta_capture_python_context(Context),
    next_metta_handle(Number),
    future_space_name(Number, Space),
    %The future exists from the moment the timer is SCHEDULED, not from when it
    %fires, so awaiting a pending timer waits for it and settled? answers false
    %instead of both raising "no such future".
    message_queue_create(Done, [max_size(1)]),
    assertz(metta_future(Space, none, Done)),
    assertz(metta_timer_context(Space, Repeat, Context)),
    get_time(Now),
    Deadline is Now + Seconds,
    metta_timer_queue(Queue),
    catch(thread_send_message(
              Queue,
              schedule(Deadline,
                       timer(Space, Module, Expr, Repeat, Context))),
          Error,
          ( retractall(metta_timer_context(Space, Repeat, Context)),
            retractall(metta_future(Space, none, Done)),
            message_queue_destroy(Done),
            metta_release_python_context(Context),
            throw(Error) )).

% ------------------------------------------------ blocking on a space change
%
%Linda's two blocking binds, over a MeTTa space. `rd` reads a matching tuple
%and leaves it; `in` withdraws one. The difference is the whole coordination
%model: an in-based interaction "implements one-of-n semantics (only one
%consumer reads a given tuple) whereas read-based interaction can be used to
%implement one-to-n message delivery (a given tuple can be read by all such
%consumers)" [source: Eugster, Felber, Guerraoui and Kermarrec, The Many
%Faces of Publish/Subscribe, ACM Computing Surveys 35(2), 2003, on the shared
%data-space model]. Gelernter's tuple spaces are the origin (TOPLAS 7(1),
%1985) and JavaSpaces is the production spelling this follows: "the take
%requests perform exactly like the corresponding read requests, except that
%the matching entry is removed", and "two take operations will never return
%copies of the same entry" [source: JavaSpaces Service Specification,
%JS.2.5].
%
%The non-blocking pair, Linda's rdp and inp, needs nothing here: match/4 is
%rdp and 'remove-atom'/3 is inp, and both already answer at once.

%Block until an atom unifying with Pattern is in Space, and answer it with
%the caller's variables bound, WITHOUT removing it. Linda's rd.
%
%Event-driven, not polled: this installs a clause on the engine's own
%seam:atom_added/2 extension point, the same one Python subscriptions use
%[source: extensions/python/metta/_binding/subscriptions.pl:41; commit=cd62330ceacc8f1254eed9791c3f6203b48a1c9e], so the
%write itself delivers. Installing the hook also takes the space off the bulk
%add fast path for as long as the wait lasts, which is what makes per-atom
%events fire at all [source: engine/spaces.pl, metta_add_hooks_idle/1].
space_await(Space, Pattern, Out) :-
    space_wait_(Space, Pattern, true, infinite, peek, Out).

%The same, giving up after Timeout seconds with no answer.
space_await(Space, Pattern, Timeout, Out) :-
    must_be(number, Timeout),
    space_wait_(Space, Pattern, true, Timeout, peek, Out).

%The same again, with a GUARD: a term over the pattern's variables that must
%evaluate true before the candidate is claimed. match/4 has taken a guard all
%along and the blocking pair had no way to say one, so "wait for a job whose
%priority is above five" had to be spelled as a wait plus a re-wait in the
%caller. A guard is one more reason to keep waiting, which is exactly the
%shape await_matching_ already has for a candidate that fails the real
%unification after passing the hook's loose test.
space_await_where(Space, Pattern, Guard, Out) :-
    space_wait_(Space, Pattern, Guard, infinite, peek, Out).

space_await_where(Space, Pattern, Guard, Timeout, Out) :-
    must_be(number, Timeout),
    space_wait_(Space, Pattern, Guard, Timeout, peek, Out).

%Block until an atom unifying with Pattern is in Space, then REMOVE exactly
%one and answer it. Linda's in, and the primitive futures, worker pools and
%rendezvous are one line of MeTTa over.
space_take(Space, Pattern, Out) :-
    space_wait_(Space, Pattern, true, infinite, take, Out).

space_take(Space, Pattern, Timeout, Out) :-
    must_be(number, Timeout),
    space_wait_(Space, Pattern, true, Timeout, take, Out).

%Guarded take. The guard is checked BEFORE the removal, so a candidate the
%guard rejects is left in the space for whoever wants it, and the waiter goes
%back to waiting on the deadline it already has.
space_take_where(Space, Pattern, Guard, Out) :-
    space_wait_(Space, Pattern, Guard, infinite, take, Out).

space_take_where(Space, Pattern, Guard, Timeout, Out) :-
    must_be(number, Timeout),
    space_wait_(Space, Pattern, Guard, Timeout, take, Out).

%Waiting is a promise about the CONTEXT, so a context that declares no event
%delivery is refused here rather than parked on a channel that will never
%report anything [P12.14]. A native space needs no declaration.
space_wait_(Space, Pattern, Guard, Timeout, Mode, Out) :-
    ( Mode == take -> Waiter = space_take ; Waiter = space_await ),
    metta_refuse_wait_in_transaction(Waiter),
    metta_require_events(Space, 'be waited on'),
    (   Timeout == infinite
    ->  Deadline = infinite
    ;   get_time(Now),
        Deadline is Now + Timeout
    ),
    (   nb_current('$metta_scheduler_task', Task)
    ->  scheduler_space_wait_(Task, Space, Pattern, Guard, Deadline, Mode, Out)
    ;   blocking_space_wait_(Space, Pattern, Guard, Deadline, Mode, Out)
    ).

blocking_space_wait_(Space, Pattern, Guard, Deadline, Mode, Out) :-
    message_queue_create(Queue),
    %The clause gets its own copy of the pattern, so its variables are fresh
    %on every write and testing a candidate never binds the caller's.
    copy_term(Pattern, HookPattern),
    setup_call_cleanup(
        %The send tolerates a DEAD queue, and that is a correctness clause
        %rather than defensiveness: erase/1 does not stop an execution already
        %inside this hook (SWI's logical update view lets a running goal finish
        %on the clause it entered with), so a writer can be mid-hook when a
        %timed-out waiter erases it and destroys the queue, and the writer's
        %in-flight send then raised existence_error IN THE WRITER's add-atom.
        %A wake-up is a hint and the STORE is the truth (the comment below), so
        %a hint to a departed waiter is dropped, never an error. Only the
        %dead-queue error is caught; anything else still surfaces
        %[tested: lib_thread:a_wakeup_to_a_departed_waiter_is_dropped].
        assertz((seam:atom_added(Space, Candidate) :-
                    (   \+ HookPattern \= Candidate
                    ->  catch(thread_send_message(Queue, Candidate),
                              error(existence_error(message_queue, _), _),
                              true)
                    ;   true
                    )), HookRef),
        space_claim_(Space, Pattern, Guard, Queue, Deadline, Mode, Out),
        ( erase(HookRef),
          catch(message_queue_destroy(Queue), _, true) )).

%A scheduled engine parks itself, not its carrier. The atom-added hook is the
%waker: it marks the task runnable, and the resumed engine rechecks the store
%before trusting the hint. A finite deadline is another one-shot wake record
%on the existing timer heap, so no sleeping thread is introduced.
scheduler_space_wait_(Task, Space, Pattern, Guard, Deadline, Mode, Out) :-
    copy_term(Pattern, HookPattern),
    space_wait_slice(first, Slice),
    setup_call_cleanup(
        assertz((seam:atom_added(Space, Candidate) :-
                    (   \+ HookPattern \= Candidate
                    ->  metta_scheduler_wake(Task)
                    ;   true
                    )), HookRef),
        setup_call_cleanup(
            scheduler_deadline_start_(Task, Deadline, DeadlineToken),
            scheduler_space_claim_(Task, Space, Pattern, Guard, Deadline,
                                   Slice, Mode, Out),
            scheduler_deadline_cancel_(DeadlineToken)),
        erase(HookRef)).

scheduler_deadline_start_(_, infinite, none) :- !.
scheduler_deadline_start_(Task, Deadline,
                          deadline(Token, scheduler_wake(Task, Token))) :-
    ensure_timer_service,
    flag('$metta_scheduler_deadline_id', Token, Token + 1),
    with_mutex('$metta_scheduler_deadlines',
               assertz(metta_scheduler_deadline(Token, Task))),
    metta_timer_queue(Queue),
    catch(thread_send_message(
              Queue, schedule(Deadline, scheduler_wake(Task, Token))),
          Error,
          ( with_mutex('$metta_scheduler_deadlines',
                       retractall(metta_scheduler_deadline(Token, Task))),
            throw(Error) )).

scheduler_deadline_cancel_(none) :- !.
scheduler_deadline_cancel_(deadline(Token, Timer)) :-
    with_mutex('$metta_scheduler_deadlines',
               (   retract(metta_scheduler_deadline(Token, _))
               ->  Cancel = true
               ;   Cancel = false
               )),
    (   Cancel == true
    ->  metta_timer_queue(Queue),
        catch(thread_send_message(Queue, cancel(Timer)), _, true)
    ;   true
    ).

%A parked engine re-reads the store on every resume, so all it needs is a
%resume: the same look-again the blocking wait does, in the shape a scheduler
%task can take. Without one a lost hint parks the task until its deadline, and
%forever when it has none -- the same defect the blocking wait had and the
%worse half of it [tested:
%lib_thread:a_wait_finds_an_atom_whose_hint_was_never_published].
scheduler_space_claim_(Task, Space, Pattern, Guard, Deadline, Slice, Mode,
                       Out) :-
    copy_term(Pattern-Guard, Attempt-AttemptGuard),
    (   space_already_holds_(Space, Attempt, AttemptGuard, Candidate)
    ->  scheduler_claim_candidate_(Task, Space, Pattern, Guard, Candidate,
                                   Deadline, Mode, Out)
    ;   scheduler_deadline_open_(Deadline)
    ->  setup_call_cleanup(
            scheduler_look_again_(Task, Deadline, Slice, Token),
            engine_yield('$metta_scheduler_suspend'),
            scheduler_deadline_cancel_(Token)),
        space_wait_slice(ceiling, Ceiling),
        Next is min(Slice * 2, Ceiling),
        scheduler_space_claim_(Task, Space, Pattern, Guard, Deadline, Next,
                               Mode, Out)
    ;   fail
    ).

%One wake token on the timer heap the deadline already uses. A slice that
%would land past the deadline needs none, because the deadline's own wake is
%sooner and the loop gives up when it arrives.
scheduler_look_again_(Task, Deadline, Slice, Token) :-
    get_time(Now),
    At is Now + Slice,
    (   Deadline \== infinite,
        At >= Deadline
    ->  Token = none
    ;   scheduler_deadline_start_(Task, At, Token)
    ).

scheduler_claim_candidate_(_, _, Pattern, _Guard, Candidate, _, peek, Out) :- !,
    Pattern = Candidate,
    Out = Candidate.
scheduler_claim_candidate_(Task, Space, Pattern, Guard, Candidate, Deadline,
                           take, Out) :-
    (   metta_remove_atom(Space, Candidate, true)
    ->  Pattern = Candidate, Out = Candidate
    ;   space_wait_slice(first, Slice),
        scheduler_space_claim_(Task, Space, Pattern, Guard, Deadline, Slice,
                               take, Out)
    ).

scheduler_deadline_open_(infinite) :- !.
scheduler_deadline_open_(Deadline) :-
    get_time(Now),
    Now < Deadline.

%ONE hook for the whole wait, retries included, and that is not tidiness: a
%losing taker that tore its hook down and built a new one would miss any
%write that landed in between, which is the same lost-write race installing
%after the check would cause. Measured 2026-08-21 with the hook rebuilt per
%retry: eight takers over four atoms claimed three and left one behind.
%
%The STORE rather than the queue is the truth, and the claim is
%metta_remove_atom/3 rather than the language's 'remove-atom'/3 BECAUSE it
%reports. Two takers wake on one atom, one removal answers true and the other
%answers false, and the loser goes round; going round re-checks what the space
%holds FIRST, so an atom that arrived while this caller was losing a race is
%found whether it is still queued or not, and a queue entry for an atom
%somebody else took is discarded by the same claim that fails. The removal is
%the one atomic step and everything else is a wake-up, which is what makes
%exactly-one hold with no lock held across the wait.
%
%'remove-atom'/3 cannot serve here since 2026-08-30: it answers True whether
%or not the space held the atom, which is upstream's law, so every loser would
%read its own claim as a win. It also DRAINS what unifies, where a take wants
%one tuple. Both are why the reporting one-occurrence door exists
%[source: engine/spaces/foreign.pl, remove_matching_atoms/2;
%tested: lib_thread:test_a_blocking_take_waits_for_a_matching_atom_and_removes_exactly_one].
%
%Each attempt probes with a fresh COPY of the pattern, because a match binds
%and a retry must not inherit the losing attempt's bindings; the caller's own
%variables are bound once, by the winning candidate.
space_claim_(Space, Pattern, Guard, Queue, Deadline, Mode, Out) :-
    %The pair is copied TOGETHER so the guard keeps sharing the pattern's
    %variables; copying them apart would leave the guard testing free ones.
    copy_term(Pattern-Guard, Attempt-AttemptGuard),
    %Check the space only AFTER the hook is live. An atom that is already
    %there answers at once, which is what "wait until this holds" means,
    %and doing it in this order means a write landing between the check and
    %the wait is caught by the hook rather than missed. Checking first and
    %installing after loses exactly that write, which is what made a
    %spawned writer race this and win.
    (   space_already_holds_(Space, Attempt, AttemptGuard, Candidate)
    ->  true
    ;   await_matching_(Space, Queue, Attempt, AttemptGuard, Deadline, Candidate)
    ),
    (   Mode == peek
    ->  Pattern = Candidate, Out = Candidate
    ;   metta_remove_atom(Space, Candidate, true)
    ->  Pattern = Candidate, Out = Candidate
    ;   space_claim_(Space, Pattern, Guard, Queue, Deadline, Mode, Out)
    ).

space_already_holds_(Space, Pattern, Guard, Out) :-
    current_metta_module(Module),
    eval_metta_in_module(Module, [match, Space, Pattern, Pattern], Out),
    guard_holds_(Module, Guard).

%A guard is a MeTTa term over the pattern's variables, evaluated once the
%candidate has bound them and required TRUE, which is match/4's own rule for
%its where-guard. `true` is the unguarded spelling and costs no evaluation.
guard_holds_(_Module, Guard) :-
    Guard == true,
    !.
guard_holds_(Module, Guard) :-
    eval_metta_in_module(Module, Guard, Verdict),
    Verdict == true.

%A WAKE-UP IS A HINT AND THE STORE IS THE TRUTH, so a wait that hears nothing
%looks again rather than concluding that nothing was written. A hint really is
%lost sometimes, and the mechanism is the engine's own: the write door carries
%its event publisher only while some seam:atom_added/2 clause exists
%[source: engine/ext_points.pl, enable_atom_hook/1 and disable_atom_hook/1],
%so a writer already inside that door when a waiter registers writes without
%publishing anything, and a write that then lands after the waiter's own first
%read is one nobody ever mentions. The waiter used to sit out its whole
%deadline with the atom in the space beside it.
%
%Measured over the corpus example's own spawn-and-wait, 3,000 rounds a process
%under the load the example corpus itself makes: 7 of 90,000 rounds waited the
%full ten seconds and found the atom PRESENT the moment they gave up, at
%loadavg 34 to 92; none of 60,000 rounds ever read a store that missed a write
%whose future had already settled, so the store read is sound and the hint is
%what goes missing; and with one waiter parked for the whole run, which holds
%the door's publisher in place, 60,000 rounds at loadavg 116 to 124 missed
%nothing at all
%[measured 2026-09-08; command=sh run.sh over a rounds probe under `sh
%test.sh`; fixture=examples/ch17-concurrency-and-the-loop/01-thread_lib.metta's
%own (spawn (add-atom ...)) beside (await-atom ... 10); commit=5f92ecfb105f7a11d8f3b1a4c0a7e3b6d4b656a6].
%
%Re-reading is the discipline every condition variable is used with, for the
%same reason: the signal is not the state, so the waiter re-tests the
%predicate instead of trusting the wake-up [source: POSIX
%pthread_cond_wait/3's spurious-wakeup rule, and Java's Object.wait(),
%documented as usable only inside a loop that tests the condition]. The slices
%BACK OFF because the race is at registration: a lost hint costs the first
%slice, and a wait parked for hours costs one store read a second.
%
%The hook test is deliberately loose (unifiable, binding nothing), so a
%candidate can still fail the real unification here; keep waiting when it does.
space_wait_slice(first, 0.05).
space_wait_slice(ceiling, 1.0).

await_matching_(Space, Queue, Pattern, Guard, Deadline, Out) :-
    current_metta_module(Module),
    space_wait_slice(first, Slice),
    await_matching_(Space, Queue, Pattern, Guard, Module, Deadline, Slice, Out).

%ONE deadline for the whole call, computed once by space_wait_/6 and carried
%through every claim retry, not one per candidate: thread_get_message/3 FAILS
%when its timeout expires, so a repeat loop around a per-call timeout would
%restart the clock on every non-matching write and never give up.
await_matching_(Space, Queue, Pattern, Guard, Module, Deadline, Slice, Out) :-
    await_slice_(Deadline, Slice, Wait),
    (   thread_get_message(Queue, Candidate, [timeout(Wait)])
    ->  %The candidate is tested against a FRESH copy so a rejection leaves the
        %caller's pattern unbound for the next one; the guard rides along in
        %the copy for the same reason.
        (   copy_term(Pattern-Guard, Try-TryGuard),
            Try = Candidate,
            guard_holds_(Module, TryGuard)
        ->  Out = Candidate
        ;   await_matching_(Space, Queue, Pattern, Guard, Module, Deadline,
                            Slice, Out)
        )
    ;   copy_term(Pattern-Guard, Look-LookGuard),
        (   space_already_holds_(Space, Look, LookGuard, Candidate)
        ->  Out = Candidate
        ;   space_wait_slice(ceiling, Ceiling),
            Next is min(Slice * 2, Ceiling),
            await_matching_(Space, Queue, Pattern, Guard, Module, Deadline,
                            Next, Out)
        )
    ).

%How long this slice may sleep: the slice, or what is left of the deadline
%when that is less. A wait with no deadline sleeps whole slices forever, and
%one whose deadline has passed fails, which is what a deadline means.
await_slice_(infinite, Slice, Slice) :- !.
await_slice_(Deadline, Slice, Wait) :-
    get_time(Now),
    Remaining is Deadline - Now,
    Remaining > 0,
    Wait is min(Remaining, Slice).

% --------------------------------------------------------- synchronisation

%Run an expression while holding a named lock, WITHOUT collapsing it to its
%first answer.
%
%SWI's with_mutex/2 behaves as once/1, so the obvious spelling silently turns
%a three-answer expression into a one-answer expression [measured 2026-08-15:
%(collapse (with_mutex m (superpose (1 2 3)))) answered (1)]. setup_call_cleanup/3
%holds the lock across backtracking instead and releases it when the goal
%runs out of choice points or is cut.
%
%The cost of keeping the answers is the deadlock the manual warns about: a
%caller that abandons this goal with a choice point still open holds the lock
%until that choice point is cut. Enumerate the answers fully, or wrap the call
%in once, if the lock matters.
with_lock(Name, Expr, Out) :-
    must_be(atom, Name),
    current_metta_module(Module),
    setup_call_cleanup(mutex_lock(Name),
                       eval_metta_in_module(Module, Expr, Out),
                       mutex_unlock(Name)).

% ------------------------------------------------------------ introspection

cpu_count(Count) :-
    (   current_prolog_flag(cpu_count, Cores), integer(Cores)
    ->  Count = Cores
    ;   Count = 1
    ).

thread_count(Count) :-
    aggregate_all(count, thread_property(_, status(running)), Count).
