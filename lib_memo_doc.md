# lib_memo - Memoization Library for MeTTa
Thread-safe, policy-driven memoization system with multiple eviction strategies (LRU and WTinyLFU), variant-key support for non-ground calls, and multi-answer caching.
This document explains the public API, configuration options, internal behavior you should rely on, and practical recommendations for effective usage.
## Quick Start
Pure recursive definitions are considered automatically. A recursive strongly
connected component is selected when one equation body calls that component at
least twice; a single recursive call has no repeated subproblem and stays
uncached. The effect walk remains a hard gate, so a function that writes state,
prints, or reads a space is never selected automatically.

```metta
(= (fib-shape $n)
   (if (< $n 1)
       1
       (+ (fib-shape (- $n 1)) (fib-shape (- $n 1)))))

!(import! &self (library lib_memo)) ; expose inspection/configuration forms
!(is-memoized fib-shape)             ; true
!(explain (fib-shape 20))
; includes: (cache automatic (recursive-scc (fib-shape) body-call-count 2))
```

The automatic dispatcher is resident in the engine. Importing `lib_memo`
exposes the public inspection and configuration forms; it does not enable the
decision or reload the cache state.

### Override the automatic decision

Overrides are catalog declarations in `&petta`, not process flags:

```metta
!(add-atom &petta (cache tail-recursive force))
!(add-atom &petta (cache branching-search refuse))
```

`force` bypasses only the repeated-call profitability rule. It cannot make an
impure function cacheable. `refuse` disables an automatic choice. Remove the
declaration to return to the automatic rule:

```metta
!(remove-atom &petta (cache branching-search refuse))
```

An explicit `lib_tabling` declaration takes precedence while its SWI answer
trie is live. Automatic bag memoization is withdrawn when `(tabled ...)` lands
in `&petta` and reconsidered when `(untabled ...)` removes it, so the two cache
substrates never stack on one function.

### Enable Memoization
```metta
!(memoize fib)
!(memoize fib 1) ; only memoize fib with one input argument
```
### Check Status
```metta
!(is-memoized fib)  ; Returns: true or false
!(is-memoized fib 1) ; Returns: true if fib/1-input arity is memoized
```
### Configure Cache
```metta
; Set eviction strategy
!(config-memoize (strategy wtinylfu))
; Set max entries per function (unique entries)
!(config-memoize (unique-limit 1000))
; Set global memory limit (in GB)
!(config-memoize (size-limit 5))
; Set float precision (decimal places)
!(config-memoize (float 6))
; Combine options
!(config-memoize (strategy lru) (unique-limit 500) (size-limit 10))
```
### Get Configuration & Stats
```metta
!(get-memoize-config)
; Example return: ((strategy wtinylfu) ('unique-limit' 100) ('size-limit' 5368709120)
;                  (float 12) ('answer-limit' 2048) (aggregate none))
!(get-memoize-stats)
; Returns runtime counters as a list of [Key, Value] pairs, e.g. ((cache_miss 1001) (cache_hit 998))
```

### Clear Memoization
```metta
!(clear-memoize)            ; Clears every space's cached entries and queue state
!(invalidate-memoize my-fun) ; Invalidate one function in this space, and its dependents
!(clear-memoize-stats)      ; Reset runtime counters
```
`clear-memoize` is process-wide because the memory budget it resets is one
global budget. `invalidate-memoize` drops one function in the space that
asks.

## Memoization is per space

A named space compiles its own equations into a module of its own, so two
spaces defining the same function name hold two different functions. Every
memoization decision follows that: `!(memoize f)` enables the `f` of the
space it runs in, that space gets its own cache, and no other space's
answers change. `!(is-memoized f)` answers for the space that asks.

```metta
!(bind! &metric (new-space))
!(add-atom &metric (= (shipping-cost $w) (* $w 9)))
(= (shipping-cost $w) (* $w 2))

!(memoize shipping-cost)                              ; this space's function
!(test (shipping-cost 3) 6)
!(test (evalc (shipping-cost 3) &metric) 27)          ; still its own answer
!(test (evalc (is-memoized shipping-cost) &metric) false)
```

