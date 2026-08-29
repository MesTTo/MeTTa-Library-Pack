% Purpose: concurrency for MeTTa over SWI's own primitives. Futures are
%   suspended SWI engines multiplexed over one bounded carrier pool; waits,
%   channel backpressure and blocking host calls release those carriers.
%   Every predicate follows the compiled convention, inputs then one output.
% Assumes:
%   - eval_metta_in_module/3 in engine/translator.pl evaluates one MeTTa
%     expression under a named space's module, which is what a worker thread
%     needs because SWI global variables are thread-local [source:
%     engine/translator.pl, eval_metta_in_module/3]
%   - concurrent_maplist/3 already sizes its pool to min(cpu_count, length)
%     and calls each goal once [source 2026-08-15:
%     /usr/lib/swi-prolog/library/thread.pl, workers/2 and once_in_module/5]
% Guarantees:
%   - spawned computations are SWI engines stepped over a bounded carrier
%     pool, and a space write wakes rather than parks a carrier [tested:
%     lib_thread:spawned_engines_multiplex_over_bounded_carriers,
%     lib_thread:a_suspended_engine_resumes_when_its_space_waker_fires,
%     lib_thread:cancelling_a_suspended_engine_releases_it_without_an_answer;
%     commit=39092863ae34184a9f955f185ff57c1ff177ec40]
%   - oracleIO host operations detach onto transient offload threads before
%     entering foreign code, so even more blocked calls than normal carriers
%     cannot consume scheduler capacity; cancellation reports false until a
%     running foreign call returns and the engine actually settles [tested:
%     test_a_blocking_oracle_uses_the_dirty_lane_without_pinning_normal_work;
%     commit=39092863ae34184a9f955f185ff57c1ff177ec40]
%   - future await, empty channel receive and full channel send suspend their
%     engines and wake from completion or mailbox state instead of blocking
%     all carriers [tested:
%     lib_thread:awaiting_futures_suspends_engines_instead_of_all_carriers,
%     lib_thread:empty_channel_receives_suspend_engines_instead_of_all_carriers,
%     lib_thread:full_channel_sends_suspend_engines_instead_of_all_carriers;
%     commit=39092863ae34184a9f955f185ff57c1ff177ec40]
%   - future completion is single-assignment, settled pool work cannot be
%     reported as cancelled, timer dispatch cannot cross a successful
%     cancellation, and a repeating timer coalesces ticks while its prior
%     invocation is still running [tested:
%     lib_thread:a_future_terminal_outcome_is_single_assignment,
%     lib_thread:cancelling_a_completed_unawaited_pool_future_is_false,
%     lib_thread:timer_fire_and_cancel_have_one_atomic_transition,
%     lib_thread:a_repeating_timer_never_overlaps_its_own_invocations;
%     commit=39092863ae34184a9f955f185ff57c1ff177ec40]
%   - a blocking take parks until a matching atom arrives, removes exactly
%     one, and two takers never claim the same atom: eight takers over four
%     atoms claim four distinct ones and the space is left empty [tested:
%     lib_thread:test_a_blocking_take_waits_for_a_matching_atom_and_removes_exactly_one,
%     lib_thread:a_blocking_peek_parks_without_removing; commit=c05f93baf8c6ecd483487efb72d7f8eb92c97809]
%   - par-map answers one result per element, in the input list's order,
%     because concurrent_maplist/3 preserves position [tested: lib_thread:par_map_answers_one_result_per_element_in_order]
%   - par-race releases every worker from one start barrier and ignores Empty
%     answers, so source order cannot buy a branch thread-creation time and a
%     pruned branch cannot win [tested: lib_thread:race_survives_a_failing_branch;
%     commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87]
%   - a future holds its expression's whole ANSWER SET, because it is a space
%     the evaluating engine adds every answer to; awaiting twice answers the
%     same set without blocking a second time [tested: lib_thread:a_future_holds_the_whole_answer_set]
%   - a channel send never loses a term: message queues copy, so the receiver
%     gets its own copy and variable bindings do not cross [tested: lib_thread:a_channel_round_trips_a_term, a_channel_carries_a_term_between_threads]
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
%     failed removal per loser per atom. Tens of waiters are what this is
%     for; thousands want a channel, which hands each message to one
%     receiver.
%   - a branch needs the caller's variable bindings back. Threads copy terms,
%     so bindings made inside a branch do not escape it.
% Owns:
%   - one seam:atom_added/2 clause and one message queue per live
%     space_await/space_take call, both released when the call leaves
%   - one SWI engine and one completion queue per live spawned future; one
%     bounded normal carrier pool for the process; one transient offload
%     thread per currently blocking oracleIO step; one message queue per live
%     channel; and, once any timer has been used, one timer thread plus one
%     bounded timer pool for the process.
% Guarded by:
%   - '$metta_engine_scheduler' protects task state and carrier creation;
%     '$metta_timers' serialises starting the timer service; one outcome mutex
%     per future claims its terminal value, and one await mutex serialises
%     cancellation, waiter registration and mailbox consumption;
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
%   Future Enhancements: structured concurrency (a scope owning its children),
%     latches and barriers over spaces, and supervision, are tracked in
%     ai-todo-parallel.md B9.2 to B9.4.

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
:- dynamic metta_channel/2.         % Id, Queue
:- dynamic metta_scheduler_task/6.  % Id, Engine, Space, Done, Context, State
:- dynamic metta_scheduler_lane/3.  % Lane, runnable queue, carrier threads
:- dynamic metta_future_waiter/2.   % Future space, suspended scheduler task
:- dynamic metta_channel_waiter/3.  % Channel, send | recv, scheduler task
:- dynamic metta_timer_context/3.   % Future space, repeat policy, Python Context
:- dynamic metta_scheduler_deadline/2. % Token, suspended scheduler task
:- dynamic metta_async_future/4.    % Token, operation name, space, DoneQueue

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
           catch(thread_join(Thread, _), _, true)).

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
%nothing: (get-metatype &future-1) answered Symbol, metta_space_names/1 omitted
%it, and a host codec asking the engine what species the atom is was told a
%symbol, so !(spawn (+ 1 2)) reached Python as a Symbol rather than a
%FutureSpace [measured 2026-08-27]. The timer path below already said this in
%prose. ensure_native_storage_module/2 is idempotent, so the first write is a
%cache hit.
future_space_name(Number, Space) :-
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
metta_scheduler_body(Task, Context, Module, Expr, done) :-
    b_setval('$metta_scheduler_task', Task),
    b_setval('$metta_python_context', Context),
    forall(eval_metta_in_module(Module, Expr, Value),
           engine_yield('$metta_scheduler_answer'(Value))).

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
metta_scheduler_event(Task, _, no) :- !,
    metta_scheduler_finish(Task, done).
