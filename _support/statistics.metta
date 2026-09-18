; Purpose: private sample validation and exact probability arithmetic.
; Assumes: the native boundary checks finite expression structure; Math and
; Vector own numeric representation and division.
; Guarantees: a host approximation is refused before an exact result is claimed.
; [tested: lib_statistics; commit=e1be99ea1c08f70444c1c35cada441e089777906].
; Guarantees: weighted-subset rows merge equal sums, truncate at the target
; and preserve exact integer coefficients and literal candidate identities.
; [tested: weighted_subset, test_weighted_subset_matches_exhaustive;
; commit=e1be99ea1c08f70444c1c35cada441e089777906].
(: statistics-data (-> Expression Expression))
(= (statistics-data $data)
   (let* (($checked (collections-expression $data))
          ($values (map-atom $checked $value
                     (let $exact (math-rational $value)
                       (let $number (assertEqualMsg (if-error $exact False True) True
                                                   (quote (finite-observation $value $exact)))
                         $exact))))
          ($floats (filter-atom $checked $value
                     (let $class (math-class $value)
                       (not (or (== $class integer) (== $class rational)))))))
     ($values (!= $floats ()))))

(: statistics-exact (-> Number Number))
(= (statistics-exact $value)
   (let $class (math-class $value)
     (let $checked (assertEqualMsg (or (== $class integer) (== $class rational)) True
                                  (quote (exact-statistics-arithmetic $value)))
       $value)))

(: statistics-add (-> Number Number Number))
(= (statistics-add $left $right) (statistics-exact (+ $left $right)))

(: statistics-divide (-> Number Number Number))
(= (statistics-divide $left $right)
   (index-atom (vector-divide ($left) ($right)) 0))

(: statistics-result (-> Bool Number Number))
(= (statistics-result $floating $value) (if $floating (math-float $value) $value))

(: statistics-size (-> Expression Number Number))
(= (statistics-size $values $degrees)
   (let* (($n (collections-size $values))
          ($checked (assertEqualMsg
                     (and (collections-integer? $degrees)
                          (and (>= $degrees 0) (> $n $degrees))) True
                     (quote (statistical-sample-size $n $degrees)))))
     $n))

(: statistics-nonnegative (-> Expression Expression))
(= (statistics-nonnegative $data)
   (let* ((($values $floating) (statistics-data $data))
          ($n (statistics-size $values 0))
          ($checked (forall (index-atom $values (range 0 $n))
                     (|-> ($value) (assertEqualMsg (>= $value 0) True
                                                 (quote (nonnegative-observation $value)))))))
     ($values $floating $n)))

(: statistics-paired (-> Expression Expression Expression))
(= (statistics-paired $left $right)
   (let* ((($a $af) (statistics-data $left))
          (($b $bf) (statistics-data $right))
          ($checked (assertEqualMsg (size-atom $a) (size-atom $b)
                                   (quote (paired-observation-lengths $left $right)))))
     ($a $b (or $af $bf))))

(: statistics-method (-> Symbol Bool))
(= (statistics-method $method)
   (assertEqualMsg (or (== $method inclusive) (== $method exclusive)) True
                   (quote (quantile-method $method))))

(: statistics-sorted (-> Expression Expression))
(= (statistics-sorted $data)
   (let* ((($values $floating) (statistics-data $data))
          ($n (statistics-size $values 0))
          ($pool (sort-atom $values)))
     (($pool $n) $floating)))

; Interpolation follows CPython's inclusive and exclusive order positions.
; https://github.com/python/cpython/blob/ebf955df7a89ed0c7968f79faec1de49f61ed7cb/Lib/statistics.py#L1165-L1218
(: statistics-quantile (-> Expression Number Number Symbol Number))
(= (statistics-quantile $pool $n $p $method)
   (if (== $n 1) (index-atom $pool 0)
     (let* (($position (statistics-exact
                        (if (== $method inclusive) (* $p (- $n 1))
                                                    (- (* $p (+ $n 1)) 1))))
            ($j (max-atom (0 (min-atom ((floor-math $position) (- $n 2))))))
            ($delta (statistics-exact (- $position $j)))
            ($a (index-atom $pool $j))
            ($b (index-atom $pool (+ $j 1))))
       (statistics-exact (+ (* $a (- 1 $delta)) (* $b $delta))))))