A space that does not define the function but inherits `&self`'s is calling
the same function, so it shares the one cache rather than building a second.
`examples/libraries/memo_spaces.metta` runs the whole property.
## Configuration Options
| Option | Default | Description |
|--------|---------|-------------|
| `strategy` | `wtinylfu` | Eviction policy: `wtinylfu` or `lru` |
| `unique-limit` | 100 | Maximum cached entries per function (per-function queue capacity) |
| `size-limit` | 5 | **Global** memory limit in GB (across all functions) |
| `float` | 12 | Decimal precision for float quantization (see notes) |
| `answer-limit` | 2048 | Maximum answers stored per cache key |
| `aggregate` | `none` | Ground-call aggregation mode: `none|min|max|sum|count` |

## Arity-Aware Memoization
- `!(memoize fun)` enables memoization for all arities of `fun` (backward compatible behavior).
- `!(memoize fun N)` enables memoization only for arity `N`, where `N` is the number of input arguments in MeTTa.
- Arities do not conflict: functions like `(fun $x)` and `(fun $x $y)` can be memoized independently, including in the same file.
- Status checks support the same shape: `!(is-memoized fun)` (any arity enabled) and `!(is-memoized fun N)` (specific arity).
## Eviction Policies
- LRU (Least Recently Used): simple FIFO per-function queue; evicts oldest entries when per-function capacity is reached. Good for workloads with recent locality.
- WTinyLFU (Window TinyLFU): uses a Count‑Min Sketch to estimate frequency and an admission policy that compares a candidate's frequency against the victim's frequency. Prevents "one‑hit wonders" from polluting the cache and is a good default when a small subset of keys are hot.
Choose `wtinylfu` when you expect a stable hot set; choose `lru` when recency is the dominant access pattern.
## Global Memory (`size-limit`)
- `size-limit` is a global cap across all cached entries. The code converts the GB value to bytes internally.
- Estimated entry size = (term_size(Args) + term_size(Results)) × 8 bytes (rough term-cell estimate).
- On store: if CurrentTotal + NewEntry > Limit, the runtime evicts the oldest entries across all functions until there is enough space, updating the global total accordingly.
- `size-limit` controls only the estimated cache entry memory; it does not cap the Prolog VM's other memory usage (stacks, atoms, etc.).
## Replay Semantics & Multi-Answer Caching
- Ground calls: cache keys are quantized (floats rounded to configured precision) and replay mode returns stored outputs only. Ground aggregation modes (`count|min|max|sum`) apply to the collected answers.
- Non-ground (variant) calls: the cache stores answer patterns `(Args, Out)` and replays bindings on hit; this preserves tabling-like semantics.
- Multi-answer support: probing collects up to `answer-limit` answers per key; excess answers are truncated and the `answer_limit_truncated` metric is incremented.
- In-progress guard: for variant keys, the runtime uses `metta_memo_in_progress/5` to avoid duplicated concurrent recomputation. Callers will briefly wait for in-progress work to finish and then replay results; if waiting fails they fall back to direct execution.

Those configuration semantics describe explicit `memoize`. An automatic cache
must preserve the program's answer bag, so it uses exact keys, ignores manual
aggregation, and never truncates at `answer-limit`. When a probe finds more
answers than the configured limit, that call runs directly and increments
`automatic_answer_limit_bypass`; duplicate answers remain duplicate.

Python `@space.cache` takes a separate exact path. The compiler emits a direct
call to a generated table for each function arity. A raw answer contributes
the coefficient `1`; SWI's mode-directed `sum` combines coefficients for equal
solved answers in its C trie, and replay emits that answer the recorded number
of times. Exact decorator keys do not use manual float quantization,
aggregation, or `answer-limit`. `cache_info()` counts tabled call variants as
entries and sums their coefficients as answer occurrences.

SWI answer tables are private to each Prolog engine unless declared shared.
The exact path therefore carries `metta_memo_generation/4` as a hidden first
table argument. Invalidation advances that process-wide generation before it
reclaims the caller engine's old tries, so a carrier that already cached the
same function selects a fresh variant instead of replaying its private stale
table. Generations stay monotonic across `clear-memoize` and disable/re-enable
cycles for the same reason; only live-generation tries contribute to
`cache_info()`.

Bounded search is not admitted automatically. `lib_memo` eagerly collects a
miss's complete bag; probing recursion beneath `once`, `take`, or `top` could
continue after the source construct had its answer and then wait on the same
in-progress variant. `explain` reports `(bounded-search <construct>)` for this
safety refusal. Explicit `memoize` retains its requested variant behaviour.
## Core State (short reference)
Dynamic predicates exposed in the runtime (for debugging and reasoning):
Every table below is keyed by `(Fun, Module)`, where the module is the one
holding the function's clauses. See "Memoization is per space" above.

