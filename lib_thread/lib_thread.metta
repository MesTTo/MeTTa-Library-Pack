; Purpose: publish parallel data operations, M:N engine futures, timers,
;   channels, pools, Linda waits and locks over SWI-Prolog primitives.
; Guarantees: scope-defer transfers cleanup with a returned owned value;
;   drop-space releases through the scope-aware native door
;   [tested: lib_thread_scope_deferred; commit=9b0a084e534ddf7dd67980ad84c27c8279b877f1].
; Guarantees: scope-defer can hold a query for current dependencies, read after
;   children join when its value is kept [tested: lib_thread_scope_deferred;
;   commit=WORKTREE].
; Guarantees:
;   - scope joins children and returns their retained spaces; capture holds an
;     expression in its current space [tested: lib_thread_scope; commit=c6e1198c490a824b96f6fc6e1c0622a542917024]
;   - spawn computations multiplex as suspended engines over a bounded carrier
;     pool; await and channel backpressure wake engines instead of parking
;     carriers [tested: tests/prolog/suites/libraries/lib_thread.plt; commit=39092863ae34184a9f955f185ff57c1ff177ec40]
;
;(scope $expr) joins children, cancels siblings on failure and releases owned
;spaces, channels, timers and pools. Spaces in its result transfer to its parent.
;(capture $expr) returns (evalc $expr <current-space>) with $expr held.
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
;the end. A scheduled await suspends its engine until completion, so it leaves
;the small carrier pool free. (settled? $f) asks without waiting, (cancel $f)
;stops one running. True acknowledges a stopped body; False means it finished.
;An unknown future refuses rather than claiming completion.
;A foreign call must return before its engine can acknowledge cancellation.
;
;Timers, which are futures that start later. (after $seconds $expr) is
;setTimeout and (every $seconds $expr) is setInterval; both answer a space the
;answers will appear in, and both are stopped with the same (cancel $f) that
;stops a spawn, so there is no separate clearTimeout. Consume a repeating timer
;with await-atom rather than await, since it never finishes. A slow repeating
;body coalesces later ticks rather than overlapping itself. Timers cost no
;per-timer threads: one timer thread and one bounded pool serve every timer,
;and a saturated body pool does not delay scheduler deadline wakeups.
;
;Channels are FIFO spaces any thread may use. (channel) answers a space,
;(channel $max-size) one that blocks its senders when full. (send $ch $term),
;(recv $ch) blocking, (recv $ch $seconds) with a deadline, (try-recv $ch)
;never blocking, (channel-size $ch), (channel-close $ch). A sent term is
;COPIED, so the receiver gets its own copy and no variable binding crosses.
;Inside a spawned engine, an empty receive or full send suspends the engine.
;add-atom, remove-atom and get-atoms operate on that same buffer.
;
;Pools, for when the fan-out is bigger than the machine. (pool $name $size)
;creates one, (submit $name $expr) answers the same handle await takes, so
;pooled work and spawned work are interchangeable. (pool-stats $name) and
;(pool-destroy $name) round it out.
;
;Blocking binds, Linda's two. (peek-atom $space $pattern) blocks until an atom
;unifying with $pattern is in $space and answers it with your variables bound,
;LEAVING it there, which is Linda's rd; (take-atom $space $pattern) does the
;same and REMOVES exactly one, which is Linda's in. Under contention two takers
;never get the same atom: the removal is the atomic step and a loser goes back
;to waiting. Both are event-driven through the engine's write hooks, not polls,
;and both take an optional $seconds deadline. (await-atom ...) is the older
;name for peek-atom and stays as sugar. The non-blocking pair needs nothing new:
;(match ...) is Linda's rdp and (remove-atom ...) is its inp.
;
;(space_await_where $space $pattern $guard) and (space_take_where ...) are the
;same two with match's where-guard: a term over the pattern's variables,
;evaluated once a candidate binds them and required true, so "wait for a job
;whose priority is above five" is one call rather than a wait and a re-wait
;around every rejection with the deadline restarting each time. The guard runs
;BEFORE a take removes anything, so a candidate it rejects stays for whoever
;does want it. They carry their own names because a guard and a $seconds
;deadline would both sit third and nothing could tell them apart; the host
;surfaces spell it peek(where=) and take(where=), which is where match's own
;guard lives too.
;
;This is the blackboard reading of a space: agents wait on the space instead of
;polling it, and a worker pool is (take-atom &jobs (job $x)) in a loop.
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
   scope_body scope_defer space_drop capture
   space_await space_take space_await_where space_take_where
   with_lock cpu_count thread_count))

