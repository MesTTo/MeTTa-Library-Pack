; Purpose: pure operations over transparent finite value distributions.
; Assumes: a distribution is an expression of (weight value) pairs; functions
;   passed to ws-map and ws-map2-independent are pure and deterministic.
; Guarantees: every distribution result is normalized, duplicate outcomes are
;   collapsed at their first occurrence, and product operations state their
;   independence assumption in their names [tested:
;   test_additive_convolution_is_commutative_associative_and_linear,
;   test_independent_marginals_and_a_correlated_joint_are_not_interchangeable,
;   test_operations_preserve_the_normalization_refusal,
;   examples/ch22-a-reasoner-you-can-serve/22-02-weighted-answers/12-distribution.metta;
;   commit=WORKTREE].
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
;[source: https://github.com/numpy/numpy/blob/2f7fe64b8b6d7591dd208942f1cc74473d5db4cb/numpy/_core/numeric.py#L793-L801; commit=WORKTREE]
;ProbLog's probability semiring and Scallop's add-multiply probability
;provenance both add alternative weights and multiply combined weights.
;[source: https://github.com/ML-KULeuven/problog/blob/168f0399543f32506253fd9f7774dd8aa1222be8/problog/evaluator.py#L184-L209 and https://github.com/scallop-lang/scallop/blob/668bfb6d45ce302fd4ffa7f29916baf3c7ce36ef/core/src/runtime/provenance/probabilistic/add_mult_prob.rs#L48-L62; commit=WORKTREE]
;PRISM makes the preconditions explicit: product is for independent switch
;instances, while sum is for mutually exclusive explanations.
;[source: https://rjida.meijo-u.ac.jp/prism/download/prism23.pdf, PDF page 20, sha256=7998dda53cdcfb713228dff497eaef59e7cc4608a712a42683aa83a9cb6b36e3; commit=WORKTREE]
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
;[source: https://github.com/rTreutlein/PeTTaChainer/blob/b0e24f9b9d7106ccabf51917f1703abf3ab8c570/pettachainer/metta/dist_formulas.metta#L296-L310; commit=WORKTREE]
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
;their sum before one unary map divides by the number of inputs.
(= (ws-average-independent $dists)
   (if (== $dists ())
       (Error $dists "ws-average-independent requires at least one distribution; provide a nonempty expression of independent distributions")
       (let $sum
            (foldl-atom $dists ((1 0))
              (|-> ($acc $dist) (ws-map2-independent + $acc $dist)))
         (if-error $sum
           $sum
           (let $count (size-atom $dists)
             (ws-map (|-> ($x) (/ $x $count)) $sum))))))

;Add one independent Bernoulli(p) trial to every numeric outcome. The explicit
;probability belongs to the value distribution; proposition truth and
;derivation weights are deliberately not accepted here. PeTTaChainer uses the
;same two-branch additive update, but derives p from an STV; this surface keeps
;those questions separate.
;[source: https://github.com/rTreutlein/PeTTaChainer/blob/b0e24f9b9d7106ccabf51917f1703abf3ab8c570/pettachainer/metta/dist_formulas.metta#L423-L452; commit=WORKTREE]
(= (ws-add-bernoulli-independent $ps $p)
   (if (or (isnan-math $p)
           (or (isinf-math $p) (or (< $p 0.0) (> $p 1.0))))
       (Error $p "ws-add-bernoulli-independent requires p in [0, 1]; provide a valid Bernoulli probability")
       (ws-map2-independent + $ps (((- 1.0 $p) 0) ($p 1)))))
