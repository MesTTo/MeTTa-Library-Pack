# lib_thread: concurrency for MeTTa

This library gives you parallel evaluation, futures, channels, worker pools,
and a way to block until a space changes. `spawn` computations are suspended
SWI engines multiplexed over at most four long-lived carrier threads. A space
write, future completion or channel state change wakes a parked engine without
parking one of those carriers.

Load it the usual way:

```metta
!(import! &self (library lib_thread))
```

## Running a function over a list, in parallel

`par-map` evaluates your function for every element at once and answers one
result per element, in the input list's order.

```metta
(= (inc $x) (+ $x 1))

!(par-map inc (1 2 3 4))
; (2 3 4 5)
```

Order is preserved no matter which element finishes first, so you can rely on
positions lining up with the input.

`par-filter` keeps the elements your function answers `True` for:

```metta
(= (big? $x) (> $x 2))

!(par-filter big? (1 2 3 4 5))
; (3 4 5)
```

And the two quantifiers, both of which stop early:

```metta
!(par-forall big? (3 4 5))    ; True
!(par-forall big? (1 4 5))    ; False, and elements 4 and 5 are dropped
!(par-any big? (1 2 9))       ; True, and nothing after 9 is evaluated
```

A caution worth stating once. These pay one thread per element, so they are a
win when the work per element is real and a loss when it is a single
arithmetic operation. Measure before reaching for them.

## Racing

`par-race` evaluates every expression at once and answers whichever finishes
first. The losers are stopped.

```metta
(= (slow $x) (let $_ (spin 400000) $x))

!(par-race ((slow 1) (inc 41)))
; 42, and it comes back immediately rather than waiting for (slow 1)
```

A branch that fails simply drops out; it does not end the race. A branch that
raises does end it, and the error reaches you, because a broken branch should
never be the silent reason a different one won.

## Futures

`spawn` starts evaluating now and answers a handle. `await` waits for it.

```metta
!(let $f (spawn (slow 7)) (await $f))
; 7
```

The point is doing two things at once:

```metta
!(let $a (spawn (slow 1))
   (let $b (spawn (slow 2))
     (+ (await $a) (await $b))))
; 3, in about the time one of them takes on its own
```

### A future is a space

This is the part worth understanding, because it is what makes futures fit
MeTTa rather than fit Java.

A MeTTa expression does not have a value, it has an **answer set**. So a future
does too. `spawn` answers a space, the evaluating engine adds every answer to
it as it finds them, and `await` yields them all:

```metta
!(collapse (await (spawn (superpose (1 2 3)))))
; (1 2 3)      not (1)
```

Because the handle is an ordinary space, everything that already works on
spaces works on a future:

```metta
!(is-space (spawn (inc 1)))                       ; True
!(let $f (spawn (inc 41))
   (let $_ (await $f) (collapse (get-atoms $f))))  ; (42)
```

That also gives you streaming for free. `await` waits for the end, but
`await-atom` on the future's space takes answers **as they land**:

```metta
!(let $f (spawn (slow-search))
   (await-atom $f (found $x)))    ; returns on the first hit, not the last
```

Awaiting the same handle twice answers the same set without waiting again, so
a handle can be shared. `(settled? $f)` asks whether it has finished without
blocking, and `(cancel $f)` stops one that has not. An `await` inside another
spawned computation suspends that engine. It does not occupy a carrier while
the child is unfinished, so four parents awaiting four children cannot
deadlock the four-carrier scheduler.

Registered `oracleIO` operations may block in Python or other foreign code.
Before entering one, the engine detaches from its carrier and continues on a
transient offload thread, following Go's blocking-syscall handoff. A blocked
call owns that temporary thread, while the bounded carrier pool keeps running
other engines. Cancelling such a call reports `False` until the foreign body
returns because the engine has not actually stopped yet.

## Timers

A timer is a **future that starts later**. That single idea replaces the whole
`setTimeout` / `clearTimeout` / `setInterval` / `clearInterval` vocabulary,
because a timer answers a space like `spawn` does and is stopped by the same
`cancel`:

```metta
!(collapse (await (after 0.05 (inc 41))))
; (42), about 50ms later
```

There is no `clearTimeout`, because there is nothing new to clear:

```metta
!(let $t (after 30 (do-something))
   (cancel $t))        ; True, and it never fires
```

`every` is the repeating form. It never finishes, so consume it with
`await-atom` rather than `await`, and stop it with `cancel`:

