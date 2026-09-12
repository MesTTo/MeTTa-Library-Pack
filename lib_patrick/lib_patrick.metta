;lib_patrick's four idioms. The general collection operations these grew out of
;are lib_functional, and that stays a SEPARATE import: an import from here would
;load the whole library for every program that wants only these four, and it
;measured 19,326 more inferences on 11-patrick's twin, which costs 18,105 in
;total without it [measured 2026-09-12: min-of-3 serial fresh processes;
;command=python extensions/python/tools/twin_coverage.py --measure --rounds 3
;examples/ch08-data/08-01-atoms-lists-and-folds/11-patrick.metta].

;General function composition:
(: compose (-> Atom _ _))
(= (compose (cons $f $rest) $args)
   (if (== $rest ())
       (if (== (length $args) 1) ;optimization for single arg, avoids
           (let ($arg) $args ($f $arg)) ;reduce for function call
           (let $func (cons $f $args) (reduce $func)))
       ($f (compose $rest $args))))

;Reverse Function Matching
(= (@ $a $b) (let $a $b $a))

;For loop
(: for (-> Atom _ Atom _))
(= (for $var $collection $body)
   (noeval (let $var (superpose $collection)
                     $body)))
!(add-translator-rule! for)

;Iteration with function
(= (iterate $i $n $state $step)
   (if (== $n 0)
       $state
       (iterate (+ $i 1)
                (- $n 1)
                ($step $i $state)
                $step)))