(: statistics-bits (-> Number Number))
(= (statistics-bits $number)
   (size-atom
     (unfold (|-> ($value)
               (if (== $value 0) (empty)
                 (let $next (bit-shift-right $value 1) ($value $next))))
             $number)))

(: statistics-scale (-> Number Number Number))
(= (statistics-scale $value $exponent)
   (if (>= $exponent 0)
     (statistics-exact (* $value (bit-shift-left 1 $exponent)))
     (statistics-divide $value (bit-shift-left 1 (- 0 $exponent)))))

(: statistics-log-parts (-> Expression Number Expression))
(= (statistics-log-parts $state $value)
   (let* ((($exponent $logs) $state)
          (($numerator $denominator) (math-ratio $value))
          ($shift (- (statistics-bits $numerator) (statistics-bits $denominator)))
          ($mantissa (math-float (statistics-scale $value (- 0 $shift))))
          ($log (math-rational (log-math (math-real e ()) $mantissa))))
     ((+ $exponent $shift) (statistics-exact (+ $logs $log)))))

(: statistics-quantile-walk (-> Expression Number Number %Undefined%))
(= (statistics-quantile-walk (($value $weight) (:seg $rest)) $level $seen)
   (let $mass (+ $seen $weight)
     (if (or (>= $mass $level) (== $rest ())) (quote $value)
       (statistics-quantile-walk $rest $level $mass))))

; A probability-generating row is an ordered expression of (Sum Weight) pairs.
; Integer coefficients share the product of canonical prior denominators.
; The forward/backward algorithm and its exact-number contract are recorded in
; docs/journal/2026-09-05-pettachainer-adaptations.md, Finding9.
(: statistics-subset-ratio (-> Number Number Expression))
(= (statistics-subset-ratio $numerator $denominator)
   (let* (($divisor (math-gcd ($numerator $denominator)))
          ($n (floor-div $numerator $divisor))
          ($d (floor-div $denominator $divisor)))
     (quote (ratio $n $d))))

(: statistics-subset-candidate (-> Atom Atom Expression))
(= (statistics-subset-candidate $operation $raw)
   (let $shape (assertEqualMsg
                (if (== (get-metatype $raw) Expression) (collections-size $raw) -1)
                4 (quote ($operation "use (candidate ID LOSS (ratio NUMERATOR DENOMINATOR)) for every row" $raw)))
     (let ($tag $id $loss $prior) (noeval $raw)
       (let* (($candidate (assertEqualMsg (== $tag candidate) True
                           (quote ($operation "use (candidate ID LOSS (ratio NUMERATOR DENOMINATOR)) for every row" $raw))))
              ($identity (assertEqualMsg (is-ground $id) True
                           (quote ($operation "assign each independent Bernoulli event a distinct ground acyclic ID" $id))))
              ($lattice (assertEqualMsg
                          (and (collections-integer? $loss) (>= $loss 0)) True
                          (quote ($operation "use a nonnegative integer loss; fixed-point callers must choose one shared integer scale" $id $loss))))
              ($shape (assertEqualMsg
                        (if (== (get-metatype $prior) Expression) (collections-size $prior) -1)
                        3 (quote ($operation "use an exact (ratio NUMERATOR DENOMINATOR) with integer 0 <= NUMERATOR <= DENOMINATOR and DENOMINATOR > 0" $id $prior)))))
         (let ($ratio-tag $n $d) (noeval $prior)
           (let* (($probability (assertEqualMsg
                                 (and (== $ratio-tag ratio)
                                   (and (and (collections-integer? $n) (collections-integer? $d))
                                     (and (> $d 0) (and (>= $n 0) (<= $n $d))))) True
                                 (quote ($operation "use an exact (ratio NUMERATOR DENOMINATOR) with integer 0 <= NUMERATOR <= DENOMINATOR and DENOMINATOR > 0" $id $prior))))
                  ($canonical (statistics-subset-ratio $n $d)))
             (quote (candidate $id $loss $canonical))))))))

