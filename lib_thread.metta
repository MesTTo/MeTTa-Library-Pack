;Concurrency for MeTTa, over the engine's own SWI primitives. Four kinds of
;thing live here and they compose.
;
;Parallel evaluation over a list. (par-map $f $list) evaluates ($f $element)
;for every element at once and answers one result per element, in the input
;list's order. (par-filter $f $list) keeps the elements for which $f answers
;True. (par-forall $f $list) and (par-any $f $list) are the quantifiers, and
;both stop early: par-forall drops the rest as soon as one element fails,
;par-any as soon as one succeeds. (par-race $exprs) evaluates every expression
;at once and answers whichever finishes first, killing the losers.
;
;Futures, and a future IS A SPACE. (spawn $expr) starts evaluating now and
;answers a space; every answer the expression produces is added to it, and
;(await $f) waits for the end and then yields them all. So
;(collapse (await (spawn (superpose (1 2 3))))) is (1 2 3), not (1): an
;expression has an answer set and so does its future. Because the handle is an
;ordinary space you can also (match $f ...) it, (get-atoms $f) it, or
;(await-atom $f $pattern) to take answers as they land instead of waiting for
;the end. (settled? $f) asks without waiting, (cancel $f) stops one running.
;
;Timers, which are futures that start later. (after $seconds $expr) is
;setTimeout and (every $seconds $expr) is setInterval; both answer a space the
;answers will appear in, and both are stopped with the same (cancel $f) that
;stops a spawn, so there is no separate clearTimeout. Consume a repeating timer
;with await-atom rather than await, since it never finishes. Timers cost no
;threads: one timer thread and one bounded pool serve every timer.
;
;Channels, which are mailboxes any thread may use. (channel) answers a handle,
;(channel $max-size) one that blocks its senders when full. (send $ch $term),
;(recv $ch) blocking, (recv $ch $seconds) with a deadline, (try-recv $ch)
;never blocking, (channel-size $ch), (channel-close $ch). A sent term is
;COPIED, so the receiver gets its own copy and no variable binding crosses.
;
;Pools, for when the fan-out is bigger than the machine. (pool $name $size)
;creates one, (submit $name $expr) answers the same handle await takes, so
;pooled work and spawned work are interchangeable. (pool-stats $name) and
;(pool-destroy $name) round it out.
;
;Two more. (await-atom $space $pattern) blocks until an atom unifying with
;$pattern is added to $space and answers it with your variables bound; it is
;event-driven through the engine's write hooks, not a poll, and
;(await-atom $space $pattern $seconds) gives up after a deadline. This is the
;blackboard reading of a space: agents wait on the space instead of polling it.
;
;(with-lock $name $expr) holds a named lock while evaluating $expr and, unlike
;the built-in with_mutex, does NOT collapse $expr to its first answer. The
;price is that a caller who abandons the call with answers still pending holds
;the lock until it is cut, so enumerate fully or wrap it in once.
;
;(cpu-count) and (thread-count) report what the machine is doing.

!(import! &self (library lib_import))
!(import_prolog_functions_from_file (library lib_thread.pl)
  (par_map par_filter par_forall par_any par_race
   thread_spawn thread_await thread_settled thread_cancel
   channel_new channel_send channel_recv channel_try_recv
   channel_size channel_close
   pool_create pool_submit pool_stats pool_destroy
   timer_after timer_every
   space_await with_lock cpu_count thread_count))

;Anything that defers evaluation has to say so. MeTTa evaluates arguments, so
;without these declarations (par-race ((slow 1) (fast 2))) would compute both
;branches first and race two finished values, and (spawn $expr) would evaluate
;$expr on the calling thread and hand the answer to a thread with nothing left
;to do. Atom is the parameter type that stops that [source: lib/lib_he.metta,
;which declares the same for its assertion forms].
(: par-race (-> Atom %Undefined%))
(: spawn (-> Atom %Undefined%))
(: submit (-> %Undefined% Atom %Undefined%))
(: with-lock (-> %Undefined% Atom %Undefined%))
(: after (-> Number Atom %Undefined%))
(: every (-> Number Atom %Undefined%))
(: await-atom (-> %Undefined% Atom %Undefined%))
(: await-atom (-> %Undefined% Atom Number %Undefined%))

(= (par-map $f $list) (par_map $f $list))
(= (par-filter $f $list) (par_filter $f $list))
(= (par-forall $f $list) (par_forall $f $list))
(= (par-any $f $list) (par_any $f $list))
(= (par-race $exprs) (par_race $exprs))

(= (spawn $expr) (thread_spawn $expr))
(= (await $handle) (thread_await $handle))
(= (settled? $handle) (thread_settled $handle))
(= (cancel $handle) (thread_cancel $handle))

(= (channel) (channel_new))
(= (channel $max-size) (channel_new $max-size))
(= (send $ch $term) (channel_send $ch $term))
(= (recv $ch) (channel_recv $ch))
(= (recv $ch $seconds) (channel_recv $ch $seconds))
(= (try-recv $ch) (channel_try_recv $ch))
(= (channel-size $ch) (channel_size $ch))
(= (channel-close $ch) (channel_close $ch))

(= (pool $name $size) (pool_create $name $size))
(= (submit $name $expr) (pool_submit $name $expr))
(= (pool-stats $name) (pool_stats $name))
(= (pool-destroy $name) (pool_destroy $name))

(= (after $seconds $expr) (timer_after $seconds $expr))
(= (every $seconds $expr) (timer_every $seconds $expr))

(= (await-atom $space $pattern) (space_await $space $pattern))
(= (await-atom $space $pattern $seconds) (space_await $space $pattern $seconds))

(= (with-lock $name $expr) (with_lock $name $expr))

(= (cpu-count) (cpu_count))
(= (thread-count) (thread_count))
