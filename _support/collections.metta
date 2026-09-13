; Purpose: share the finite-expression and integer checks used by collection libraries.
; Guarantees: an unbound or non-expression size input raises without binding it;
; the integer predicate rejects floats and non-numbers.
; [tested: lib_combinatorics_surface, lib_statistics, lib_math; commit=6fa571d1b7059b610f73e9feed657711414251e5].
; These equations are internal support for the public library operations.

!(import! &self (library lib_import))
!(import_prolog_functions_from_file
   (library "_support/collections_data.pl") (collections-expression))
(: collections-expression (-> Atom Expression))

(: collections-size (-> Atom Number))
(= (collections-size $value)
   (let $checked (collections-expression $value) (size-atom $checked)))
(@doc collections-size
  (@desc "The length of a finite expression. Refuse non-expressions, open or improper lists and cyclic host terms before traversal. Internal collection boundary check.")
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
