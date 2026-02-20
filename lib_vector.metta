(= (dot () ()) 0.0)
(= (dot (cons $a $as) (cons $b $bs))
   (+ (* $a $b) (dot $as $bs)))

(= (cosine-of-normalized $a $b)
   (dot $a $b))

(= (norm $v)
   (sqrt-math (dot $v $v)))

(= (cosine $a $b)
   (/ (dot $a $b)
      (* (norm $a) (norm $b))))
