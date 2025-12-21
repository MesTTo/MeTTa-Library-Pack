;General function composition:
(: . (-> Expression Atom Atom))
(= (. (cons $f $rest) $args)
   (if (== $rest ())
       (let $func (cons $f $args) (eval $func))
       ($f (. $rest $args))))

;Reverse Function Matching
(= (@ $a $b) (let $a $b $a))