(: statistics-subset-prepare (-> Atom Atom Number Expression))
(= (statistics-subset-prepare $operation $raw $target)
   (let* (($lattice (assertEqualMsg
                     (and (collections-integer? $target) (>= $target 0)) True
                     (quote ($operation "use a nonnegative integer target; fixed-point callers must choose one shared integer scale" $target))))
          ($finite (collections-expression $raw))
          ($candidates (map-atom $finite $row (statistics-subset-candidate $operation $row)))
          ($ids (map-atom $candidates $row (index-atom $row 1)))
          ($distinct (assertEqualMsg (size-atom (unique-atom $ids)) (size-atom $ids)
                       (quote ($operation "assign each independent Bernoulli event a distinct ground ID" $ids))))
          ($denominator (foldl-atom $candidates 1 $product $row
                          (* $product (index-atom (index-atom $row 3) 2)))))
     (quote ($candidates $denominator))))

(: statistics-subset-shift (-> Expression Number Number Number Expression))
(= (statistics-subset-shift $row $factor $shift $target)
   (if (== $factor 0) ()
     (map-atom (filter-atom $row $cell (<= (+ (index-atom $cell 0) $shift) $target))
       $cell
       (let* ((($sum $weight) $cell)
              ($next (+ $sum $shift)) ($scaled (* $weight $factor)))
         (quote ($next $scaled))))))

; Each unfold step consumes at least one ordered tail. Equal keys combine once.
(: statistics-subset-merge-step (-> Expression Expression))
(= (statistics-subset-merge-step ($left $right))
   (if (== $left ())
     (if (== $right ()) (empty)
       (let ($head (:seg $rest)) (quote $right) (quote ($head (() $rest)))))
     (let (($a $aw) (:seg $as)) (quote $left)
       (if (== $right ()) (quote (($a $aw) ($as ())))
         (let (($b $bw) (:seg $bs)) (quote $right)
           (if (< $a $b) (quote (($a $aw) ($as $right)))
             (if (> $a $b) (quote (($b $bw) ($left $bs)))
               (let $weight (+ $aw $bw) (quote (($a $weight) ($as $bs)))))))))))

(: statistics-subset-step (-> Number Expression Atom Expression))
(= (statistics-subset-step $target $before $candidate)
   (let ($tag $id $loss ($ratio-tag $n $d)) (noeval $candidate)
     (unfold statistics-subset-merge-step
       ((statistics-subset-shift $before (- $d $n) 0 $target)
        (statistics-subset-shift $before $n $loss $target)))))

(: statistics-subset-rows (-> Atom Number Expression))
(= (statistics-subset-rows $candidates $target)
   (unfold
     (|-> ($state)
       (if (== $state ()) (empty)
         (let ($pending $before) $state
           (if (== $pending ()) (quote ($before ()))
             (let* ((($first (:seg $rest)) (quote $pending))
                    ($after (statistics-subset-step $target $before $first)))
               (quote ($before ($rest $after))))))))
     (quote ($candidates ((0 1))))))

(: statistics-subset-weight (-> Expression Number Number))
(= (statistics-subset-weight $row $target)
   (case (pairs-lookup $row $target) ((Empty 0) ($weight $weight))))

; Prefix keys ascend and suffix keys descend, so each comparison discards a tail
; head that cannot contribute another matching pair. Only equality multiplies.
(: statistics-subset-convolution-step (-> Number Expression Expression))
(= (statistics-subset-convolution-step $target ($left $right))
   (if (or (== $left ()) (== $right ())) (empty)
     (let* (((($a $aw) (:seg $as)) $left)
            ((($b $bw) (:seg $bs)) $right)
            ($sum (+ $a $b)))
       (if (< $sum $target) (quote (0 ($as $right)))
         (if (> $sum $target) (quote (0 ($left $bs)))
           (let $product (* $aw $bw) (quote ($product ($as $bs)))))))))

(: statistics-subset-convolution (-> Expression Expression Number Number))
(= (statistics-subset-convolution $left $right $target)
   (if (< $target 0) 0
     (let* (($descending (reverse $right))
            ($products (unfold (statistics-subset-convolution-step $target)
                         (quote ($left $descending)))))
       (foldl-atom $products 0 $total $product (+ $total $product)))))

(: statistics-subset-marginal (-> Number Number Atom Expression))
(= (statistics-subset-marginal $target $observation $entry)
   (let (($tag $id $loss ($ratio-tag $n $d)) ($prefix $suffix)) (noeval $entry)
     (let* (($others (statistics-subset-convolution $prefix $suffix (- $target $loss)))
            ($ratio (statistics-subset-ratio (* $n $others) $observation)))
       (quote (candidate-posterior $id $ratio)))))
