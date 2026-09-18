The gamma equations in `../../_support/random.metta` adapt the Marsaglia/Tsang method and
shape-boosting identity implemented by Rand at revision
`d65b9bbf991e56d8a097a35d934e6f93d9194ac0`. Its MIT license is `RAND-LICENSE`.

Source: [gamma.rs](https://github.com/rust-random/rand_distr/blob/d65b9bbf991e56d8a097a35d934e6f93d9194ac0/src/gamma.rs).
The translation keeps multiplicative factors separate from the boosting power,
combines ordinary products exactly, and preserves extreme powers through their
logarithms until the final scale or beta ratio is known. Standard normal draws
use Box-Muller with two host uniforms and no cached spare.

The normal and inverse-transform formulas were checked against
[CPython random.py](https://github.com/python/cpython/blob/ebf955df7a89ed0c7968f79faec1de49f61ed7cb/Lib/random.py).
That revision's license is already shipped in
`../../lib_vector/vendor/PYTHON-LICENSE`. Neither upstream project is a runtime
dependency; every uniform draw uses the core random-float operation and SWI's
existing thread-local generator. The public constructors in
`../lib_random.metta` return sample programs as ordinary MeTTa expressions.
