Statistics contains descriptive sample recipes and finite probability laws.
Both use inspectable MeTTa expressions and equations. Math supplies exact number
representations and final floating rounding; Measure supplies weighted rows.

```metta
!(import! &self (library lib_statistics))
!(math-ratio (stats-mean (1 2))) ; (3 2)
!(ws-map-independent + ((1 2)) ((1 3))) ; ((1 5))
```

Sample heads take expressions of finite observations. Exact observations retain
exact results; a floating observation makes the final result floating. Intermediate
moments stay exact, and standard deviation takes its root before rounding.
Population and sample variance differ through the degrees-of-freedom argument.

A finite law is an expression of `(Weight Value)` rows. Product mapping takes
zero or more independent laws. A function with alternative rewrites produces
alternative complete laws, each with its own normalized masses. Correlated
quantities belong in one joint law. Sample quantiles interpolate observations;
finite-law quantiles select supported values by cumulative mass.

`lib_distribution` has been consolidated here. Replace its import with
`lib_statistics`, and replace `ws-map2-independent` with the variadic
`ws-map-independent`. Independent averages now inherit `stats-mean`'s exact or
floating numeric result type.
