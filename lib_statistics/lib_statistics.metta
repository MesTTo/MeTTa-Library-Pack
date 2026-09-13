; Purpose: derive sample summaries and finite probability laws in MeTTa.
; Assumes: samples contain finite Numbers; laws use Measure's visible
; (weight value) rows. Independent products require independent inputs.
; Guarantees: exact sample arithmetic precedes final floating conversion;
; callbacks preserve alternative complete laws and literal values.
; [tested: lib_statistics, test_statistics_exact_reductions,
; test_independent_marginals_and_a_correlated_joint_are_not_interchangeable;
; commit=6fa571d1b7059b610f73e9feed657711414251e5].
; Owns resources: expressions and query-local arithmetic; no stored state.
; Decides: sample quantiles interpolate; finite-law quantiles invert the CDF.
; Moments, order counts and product laws remain inspectable equations.

!(import! &self (library lib_math))
!(import! &self (library lib_functional))
!(import! &self (library lib_measure))
!(import! &self (library "_support/statistics.metta"))

(= (stats-sum $data)
   (let ($values $floating) (statistics-data $data)
     (statistics-result $floating (foldl-atom $values 0 statistics-add))))

(= (stats-mean $data)
   (let* ((($values $floating) (statistics-data $data))
          ($n (statistics-size $values 0))
          ($mean (statistics-divide (stats-sum $values) $n)))
     (statistics-result $floating $mean)))

(= (stats-harmonic-mean $data)
   (let ($values $floating $n) (statistics-nonnegative $data)
     (let $mean
          (if (== (min-atom $values) 0) 0
            (statistics-divide $n
              (stats-sum (map-atom $values $x (statistics-divide 1 $x)))))
       (statistics-result $floating $mean))))

; Average mantissa logs while exact integer exponents cancel separately.
; https://github.com/python/cpython/blob/ebf955df7a89ed0c7968f79faec1de49f61ed7cb/Lib/statistics.py#L224-L261
(= (stats-geometric-mean $data)
   (let ($values $floating $n) (statistics-nonnegative $data)
     (if (== (min-atom $values) 0) 0.0
       (let* ((($exponent $logs)
                (foldl-atom $values (0 0) statistics-log-parts))
              ($q (floor-div $exponent $n))
              ($r (- $exponent (* $q $n)))
              ($log (statistics-divide
                      (statistics-exact
                        (+ $logs (* $r (math-rational (log-math (math-real e ()) 2)))))
                      $n))
              ($power (math-rational (exp-math (math-float $log))))
              ($approx (statistics-scale $power $q))
              ($bounded (max-atom ((min-atom $values)
                                  (min-atom ((max-atom $values) $approx))))))
         (math-float $bounded)))))

(= (stats-median $data) (stats-quantile $data (math-rational 1 2) inclusive))

(= (stats-quantile $data $probability $method)
   (let* (($checked (statistics-method $method))
          ($p (math-rational $probability))
          ($valid (assertEqualMsg (and (>= $p 0) (<= $p 1)) True
                                 (quote (stats-quantile $probability))))
          ((($pool $n) $floating) (statistics-sorted $data)))
     (statistics-result $floating (statistics-quantile $pool $n $p $method))))

(= (stats-quantiles $data $partitions $method)
   (let* (($checked (assertEqualMsg
                     (and (collections-integer? $partitions) (> $partitions 0)) True
                     (quote (stats-quantiles $partitions))))
          ($valid (statistics-method $method))
          ((($pool $n) $floating) (statistics-sorted $data)))
     (collapse
       (let $i (range 1 $partitions)
         (statistics-result $floating
           (statistics-quantile $pool $n (math-rational $i $partitions) $method))))))

(= (stats-mode $data)
   (let* (($values (collections-expression $data))
          ($n (statistics-size $values 0))
          ($groups (group-by (|-> ($value) (quote $value)) (quote $values)))
          ($counts (map-atom $groups $group (size-atom (index-atom $group 1))))
          ($most (max-atom $counts))
          ($group (index-atom $groups (range 0 (size-atom $groups)))))
     (if (== (size-atom (index-atom $group 1)) $most)
       (index-atom $group 0) (empty))))

(= (stats-variance $data $degrees)
   (stats-covariance $data $data $degrees))

(= (stats-stdev $data $degrees)
   (let ($values $floating) (statistics-data $data)
     (math-sqrt (stats-variance $values $degrees))))