```metta
!(let $ticker (every 1 (poll-sensor))
   (await-atom $ticker (reading $v)))   ; blocks until the next reading
```

One repeating timer never overlaps its own invocation. If its body is still
running at the next period, that tick is coalesced instead of queuing another
copy. One timer thread and one bounded pool serve every timer in the process,
so timers cost no per-timer thread. A saturated body pool does not block the
timer thread; one-shot work retries after 10 ms and repeating work retries at
its next period, leaving channel and space deadlines responsive. The timer
thread holds a heap keyed by deadline and waits with a timed receive, which
measured a constant 0.06 ms drift from 1 ms out to 500 ms, and 20,000 timers
went into the heap in 29 ms.

The obvious implementation, SWI's own `alarm/4`, is not what this uses: an
alarm's goal runs as a **signal on whichever thread scheduled it**, so a firing
timer would interrupt unrelated evaluation, and running MeTTa evaluation from a
signal handler took SIGSEGV when it was tried.

## Channels

A channel is a mailbox any thread can use.

```metta
!(let $c (channel)
   (let $_ (send $c hello)
     (recv $c)))
; hello
```

`(recv $c)` blocks, `(recv $c 0.5)` gives up after half a second with no
answer, and `(try-recv $c)` never blocks. `(channel $n)` bounds the channel so
senders block when it is full, which is how you apply backpressure. Inside a
spawned computation, an empty receive or full send suspends the engine and a
mailbox change wakes it; neither condition consumes a carrier.

One thing to know: a sent term is **copied**. The receiver gets its own copy,
so bindings made on one side do not appear on the other. That is what makes a
channel safe between threads.

## Worker pools

`par-map` over a hundred thousand elements would ask for a hundred thousand
threads. A pool bounds that: work beyond the pool's size queues instead.

```metta
!(pool workers 4)
!(let $h (submit workers (inc 9)) (await $h))
; 10
```

`submit` answers the same kind of handle `spawn` does, so pooled and unpooled
work are interchangeable. `(pool-stats workers)` reports size, running,
backlog and free; `(pool-destroy workers)` tears it down.

## Waiting on a space

This is the blackboard reading of a space: rather than polling for an atom,
block until somebody writes one.

```metta
!(await-atom &self (ready $what))
; blocks, then answers (ready now) with $what bound to now
```

It is event-driven, not a poll. The engine's own write hooks deliver, the same
mechanism Python subscriptions use. `(await-atom &self (ready $x) 5)` gives up
after five seconds with no answer.

## Locking without losing answers

`with-lock` holds a named lock while evaluating an expression:

```metta
!(collapse (with-lock counter (superpose (1 2 3))))
; (1 2 3)
```

Compare the built-in, which is SWI's `with_mutex/2` and behaves as `once`:

```metta
!(collapse (with_mutex counter (superpose (1 2 3))))
; (1)
```

That difference is the reason this exists. Two of the three answers vanish
with no error and no warning.

The price of keeping them is that the lock is held across backtracking. If you
abandon a `with-lock` call with answers still pending, the lock stays held
until that choice point is cut. Enumerate the answers fully, or wrap the call
in `once`, whenever the lock actually protects something.

## What is safe to do concurrently

Space writes are safe. MeTTa's shared structures already carry their own locks
because `hyperpose` workers have always reached the same database:
`'$metta_specializer'` guards specialization, `'$metta_native_storage'` guards
storage-module creation, `metta_loader` guards compilation through
`process_metta_string`, and the memoization cache holds one mutex per
function. SWI keeps individual dynamic predicates consistent by itself.

Two things are not safe and are worth naming. Memoization's admission sketch
is per-thread while the cache it governs is process-wide, so a memoized
function called from several threads makes worse eviction decisions than it
should. And `with_mutex` and `transaction`, the built-ins, both collapse to
one answer as shown above.

## Machine facts

```metta
!(cpu-count)      ; 32 here
!(thread-count)   ; how many threads are running right now
```

## Choosing between the three fan-outs

There are three, and they are not interchangeable.

`hyperpose`, and this library's `par-map` and friends, split work **inside the
engine**: one call from the host, the branches split below it. That is the
right choice when the fan-out is a MeTTa expression.

`MeTTa.pool()` in the Python library splits work **across engines**, one per
worker thread. That is the right choice when the fan-out is a Python loop.

`AsyncMeTTa` in `metta.aio` gives you a live event loop rather than
parallelism; it serialises onto one engine on purpose.

They compose. A pool worker may evaluate a `par-map`, and a `par-map` branch
may spawn futures.