;Anything that defers evaluation has to say so. MeTTa evaluates arguments, so
;without these declarations (par-race ((slow 1) (fast 2))) would compute both
;branches first and race two finished values, and (spawn $expr) would evaluate
;$expr on the calling thread and hand the answer to a thread with nothing left
;to do. Atom is the parameter type that stops that [source: lib/lib_he/lib_he.metta,
;which declares the same for its assertion forms].
(: par-race (-> Atom %Undefined%))
(: spawn (-> Atom %Undefined%))
(: scope (-> Atom %Undefined%))
(: capture (-> Atom Atom))
(: scope_body (-> Atom %Undefined%))
(: scope-defer (-> %Undefined% Atom Bool))
(: scope_defer (-> %Undefined% Atom Bool))
(: scope-defer (-> %Undefined% Atom Atom Bool))
(: scope_defer (-> %Undefined% Atom Atom Bool))
(: drop-space (-> SpaceType Bool))
(: space_drop (-> SpaceType Bool))
(: submit (-> %Undefined% Atom %Undefined%))
(: with-lock (-> %Undefined% Atom %Undefined%))
(: after (-> Number Atom %Undefined%))
(: every (-> Number Atom %Undefined%))
(: await-atom (-> %Undefined% Atom %Undefined%))
(: await-atom (-> %Undefined% Atom Number %Undefined%))
(: peek-atom (-> %Undefined% Atom %Undefined%))
(: peek-atom (-> %Undefined% Atom Number %Undefined%))
(: take-atom (-> %Undefined% Atom %Undefined%))
(: take-atom (-> %Undefined% Atom Number %Undefined%))

;The public equations delegate to imported Prolog operations.  Their own
;declarations must carry the same held positions because that delegation is a
;second application boundary: without these rows `(par-race $exprs)` receives
;$exprs as written and then `par_race` evaluates the whole branch list before
;there is anything left to race.  The same rule preserves deferred futures,
;timer bodies, lock bodies, and Linda patterns.
(: par_race (-> Atom %Undefined%))
(: thread_spawn (-> Atom %Undefined%))
(: pool_submit (-> %Undefined% Atom %Undefined%))
(: with_lock (-> %Undefined% Atom %Undefined%))
(: timer_after (-> Number Atom %Undefined%))
(: timer_every (-> Number Atom %Undefined%))
(: space_await (-> %Undefined% Atom %Undefined%))
(: space_await (-> %Undefined% Atom Number %Undefined%))
(: space_take (-> %Undefined% Atom %Undefined%))
(: space_take (-> %Undefined% Atom Number %Undefined%))
;The guarded pair holds BOTH the pattern and the guard: a guard evaluated
;before the wait is a guard evaluated against unbound variables. They carry
;their own names rather than another arity of peek-atom, because a guard and
;a timeout would both sit third and nothing could tell (peek-atom &s (job $x) 5)
;apart. This is match/4's arrangement too: MeTTa's match has no guard arity
;either, and where= is the host surface's word over the engine's guarded query.
(: space_await_where (-> %Undefined% Atom Atom %Undefined%))
(: space_await_where (-> %Undefined% Atom Atom Number %Undefined%))
(: space_take_where (-> %Undefined% Atom Atom %Undefined%))
(: space_take_where (-> %Undefined% Atom Atom Number %Undefined%))

(= (par-map $f $list) (par_map $f $list))
(= (par-filter $f $list) (par_filter $f $list))
(= (par-forall $f $list) (par_forall $f $list))
(= (par-any $f $list) (par_any $f $list))
(= (par-race $exprs) (par_race $exprs))

(= (spawn $expr) (thread_spawn $expr))
(= (scope $expr) (scope_body $expr))
(= (scope-defer $value $cleanup) (scope_defer $value $cleanup))
(= (scope-defer $value $cleanup $dependencies) (scope_defer $value $cleanup $dependencies))
(= (drop-space $space) (space_drop $space))
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

;Linda's rd, and await-atom as the documented older spelling of it.
(= (peek-atom $space $pattern) (space_await $space $pattern))
(= (peek-atom $space $pattern $seconds) (space_await $space $pattern $seconds))
(= (await-atom $space $pattern) (peek-atom $space $pattern))
(= (await-atom $space $pattern $seconds) (peek-atom $space $pattern $seconds))

;Linda's in: wait, then remove exactly one.
(= (take-atom $space $pattern) (space_take $space $pattern))
(= (take-atom $space $pattern $seconds) (space_take $space $pattern $seconds))

(= (with-lock $name $expr) (with_lock $name $expr))

(= (cpu-count) (cpu_count))
(= (thread-count) (thread_count))

(@doc scope (@desc "Join children and release resources created by the body; child failure cancels siblings; returned spaces transfer to the enclosing scope") (@params ((@param "the held body"))) (@return "each body answer"))
(@doc capture (@desc "Hold an expression with its current evaluation space as an evalc value") (@params ((@param "the held expression"))) (@return "(evalc expression space)"))
(@doc scope-defer (@desc "Register held cleanup in the current scope; returning its value transfers cleanup and current dependencies to the enclosing scope; outside a scope no cleanup is registered. An optional held dependency query must terminate without side effects. Close evaluates it after children join; an error retains resources for retry. Cleanup runs in reverse acquisition order.") (@params ((@param "the owned ground value") (@param "the held cleanup expression in its defining space") (@param "optional held query yielding current dependency values"))) (@return "True"))
(@doc scope_defer (@desc "Native spelling of scope-defer") (@params ((@param "the owned ground value") (@param "the held cleanup expression") (@param "optional held query yielding current dependency values"))) (@return "True"))
(@doc drop-space (@desc "Release a space through its scope owner, including owned children and deferred cleanup") (@params ((@param "the space to release"))) (@return "True"))
(@doc space_drop (@desc "Native spelling of drop-space") (@params ((@param "the space to release"))) (@return "True"))