metta_scheduler_event(Task, _, throw(Error)) :- !,
    metta_scheduler_finish(Task, error(Error)).
metta_scheduler_event(Task, _, Unexpected) :-
    metta_scheduler_finish(
        Task,
        error(error(metta_scheduler_protocol(Unexpected),
                    context(metta_scheduler_step/2,
                            'a scheduled engine yielded an unknown event')))).

metta_scheduler_write_answer(Task, Value) :-
    metta_scheduler_task(Task, _, Space, _, _, _),
    'add-atom'(Space, Value, _).

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
        retractall(metta_channel_waiter(_, _, Task)),
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
    with_mutex('$metta_engine_scheduler',
               metta_scheduler_cancel_locked(Task, Action, Answer)),
    metta_scheduler_cancel_action(Action).

metta_scheduler_cancel_locked(Task, Action, Answer) :-
    (   retract(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                     queued(_)))
    ->  Action = dispose(Task, Engine, Space, Done, Context), Answer = true
    ;   retract(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                     offloaded(_)))
    ->  Action = dispose(Task, Engine, Space, Done, Context), Answer = true
    ;   retract(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                     suspended(_)))
    ->  Action = dispose(Task, Engine, Space, Done, Context), Answer = true
    ;   retract(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                     running(Lane, Thread)))
    ->  assertz(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                     cancelling(Lane, Thread))),
        Action = none, Answer = false
    ;   retract(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                     wake_pending(Lane, Thread)))
    ->  assertz(metta_scheduler_task(Task, Engine, Space, Done, Context,
                                     cancelling(Lane, Thread))),
        Action = none, Answer = false
    ;   metta_scheduler_task(Task, _, _, _, _, cancelling(_, _))
    ->  Action = none, Answer = false
    ;   Action = none, Answer = false
    ).

