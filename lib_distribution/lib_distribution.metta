; Purpose: pure operations over transparent finite value distributions.
; Assumes: a distribution is an expression of (weight value) pairs; functions
;   passed to ws-map and ws-map2-independent are pure and deterministic.
; Guarantees: every distribution result is normalized, duplicate outcomes are
;   collapsed at their first occurrence, and product operations state their
;   independence assumption in their names [tested:
;   test_additive_convolution_is_commutative_associative_and_linear,
;   test_average_preserves_a_refusal_at_every_input_position,
;   test_independent_marginals_and_a_correlated_joint_are_not_interchangeable,
;   test_operations_preserve_the_normalization_refusal,
;   examples/ch22-a-reasoner-you-can-serve/22-02-weighted-answers/12-distribution.metta;
;   commit=f99382c5b4127b49de6e0a6e355d50eda39c5df6].
; Fails when: an input is empty, has a negative or nonfinite weight, or has no
;   positive mass; each refusal names a remedy.
; Decides: "at least" is inclusive, comparison means strict independent win
;   probability, and every product-law head names its independence assumption.
; Open Obligations:
;   To Do: None
;   Hacks: None
;   Future Enhancements: None
;
;Finite value distributions retain lib_measure's visible weight-first rows.
;There is no particle handle, hidden store, or sample budget: map and product
;enumerate the finite support exactly, and ws-normalize owns validity and
;canonicalization.

!(import! &self (library lib_measure))

;The push-forward of a distribution. If several inputs map to the same value,
;their masses add at the first mapped occurrence.
(= (ws-map $fun $ps)
   (let $dist (ws-normalize $ps)
     (if-error $dist
       $dist
       (ws-normalize
         (map-atom $dist
           (|-> ($p) ((index-atom $p 0) ($fun (index-atom $p 1)))))))))

