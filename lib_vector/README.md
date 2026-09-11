Numeric vectors are ordinary expressions. `lib_vector` computes exact finite
reductions before rounding and supplies component arithmetic, lengths,
directions, distances, construction and random positive directions.

```metta
!(import! &self (library lib_vector))
!(vector-add (1 2) (3 4))                 ; (4 6)
!(dot (18014398509481984.0 1.0 -18014398509481984.0) (1 1 1)) ; 1.0
!(vector-normalize (3 4))                ; (0.6 0.8)
!(vector-distance (1 2) (4 6))            ; 5.0
```

Every component must be a Number and paired vectors must have equal dimensions.
A mismatch raises `domain_error(vector_dimensions,[LeftLength,RightLength])`;
it does not truncate or produce an empty answer. Existing expression operations
apply, including `size-atom`, `car-atom`, `cdr-atom` and `cons-atom`.

| Operation | Result |
| --- | --- |
| `dot`, `cosine-of-normalized` | Exact finite products and sum, rounded once to float. |
| `norm`, `vector-distance` | Correctly rounded square root of the exact squared sum. |
| `cosine` | Exact dot/norm ratio rounded once, even when a norm would overflow or underflow. |
| `vector-add`, `vector-subtract`, `vector-multiply`, `vector-divide` | Component results; exact inputs stay exact, and a floating input makes its result floating. |
| `vector-scale Vector Factor` | Multiply each component with the same number rules. |
| `vector-normalize` | Floating coordinates from exact ratios, preserving finite direction. |
| `vector-fill Count Value` | Count copies of Value; Count is a nonnegative integer. |
| `random-normal-vector Count [Accumulator]` | Prepend positive uniform draws, then normalize the whole vector. |

Finite floats denote their stored binary values. Products use those exact values,
so cancellation and underflow do not lose information before the final rounding.
Exact division returns a rational; an exact zero divisor raises for the whole
operation. Floating zero division follows IEEE infinity and NaN rules.

Empty dot, norm and distance return `0.0`; empty normalization is empty. Cosine
of a zero or nonfinite vector is NaN. A zero vector normalizes to NaN coordinates.
With an infinite norm, finite coordinates become signed zero and infinite ones
become NaN. NaN propagates through a squared sum. Signed zero coordinates keep
their signs. `cosine-of-normalized` remains a dot product with no unit-length
check: `(3 4)` with itself gives `25.0`.

Random draws use the current thread's existing generator and `with-seed` seam.
Count must be an integer; negative counts draw nothing and normalize the
accumulator. Validation precedes draws. Each new draw is prepended, preserving
the existing order. With an empty accumulator, the distribution is the positive
cube projected onto the unit sphere. It is neither Gaussian nor uniform on the
sphere. Use it when that positive-direction distribution is intended.

Traversal is linear in the dimension, which must be read completely. Exact
arithmetic also depends on the number of bits in its inputs and intermediates;
the library does not silently replace it with a floating approximation. It
requires SWI-Prolog built with GMP integers and rationals. A configured
`max_rational_size_action=float` that approximates an intermediate raises
`representation_error(exact_vector_arithmetic)`.

In Python, keep returned expressions or their child atoms when composing native
rational operations. For example, `q = m.fn.vector_divide((1,), (3,)).one()`
followed by `m.fn.vector_scale(q, 3).one()` returns `(1)`. A child atom preserves
its numeric identity; its `.value` is the Python `Fraction` payload. Creating
`G(Fraction(...))` explicitly uses the host object channel and retains that
Python object's identity.

The [example](../../examples/ch08-data/08-03-the-shipped-libraries/13-vector_lib.metta)
calls every head. Native PlDoc declarations generate the MeTTa imports, arrow
types and documentation. The [provider notice](vendor/README.md) records the
licensed fraction square-root translation and its primary sources.
