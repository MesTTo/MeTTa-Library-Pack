; Purpose: continue a numerical range after its public boundary validates it.
; Assumes: range-step has checked the initial bounds and nonzero integer stride.
; Guarantees: each demanded step advances or raises, and crossing the excluded
; endpoint stops the stream [tested: lib_combinatorics_surface; commit=6471fbad35eced5ed6440ebf2c25a053b20221f3].
; These equations are internal support for lib_combinatorics.

(: combinatorics-range-loop (-> Number Number Number Number))
(= (combinatorics-range-loop $from $to $step)
   (if (if (> $step 0) (< $from $to) (> $from $to))
     (superpose ($from
       (let $next (+ $from $step)
         (let $progress (assertEqualMsg (!= $next $from) True
                              (quote (range-step $from $to $step)))
           (combinatorics-range-loop $next $to $step)))))
     (empty)))
(@doc combinatorics-range-loop
  (@desc "Continue a validated range and check that its next step makes progress. Internal recursion for range-step.")
  (@params ((@param "From") (@param "To") (@param "Step")))
  (@return "Value"))
