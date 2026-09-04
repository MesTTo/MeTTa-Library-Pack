; Purpose: finite-choice combinators and exact posterior marginals for
; independent Bernoulli choices conditioned on an additive observation.
; Assumes: weighted subset candidates use the public
; (candidate ID LOSS (ratio NUMERATOR DENOMINATOR)) shape documented in
; 11-weighted_subset_posterior.metta.
; Guarantees: weighted-subset-posterior-independent preserves candidate order
; and exact reduced ratios [tested: test_weighted_subset_matches_exhaustive;
; commit=WORKTREE].
; Fails when: candidate identity or exact-number contracts are missing, or an
; observation has zero mass; each refusal names the supported remedy.

!(import! &self (library lib_import))
!(import_prolog_functions_from_file (library lib_combinatorics.pl)
  (weighted-subset-mass-independent weighted-subset-posterior-independent))

;Range number generator, separate non-det return of each item:
(= (range $K $N)
   (if (< $K $N)
       (superpose ($K (range (+ $K 1) $N)))
       (empty)))

;Combine two elements of $L uniquely e.g. (a b) but not (b a):
(= (choose2 $L)
   (let $j (range 0 (length $L))
           (let $i (range 0 $j)
                ((index-atom $L $i) (index-atom $L $j)))))
(= (choose2l $L)
   (collapse (choose2 $L)))

; choose exactly k elements, unordered
(= (chooseKl $L 0) (let $temp (cut) (())))
(= (chooseKl () $k) (let $temp (cut) ()))
;map-atom's list parameter is Expression and holds its operand as written, so
;the smaller choice set is NAMED before the map reads it.
(= (chooseKl (cons $h $t) $k)
   (let $smaller (chooseKl $t (- $k 1))
     (append (map-atom $smaller (|-> ($c) (cons $h $c)))
             (chooseKl $t $k))))
(= (chooseK $L $k)
   (let $options (chooseKl $L $k) (superpose $options)))


;Take the first K items from the list:
(= (takeK $k ()) ())
(= (takeK $k (cons $head $tail))
   (if (> $k 0)
       (cons $head (takeK (- $k 1) $tail))
       ()))
