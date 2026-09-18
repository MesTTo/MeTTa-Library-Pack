# Sample programs

```metta
!(import! &self (library lib_random))
!(let $sample (random-normal 0 1)
   (with-seed 42 (size-atom (collapse (repeat 3 $sample)))))
; 3
!(let $sample (random-uniform 2 10)
   (let ($head $entropy $low $high) (quote $sample)
     (let $rewritten (quote ($head 0.25 $low $high))
       (eval $rewritten))))
; 4.0
```

A sampler is an ordinary expression containing a computation. Construction
validates its parameters and returns that expression without consuming
randomness. Bind the returned program before passing it to `eval`, which runs
one sample, or `repeat`, which streams samples. `collapse` collects the stream;
`once` demands only its first answer. A caller can store, match, rewrite or
combine sample programs using the same operations as other MeTTa code.

The ten numeric constructors cover uniform, normal, lognormal, exponential,
triangular, gamma, beta, Bernoulli, Pareto and Weibull sampling. Parameters must
convert to finite binary64 values in the documented domains. Constant cases
consume no entropy. Exact intermediate arithmetic preserves representable
results across extreme parameters; final floating results may underflow or
overflow. The [API reference](../../website/reference/metta-libraries.md#lib_random)
describes each constructor's parameters and numerical policy.

`random-choice` constructs a program that selects one population position.
Populations are held expressions, so runnable terms remain data and equal
values at different positions remain separate choices. `random-sample!` selects
a count of distinct positions; `random-shuffle!` selects every position. Their
immutable removal steps use segments and `unfold`, costing O(n × count).
For independent choices with replacement, compose a choice program with
`repeat`. Use `map-atom` when the resulting collection must retain sharing
between caller variables.

`with-seed` owns the existing thread-local generator and restores it on every
exit. Sampling introduces no generator handle, distribution registry or cached
normal spare. Statistics' finite laws remain weighted data; Random's programs
consume entropy when evaluated. Both compose with ordinary MeTTa functions.

Python imports the same equations through `m += lib.random`. Constructors return
an expression that `m.eval(program)` or `m.fn.with_seed(seed, program)` runs.
Recording uses the core entropy declarations. Replay requires the recorded
space content: a first run can publish specialization equations, changing that
content. Record over the resulting equations before replaying in that space.
Sampling and shuffling also retain validating assertions; the recording planner
conservatively refuses their possible diagnostic output as unseeded I/O.

The [executable example](../../examples/ch08-data/08-03-the-shipped-libraries/36-random_lib.metta)
also reconstructs a constructor from its stored equation and composes sample
programs with alternative answers. [Vendor notes](vendor/README.md) identify the
numeric algorithms and their retained licenses.
