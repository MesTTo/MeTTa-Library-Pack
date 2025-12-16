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

; choose exactly k elements, unordered
(= (chooseK $L 0) (let $temp (cut) (())))
(= (chooseK () $k) (let $temp (cut) ()))
(= (chooseK (cons $h $t) $k)
   (append (map-atom (chooseK $t (- $k 1)) (|-> ($c) (cons $h $c)))
           (chooseK $t $k)))

;Take the first K items from the list:
(= (takeK $k ()) ())
(= (takeK $k (cons $head $tail))
   (if (> $k 0)
       (cons $head (takeK (- $k 1) $tail))
       ()))