; Exact paired moments extend CPython's reduction to cross products.
; https://github.com/python/cpython/blob/ebf955df7a89ed0c7968f79faec1de49f61ed7cb/Lib/statistics.py#L1501-L1545
(= (stats-covariance $left $right $degrees)
   (let* ((($a $b $floating) (statistics-paired $left $right))
          ($n (statistics-size $a $degrees))
          ($xy (stats-sum (vector-multiply $a $b)))
          ($centered (statistics-exact
                       (- (* $n $xy) (* (stats-sum $a) (stats-sum $b)))))
          ($covariance (statistics-divide $centered (* $n (- $n $degrees)))))
     (statistics-result $floating $covariance)))

(= (stats-correlation $left $right)
   (let* ((($a $b $floating) (statistics-paired $left $right))
          ($n (statistics-size $a 1))
          ($xx (stats-variance $a 0))
          ($yy (stats-variance $b 0))
          ($xy (stats-covariance $a $b 0))
          ($checked (assertEqualMsg (and (> $xx 0) (> $yy 0)) True
                                   (quote (nonconstant-observations $left $right))))
          ($ratio (statistics-divide (statistics-exact (* $xy $xy))
                                     (statistics-exact (* $xx $yy))))
          ($magnitude (math-sqrt $ratio)))
     (if (< $xy 0) (- 0 $magnitude) $magnitude)))

(= (stats-ranks $data)
   (let ($values $floating) (statistics-data $data)
     (map-atom $values $value
       (let* (($less (filter-atom $values $other (< $other $value)))
              ($equal (filter-atom $values $other (== $other $value))))
         (math-rational (+ (+ (* 2 (size-atom $less)) (size-atom $equal)) 1) 2)))))

(= (stats-regression $independent $dependent $proportional)
   (let* (($checked (assertEqualMsg
                     (and (not (is-var $proportional))
                          (or (== $proportional True) (== $proportional False))) True
                     (quote (stats-regression $proportional))))
          (( $a $b $floating) (statistics-paired $independent $dependent))
          ($n (statistics-size $a (if $proportional 0 1)))
          ($xx (if $proportional (stats-sum (vector-multiply $a $a))
                                (stats-variance $a 0)))
          ($xy (if $proportional (stats-sum (vector-multiply $a $b))
                                (stats-covariance $a $b 0)))
          ($valid (assertEqualMsg (> $xx 0) True
                                 (quote (identifiable-regression $independent))))
          ($slope (statistics-divide $xy $xx))
          ($intercept (if $proportional 0
                        (statistics-exact (- (stats-mean $b) (* $slope (stats-mean $a)))))))
     (linear-fit (statistics-result $floating $slope)
                 (statistics-result $floating $intercept))))

(: stats-correlation (-> Expression Expression Number))
(@doc stats-correlation
  (@desc "Pearson correlation, correctly rounded into [-1,1] from exact paired moments. Both finite expressions need equal lengths, at least two observations and nonzero variance. Constant input raises. Compose stats-ranks on both inputs to obtain Spearman correlation with averaged ties.")
  (@params ((@param "Left") (@param "Right")))
  (@return "Correlation"))

(: stats-covariance (-> Expression Expression Number Number))
(@doc stats-covariance
  (@desc "Paired covariance, dividing the sum of centered products by N-DegreesOfFreedom. The finite expressions have equal lengths and N must exceed the nonnegative integer DegreesOfFreedom. Exact paired moments and final rounding follow stats-variance; choose 0 for population covariance or 1 for a sample estimate.")
  (@params ((@param "Left") (@param "Right") (@param "DegreesOfFreedom")))
  (@return "Covariance"))

(: stats-geometric-mean (-> Expression Number))
(@doc stats-geometric-mean
  (@desc "Floating geometric mean of nonnegative finite observations. Validate the whole expression before returning zero for a zero observation. Empty or negative input raises. Sum binary exponents separately from mantissa logs, so huge and tiny exact observations can cancel without an overflowing product. Native log/exp precision applies; bound the approximation by the observed minimum and maximum before final rounding. Equal observations retain their rounded value. A result outside binary64 rounds to zero or infinity.")
  (@params ((@param "Data")))
  (@return "Mean"))

(: stats-harmonic-mean (-> Expression Number))
(@doc stats-harmonic-mean
  (@desc "N divided by the sum of reciprocals, for nonnegative finite observations. A zero makes the mean zero after every observation is validated. Empty or negative input raises. Exact inputs retain an exact result.")
  (@params ((@param "Data")))
  (@return "Mean"))

(: stats-mean (-> Expression Number))
(@doc stats-mean
  (@desc "Arithmetic mean of a nonempty finite expression, with stats-sum's exact accumulation and result type. A sum may exceed binary64 while its mean fits.")
  (@params ((@param "Data")))
  (@return "Mean"))

