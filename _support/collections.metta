; Purpose: share the finite-expression and integer checks used by collection libraries.
; Guarantees: an unbound or non-expression size input raises without binding it;
; the integer predicate rejects floats and non-numbers.
; [tested: lib_combinatorics_surface; commit=6471fbad35eced5ed6440ebf2c25a053b20221f3].
; These equations are internal support for the public library operations.

(: collections-size (-> Atom Number))
(= (collections-size $value)
   (let $checked (assertEqualMsg (get-metatype $value) Expression
                                (quote (collections-size $value)))
     (size-atom $value)))
(@doc collections-size
  (@desc "The length of a finite expression. Refuse a non-expression through a core assertion. Internal collection boundary check.")
  (@params ((@param "Value")))
  (@return "Size"))

(: collections-integer? (-> %Undefined% Bool))
(= (collections-integer? $number)
   (if (is-var $number) False
     (let $remainder (catch (% $number 1))
       (if-error $remainder False (== $remainder 0)))))
(@doc collections-integer?
  (@desc "Whether the value is an integer, without binding a variable or treating an integral float as an integer. Internal count check.")
  (@params ((@param "Value")))
  (@return "Answer"))
