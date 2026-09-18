; Purpose: derive set operations over canonical expressions from core collections.
; Guarantees: each set result is ordered and duplicate-free, while membership
; compares term identity without binding the caller's variables.
; [tested: lib_sets; commit=6fa571d1b7059b610f73e9feed657711414251e5].
; Fails when: an input requiring a canonical set is unordered or duplicated,
; or set-intersection receives no sets; core assertions report the refusal.
; Decides: set-of canonicalizes with unique-atom and sort-atom; intersections
; and differences reuse the core multiset operations over canonical inputs.

!(import! &self (library "_support/collections.metta"))

(: set-difference (-> Expression Expression Expression))
(= (set-difference $left $right)
   (let* (($l (assertEqualMsg (set-is (quote $left)) True (quote $left)))
          ($r (assertEqualMsg (set-is (quote $right)) True (quote $right))))
     (subtraction-atom $left $right)))
(@doc set-difference
  (@desc "The elements of the first that the second does not hold. The order matters: this is not symmetric, and set-symmetric-difference is the one that is.")
  (@params ((@param "Left") (@param "Right")))
  (@return "Rest"))

(: set-disjoint (-> Expression Expression Bool))
(= (set-disjoint $left $right)
   (== (set-intersection (quote $left) (quote $right)) ()))
(@doc set-disjoint
  (@desc "Whether they share no element. The empty set is disjoint from everything, including itself.")
  (@params ((@param "Left") (@param "Right")))
  (@return "Answer"))

(: set-insert (-> Expression %Undefined% Expression))
(= (set-insert $set $value) (set-union (quote $set) (quote ($value))))
(@doc set-insert
  (@desc "The set with the element added, which is the set itself when it was already there. The input is left alone, as every operation here leaves its inputs.")
  (@params ((@param "Set") (@param "Element")))
  (@return "Bigger"))

(: set-intersection (-> (:seg Expression) Expression))
(= (set-intersection (:seg $sets))
   (let $nonempty (assertEqualMsg (> (size-atom $sets) 0) True (quote $sets))
     (let ($first (:seg $rest)) (quote $sets)
       (let $valid (assertEqualMsg (set-is (quote $first)) True (quote $first))
         (foldl-atom $rest $first $result $set
           (let $valid (assertEqualMsg (set-is (quote $set)) True (quote $set))
             (intersection-atom $result $set)))))))
(@doc set-intersection
  (@desc "The elements every argument holds, once. Accept one or more canonical sets; one returns that set. Zero arguments raises because no universe was supplied. Pass a runtime collection through apply-to.")
  (@params ((@param "Sets")))
  (@return "Common"))

(: set-is (-> %Undefined% Bool))
(= (set-is $value)
   (if (== (get-metatype $value) Expression)
     (let $verdict (catch (let $canonical (set-of (quote $value))
                           (== $canonical $value)))
       (if-error $verdict False $verdict)) False))
(@doc set-is
  (@desc "Whether the value is a set: an expression in the standard order of terms with no duplicates. This is the question every other head asks before it merges, asked out loud.")
  (@params ((@param "Value")))
  (@return "Answer"))

(: set-member (-> Expression %Undefined% Bool))
(= (set-member $set $value)
   (let $common (set-intersection (quote $set) (quote ($value)))
     (== $common (quote ($value)))))
(@doc set-member
  (@desc "Whether the term belongs to the canonical set. Compare terms by identity, without unifying a variable with a different member.")
  (@params ((@param "Set") (@param "Element")))
  (@return "Answer"))

(: set-of (-> Expression Expression))
(= (set-of $items)
   (let* (($size (collections-size $items)) ($unique (unique-atom $items)))
     (sort-atom $unique)))
(@doc set-of
  (@desc "Canonicalize an expression through unique-atom and sort-atom: each literal term once, in the standard order of terms. Variables are compared by identity and remain the caller's variables.")
  (@params ((@param "Items")))
  (@return "Set"))

(: set-remove (-> Expression %Undefined% Expression))
(= (set-remove $set $value) (set-difference (quote $set) (quote ($value))))
(@doc set-remove
  (@desc "The set without the element, which is the set itself when it was not there, so removing something absent is not an error.")
  (@params ((@param "Set") (@param "Element")))
  (@return "Smaller"))

(: set-subset (-> Expression Expression Bool))
(= (set-subset $left $right)
   (== (set-difference (quote $left) (quote $right)) ()))
(@doc set-subset
  (@desc "Whether every element of the first is in the second. A set is a subset of itself, and the empty set is a subset of everything.")
  (@params ((@param "Left") (@param "Right")))
  (@return "Answer"))

(: set-symmetric-difference (-> Expression Expression Expression))
(= (set-symmetric-difference $left $right)
   (let* (($only-left (set-difference (quote $left) (quote $right)))
          ($only-right (set-difference (quote $right) (quote $left))))
     (set-union (quote $only-left) (quote $only-right))))
(@doc set-symmetric-difference
  (@desc "The elements exactly one of them holds, which is the union of the two differences and the same set whichever way round the arguments go.")
  (@params ((@param "Left") (@param "Right")))
  (@return "Either"))

(: set-union (-> (:seg Expression) Expression))
(= (set-union (:seg $sets))
   (foldl-atom (quote $sets) () $result $set
     (let $valid (assertEqualMsg (set-is (quote $set)) True (quote $set))
       (let $combined (union-atom $result $set) (set-of (quote $combined))))))
(@doc set-union
  (@desc "Every element of any canonical input set, once and in term order. Accept zero or more sets; zero returns the empty set. Pass a runtime collection through apply-to.")
  (@params ((@param "Sets")))
  (@return "Union"))