metta_scheduler_cancel_action(none).
metta_scheduler_cancel_action(dispose(Task, Engine, Space, Done, Context)) :-
    catch(engine_destroy(Engine), _, true),
    retractall(metta_future_waiter(_, Task)),
    retractall(metta_channel_waiter(_, _, Task)),
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
    (   current_predicate(py_call/2),
        catch(py_call(metta_ops:async_cancel(Token), Cancelled), _, fail),
        ( Cancelled == true ; Cancelled == @(true) )
    ->  Answer = true
    ;   Answer = false
    ).

%A nested spawn forks the scheduled engine's retained Context after any host
%callback mutations made by that engine. A top-level door snapshots the Python
%caller's ambient Context. Falling back to the carrier's ambient context here
%would lose nested changes because carriers deliberately do not inherit task
%state between engine steps.
metta_capture_python_context(Context) :-
    (   nb_current('$metta_python_context', Parent), integer(Parent)
    ->  py_call(metta_ops:fork_context(Parent), Context)
    ;   current_predicate(metta_py_dispatch_det/3)
    ->  py_call(metta_ops:capture_context(), Context)
    ;   Context = none
    ).

metta_capture_python_contexts(Count, Contexts) :-
    (   nb_current('$metta_python_context', Parent), integer(Parent)
    ->  py_call(metta_ops:fork_contexts(Parent, Count), Contexts)
    ;   current_predicate(metta_py_dispatch_det/3)
    ->  py_call(metta_ops:capture_contexts(Count), Contexts)
    ;   length(Contexts, Count),
        maplist(=(none), Contexts)
    ).

metta_release_python_context(none) :- !.
metta_release_python_context(Context) :-
    (   current_predicate(py_call/2)
    ->  catch(py_call(metta_ops:release_context(Context), _), _, true)
    ;   true
    ).

metta_release_python_contexts(Contexts) :-
    maplist(metta_release_python_context, Contexts).

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
    call_cleanup(
        future_body_outcome_(Context, Module, Expr, Space, Outcome),
        metta_release_python_context(Context)),
    metta_future_complete(Space, Done, Outcome).

future_body_outcome_(Context, Module, Expr, Space, Outcome) :-
    setup_call_cleanup(
        metta_python_context_push(Context, Previous),
        (   catch(( forall(eval_metta_in_module(Module, Expr, Value),
                           'add-atom'(Space, Value, _)),
                    Outcome = done ),
                  Error,
                  Outcome = error(Error))
        ->  true
        ;   Outcome = done
        ),
        metta_python_context_pop(Previous)).

future_mutex_(Space, Mutex) :-
    atom_concat('$metta_future_', Space, Mutex).

future_completion_mutex_(Space, Mutex) :-
    atom_concat('$metta_future_completion_', Space, Mutex).

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
        ;   assertz(metta_future_result(Space, Outcome)),
            Claimed = true
        )),
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
thread_await(Space, Out) :-
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

