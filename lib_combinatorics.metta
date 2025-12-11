;Range number generator, separate non-det return of each item:
(= (range $K $N)
   (if (< $K $N)
       (superpose ($K (range (+ $K 1) $N)))
       (empty)))

;Combine two elements of $L uniquely e.g. (a b) but not (b a):
(= (choose2 $L)
   (let $j (range 0 (length $L))
           (let $i (range 0 $j)
                ((index-atom $L $i) (index-atom $L $j)))))
