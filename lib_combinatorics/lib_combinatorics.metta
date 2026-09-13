; Purpose: finite choices as MeTTa answer streams, with a native exact posterior algorithm.
; Guarantees: choices preserve order, multiplicity, literal values and variable
; identity; counts stay exact and invalid finite domains raise.
; [tested: lib_combinatorics_surface; commit=6fa571d1b7059b610f73e9feed657711414251e5].
; The weighted-subset native contract is documented in its provider and example.

!(import! &self (library "_support/collections.metta"))
!(import! &self (library "_support/combinatorics.metta"))

;Range number generator, separate non-det return of each item:
(: range (-> Number Number Number))
(= (range $K $N) (range-step $K $N 1))
(@doc range
  (@desc "Answer numbers from K to the excluded N in unit steps; the unit-stride specialization of range-step.")
  (@params ((@param "K") (@param "N")))
  (@return "Value"))

;Combine two elements of $L uniquely e.g. (a b) but not (b a):
(: choose2 (-> Expression Expression))
(= (choose2 $L)
   (let $size (collections-size $L)
     (let ((:seg $before) $later (:seg $after)) (quote $L)
       (let ((:seg $pre) $earlier (:seg $post)) (quote $before)
         (quote ($earlier $later))))))
(@doc choose2
  (@desc "Choose two positions, the later index varying slowest. Duplicate values at distinct positions remain separate choices.")
  (@params ((@param "Items")))
  (@return "Pair"))
(: choose2l (-> Expression Expression))
(= (choose2l $L)
   (collapse (choose2 $L)))
(@doc choose2l
  (@desc "The existing collected spelling of choose2: collapse its answer stream.")
  (@params ((@param "Items")))
  (@return "Pairs"))

; The stream is the basis; collecting it is an ordinary collapse.
(: chooseK (-> Expression Number Expression))
(= (chooseK $items $count)
   (let* (($size (collections-size $items))
          ($checked (assertEqualMsg (and (collections-integer? $count) (>= $count 0))
                                    True (quote (chooseK $items $count)))))
     (if (== $count 0) ()
       (if (> $count $size) (empty)
         (let ($head (:seg $rest)) (quote $items)
           (superpose
             ((let $tail (chooseK (quote $rest) (- $count 1))
                (cons-atom $head $tail))
              (chooseK (quote $rest) $count))))))))
(@doc chooseK
  (@desc "Choose a nonnegative integer Count of the positions, keeping input order. Each choice is an answer, so once can stop before later choices are built. Zero gives one empty choice; too many gives no answers.")
  (@params ((@param "Items") (@param "Count")))
  (@return "Choice"))
(: chooseKl (-> Expression Number Expression))
(= (chooseKl $items $count)
   (collapse (chooseK (quote $items) $count)))
(@doc chooseKl
  (@desc "The existing collected spelling of chooseK: collapse its answer stream.")
  (@params ((@param "Items") (@param "Count")))
  (@return "Choices"))


;Take the first K items from the list:
(: takeK (-> Number Expression Expression))
(= (takeK $k ()) ())
(= (takeK $k (cons $head $tail))
   (if (> $k 0)
       (cons $head (takeK (- $k 1) $tail))
       ()))
(@doc takeK
  (@desc "The first K items, or the whole expression when it is shorter. Zero or a negative count gives the empty prefix.")
  (@params ((@param "Count") (@param "Items")))
  (@return "Prefix"))

(: range-step (-> Number Number Number Number))
(= (range-step $from $to $step)
   (let* (($finite (assertEqualMsg
                   (or (or (isinf-math $from) (isnan-math $from))
                       (or (isinf-math $to) (isnan-math $to)))
                   False (quote (range-step $from $to $step))))
          ($step-ok (assertEqualMsg (and (collections-integer? $step) (!= $step 0))
                                   True (quote (range-step $from $to $step)))))
     (combinatorics-range-loop $from $to $step)))
(@doc range-step
  (@desc "Answer numbers from From toward the excluded To, moving by a nonzero integer Step. Endpoints may be finite fractions. Refuse non-finite endpoints and a step too small to change the current float. A step pointing away from To has no answers.")
  (@params ((@param "From") (@param "To") (@param "Step")))
  (@return "Value"))

(: tuples (-> Expression Expression))
(= (tuples $sets)
   (let* (($size (collections-size $sets))
          ($checked (forall (index-atom $sets (range 0 $size))
                     (|-> ($set) (let $length (collections-size $set) True)))))
     (map-atom $sets $set
       (let ((:seg $before) $item (:seg $after)) (quote $set) (quote $item)))))
(@doc tuples
  (@desc "Choose one literal value from every population, the last varying fastest. Validate every population before enumerating. An empty population gives no answers; no populations gives one empty tuple. Variable sharing is retained.")
  (@params ((@param "Sets")))
  (@return "Tuple"))