- `memo_enabled/2` — functions with memoization enabled (`Fun`, Module)
- `memo_enabled/3` — arity-specific memoization enables (`Fun`, Module, InputArity)
- `memo_automatic_enabled/2` — functions selected by the automatic policy
- `memo_automatic_decision/4` — the reported automatic choice and reason
- `exact_memo_specialization/5` — generated replay and table names with their owning function arity
- `metta_memo_entry/6` — cached results (Fun, Module, Arity, Gen, Args, Results)
- `metta_memo_generation/4` — generation counter per function (used for invalidation)
- `metta_memo_count/4`, `metta_memo_head/4`, `metta_memo_tail/4`, `metta_memo_q/5` — per-function queue state
- `metta_memo_total_bytes/1` — global estimated bytes used by cache entries
- `metta_memo_in_progress/5` — keys currently being computed (variant path)
- `supports/2` — the common support graph's indexed `Support`→`Derived`
  edges; memo nodes use these for dependency-aware invalidation
- `metta_memo_stat/2` — runtime counters (cache_hit, cache_miss, waited_on_in_progress, etc.)
Refer to source predicates if you need deeper internal debugging; avoid relying on internal facts for program logic unless you intend to keep compatibility with future changes.
## Integration Hooks & Synchronization
The library integrates with the MeTTa runtime via multifile hooks:
- `seam:dispatch_call/4` — intercepts dispatch to memoized functions, and is told the module the call site lives in
- `seam:function_call_graph_changed/2` — schedules a new SCC decision only when a source-call edge changes
- `seam:source_program_compiled/0` — drains one batched decision after a source unit
- `seam:cache_policy_changed/1` — applies a force/refuse or explicit-tabling mutation
- `seam:function_removed/1` — invalidates and disables memoization when a function is removed
Synchronization primitives:
- `with_cache_fun_mutex/4` — per-(Fun,Module,Arity) mutex to protect queue/state for that function
- `with_cms_mutex/1` — global mutex used for the Count‑Min Sketch updates
## Practical Recommendations & Effective API Usage
These are concise, actionable guidelines derived from observed behaviors and common pitfalls.
1. Global vs per-function config
- Configuration options (strategy, unique-limit, size-limit, float, answer-limit, aggregate) are global to the running MeTTa/Prolog process. Which functions are memoized is per-function (`!(memoize <fun>)`).
- If you need different cache parameters for different examples, set the global config and clear the cache before running each example (procedural approach). See the helper snippet below.
2. Clear before experiments
Always run a reproducible preset when benchmarking:
```metta
!(clear-memoize)
!(clear-memoize-stats)
!(config-memoize (unique-limit 10000) (strategy wtinylfu) (size-limit 5))
!(<run workload>)
!(println! (get-memoize-stats))
```
3. Unique-limit guidance
- `unique-limit` is the per-function queue capacity. For divide-and-conquer or DP workloads (e.g., `fib`), set `unique-limit` ≥ number of distinct inputs you expect (for `fib(N)` that is `N+1`) to avoid cache thrashing and repeated recomputation.
4. Interpreting hits/misses
- Under a small `unique-limit`, the cache can thrash: entries are evicted and later recomputed, producing many `cache_miss` events and also many `cache_hit` events as recomputed entries are accessed. When capacity is sufficient, misses drop to ~distinct-keys and runtime improves.
5. Choosing strategy
- `wtinylfu` (default): good general-purpose choice when a small hot set exists.
- `lru`: use when temporal locality dominates and you want a simple recency-based policy.
6. Float precision
- `float` controls quantization of float arguments for canonical keys. Higher precision reduces quantization collisions but can increase cache fragmentation. Avoid extremely large values (e.g., >18) to prevent numerical issues.
7. Printing stats
- `!(get-memoize-stats)` returns counters; call it after running the workload. If your MeTTa host does not echo return values, use `!(println! (get-memoize-stats))` or add a helper `!(print-memoize-stats (println! (get-memoize-stats)))`.
8. Automatic overrides
- Use `(cache <function> force)` or `(cache <function> refuse)` in `&petta` for one function. These declarations change admission, not eviction, size, aggregation, or key configuration.
