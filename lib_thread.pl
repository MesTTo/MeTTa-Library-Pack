% Purpose: concurrency for MeTTa over SWI's own primitives. Parallel map,
%   filter and quantifiers ride library(thread)'s concurrent_maplist/3 and
%   concurrent_forall/2, racing rides first_solution/3, futures are threads
%   with a result mailbox, and channels are message queues. Nothing here
%   hand-rolls a scheduler. Every predicate follows the compiled convention,
%   inputs then one output.
% Assumes:
%   - eval_metta_in_module/3 in engine/translator.pl evaluates one MeTTa
%     expression under a named space's module, which is what a worker thread
%     needs because SWI global variables are thread-local [source:
%     engine/translator.pl, eval_metta_in_module/3]
%   - concurrent_maplist/3 already sizes its pool to min(cpu_count, length)
%     and calls each goal once [source 2026-08-15:
%     /usr/lib/swi-prolog/library/thread.pl, workers/2 and once_in_module/5]
% Guarantees:
%   - par-map answers one result per element, in the input list's order,
%     because concurrent_maplist/3 preserves position [tested: lib_thread:par_map_answers_one_result_per_element_in_order]
%   - a future holds its expression's whole ANSWER SET, because it is a space
%     the evaluating thread adds every answer to; awaiting twice answers the
%     same set without blocking a second time [tested: lib_thread:a_future_holds_the_whole_answer_set]
%   - a channel send never loses a term: message queues copy, so the receiver
%     gets its own copy and variable bindings do not cross [tested: lib_thread:a_channel_round_trips_a_term, a_channel_carries_a_term_between_threads]
%   - timers cost no threads: one timer thread and one bounded pool serve every
%     timer in the process [assumed 2026-08-16: no test counts threads around an armed timer]
% Fails when:
%   - the work per element is small. A parallel map over cheap elements pays
%     thread creation for nothing; measure before reaching for it.
%   - a branch needs the caller's variable bindings back. Threads copy terms,
%     so bindings made inside a branch do not escape it.
% Owns:
%   - one OS thread per live spawned future until it is awaited or cancelled,
%     one message queue per live channel until it is closed, and, once any
%     timer has been used, one timer thread plus one bounded pool for the life
%     of the process.
% Guarded by:
%   - '$petta_thread_ids' serialises handle allocation; '$petta_timers'
%     serialises starting the timer service; one mutex per future serialises
%     that future's await so two awaiters cannot both block on its mailbox.
% Decides:
%   - a future IS a space, so it carries an answer SET rather than one value.
%     A MeTTa expression has an answer set, and a future answering only the
%     first would discard the evaluation model at the concurrency boundary.
%   - a timer is a future that starts later, so setTimeout and clearTimeout are
%     spawn-with-a-delay and thread-cancel rather than a separate handle type.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: structured concurrency (a scope owning its children),
%     latches and barriers over spaces, and supervision, are tracked in
%     ai-todo-parallel.md B9.2 to B9.4.

:- use_module(library(thread)).
:- use_module(library(thread_pool)).
:- use_module(library(error)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(aggregate)).
:- use_module(library(heaps)).

:- dynamic petta_handle_counter/1.
:- dynamic petta_future/3.          % Space, ThreadId, DoneQueue
:- dynamic petta_future_result/2.   % Space, done | cancelled | error(Error)
:- dynamic petta_channel/2.         % Id, Queue

petta_handle_counter(0).

%Handles are small integers rather than blobs so they print, compare and
%cross the Python boundary as ordinary MeTTa values.
next_petta_handle(Id) :-
    with_mutex('$petta_thread_ids',
               ( retract(petta_handle_counter(N)),
                 Id is N + 1,
                 assertz(petta_handle_counter(Id)) )).

% ------------------------------------------------------- parallel over data

%Evaluate (F Element) for each element, one answer each, positions preserved.
par_map(F, List, Out) :-
    must_be(list, List),
    current_metta_module(Module),
    concurrent_maplist(par_apply_(Module, F), List, Out).

par_apply_(Module, F, Element, Result) :-
    eval_metta_in_module(Module, [F, Element], Result).

%Keep the elements for which (F Element) answers True.
par_filter(F, List, Out) :-
    must_be(list, List),
    current_metta_module(Module),
    concurrent_maplist(par_true_(Module, F), List, Flags),
    keep_flagged_(List, Flags, Out).

par_true_(Module, F, Element, Flag) :-
    (   eval_metta_in_module(Module, [F, Element], Answer),
        Answer == true
    ->  Flag = true
    ;   Flag = false
    ).