;The push-forward of the product of TWO INDEPENDENT distributions. NumPy's
;convolution contract identifies the same construction for addition: the sum
;of independent random variables has the convolution of their distributions.
;[source: https://github.com/numpy/numpy/blob/2f7fe64b8b6d7591dd208942f1cc74473d5db4cb/numpy/_core/numeric.py#L793-L801; commit=f99382c5b4127b49de6e0a6e355d50eda39c5df6]
;ProbLog's probability semiring and Scallop's add-multiply probability
;provenance both add alternative weights and multiply combined weights.
;[source: https://github.com/ML-KULeuven/problog/blob/168f0399543f32506253fd9f7774dd8aa1222be8/problog/evaluator.py#L184-L209 and https://github.com/scallop-lang/scallop/blob/668bfb6d45ce302fd4ffa7f29916baf3c7ce36ef/core/src/runtime/provenance/probabilistic/add_mult_prob.rs#L48-L62; commit=f99382c5b4127b49de6e0a6e355d50eda39c5df6]
;PRISM makes the preconditions explicit: product is for independent switch
;instances, while sum is for mutually exclusive explanations.
;[source: https://rjida.meijo-u.ac.jp/prism/download/prism23.pdf, PDF page 20, sha256=7998dda53cdcfb713228dff497eaef59e7cc4608a712a42683aa83a9cb6b36e3; commit=f99382c5b4127b49de6e0a6e355d50eda39c5df6]
;
;The name carries the assumption because marginals cannot reveal correlation.
;Rows are visited left-major, then right-major, and equal outputs merge at the
;first such position. If the values share a cause, represent their law as one
;distribution over (Pair left right) and use ws-map on that joint distribution.
(= (ws-map2-independent $fun $left $right)
   (let $a (ws-normalize $left)
     (if-error $a
       $a
       (let $b (ws-normalize $right)
         (if-error $b
           $b
           (let $mapped
                (foldl-atom $a ()
                  (|-> ($outer $pa)
                    (foldl-atom $b $outer
                      (|-> ($inner $pb)
                        (ws-merge-into $inner
                          ((* (index-atom $pa 0) (index-atom $pb 0))
                           ($fun (index-atom $pa 1) (index-atom $pb 1))))))))
             (ws-normalize $mapped)))))))

;Inclusive threshold mass, P(X >= threshold). "at-least" fixes the boundary in
;the name; at the minimum supported value it is one.
(= (ws-mass-at-least $ps $threshold)
   (ws-expect
     (ws-map (|-> ($x) (if (>= $x $threshold) 1.0 0.0)) $ps)))

;Strict independent win probability, P(X > Y). Ties contribute zero. This is
;named for its meaning rather than "compare": stochastic dominance compares
;all thresholds, total variation is a symmetric distance, and expectation
;ordering discards the rest of each distribution.
;[source: https://github.com/rTreutlein/PeTTaChainer/blob/b0e24f9b9d7106ccabf51917f1703abf3ab8c570/pettachainer/metta/dist_formulas.metta#L296-L310; commit=f99382c5b4127b49de6e0a6e355d50eda39c5df6]
(= (ws-prob-gt-independent $left $right)
   (ws-expect
     (ws-map2-independent
       (|-> ($x $y) (if (> $x $y) 1.0 0.0))
       $left $right)))

;The conditional distribution of the second field given an exact first field.
;Joint outcomes have shape (Pair input output), preserving dependence instead
;of reconstructing it from marginals. An absent observation refuses rather
;than returning an empty object that looks like a distribution.
(= (ws-condition-joint $joint $observed)
   (let $dist (ws-normalize $joint)
     (if-error $dist
       $dist
       (let $matching
            (filter-atom $dist
              (|-> ($p)
                (== (index-atom (index-atom $p 1) 1) $observed)))
         (if (== $matching ())
             (Error $observed "ws-condition-joint requires positive mass for the observed value; choose an observation in the joint support")
             (ws-map (|-> ($pair) (index-atom $pair 2)) $matching))))))

;The distribution of the arithmetic mean of a nonempty expression of MUTUALLY
;INDEPENDENT numeric distributions. The product fold forms the distribution of
;their sum before one unary map divides by the number of inputs. A refusal
;short-circuits each fold step so a later input cannot consume Error as rows.
(= (ws-average-independent $dists)
   (if (== $dists ())
       (Error $dists "ws-average-independent requires at least one distribution; provide a nonempty expression of independent distributions")
       (let $sum
            (foldl-atom $dists ((1 0))
              (|-> ($acc $dist)
                (if-error $acc
                  $acc
                  (ws-map2-independent + $acc $dist))))
         (if-error $sum
           $sum
           (let $count (size-atom $dists)
             (ws-map (|-> ($x) (/ $x $count)) $sum))))))

;Add one independent Bernoulli(p) trial to every numeric outcome. The explicit
;probability belongs to the value distribution; proposition truth and
;derivation weights are deliberately not accepted here. PeTTaChainer uses the
;same two-branch additive update, but derives p from an STV; this surface keeps
;those questions separate.
;[source: https://github.com/rTreutlein/PeTTaChainer/blob/b0e24f9b9d7106ccabf51917f1703abf3ab8c570/pettachainer/metta/dist_formulas.metta#L423-L452; commit=f99382c5b4127b49de6e0a6e355d50eda39c5df6]
(= (ws-add-bernoulli-independent $ps $p)
   (if (or (isnan-math $p)
           (or (isinf-math $p) (or (< $p 0.0) (> $p 1.0))))
       (Error $p "ws-add-bernoulli-independent requires p in [0, 1]; provide a valid Bernoulli probability")
       (ws-map2-independent + $ps (((- 1.0 $p) 0) ($p 1)))))

;The moments and the order statistics of a numeric distribution. Each one is a
;fold over the normalized support, so nothing is sampled and the answer is
;exactly what the finite law says; ws-expect is the first moment and the rest
;are written over it.

;The variance, the second moment about the mean. The one-pass form
;E[X^2] - E[X]^2 is not used: it subtracts two nearly equal numbers when the
;mean is large, which loses every significant digit. Two passes over a finite
;support cost twice nothing.
(= (ws-variance $ps)
   (let $dist (ws-normalize $ps)
     (if-error $dist
       $dist
       (let $mean (ws-expect $dist)
         (ws-expect (ws-map (|-> ($x) (let $d (- $x $mean) (* $d $d))) $dist))))))

;The standard deviation, the square root of the variance, in the values' own
;units.
(= (ws-deviation $ps)
   (let $variance (ws-variance $ps)
     (if-error $variance $variance (sqrt-math $variance))))

;The nth moment about the mean, so 2 is the variance and 3 and 4 are what skew
;and kurtosis are computed from. The first central moment is 0.0 by definition,
;and this answers exactly that rather than a rounding of it.
(= (ws-central-moment $ps $n)
   (let $dist (ws-normalize $ps)
     (if-error $dist
       $dist
       (let $mean (ws-expect $dist)
         (ws-expect (ws-map (|-> ($x) (pow-math (- $x $mean) $n)) $dist))))))

;The probability that a draw is at most the threshold, which is the cumulative
;distribution function at that point; ws-mass-at-least is its inclusive upper
;tail.
(= (ws-mass-at-most $ps $threshold)
   (ws-expect (ws-map (|-> ($x) (if (<= $x $threshold) 1.0 0.0)) $ps)))

;The smallest value whose cumulative mass reaches the level, which is the
;quantile function: the median is the quantile at 0.5. A level outside (0, 1]
;refuses, because no value answers it.
(= (ws-quantile $ps $level)
   (let $dist (ws-normalize $ps)
     (if-error $dist
       $dist
       (if (or (<= $level 0.0) (> $level 1.0))
           (Error $level "ws-quantile takes a level in (0, 1]; 0.5 is the median")
           (ws-quantile-walk (sort-atom (ws-flip $dist)) $level 0.0)))))

;The walk the quantile is defined by: values in increasing order, mass added
;until the level is reached. The last value answers whatever rounding leaves,
;so a level of 1.0 always has an answer.
(= (ws-quantile-walk $pairs $level $seen)
   (let $pair (car-atom $pairs)
     (let $rest (cdr-atom $pairs)
       (let $mass (+ $seen (index-atom $pair 1))
         (if (or (>= $mass $level) (== $rest ()))
             (index-atom $pair 0)
             (ws-quantile-walk $rest $level $mass))))))

;The median, which is the quantile at one half.
(= (ws-median $ps) (ws-quantile $ps 0.5))

;The support as an ordered expression of values, weights dropped: what the
;distribution can answer, once each, smallest first.
(= (ws-support $ps)
   (let $dist (ws-normalize $ps)
     (if-error $dist
       $dist
       (sort-atom (map-atom $dist (|-> ($p) (index-atom $p 1)))))))

;n independent draws, summed: the distribution of a total rather than of one
;draw. Zero draws are the point mass at 0, and the convolution is exact, so
;this is the law and not a simulation of it.
(= (ws-sum-independent $ps $n)
   (if (< $n 0)
       (Error $n "ws-sum-independent takes a nonnegative count of independent draws")
       (if (== $n 0)
           ((1.0 0))
           (let $one (ws-normalize $ps)
             (if-error $one
               $one
               (ws-map2-independent + $one (ws-sum-independent $one (- $n 1))))))))

(@doc ws-variance
  (@desc "The variance of a numeric distribution, computed about the mean in two passes over the finite support, because the one-pass E[X^2]-E[X]^2 form loses its significant digits when the mean is large.")
  (@params ((@param "a distribution of (weight value) pairs")))
  (@return "the variance"))
(@doc ws-deviation
  (@desc "The standard deviation, the square root of the variance, in the values' own units.")
  (@params ((@param "a distribution of (weight value) pairs")))
  (@return "the standard deviation"))
(@doc ws-central-moment
  (@desc "The nth moment about the mean: 2 is the variance, and 3 and 4 are what skew and kurtosis are computed from. The first is exactly 0.0.")
  (@params ((@param "a distribution of (weight value) pairs") (@param "which moment")))
  (@return "the moment"))
(@doc ws-mass-at-most
  (@desc "The probability that a draw is at most the threshold, which is the cumulative distribution function at that point. ws-mass-at-least is the inclusive upper tail.")
  (@params ((@param "a distribution of (weight value) pairs") (@param "the threshold, included")))
  (@return "the mass at or below it"))
(@doc ws-quantile
  (@desc "The smallest value whose cumulative mass reaches the level, the quantile function. A level outside (0, 1] refuses, because no value answers it.")
  (@params ((@param "a distribution of (weight value) pairs") (@param "a level in (0, 1]")))
  (@return "the value at that level"))
(@doc ws-median
  (@desc "The median, which is the quantile at one half.")
  (@params ((@param "a distribution of (weight value) pairs")))
  (@return "the median value"))
(@doc ws-support
  (@desc "The values the distribution can answer, once each, smallest first, with the weights dropped.")
  (@params ((@param "a distribution of (weight value) pairs")))
  (@return "the ordered support"))
(@doc ws-sum-independent
  (@desc "The distribution of the sum of n independent draws, by exact convolution rather than simulation. Zero draws are the point mass at 0; a negative count refuses.")
  (@params ((@param "a distribution of (weight value) pairs") (@param "how many independent draws")))
  (@return "the distribution of the total"))
