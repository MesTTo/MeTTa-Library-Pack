; Purpose: validate immutable map and priority-queue values as ordered relations.
; Guarantees: validation preserves literal terms and variable identity, rejects
; malformed or cross-kind values and names the calling operation.
; [tested: lib_datastructures; commit=9c9e60542491416e2c5e431a2672bb20f04264fa].

!(import! &self (library lib_pairs))

(: datastructures-rows (-> Atom Atom %Undefined% Expression))
(= (datastructures-rows $kind $operation $value)
   (let* (($shape (assertEqualMsg
                    (if (== (get-metatype $value) Expression)
                      (== (collections-size $value) 2) False)
                    True (quote ($operation $kind $value))))
          ($tag (assertEqualMsg (== (index-atom $value 0) $kind) True
                                 (quote ($operation $kind $value))))
          ($rows (index-atom $value 1))
          ($pairs (assertEqualMsg (pairs-is (quote $rows)) True
                                   (quote ($operation pairs $rows))))
          ($keys (pairs-keys (quote $rows)))
          ($order (assertEqualMsg (== $keys (sort-atom $keys)) True
                                   (quote ($operation ordered-keys $value)))))
     (quote $rows)))

(: datastructures-map-rows (-> Atom %Undefined% Expression))
(= (datastructures-map-rows $operation $map)
   (let* (($rows (datastructures-rows SortedMap $operation $map))
          ($unique (datastructures-unique-keys $operation (quote $rows))))
     (quote $rows)))

(: datastructures-unique-keys (-> Atom Expression Bool))
(= (datastructures-unique-keys $operation $rows)
   (let* (($pairs (assertEqualMsg (pairs-is (quote $rows)) True
                                  (quote ($operation pairs $rows))))
          ($keys (pairs-keys (quote $rows)))
          ($unique (assertEqualMsg (size-atom (unique-atom $keys)) (size-atom $keys)
                                   (quote ($operation duplicate-map-key $rows)))))
     True))

(: datastructures-without-key (-> Expression %Undefined% Expression))
(= (datastructures-without-key $rows $key)
   (filter-atom $rows $pair (!= (index-atom $pair 0) $key)))

(: datastructures-has-key (-> Expression %Undefined% Bool))
(= (datastructures-has-key $rows $key)
   (> (size-atom (filter-atom $rows $pair (== (index-atom $pair 0) $key))) 0))
