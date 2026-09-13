; Purpose: construct inspectable sample programs and select distinct occurrences.
; Guarantees: construction validates without drawing; eval and repeat consume
; only demanded samples from the existing thread-local generator.
; [tested: lib_random; commit=WORKTREE].
; Owns resources: no stored state; with-seed owns generator restoration.
; [source: engine/metta/control.pl:metta_with_seed/4; commit=WORKTREE].
; Decides: parameters use finite binary64, numeric results use IEEE saturation,
; and sample programs remain ordinary expressions which callers may rewrite.

!(import! &self (library lib_math))
!(import! &self (library lib_functional))
!(import! &self (library "_support/random.metta"))

(: random-choice (-> Atom Expression))
(= (random-choice $items)
   (let* (($size (collections-size $items))
          ($checked (assertEqualMsg (> $size 0) True
                                   (quote (nonempty-population $items)))))
     (quote (index-atom (quote $items) (random-position $size)))))
(@doc random-choice
  (@desc "A sample program that chooses one occurrence uniformly from held, nonempty Items. Construction validates without drawing. eval runs one choice; repeat streams choices and map-atom builds a collection while retaining variable sharing. Runnable terms remain literal data. Equal values at different positions remain separate choices; a singleton uses no entropy.")
  (@params ((@param "Items")))
  (@return "Program"))

(: random-sample! (-> Atom Number Expression))
(= (random-sample! $items $count)
   (let* (($size (collections-size $items))
          ($checked (assertEqualMsg
                     (and (collections-integer? $count)
                          (and (>= $count 0) (<= $count $size))) True
                     (quote (sample-size $count $size)))))
     (unfold
       (|-> ($state)
         (let ($remaining $left) (quote $state)
           (if (== $left 0) (empty)
             (let* (($position (random-position (size-atom $remaining)))
                    ($prefix (takeK $position (quote $remaining))))
               (let ((:seg $prefix) $item (:seg $rest)) (quote $remaining)
                 (let* (($next (union-atom $prefix $rest))
                        ($next-count (- $left 1)))
                   (quote ($item ($next $next-count)))))))))
       (quote ($items $count)))))
(@doc random-sample!
  (@desc "Select Count ordered, distinct positions from held Items. Duplicate values remain separate occurrences and caller variables keep their identity. Validate the finite population and nonnegative integer count before drawing; Count cannot exceed its size. Zero returns empty. An unfold removes one selected position per step, using immutable expressions in O(n*Count) work. For replacement, compose random-choice with repeat or map-atom.")
  (@params ((@param "Items") (@param "Count")))
  (@return "Sample"))

(: random-shuffle! (-> Atom Expression))
(= (random-shuffle! $items)
   (random-sample! $items (collections-size $items)))
(@doc random-shuffle!
  (@desc "A permutation of all held occurrences, derived by sampling the population size without replacement. The input remains unchanged. Empty and singleton populations consume no entropy.")
  (@params ((@param "Items")))
  (@return "Shuffled"))

(: random-uniform (-> Number Number Expression))
(= (random-uniform $low $high)
   (let* ((($a $b) (random-parameters ($low $high)))
          ($checked (assertEqualMsg (<= $a $b) True (quote (uniform-bounds $low $high)))))
     (if (<= $b $a) (quote (quote $a))
       (quote (random-interpolate (random-float 0 1) $a $b)))))
(@doc random-uniform
  (@desc "A uniform sample program between finite Low and High, with Low<=High. Equal bounds consume no entropy and retain the floating value's sign. Interpolation rounds only its final result, including opposite bounds near binary64 limits. Rounding may reach an endpoint.")
  (@params ((@param "Low") (@param "High")))
  (@return "Program"))

(: random-normal (-> Number Number Expression))
(= (random-normal $mean $deviation)
   (let* ((($m $d) (random-parameters ($mean $deviation)))
          ($checked (assertEqualMsg (>= $d 0) True (quote (normal-deviation $deviation)))))
     (if (<= $d 0) (quote (quote $m))
       (quote (dot (1 (random-standard-normal)) ($m $d))))))
(@doc random-normal
  (@desc "A normal sample program with finite Mean and nonnegative StandardDeviation. Zero deviation returns Mean without entropy, including negative zero. Box-Muller uses two open-unit core draws with no cached spare. The final affine transform rounds once and may saturate.")
  (@params ((@param "Mean") (@param "StandardDeviation")))
  (@return "Program"))

(: random-lognormal (-> Number Number Expression))
(= (random-lognormal $mean $deviation)
   (let $normal (random-normal $mean $deviation)
     (quote (exp-math (eval $normal)))))
(@doc random-lognormal
  (@desc "Exponentiate the program made by random-normal. MeanOfLog and StandardDeviationOfLog describe the logarithm. Construction validates without entropy; evaluation may underflow to zero or overflow to infinity.")
  (@params ((@param "MeanOfLog") (@param "StandardDeviationOfLog")))
  (@return "Program"))

