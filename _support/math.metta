; Purpose: private integer validation and the Euclidean reduction for Math.
; Guarantees: complete inputs are checked before zero can end a reduction.
; [tested: lib_math; commit=WORKTREE].

(: math-integers (-> Expression Expression))
(= (math-integers $values)
   (let* (($size (collections-size $values))
          ($checked (forall (index-atom $values (range 0 $size))
                     (|-> ($value)
                       (assertEqualMsg (collections-integer? $value) True
                                       (quote (integer $value)))))))
     $values))

(: math-gcd-pair (-> Number Number Number))
(= (math-gcd-pair $left $right)
   (if (== $right 0) $left (math-gcd-pair $right (% $left $right))))
