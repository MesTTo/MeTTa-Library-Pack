The numerical helpers in `../lib_vector.pl` translate the fraction square-root
method in CPython 3.14.0's `statistics._float_sqrt_of_frac` and
`statistics._integer_sqrt_of_frac_rto`. The source revision is
`ebf955df7a89ed0c7968f79faec1de49f61ed7cb` and its license is `PYTHON-LICENSE`.

Source: [statistics.py, lines 1695–1721](https://github.com/python/cpython/blob/ebf955df7a89ed0c7968f79faec1de49f61ed7cb/Lib/statistics.py#L1695-L1721).
The translation uses SWI's integer square root and GMP rationals, preserves
the 109-bit round-to-odd intermediate, and replaces the final integer division
with rounding at the actual binary64 quantum. It explicitly returns IEEE
overflow and underflow results. Integer scaling and ties-to-even rounding also
follow the method documented in [long_true_divide](https://github.com/python/cpython/blob/ebf955df7a89ed0c7968f79faec1de49f61ed7cb/Objects/longobject.c#L4508).
The library owns the translated Prolog implementation; CPython is not a runtime
dependency.
