The exact moment reduction, quantile interpolation and geometric-mean log
reduction in `../lib_statistics.pl` adapt CPython's `statistics.py` at revision
`ebf955df7a89ed0c7968f79faec1de49f61ed7cb`. Its license is `PYTHON-LICENSE`.

Source: [statistics.py](https://github.com/python/cpython/blob/ebf955df7a89ed0c7968f79faec1de49f61ed7cb/Lib/statistics.py).
Exact paired moments extend that reduction to covariance, correlation and
regression. The geometric mean separates integer binary exponents from native
mantissa logs before averaging. The fractional square root is the existing
licensed implementation imported from `../../lib_vector/lib_vector.pl`.
CPython is not a runtime dependency.
