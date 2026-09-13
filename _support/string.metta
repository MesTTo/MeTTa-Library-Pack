; Purpose: share String padding through an ordinary function of the missing width.
; Assumes: public padding equations supply a function returning an integer
; between zero and the missing width.
; [source: lib/lib_string/lib_string.metta:string-center; commit=WORKTREE].
; Guarantees: coerce both texts and validate Width before constructing padding;
; each side restarts the filler and no padding truncates the input.
; [tested: lib_string_surface:padding_contracts, test_string_padding_oracles; commit=WORKTREE].

(: string-padding (-> String Number String))
(= (string-padding $filler $count)
   (if (or (<= $count 0) (== $filler "")) ""
     (let $size (string-length $filler)
       (string-slice
         (string-repeat $filler (floor-div (+ $count (- $size 1)) $size))
         0 $count))))
(@doc string-padding
  (@desc "Repeat and truncate a validated filler to a nonnegative missing width. Empty filler produces no padding. Internal String recipe.")
  (@params ((@param "Filler") (@param "Count")))
  (@return "Fill"))

(: string-pad (-> %Undefined% Number %Undefined% %Undefined% String))
(= (string-pad $value $width $pad $split)
   (let* (($text (string-join "" (quote ($value))))
          ($filler (string-join "" (quote ($pad))))
          ($checked (assertEqualMsg (collections-integer? $width) True
                       (quote (string-pad "use an integer width" $width))))
          ($missing (max 0 (- $width (string-length $text))))
          ($left ($split $missing))
          ($before (string-padding $filler $left))
          ($after (string-padding $filler (- $missing $left))))
     (string-join "" (quote ($before $text $after)))))
(@doc string-pad
  (@desc "Assign the missing width to the left through Split, then put the remainder on the right. Validate both texts and integer width, including empty-output cases. Internal shared padding recipe.")
  (@params ((@param "Value") (@param "Width") (@param "Pad") (@param "Split")))
  (@return "Text"))