scheduler_future_probe_(_, Space, ready(Outcome, none)) :-
    metta_future_result(Space, Outcome), !.
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
    (   metta_future_result(Space, Recorded)
    ->  Outcome = Recorded, Worker = none
    ;   known_future_(Space, Worker, Done),
        thread_get_message(Done, Received),
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
future_join_(ThreadId) :- catch(thread_join(ThreadId, _), _, true).

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
    future_mutex_(Space, Mutex),
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
cancel_future_status_(missing, _, false) :- !.
cancel_future_status_(pending(Worker, Done), Space, Answer) :-
    cancel_future_worker_(Worker, Space, Done, Answer).

cancel_future_worker_(scheduler(Task), _, _, Answer) :- !,
    metta_scheduler_cancel(Task, Answer).
cancel_future_worker_(async(Token), _, _, Answer) :- !,
    metta_async_cancel(Token, Answer).
cancel_future_worker_(none, _, _, false) :- !.
cancel_future_worker_(ThreadId, Space, Done, Answer) :-
    catch(thread_signal(ThreadId, abort), _, true),
    catch(thread_join(ThreadId, Status), _, Status = unknown),
    future_mutex_(Space, Mutex),
    with_mutex(Mutex, future_cancel_probe_(Space, AfterJoin)),
    (   AfterJoin = terminal(_)
    ->  Answer = false
    ;   Status = exception(unwind(abort))
    ->  metta_future_complete(Space, Done, cancelled),
        Answer = true
    ;   Answer = false
    ).

cancel_repeating_worker_(none) :- !.
cancel_repeating_worker_(ThreadId) :-
    catch(thread_signal(ThreadId, abort), _, true),
    catch(thread_join(ThreadId, _), _, true).

% ----------------------------------------------------------------- channels

%A mailbox any thread may send to and receive from. Unbounded unless a size
%is given, in which case a full channel blocks its senders.
channel_new(Id) :-
    next_metta_handle(Id),
    message_queue_create(Queue, []),
    assertz(metta_channel(Id, Queue)).

channel_new(MaxSize, Id) :-
    must_be(positive_integer, MaxSize),
    next_metta_handle(Id),
    message_queue_create(Queue, [max_size(MaxSize)]),
    assertz(metta_channel(Id, Queue)).

known_channel_(Id, Queue) :-
    (   metta_channel(Id, Queue)
    ->  true
    ;   existence_error(metta_channel, Id)
    ).

%The term is COPIED into the queue, so the receiver gets its own copy and no
%variable binding crosses the boundary. That is message_queue semantics and
%it is why a channel is safe between threads.
channel_send(Id, Term, true) :-
    known_channel_(Id, Queue),
    (   nb_current('$metta_scheduler_task', Task)
    ->  scheduler_channel_send_(Task, Id, Queue, Term)
    ;   thread_send_message(Queue, Term),
        metta_channel_wake(Id, recv)
    ).

%Block until a term arrives.
channel_recv(Id, Term) :-
    known_channel_(Id, Queue),
    (   nb_current('$metta_scheduler_task', Task)
    ->  scheduler_channel_recv_(Task, Id, Queue, infinite, Term)
    ;   thread_get_message(Queue, Term),
        metta_channel_wake(Id, send)
    ).

%Block for at most Timeout seconds; no answer when it expires.
channel_recv(Id, Timeout, Term) :-
    known_channel_(Id, Queue),
    (   nb_current('$metta_scheduler_task', Task)
    ->  get_time(Now),
        Deadline is Now + Timeout,
        scheduler_channel_recv_(Task, Id, Queue, Deadline, Term)
    ;   thread_get_message(Queue, Term, [timeout(Timeout)]),
        metta_channel_wake(Id, send)
    ).

%Take a term if one is waiting, otherwise no answer, never blocking.
channel_try_recv(Id, Term) :-
    known_channel_(Id, Queue),
    thread_get_message(Queue, Term, [timeout(0)]),
    metta_channel_wake(Id, send).

channel_size(Id, Size) :-
    known_channel_(Id, Queue),
    message_queue_property(Queue, size(Size)).

channel_close(Id, true) :-
    known_channel_(Id, Queue),
    retractall(metta_channel(Id, _)),
    catch(message_queue_destroy(Queue), _, true),
    metta_channel_wake(Id, send),
    metta_channel_wake(Id, recv).

%A scheduled bounded send or empty receive follows the same level-triggered
%pattern as Linda waits: register first, probe the mailbox, and suspend the
%engine only while the store condition is false. Counterpart operations wake
%all matching waiters; the queue itself decides which resumed operation wins.
scheduler_channel_send_(Task, Id, Queue, Term) :-
    setup_call_cleanup(
        assertz(metta_channel_waiter(Id, send, Task), Ref),
        scheduler_channel_send_loop_(Task, Id, Queue, Term),
        erase(Ref)).

scheduler_channel_send_loop_(Task, Id, Queue, Term) :-
    (   thread_send_message(Queue, Term, [timeout(0)])
    ->  metta_channel_wake(Id, recv)
    ;   engine_yield('$metta_scheduler_suspend'),
        scheduler_channel_send_loop_(Task, Id, Queue, Term)
    ).

scheduler_channel_recv_(Task, Id, Queue, Deadline, Term) :-
    setup_call_cleanup(
        assertz(metta_channel_waiter(Id, recv, Task), Ref),
        setup_call_cleanup(
            scheduler_deadline_start_(Task, Deadline, DeadlineToken),
            scheduler_channel_recv_loop_(Task, Id, Queue, Deadline, Term),
            scheduler_deadline_cancel_(DeadlineToken)),
        erase(Ref)).

scheduler_channel_recv_loop_(Task, Id, Queue, Deadline, Term) :-
    (   thread_get_message(Queue, Term, [timeout(0)])
    ->  metta_channel_wake(Id, send)
    ;   scheduler_deadline_open_(Deadline)
    ->  engine_yield('$metta_scheduler_suspend'),
        scheduler_channel_recv_loop_(Task, Id, Queue, Deadline, Term)
    ;   fail
    ).

metta_channel_wake(Id, Mode) :-
    findall(Task, metta_channel_waiter(Id, Mode, Task), Tasks),
    maplist(metta_scheduler_wake, Tasks).

% ------------------------------------------------------- bounded worker pools

%A named pool with a fixed number of workers. Submitting more work than the
%pool can run queues it rather than creating unbounded threads, which is the
%difference between a pool and par-map on a huge list.
pool_create(Name, Size, true) :-
    must_be(atom, Name),
    must_be(positive_integer, Size),
    (   current_thread_pool(Name)
    ->  true
    ;   thread_pool_create(Name, Size, [])
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
    findall([Key, Value],
            % policy-inventory-exempt: mechanism-internal; reason=these are the fixed SWI thread_pool_property keys exposed by the pool statistics adapter; evidence=lib/lib_thread/lib_thread.pl:pool_stats/2
            ( member(Key, [size, running, backlog, free]),
              Property =.. [Key, Value],
              catch(thread_pool_property(Name, Property), _, fail) ),
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
%heap in 29ms [measured 2026-08-15, ai-tmp/pool/gran.pl].
%
%Not alarm/4, which is SWI's own timer wheel and would have been the obvious
%choice: its goal runs as a SIGNAL on whichever thread scheduled it, so a
%firing timer would interrupt unrelated evaluation. Running MeTTa evaluation
%from a signal handler is what took SIGSEGV when metta_timeout tried it
%[measured 2026-08-15, ai-tmp/pool/alarm.pl].
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
            catch(thread_join(ThreadId, _), _, true),
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
    call_cleanup(
        ( future_body_outcome_(Context, Module, Expr, Space, Outcome),
          metta_future_complete(Space, Done, Outcome) ),
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
        metta_in_python_context(
            Context,
            catch(forall(eval_metta_in_module(Module, Expr, Value),
                         'add-atom'(Space, Value, _)),
                  Error,
                  ( term_to_atom(Error, Message),
                    'add-atom'(Space, ['Error', Expr, Message], _) ))),
        repeating_body_finished_(Space)).

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
%[source: engine/ext_points.pl:17-19, extensions/python/metta/shim.pl:1277-1281], so the
%write itself delivers. Installing the hook also takes the space off the bulk
%add fast path for as long as the wait lasts, which is what makes per-atom
%events fire at all [source: engine/spaces.pl, metta_add_hooks_idle/1].
space_await(Space, Pattern, Out) :-
    space_wait_(Space, Pattern, infinite, peek, Out).

%The same, giving up after Timeout seconds with no answer.
space_await(Space, Pattern, Timeout, Out) :-
    must_be(number, Timeout),
    space_wait_(Space, Pattern, Timeout, peek, Out).

%Block until an atom unifying with Pattern is in Space, then REMOVE exactly
%one and answer it. Linda's in, and the primitive futures, worker pools and
%rendezvous are one line of MeTTa over.
space_take(Space, Pattern, Out) :-
    space_wait_(Space, Pattern, infinite, take, Out).

space_take(Space, Pattern, Timeout, Out) :-
    must_be(number, Timeout),
    space_wait_(Space, Pattern, Timeout, take, Out).

%Waiting is a promise about the CONTEXT, so a context that declares no event
%delivery is refused here rather than parked on a channel that will never
%report anything [P12.14]. A native space needs no declaration.
space_wait_(Space, Pattern, Timeout, Mode, Out) :-
    metta_require_events(Space, 'be waited on'),
    (   Timeout == infinite
    ->  Deadline = infinite
    ;   get_time(Now),
        Deadline is Now + Timeout
    ),
    (   nb_current('$metta_scheduler_task', Task)
    ->  scheduler_space_wait_(Task, Space, Pattern, Deadline, Mode, Out)
    ;   blocking_space_wait_(Space, Pattern, Deadline, Mode, Out)
    ).

blocking_space_wait_(Space, Pattern, Deadline, Mode, Out) :-
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
        space_claim_(Space, Pattern, Queue, Deadline, Mode, Out),
        ( erase(HookRef),
          catch(message_queue_destroy(Queue), _, true) )).

%A scheduled engine parks itself, not its carrier. The atom-added hook is the
%waker: it marks the task runnable, and the resumed engine rechecks the store
%before trusting the hint. A finite deadline is another one-shot wake record
%on the existing timer heap, so no sleeping thread is introduced.
scheduler_space_wait_(Task, Space, Pattern, Deadline, Mode, Out) :-
    copy_term(Pattern, HookPattern),
    setup_call_cleanup(
        assertz((seam:atom_added(Space, Candidate) :-
                    (   \+ HookPattern \= Candidate
                    ->  metta_scheduler_wake(Task)
                    ;   true
                    )), HookRef),
        setup_call_cleanup(
            scheduler_deadline_start_(Task, Deadline, DeadlineToken),
            scheduler_space_claim_(Task, Space, Pattern, Deadline, Mode, Out),
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

scheduler_space_claim_(Task, Space, Pattern, Deadline, Mode, Out) :-
    copy_term(Pattern, Attempt),
    (   space_already_holds_(Space, Attempt, Candidate)
    ->  scheduler_claim_candidate_(Task, Space, Pattern, Candidate,
                                   Deadline, Mode, Out)
    ;   scheduler_deadline_open_(Deadline)
    ->  engine_yield('$metta_scheduler_suspend'),
        scheduler_space_claim_(Task, Space, Pattern, Deadline, Mode, Out)
    ;   fail
    ).

scheduler_claim_candidate_(_, _, Pattern, Candidate, _, peek, Out) :- !,
    Pattern = Candidate,
    Out = Candidate.
scheduler_claim_candidate_(Task, Space, Pattern, Candidate, Deadline, take,
                           Out) :-
    (   'remove-atom'(Space, Candidate, true)
    ->  Pattern = Candidate, Out = Candidate
    ;   scheduler_space_claim_(Task, Space, Pattern, Deadline, take, Out)
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
%The STORE rather than the queue is the truth. Two takers wake on one atom,
%one 'remove-atom' answers unit and the other answers its not-in-the-space
%error, and the loser goes round; going round re-checks what the space holds
%FIRST, so an atom that arrived while this caller was losing a race is found
%whether it is still queued or not, and a queue entry for an atom somebody
%else took is discarded by the same claim that fails. The removal is the one
%atomic step and everything else is a wake-up, which is what makes
%exactly-one hold with no lock held across the wait.
%
%Each attempt probes with a fresh COPY of the pattern, because a match binds
%and a retry must not inherit the losing attempt's bindings; the caller's own
%variables are bound once, by the winning candidate.
space_claim_(Space, Pattern, Queue, Deadline, Mode, Out) :-
    copy_term(Pattern, Attempt),
    %Check the space only AFTER the hook is live. An atom that is already
    %there answers at once, which is what "wait until this holds" means,
    %and doing it in this order means a write landing between the check and
    %the wait is caught by the hook rather than missed. Checking first and
    %installing after loses exactly that write, which is what made a
    %spawned writer race this and win.
    (   space_already_holds_(Space, Attempt, Candidate)
    ->  true
    ;   await_matching_(Queue, Attempt, Deadline, Candidate)
    ),
    (   Mode == peek
    ->  Pattern = Candidate, Out = Candidate
    ;   'remove-atom'(Space, Candidate, true)
    ->  Pattern = Candidate, Out = Candidate
    ;   space_claim_(Space, Pattern, Queue, Deadline, Mode, Out)
    ).

space_already_holds_(Space, Pattern, Out) :-
    current_metta_module(Module),
    eval_metta_in_module(Module, [match, Space, Pattern, Pattern], Out).

%The hook test is deliberately loose (unifiable, binding nothing), so a
%candidate can still fail the real unification here; keep waiting when it does.
await_matching_(Queue, Pattern, infinite, Out) :-
    !,
    repeat,
      thread_get_message(Queue, Candidate),
      Pattern = Candidate,
      !,
      Out = Candidate.
%ONE deadline for the whole call, computed once by space_wait_/5 and carried
%through every claim retry, not one per candidate: thread_get_message/3 FAILS
%when its timeout expires, so a repeat loop around a per-call timeout would
%restart the clock on every non-matching write and never give up.
await_matching_(Queue, Pattern, Deadline, Out) :-
    await_until_(Queue, Pattern, Deadline, Out).

await_until_(Queue, Pattern, Deadline, Out) :-
    get_time(Now),
    Remaining is Deadline - Now,
    Remaining > 0,
    thread_get_message(Queue, Candidate, [timeout(Remaining)]),
    (   Pattern = Candidate
    ->  Out = Candidate
    ;   await_until_(Queue, Pattern, Deadline, Out)
    ).

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
