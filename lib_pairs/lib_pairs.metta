; Purpose: read ordinary (Key Value) pairs as a relation through collection operations.
; Guarantees: projections, stable orderings and grouping preserve duplicates,
; literal values and variable identity; lookup compares keys without unification.
; [tested: lib_pairs; commit=6fa571d1b7059b610f73e9feed657711414251e5].
; Fails when: an operation receives a malformed pair or group; unzip and the
; shared collection check report the offending shape through core assertions.

!(import! &self (library lib_functional))

(: pairs-group (-> Expression Expression))
(= (pairs-group $pairs)
   (let* (($sorted (pairs-sort-by-key (quote $pairs)))
          ($groups (group-by (|-> ($pair) (index-atom $pair 0)) (quote $sorted))))
     (map-atom $groups $group
       (let* (($key (index-atom $group 0)) ($rows (index-atom $group 1))
              ($values (pairs-values (quote $rows))))
         (quote ($key $values))))))
(@doc pairs-group
  (@desc "The relation as a multimap: every key once, in the standard order of terms, with every value it has as (Key Values). The sort is this head's own and is stable, so the values arrive in the relation's own order; the host's group_pairs_by_key/2 groups only ADJACENT pairs and answers a key twice for an unsorted relation, which is why this one sorts first.")
  (@params ((@param "Pairs")))
  (@return "Groups"))

(: pairs-is (-> %Undefined% Bool))
(= (pairs-is $value)
   (if (== (get-metatype $value) Expression)
     (let $verdict
       (catch (forall (index-atom $value (range 0 (size-atom $value)))
                (|-> ($pair)
                  (if (== (get-metatype $pair) Expression)
                    (== (size-atom $pair) 2) False))))
       (if-error $verdict False $verdict)) False))
(@doc pairs-is
  (@desc "Whether the value is a relation: a collection whose every element is a two-element expression. This is the question every other head asks before it walks one, asked out loud.")
  (@params ((@param "Value")))
  (@return "Answer"))

(: pairs-keys (-> Expression Expression))
(= (pairs-keys $pairs) (index-atom (unzip (quote $pairs)) 0))
(@doc pairs-keys
  (@desc "The key of every pair, in order and with duplicates kept, so the length is the relation's own. unzip answers both sides at once; this is the one projection.")
  (@params ((@param "Pairs")))
  (@return "Keys"))

(: pairs-lookup (-> Expression %Undefined% %Undefined%))
(= (pairs-lookup $pairs $key)
   (let $checked (unzip (quote $pairs))
     (let ((:seg $before) ($found $value) (:seg $after)) (quote $pairs)
       (if (== $found $key) (quote $value) (empty)))))
(@doc pairs-lookup
  (@desc "Every value whose key is identical to Key, in input order. An absent key has no answer. A variable key matches only the same variable in the relation, without binding it to a different key.")
  (@params ((@param "Pairs") (@param "Key")))
  (@return "Value"))

(: pairs-sort-by-key (-> Expression Expression))
(= (pairs-sort-by-key $pairs)
   (let $checked (unzip (quote $pairs))
     (sort-by (|-> ($pair) (index-atom $pair 0)) (quote $pairs))))
(@doc pairs-sort-by-key
  (@desc "The relation ordered by key in the standard order of terms, STABLY: pairs with equal keys keep their relative order, and none is dropped.")
  (@params ((@param "Pairs")))
  (@return "Sorted"))

(: pairs-sort-by-value (-> Expression Expression))
(= (pairs-sort-by-value $pairs)
   (let $checked (unzip (quote $pairs))
     (sort-by (|-> ($pair) (index-atom $pair 1)) (quote $pairs))))
(@doc pairs-sort-by-value
  (@desc "The relation ordered stably by its values in the standard order of terms. This specializes sort-by to the second component; duplicates and equal-value order survive.")
  (@params ((@param "Pairs")))
  (@return "Sorted"))

(: pairs-swap (-> Expression Expression))
(= (pairs-swap $pairs)
   (let* (($sides (unzip (quote $pairs)))
          ($left (index-atom $sides 0)) ($right (index-atom $sides 1)))
     (zip (quote $right) (quote $left))))
(@doc pairs-swap
  (@desc "The converse relation with the order kept: every (Key Value) becomes (Value Key) where it stands. pairs-sort-by-key over the answer is the sorted converse, which is what transposing a relation usually means.")
  (@params ((@param "Pairs")))
  (@return "Swapped"))

(: pairs-ungroup (-> Expression Expression))
(= (pairs-ungroup $groups)
   (let* (($sides (unzip (quote $groups)))
          ($all (map-atom $groups $group
            (let* (($key (index-atom $group 0)) ($values (index-atom $group 1))
                   ($size (collections-size $values)))
              (map-atom $values $value (quote ($key $value)))))))
     (flatten-once (quote $all))))
(@doc pairs-ungroup
  (@desc "The relation a multimap holds: one (Key Value) per value, keys in the multimap's order and values in each group's order. This inverts pairs-group, and a group whose values are not a collection raises.")
  (@params ((@param "Groups")))
  (@return "Pairs"))

(: pairs-values (-> Expression Expression))
(= (pairs-values $pairs) (index-atom (unzip (quote $pairs)) 1))
(@doc pairs-values
  (@desc "The value of every pair, in order and with duplicates kept.")
  (@params ((@param "Pairs")))
  (@return "Values"))