(: stats-median (-> Expression Number))
(@doc stats-median
  (@desc "Middle observation, or the exact mean of the two middle observations. Empty input raises. Numeric result types follow stats-sum, including mixed inputs.")
  (@params ((@param "Data")))
  (@return "Median"))

(: stats-mode (-> Atom %Undefined%))
(@doc stats-mode
  (@desc "Every most frequent held term, once, in first-occurrence order. Terms compare by identity, so 1 and 1.0 count separately and runnable expressions stay data. Collapse collects ties; once selects the first mode. Empty and cyclic data raise. Stable grouping and identity comparisons derive the counts; all tied terms remain alternative answers.")
  (@params ((@param "Data")))
  (@return "Mode"))

(: stats-quantile (-> Expression Number Symbol Number))
(@doc stats-quantile
  (@desc "Linearly interpolate sorted observations at Probability in [0,1]. Inclusive places the minimum at 0 and maximum at 1. Exclusive places sorted observation i at i/(N+1), extrapolating with the nearest endpoint pair outside those positions. A singleton returns its observation. Empty input or an unknown method raises. Exact observations retain exact interpolation; a float observation rounds once.")
  (@params ((@param "Data") (@param "Probability") (@param "Method")))
  (@return "Value"))

(: stats-quantiles (-> Expression Number Symbol Expression))
(@doc stats-quantiles
  (@desc "The Partitions-1 cut points at i/Partitions, using stats-quantile's inclusive or exclusive interpolation. Partitions must be positive. One partition gives empty cuts after validating the nonempty data and method. Sort once, then derive each cut with ordinary indexing and exact interpolation.")
  (@params ((@param "Data") (@param "Partitions") (@param "Method")))
  (@return "Cuts"))

(: stats-ranks (-> Expression Expression))
(@doc stats-ranks
  (@desc "One-based numeric ranks in input order. Tied numeric values receive their exact mean rank, so 1 and 1.0 tie. Empty input returns empty. Count smaller and equal observations for each input through ordinary predicates; no observation is dropped.")
  (@params ((@param "Data")))
  (@return "Ranks"))

(: stats-regression (-> Expression Expression Bool Expression))
(@doc stats-regression
  (@desc "Least-squares (linear-fit Slope Intercept) from finite paired observations. False fits an affine line and needs at least two observations with nonconstant x. True fits through the origin and needs at least one observation with nonzero sum of squared x values. Lengths match. Coefficients use exact moments and retain exact results unless either expression contains a float.")
  (@params ((@param "Independent") (@param "Dependent") (@param "Proportional")))
  (@return "Fit"))

(: stats-stdev (-> Expression Number Number))
(@doc stats-stdev
  (@desc "Correctly rounded floating square root of the exact variance. The same sample-size rules as stats-variance apply. Take the root before rounding, so a representable deviation survives an unrepresentable floating variance.")
  (@params ((@param "Data") (@param "DegreesOfFreedom")))
  (@return "Deviation"))

(: stats-sum (-> Expression Number))
(@doc stats-sum
  (@desc "Sum finite observations exactly before any rounding. Empty input returns 0. All integer/rational observations produce an exact result; any float makes the result a float rounded once. Every numeric head refuses NaN and infinity.")
  (@params ((@param "Data")))
  (@return "Total"))

(: stats-variance (-> Expression Number Number))
(@doc stats-variance
  (@desc "Sum of squared deviations divided by N-DegreesOfFreedom. Use 0 for a whole population and 1 for the usual sample estimate. DegreesOfFreedom is a nonnegative integer and N must exceed it. Exact moments prevent cancellation; result types follow stats-sum, with only the final result rounded.")
  (@params ((@param "Data") (@param "DegreesOfFreedom")))
  (@return "Variance"))

; A finite law retains Measure's transparent weight-first rows. Product laws
; multiply independent masses and add masses of equal outputs.
; if-error inspects values eagerly; core if keeps each guarded branch lazy.
; https://github.com/numpy/numpy/blob/2f7fe64b8b6d7591dd208942f1cc74473d5db4cb/numpy/_core/numeric.py#L793-L801
(: ws-map-independent (-> %Undefined% (:seg Expression) %Undefined%))
(= (ws-map-independent $function (:seg $distributions))
   (let $normalized
        (foldl-atom $distributions () $acc $input
          (if (if-error $acc True False) $acc
            (let $law (ws-normalize $input)
              (if (if-error $law True False) $law (union-atom $acc (quote ($law)))))))
     (if (if-error $normalized True False) $normalized
       (let $products (collapse (tuples $normalized))
         (ws-normalize
           (map-atom $products $tuple
             (let* (($weights (map-atom $tuple $pair (index-atom $pair 0)))
                    ($values (map-atom $tuple $pair (index-atom $pair 1)))
                    ($mass (foldl-atom $weights 1 *))
                    ($result (apply-to $function $values)))
               (quote ($mass $result)))))))))