keep_flagged_([], [], []).
keep_flagged_([E|Es], [true|Fs], [E|Out]) :- !, keep_flagged_(Es, Fs, Out).
keep_flagged_([_|Es], [_|Fs], Out) :- keep_flagged_(Es, Fs, Out).

%True when (F Element) answers True for every element, False otherwise.
%concurrent_forall/2 stops the remaining workers as soon as one fails.
par_forall(F, List, Answer) :-
    must_be(list, List),
    current_metta_module(Module),
    (   concurrent_forall(member(Element, List),
                          par_true_checked_(Module, F, Element))
    ->  Answer = true
    ;   Answer = false
    ).

par_true_checked_(Module, F, Element) :-
    eval_metta_in_module(Module, [F, Element], Answer),
    Answer == true.

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
    (   List == []
    ->  Answer = false
    ;   concurrent_forall(member(Element, List),
                          \+ par_true_checked_(Module, F, Element))
    ->  Answer = false
    ;   Answer = true
    ).

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
    message_queue_create(Queue),
    setup_call_cleanup(
        race_start_(Module, Exprs, Queue, Threads),
        race_collect_(Queue, Count, Out),
        race_stop_(Threads, Queue)).

race_start_(Module, Exprs, Queue, Threads) :-
    findall(Thread,
            ( member(Expr, Exprs),
              thread_create(race_body_(Module, Expr, Queue), Thread, []) ),
            Threads).

race_body_(Module, Expr, Queue) :-
    (   catch((   eval_metta_in_module(Module, Expr, Value)
              ->  Message = ok(Value)
              ;   Message = lost
              ),
              Error,
              Message = error(Error))
    ->  true
    ;   Message = lost
    ),
    thread_send_message(Queue, Message).

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

race_stop_(Threads, Queue) :-
    forall(member(Thread, Threads),
           catch(thread_signal(Thread, abort), _, true)),
    forall(member(Thread, Threads),
           catch(thread_join(Thread, _), _, true)),
    catch(message_queue_destroy(Queue), _, true).

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
future_space_name(Number, Space) :-
    atom_concat('&future-', Number, Space).

thread_spawn(Expr, Space) :-
    current_metta_module(Module),
    next_petta_handle(Number),
    future_space_name(Number, Space),
    message_queue_create(Done, [max_size(1)]),
    thread_create(future_body_(Module, Expr, Space, Done), ThreadId, []),
    assertz(petta_future(Space, ThreadId, Done)).

%forall/2 over the evaluation, so EVERY answer reaches the space rather than
%just the first. An expression with no answers leaves the space empty, which
%is the honest reading of "produced nothing".
future_body_(Module, Expr, Space, Done) :-
    (   catch(( forall(eval_metta_in_module(Module, Expr, Value),
                       'add-atom'(Space, Value, _)),
                Outcome = done ),
              Error,
              Outcome = error(Error))
    ->  true
    ;   Outcome = done
    ),
    thread_send_message(Done, Outcome).

future_mutex_(Space, Mutex) :-
    atom_concat('$petta_future_', Space, Mutex).

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
    future_mutex_(Space, Mutex),
    with_mutex(Mutex, future_outcome_(Space, Outcome)).

future_outcome_(Space, Outcome) :-
    (   petta_future_result(Space, Recorded)
    ->  Outcome = Recorded
    ;   known_future_(Space, ThreadId, Done),
        thread_get_message(Done, Received),
        catch(thread_join(ThreadId, _), _, true),
        assertz(petta_future_result(Space, Received)),
        Outcome = Received
    ).

known_future_(Space, ThreadId, Done) :-
    (   petta_future(Space, ThreadId, Done)
    ->  true
    ;   existence_error(petta_future, Space)
    ).

