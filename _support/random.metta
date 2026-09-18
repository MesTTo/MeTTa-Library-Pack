; Purpose: share validation and numeric recipes for inspectable sample programs.
; Guarantees: exact component operations retain gamma factors and corrections
; until a final scale or ratio, with no sampler state or cached normal spare.
; [tested: lib_random; commit=1d0b78a359f58de49f2f98bed50a6480d56cd5f6].

(: random-parameters (-> Expression Expression))
(= (random-parameters $parameters)
   (map-atom $parameters $parameter
     (let* (($value (math-float $parameter))
            ($class (math-class $value))
            ($checked (assertEqualMsg
                       (not (or (== $class infinite) (== $class nan))) True
                       (quote (finite-random-parameter $parameter)))))
       $value)))

(: random-position (-> Number Number))
(= (random-position $size)
   (if (== $size 1) 0 (random-int 0 (- $size 1))))

(: random-exact-binary (-> %Undefined% Number Number Number))
(= (random-exact-binary $operation $left $right)
   (index-atom
     ($operation ((math-rational $left)) ((math-rational $right))) 0))

(: random-interpolate (-> Number Number Number Number))
(= (random-interpolate $position $low $high)
   (let $r (math-rational $position)
     (dot ((random-exact-binary vector-subtract 1 $r) $r) ($low $high))))

; Box-Muller uses two uniforms; the host generator remains the complete state.
; https://github.com/python/cpython/blob/ebf955df7a89ed0c7968f79faec1de49f61ed7cb/Lib/random.py#L557-L592
(: random-standard-normal (-> Number))
(= (random-standard-normal)
   (let* (($u (random-float 0 1)) ($v (random-float 0 1)))
     (* (cos-math (* (* 2 (math-real pi ())) $u))
        (sqrt-math (* -2 (log-math (math-real e ()) $v))))))

; Keep the Marsaglia/Tsang factors separate from the shape-boosting power.
; https://github.com/rust-random/rand_distr/blob/d65b9bbf991e56d8a097a35d934e6f93d9194ac0/src/gamma.rs#L203-L287
(: random-gamma-parts (-> Number Expression))
(= (random-gamma-parts $shape)
   (if (< $shape 1.0)
     (let* (($factors (random-gamma-factors (+ $shape 1.0)))
            ($u (random-float 0 1))
            ($correction (random-exact-binary vector-divide
                           (log-math (math-real e ()) $u) $shape)))
       ($factors $correction))
     ((random-gamma-factors $shape) 0)))

(: random-gamma-factors (-> Number Expression))
(= (random-gamma-factors $shape)
   (if (== $shape 1.0)
     ((- 0.0 (log-math (math-real e ()) (random-float 0 1))))
     (let* (($d (- $shape (/ 1.0 3.0)))
            ($c (/ (/ 1.0 3.0) (sqrt-math $d)))
            ($v (random-gamma-accept $d $c)))
       ($d $v))))

(: random-gamma-accept (-> Number Number Number))
(= (random-gamma-accept $d $c)
   (let* (($z (random-standard-normal)) ($root (+ 1.0 (* $c $z))))
     (if (> $root 0.0)
       (let* (($v (* (* $root $root) $root))
              ($u (random-float 0 1)) ($z2 (* $z $z)))
         (if (or (< $u (- 1.0 (* (* 0.0331 $z2) $z2)))
                 (< (log-math (math-real e ()) $u)
                    (+ (* 0.5 $z2)
                       (* $d (+ (- 1.0 $v) (log-math (math-real e ()) $v))))))
           $v (random-gamma-accept $d $c)))
       (random-gamma-accept $d $c))))

(: random-product (-> Expression Number))
(= (random-product $factors)
   (foldl-atom $factors 1 $acc $factor
     (random-exact-binary vector-multiply $acc $factor)))

(: random-log-product (-> Expression Number Number))
(= (random-log-product $factors $correction)
   (foldl-atom $factors $correction $acc $factor
     (random-exact-binary vector-add $acc (log-math (math-real e ()) $factor))))

; Ordinary powers multiply exactly. Logs rescue range before the final scale.
(: random-positive-value (-> Expression Number Number))
(= (random-positive-value $factors $correction)
   (let $power (exp-math (math-float $correction))
     (if (== (math-class $power) normal)
       (math-float (random-product (cons-atom $power $factors)))
       (exp-math (math-float (random-log-product $factors $correction))))))

; Preserve underflowed powers through their exact logarithmic difference.
; https://github.com/numpy/numpy/blob/2f7fe64b8b6d7591dd208942f1cc74473d5db4cb/numpy/random/src/distributions/distributions.c#L429-L459
(: random-beta-value (-> Number Number Number))
(= (random-beta-value $alpha $beta)
   (let* ((($af $ac) (random-gamma-parts $alpha))
          (($bf $bc) (random-gamma-parts $beta)))
     (if (== $ac $bc)
       (let* (($x (random-product $af)) ($y (random-product $bf))
              ($sum (random-exact-binary vector-add $x $y)))
         (math-float (random-exact-binary vector-divide $x $sum)))
       (let* (($x (random-log-product $af $ac)) ($y (random-log-product $bf $bc))
              ($delta (random-exact-binary vector-subtract $x $y))
              ($tail (exp-math (math-float (- 0 (abs-math $delta))))))
         (if (>= $delta 0) (/ 1.0 (+ 1.0 $tail))
                           (/ $tail (+ 1.0 $tail)))))))