(: random-exponential (-> Number Expression))
(= (random-exponential $rate)
   (let* ((($r) (random-parameters ($rate)))
          ($checked (assertEqualMsg (> $r 0) True (quote (exponential-rate $rate)))))
     (quote (math-float
              (random-exact-binary vector-divide
                (- 0.0 (log-math (math-real e ()) (random-float 0 1))) $r)))))
(@doc random-exponential
  (@desc "An exponential sample program with a finite positive Rate. Divide the inverse-transform logarithm by Rate exactly before final binary64 rounding.")
  (@params ((@param "Rate")))
  (@return "Program"))

(: random-triangular (-> Number Number Number Expression))
(= (random-triangular $low $high $mode)
   (let* ((($a $b $m) (random-parameters ($low $high $mode)))
          ($checked (assertEqualMsg (and (<= $a $m) (<= $m $b)) True
                                   (quote (triangular-bounds $low $high $mode)))))
     (if (<= $b $a) (quote (quote $a))
       (let $ratio (math-float
                    (random-exact-binary vector-divide
                      (random-exact-binary vector-subtract $m $a)
                      (random-exact-binary vector-subtract $b $a)))
         (quote
           (let $u (random-float 0 1)
             (random-interpolate
               (if (<= $u $ratio) (sqrt-math (* $u $ratio))
                 (- 1.0 (sqrt-math (* (- 1.0 $u) (- 1.0 $ratio)))))
               $a $b)))))))
(@doc random-triangular
  (@desc "A triangular sample program with finite Low<=Mode<=High. Equal bounds consume no entropy. Compute the mode position exactly before conversion and share uniform's final interpolation so extreme finite bounds remain usable.")
  (@params ((@param "Low") (@param "High") (@param "Mode")))
  (@return "Program"))

(: random-gamma (-> Number Number Expression))
(= (random-gamma $shape $scale)
   (let* ((($a $s) (random-parameters ($shape $scale)))
          ($checked (assertEqualMsg (and (> $a 0) (> $s 0)) True
                                   (quote (gamma-parameters $shape $scale)))))
     (quote
       (let ($factors $correction) (random-gamma-parts $a)
         (random-positive-value (cons-atom $s $factors) $correction)))))
(@doc random-gamma
  (@desc "A gamma sample program with finite positive Shape and Scale. Marsaglia/Tsang rejection and shape boosting keep multiplicative factors separate from the power correction until Scale is applied. This retains results which premature underflow or overflow would lose, including subnormal shapes.")
  (@params ((@param "Shape") (@param "Scale")))
  (@return "Program"))

(: random-beta (-> Number Number Expression))
(= (random-beta $alpha $beta)
   (let* ((($a $b) (random-parameters ($alpha $beta)))
          ($checked (assertEqualMsg (and (> $a 0) (> $b 0)) True
                                   (quote (beta-parameters $alpha $beta)))))
     (quote (random-beta-value $a $b))))
(@doc random-beta
  (@desc "A beta sample program with finite positive Alpha and Beta. Compose two gamma factor/correction values. Equal corrections use an exact product ratio; otherwise a bounded logistic transform of exact log differences preserves extreme shapes. Rounding may reach zero or one.")
  (@params ((@param "Alpha") (@param "Beta")))
  (@return "Program"))

(: random-bernoulli (-> Number Expression))
(= (random-bernoulli $probability)
   (let* ((($p) (random-parameters ($probability)))
          ($checked (assertEqualMsg (and (>= $p 0) (<= $p 1)) True
                                   (quote (bernoulli-probability $probability)))))
     (if (<= $p 0) (quote (quote False))
       (if (>= $p 1) (quote (quote True))
         (quote (< (random-float 0 1) $p))))))
(@doc random-bernoulli
  (@desc "A Bool sample program with finite Probability in [0,1]. Zero and one are constant programs and consume no entropy.")
  (@params ((@param "Probability")))
  (@return "Program"))

(: random-pareto (-> Number Expression))
(= (random-pareto $shape)
   (let* ((($a) (random-parameters ($shape)))
          ($checked (assertEqualMsg (> $a 0) True (quote (pareto-shape $shape)))))
     (quote (random-positive-value ()
              (random-exact-binary vector-divide
                (- 0.0 (log-math (math-real e ()) (random-float 0 1))) $a)))))
(@doc random-pareto
  (@desc "A Pareto sample program with finite positive Shape and minimum one. The inverse transform may saturate to infinity for small shapes.")
  (@params ((@param "Shape")))
  (@return "Program"))

(: random-weibull (-> Number Number Expression))
(= (random-weibull $scale $shape)
   (let* ((($s $a) (random-parameters ($scale $shape)))
          ($checked (assertEqualMsg (and (> $s 0) (> $a 0)) True
                                   (quote (weibull-parameters $scale $shape)))))
     (quote (random-positive-value ($s)
              (random-exact-binary vector-divide
                (log-math (math-real e ())
                  (- 0.0 (log-math (math-real e ()) (random-float 0 1)))) $a)))))
(@doc random-weibull
  (@desc "A Weibull sample program with finite positive Scale and Shape. Keep the logarithmic power correction until applying Scale, preserving representable final values across extreme parameters.")
  (@params ((@param "Scale") (@param "Shape")))
  (@return "Program"))