%Whether the future has finished, without waiting for it.
thread_settled(Space, Answer) :-
    (   petta_future_result(Space, _)
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
    cancel_timer_(Space),
    (   petta_future_result(Space, _)
    ->  Answer = false
    ;   \+ petta_future(Space, _, _)
    ->  Answer = true                 % a timer that had not started yet
    ;   known_future_(Space, ThreadId, _),
        catch(thread_signal(ThreadId, abort), _, true),
        (   catch(thread_join(ThreadId, _), _, true),
            \+ catch(thread_property(ThreadId, status(running)), _, fail)
        ->  assertz(petta_future_result(Space, cancelled)),
            Answer = true
        ;   Answer = false
        )
    ).

% ----------------------------------------------------------------- channels

%A mailbox any thread may send to and receive from. Unbounded unless a size
%is given, in which case a full channel blocks its senders.
channel_new(Id) :-
    next_petta_handle(Id),
    message_queue_create(Queue, []),
    assertz(petta_channel(Id, Queue)).

channel_new(MaxSize, Id) :-
    must_be(positive_integer, MaxSize),
    next_petta_handle(Id),
    message_queue_create(Queue, [max_size(MaxSize)]),
    assertz(petta_channel(Id, Queue)).

known_channel_(Id, Queue) :-
    (   petta_channel(Id, Queue)
    ->  true
    ;   existence_error(petta_channel, Id)
    ).

%The term is COPIED into the queue, so the receiver gets its own copy and no
%variable binding crosses the boundary. That is message_queue semantics and
%it is why a channel is safe between threads.
channel_send(Id, Term, true) :-
    known_channel_(Id, Queue),
    thread_send_message(Queue, Term).

%Block until a term arrives.
channel_recv(Id, Term) :-
    known_channel_(Id, Queue),
    thread_get_message(Queue, Term).

%Block for at most Timeout seconds; no answer when it expires.
channel_recv(Id, Timeout, Term) :-
    known_channel_(Id, Queue),
    thread_get_message(Queue, Term, [timeout(Timeout)]).

%Take a term if one is waiting, otherwise no answer, never blocking.
channel_try_recv(Id, Term) :-
    known_channel_(Id, Queue),
    thread_get_message(Queue, Term, [timeout(0)]).

channel_size(Id, Size) :-
    known_channel_(Id, Queue),
    message_queue_property(Queue, size(Size)).

channel_close(Id, true) :-
    known_channel_(Id, Queue),
    retractall(petta_channel(Id, _)),
    catch(message_queue_destroy(Queue), _, true).

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
    ;   existence_error(petta_thread_pool, Name)
    ),
    current_metta_module(Module),
    next_petta_handle(Number),
    future_space_name(Number, Space),
    message_queue_create(Done, [max_size(1)]),
    thread_create_in_pool(Name, future_body_(Module, Expr, Space, Done),
                          ThreadId, []),
    assertz(petta_future(Space, ThreadId, Done)).

