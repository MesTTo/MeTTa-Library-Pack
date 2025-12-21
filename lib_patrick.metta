;General function composition:
(: compose (-> Expression Atom Atom))
(= (compose (cons $f $rest) $args)
   (if (== $rest ())
       (let $func (cons $f $args) (eval $func))
       ($f (compose $rest $args))))

;Reverse Function Matching
(= (@ $a $b) (let $a $b $a))
