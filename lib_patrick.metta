;General function composition:
(: . (-> Expression Atom Atom))
(= (. (cons $f $rest) $args)
   (if (== $rest ())
       (if (== (length $args) 1) ;optimization for single arg, avoids
           (let ($arg) $args ($f $arg)) ;eval for function call
           (let $func (cons $f $args) ((reduce) $func)))
       ($f (. $rest $args))))

;Reverse Function Matching
(= (@ $a $b) (let $a $b $a))