pool_stats(Name, Stats) :-
    (   current_thread_pool(Name)
    ->  true
    ;   existence_error(petta_thread_pool, Name)
    ),
    findall([Key, Value],
            % policy-inventory-exempt: mechanism-internal; reason=these are the fixed SWI thread_pool_property keys exposed by the pool statistics adapter; evidence=lib/lib_thread.pl:pool_stats/2
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
:- dynamic petta_timer_cancelled/1.

petta_timer_queue(petta_timer_requests).
petta_timer_pool(petta_timer_workers).

%The timer thread and its pool start on first use and outlive every timer.
ensure_timer_service :-
    with_mutex('$petta_timers', ensure_timer_service_locked).

ensure_timer_service_locked :-
    petta_timer_queue(Queue),
    (   is_message_queue(Queue)
    ->  true
    ;   message_queue_create(_, [alias(Queue)])
    ),
    petta_timer_pool(Pool),
    (   current_thread_pool(Pool)
    ->  true
    ;   cpu_count(Cores),
        Workers is max(1, min(Cores, 8)),
        thread_pool_create(Pool, Workers, [])
    ),
    (   catch(thread_property(petta_timer, status(running)), _, fail)
    ->  true
    ;   thread_create(timer_loop, _, [alias(petta_timer), detached(true)])
    ).

timer_loop :-
    empty_heap(Heap),
    timer_loop_(Heap).

%Wait exactly until the earliest deadline, or indefinitely when nothing is
%scheduled. A request arriving early simply preempts the wait, so adding a
%sooner timer takes effect immediately instead of after the current sleep.
timer_loop_(Heap) :-
    petta_timer_queue(Queue),
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

timer_request_(schedule(Deadline, Timer), Heap, Next) :-
    add_to_heap(Heap, Deadline, Timer, Next).

%Cancelled timers are marked rather than deleted from the heap: deletion is
%O(n) in a pairing heap and the check at fire time is O(1).
timer_fire_(Heap, Next) :-
    get_from_heap(Heap, _Deadline, Timer, Rest),
    Timer = timer(Space, Module, Expr, Repeat),
    (   petta_timer_cancelled(Space)
    ->  Next = Rest
    ;   timer_dispatch_(Space, Module, Expr, Repeat),
        (   Repeat = every(Period)
        ->  get_time(Now),
            Again is Now + Period,
            add_to_heap(Rest, Again, Timer, Next)
        ;   Next = Rest
        )
    ).

%The work runs on the pool, never on the timer thread: one slow expression
%would otherwise delay every other timer behind it.
timer_dispatch_(Space, Module, Expr, Repeat) :-
    petta_timer_pool(Pool),
    (   petta_future(Space, _, Existing)
    ->  Done = Existing
    ;   message_queue_create(Done, [max_size(1)])
    ),
    (   Repeat == once
    ->  Body = future_body_(Module, Expr, Space, Done)
    ;   Body = repeating_body_(Module, Expr, Space)
    ),
    (   catch(thread_create_in_pool(Pool, Body, ThreadId, []), _, fail)
    ->  retractall(petta_future(Space, _, _)),
        assertz(petta_future(Space, ThreadId, Done))
    ;   true
    ).

%A repeating timer never completes, so it must NOT post a completion: the
%mailbox holds one message and a second post would block a pool worker
%forever. Consume a repeating timer with await-atom on its space instead.
%
%An error has nowhere to be raised to, so it is written into the space as an
%(Error <expr> <message>) atom, HE's own error shape. The consumer sees it by
%matching, which is how it would see any other answer.
repeating_body_(Module, Expr, Space) :-
    catch(forall(eval_metta_in_module(Module, Expr, Value),
                 'add-atom'(Space, Value, _)),
          Error,
          ( term_to_atom(Error, Message),
            'add-atom'(Space, ['Error', Expr, Message], _) )).

cancel_timer_(Space) :-
    (   petta_timer_cancelled(Space)
    ->  true
    ;   assertz(petta_timer_cancelled(Space))
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
    next_petta_handle(Number),
    future_space_name(Number, Space),
    %The future exists from the moment the timer is SCHEDULED, not from when it
    %fires, so awaiting a pending timer waits for it and settled? answers false
    %instead of both raising "no such future".
    message_queue_create(Done, [max_size(1)]),
    assertz(petta_future(Space, none, Done)),
    get_time(Now),
    Deadline is Now + Seconds,
    petta_timer_queue(Queue),
    thread_send_message(Queue,
                        schedule(Deadline, timer(Space, Module, Expr, Repeat))).

% ------------------------------------------------ blocking on a space change

%Block until an atom unifying with Pattern is added to Space, and answer it
%with the caller's variables bound.
%
%Event-driven, not polled: this installs a clause on the engine's own
%metta_on_atom_added/2 extension point, the same one Python subscriptions use
%[source: engine/ext_points.pl:17-19, bindings/python/petta/shim.pl:1277-1281], so the
%write itself delivers. Installing the hook also takes the space off the bulk
%add fast path for as long as the wait lasts, which is what makes per-atom
%events fire at all [source: engine/spaces.pl, metta_add_hooks_idle/1].
space_await(Space, Pattern, Out) :-
    space_await_(Space, Pattern, infinite, Out).

%The same, giving up after Timeout seconds with no answer.
space_await(Space, Pattern, Timeout, Out) :-
    must_be(number, Timeout),
    space_await_(Space, Pattern, Timeout, Out).

space_await_(Space, Pattern, Timeout, Out) :-
    message_queue_create(Queue),
    %The clause gets its own copy of the pattern, so its variables are fresh
    %on every write and testing a candidate never binds the caller's.
    copy_term(Pattern, HookPattern),
    setup_call_cleanup(
        assertz((metta_on_atom_added(Space, Candidate) :-
                    (   \+ HookPattern \= Candidate
                    ->  thread_send_message(Queue, Candidate)
                    ;   true
                    )), HookRef),
        %Check the space only AFTER the hook is live. An atom that is already
        %there answers at once, which is what "wait until this holds" means,
        %and doing it in this order means a write landing between the check and
        %the wait is caught by the hook rather than missed. Checking first and
        %installing after loses exactly that write, which is what made a
        %spawned writer race this and win.
        (   space_already_holds_(Space, Pattern, Out)
        ->  true
        ;   await_matching_(Queue, Pattern, Timeout, Out)
        ),
        ( erase(HookRef),
          catch(message_queue_destroy(Queue), _, true) )).

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
%One deadline for the whole call, not one per candidate: thread_get_message/3
%FAILS when its timeout expires, so a repeat loop around it would restart the
%clock on every non-matching write and never give up.
await_matching_(Queue, Pattern, Timeout, Out) :-
    get_time(Now),
    Deadline is Now + Timeout,
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