(: cartesian-power (-> Expression Number Expression))
(= (cartesian-power $items $length)
   (let* (($size (collections-size $items))
          ($checked (assertEqualMsg
                     (and (collections-integer? $length) (>= $length 0))
                     True (quote (cartesian-power $items $length)))))
     (if (== $length 0) ()
       (if (== $size 0) (empty)
         (tuples (map-atom (collapse (range 0 $length)) $i (quote $items)))))))
(@doc cartesian-power
  (@desc "The Cartesian product of Length copies of Items, retaining literal values and variable sharing. A nonnegative integer length of zero gives one empty tuple. An empty population at a positive length gives no answers.")
  (@params ((@param "Items") (@param "Length")))
  (@return "Tuple"))

(: permutations (-> Expression Expression))
(= (permutations $items)
   (let $size (collections-size $items)
     (if (== $size 0) ()
       (let ((:seg $before) $item (:seg $after)) (quote $items)
         (let $rest (union-atom $before $after)
           (cons-atom $item (permutations (quote $rest))))))))
(@doc permutations
  (@desc "Every ordering of the items, one per answer, in the host's own order: the items as given first, then the orderings that swap the latest elements. A repeated item makes repeated answers, because a permutation counts positions and not values. Empty items have exactly one permutation, the empty one.")
  (@params ((@param "Items")))
  (@return "Permutation"))

(: subsets (-> Expression Expression))
(= (subsets $items)
   (let $size (collections-size $items)
     (if (== $size 0) ()
       (let ($head (:seg $rest)) (quote $items)
         (let* (($tail (subsets (quote $rest)))
                ($included (cons-atom $head $tail)))
           (superpose ((quote $included) (quote $tail))))))))
(@doc subsets
  (@desc "Every subset, one per answer, each keeping the items' own order: the powerset, so n items give 2^n answers, starting with the whole set and ending with the empty one. A repeated item is a distinct position, so (a a) has four subsets.")
  (@params ((@param "Items")))
  (@return "Subset"))

(: permutation-count (-> Number Number Number))
(= (permutation-count $n $k)
   (let $checked
       (assertEqualMsg (and (and (collections-integer? $n) (collections-integer? $k)) (>= $n 0))
                       True (quote (permutation-count $n $k)))
     (if (or (< $k 0) (> $k $n)) 0
       (foldall (|-> ($factor $acc) (* $acc $factor))
                (range (+ (- $n $k) 1) (+ $n 1)) 1))))
(@doc permutation-count
  (@desc "How many ordered choices of Chosen items there are among Count of them, exactly: Count falling by one, Chosen times. Choosing more than there are is 0, and choosing none is 1.")
  (@params ((@param "Count") (@param "Chosen")))
  (@return "Result"))

(: factorial (-> Number Number))
(= (factorial $n)
   (permutation-count $n $n))
(@doc factorial
  (@desc "The exact factorial of a nonnegative integer, with zero giving one. This specializes permutation-count to choose every position.")
  (@params ((@param "Number")))
  (@return "Result"))

(: binomial (-> Number Number Number))
(= (binomial $n $k)
   (let* (($small (min $k (- $n $k)))
          ($product (permutation-count $n $small)))
     (if (== $product 0) 0 (floor-div $product (factorial $small)))))
(@doc binomial
  (@desc "The exact number of unordered choices. Divide a falling product by its factorial over the smaller side. An integer Chosen outside zero through Count gives zero; a negative Count or non-integer raises.")
  (@params ((@param "Count") (@param "Chosen")))
  (@return "Result"))

; begin generated Prolog face
; GENERATED by extensions/python/tools/prologface.py --write from lib/*/*.pl, tests/data/prologface/*.pl, extensions/python/tools/prologface_source.pl: the prolog-face artifact in extensions/python/tools/artifacts.py, whose prolog-face lane refuses drift.
!(import! &self (library lib_import))
!(import_prolog_functions_from_file (library "lib_combinatorics/lib_combinatorics.pl")
  (weighted-subset-mass-independent weighted-subset-posterior-independent))

(: weighted-subset-mass-independent (-> Expression Number Expression))
(@doc weighted-subset-mass-independent
  (@desc "The exact probability that the losses of the independently chosen candidates add up to Target, as the reduced (ratio Numerator Denominator). Each candidate is (candidate Id Loss (ratio Numerator Denominator)) with a nonnegative integer loss, and equal partial sums are merged at every layer rather than enumerated, so the work is bounded by the target and not by 2^n. A target that cannot be reached has mass (ratio 0 1).")
  (@params ((@param "Candidates") (@param "Target")))
  (@return "Ratio"))

(: weighted-subset-posterior-independent (-> Expression Number Expression))
(@doc weighted-subset-posterior-independent
  (@desc "The observation's own mass and every candidate's posterior probability of having been chosen given that the losses add up to Target, as (subset-posterior Mass ((candidate-posterior Id Ratio) ...)) in the candidates' own order. The marginals come from one forward and one backward pass rather than from enumerating subsets. Conditioning on a target of zero mass refuses and names weighted-subset-mass-independent as the operation that still reports reachability.")
  (@params ((@param "Candidates") (@param "Target")))
  (@return "Posterior"))
; end generated Prolog face
