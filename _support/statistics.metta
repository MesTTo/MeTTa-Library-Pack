; Purpose: private sample validation and exact arithmetic compositions.
; Assumes: the native boundary checks finite expression structure; Math and
; Vector own numeric representation and division.
; Guarantees: a host approximation is refused before an exact result is claimed.
; [tested: lib_statistics; commit=WORKTREE].
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