(@doc ws-map-independent
  (@desc "Push a function through zero or more independent finite laws. Normalize each input in order and preserve the first refusal. Enumerate product tuples in input order, multiply their masses and merge equal outputs. With no inputs, apply the nullary function and give its result unit mass. Function alternatives produce alternative complete laws; they do not acquire probabilities. Correlated inputs belong in one joint law passed to ws-map.")
  (@params ((@param "Function") (@param "Distributions")))
  (@return "Law or refusal"))

(: ws-map (-> %Undefined% Expression %Undefined%))
(= (ws-map $function $law) (ws-map-independent $function $law))
(@doc ws-map
  (@desc "Push a function through one finite law. Equal mapped outcomes merge at their first occurrence. Each alternative mapping remains a separate normalized law. This is the single-input case of ws-map-independent.")
  (@params ((@param "Function") (@param "Law")))
  (@return "Law or refusal"))

(: ws-mass-at-least (-> Expression Number %Undefined%))
(= (ws-mass-at-least $law $threshold)
   (ws-expect (ws-map (|-> ($x) (if (>= $x $threshold) 1.0 0.0)) $law)))
(@doc ws-mass-at-least
  (@desc "Inclusive upper-tail probability P(X>=Threshold) of a numeric finite law.")
  (@params ((@param "Law") (@param "Threshold")))
  (@return "Mass or refusal"))

(: ws-mass-at-most (-> Expression Number %Undefined%))
(= (ws-mass-at-most $law $threshold)
   (ws-expect (ws-map (|-> ($x) (if (<= $x $threshold) 1.0 0.0)) $law)))
(@doc ws-mass-at-most
  (@desc "Inclusive cumulative probability P(X<=Threshold) of a numeric finite law.")
  (@params ((@param "Law") (@param "Threshold")))
  (@return "Mass or refusal"))

(: ws-prob-gt-independent (-> Expression Expression %Undefined%))
(= (ws-prob-gt-independent $left $right)
   (ws-expect (ws-map-independent
                (|-> ($x $y) (if (> $x $y) 1.0 0.0)) $left $right)))
(@doc ws-prob-gt-independent
  (@desc "Strict independent win probability P(X>Y). Ties contribute zero. This does not test stochastic dominance and cannot recover correlation from marginals.")
  (@params ((@param "Left") (@param "Right")))
  (@return "Probability or refusal"))

(: ws-condition-joint (-> Expression Atom %Undefined%))
(= (ws-condition-joint $joint $observed)
   (let $dist (ws-normalize $joint)
     (if (if-error $dist True False) $dist
       (let $matching
            (filter-atom $dist $pair
              (== (index-atom (index-atom $pair 1) 1) $observed))
         (if (== $matching ())
           (Error $observed "ws-condition-joint requires positive mass for the observed value; choose an observation in the joint support")
           (ws-map (|-> ($pair) (index-atom $pair 2)) $matching))))))
(@doc ws-condition-joint
  (@desc "Condition a joint law of (Pair Input Output) values on the held observed Input, using term identity. Return the Output law. An absent observation refuses because it has no positive conditional mass.")
  (@params ((@param "Joint") (@param "Observed")))
  (@return "Conditional law or refusal"))

(: ws-average-independent (-> Expression %Undefined%))
(= (ws-average-independent ((:seg $laws)))
   (if (== $laws ())
     (Error $laws "ws-average-independent requires at least one distribution; provide a nonempty expression of independent distributions")
     (ws-map-independent
       (|-> ((:seg $values)) (stats-mean $values))
       (:seg $laws))))
(@doc ws-average-independent
  (@desc "The law of the arithmetic mean of a nonempty expression of mutually independent numeric laws. A variadic function composes stats-mean with the independent product operation, retaining its exact or floating result type. Preserve the first input refusal.")
  (@params ((@param "Laws")))
  (@return "Mean law or refusal"))

(: ws-add-bernoulli-independent (-> Expression Number %Undefined%))
(= (ws-add-bernoulli-independent $law $probability)
   (if (or (isnan-math $probability)
           (or (isinf-math $probability) (or (< $probability 0) (> $probability 1))))
     (Error $probability "ws-add-bernoulli-independent requires p in [0, 1]; provide a valid Bernoulli probability")
     (ws-map-independent + $law (((- 1.0 $probability) 0) ($probability 1)))))
(@doc ws-add-bernoulli-independent
  (@desc "Add one independent Bernoulli trial with finite Probability in [0,1] to every numeric outcome. Compose the two-point law with ws-map-independent.")
  (@params ((@param "Law") (@param "Probability")))
  (@return "Law or refusal"))

(: ws-central-moment (-> Expression Number %Undefined%))
(= (ws-central-moment $law $degree)
   (let $dist (ws-normalize $law)
     (if (if-error $dist True False) $dist
       (if (not (and (collections-integer? $degree) (>= $degree 0)))
         (Error $degree "ws-central-moment requires a nonnegative integer degree")
         (let $checked (statistics-data (map-atom $dist $pair (index-atom $pair 1)))
           (if (== $degree 0) 1.0
             (if (== $degree 1) 0.0
               (let $mean (ws-expect $dist)
                 (ws-expect
                   (ws-map (|-> ($x) (pow-math (- $x $mean) $degree)) $dist))))))))))
(@doc ws-central-moment
  (@desc "The nonnegative integer Degree moment about a numeric law's mean. Degree zero is 1.0 and degree one is exactly 0.0 after validating the law and its finite numeric support. Degree two is variance. Other degrees map centered powers and take their expectation.")
  (@params ((@param "Law") (@param "Degree")))
  (@return "Moment or refusal"))

(: ws-variance (-> Expression %Undefined%))
(= (ws-variance $law) (ws-central-moment $law 2))
(@doc ws-variance
  (@desc "The second central moment of a numeric finite law. Center before squaring to avoid subtracting two nearly equal floating moments.")
  (@params ((@param "Law")))
  (@return "Variance or refusal"))

(: ws-deviation (-> Expression %Undefined%))
(= (ws-deviation $law)
   (let $variance (ws-variance $law)
     (if (if-error $variance True False) $variance (sqrt-math $variance))))
(@doc ws-deviation
  (@desc "The floating square root of ws-variance, in the outcome's units.")
  (@params ((@param "Law")))
  (@return "Deviation or refusal"))

(: ws-quantile (-> Expression Number %Undefined%))
(= (ws-quantile $law $level)
   (let $dist (ws-normalize $law)
     (if (if-error $dist True False) $dist
       (if (or (isnan-math $level)
               (or (isinf-math $level) (or (<= $level 0) (> $level 1))))
         (Error $level "ws-quantile takes a level in (0, 1]; 0.5 is the median")
         (let $pairs (ws-flip $dist)
           (statistics-quantile-walk (sort-atom $pairs) $level 0.0))))))
(@doc ws-quantile
  (@desc "The smallest supported value whose cumulative mass reaches the finite Level in (0,1]. This inverse CDF retains supported values, whereas stats-quantile interpolates observations. At level one, the last supported value absorbs final cumulative rounding.")
  (@params ((@param "Law") (@param "Level")))
  (@return "Value or refusal"))

(: ws-median (-> Expression %Undefined%))
(= (ws-median $law) (ws-quantile $law 0.5))
(@doc ws-median
  (@desc "The finite law's inverse CDF at one half.")
  (@params ((@param "Law")))
  (@return "Value or refusal"))

(: ws-support (-> Expression %Undefined%))
(= (ws-support $law)
   (let $dist (ws-normalize $law)
     (if (if-error $dist True False) $dist
       (let $values (map-atom $dist $pair (index-atom $pair 1))
         (sort-atom $values)))))
(@doc ws-support
  (@desc "The law's supported values, once each, in increasing term order.")
  (@params ((@param "Law")))
  (@return "Support or refusal"))

(: ws-sum-independent (-> Expression Number %Undefined%))
(= (ws-sum-independent $law $count)
   (if (not (and (collections-integer? $count) (>= $count 0)))
     (Error $count "ws-sum-independent takes a nonnegative count of independent draws")
     (if (== $count 0) ((1.0 0))
       (let $one (ws-normalize $law)
         (if (if-error $one True False) $one
           (let $draws (collapse (range 0 $count))
             (foldl-atom $draws ((1.0 0)) $sum $draw
               (ws-map-independent + $sum $one))))))))
(@doc ws-sum-independent
  (@desc "The law of a total of Count independent draws. Count is a nonnegative integer. Zero draws give unit mass at zero. Normalize and merge equal partial totals after each convolution, rather than retaining all draw tuples.")
  (@params ((@param "Law") (@param "Count")))
  (@return "Total law or refusal"))
