;Tracing helper
(= (traceid $x) (trace! $x $x))
(= (tracem $msg $x) (trace! ($msg $x) $x))

;Higher order functions
(= (map-flat $f ()) ())
;The recursive tail is SEQUENCED before the cons. `cons` is `cons-atom`'s
;un-suffixed spelling and its tail parameter is declared `Expression`, so the
;operation receives that operand AS WRITTEN; a `let` names the mapped tail
;first and hands the value over, which is how the reference's own stdlib
;writes every list rebuild [source: LeaTTa MettaHyperonFull/Minimal/
;Stdlib.lean:2701-2709, `map-atom`, whose recursive call is bound by a `chain`
;before `cons-atom` sees it].
(= (map-flat $f (cons $x $xs))
   (let $head ($f $x)
     (let $rest (map-flat $f $xs) (cons $head $rest))))

(= (map-nested $f ()) ())
(= (map-nested $f (cons $x $xs))
     (if (is-expr $x)
         (let $head (map-nested $f $x)
           (let $rest (map-nested $f $xs) (cons $head $rest)))
         (let $head ($f $x)
           (let $rest (map-nested $f $xs) (cons $head $rest)))))

(= (fold-flat $f $init ()) $init)
(= (fold-flat $f $init (cons $x $xs)) (fold-flat $f ($f $init $x) $xs))

(= (foldr-flat $f $init ()) $init)
(= (foldr-flat $f $init (cons $x $xs))
   (let $rest (foldr-flat $f $init $xs) ($f $x $rest)))

(= (fold-nested $f $init ()) $init)
(= (fold-nested $f $init (cons $x $xs))
      (if (is-expr $x)
        (fold-nested $f (fold-nested $f $init $x) $xs)
        (fold-nested $f ($f $init $x) $xs)))

;Set operations on Expressions

;Intersection
(= (/?\ $pred () $b) ())
(= (/?\ $pred (cons $a $as) $bs)
      (if (fold-flat or False (map-flat ($pred $a) $bs))
         (let $head $a (let $rest (/?\ $pred $as $bs) (cons $head $rest)))
         (/?\ $pred $as $bs)))

(= (/=\ $a $b) (/?\ = $a $b))
(= (/==\ $a $b) (/?\ == $a $b))
(= (/=a\ $a $b) (/?\ =alpha $a $b))

;Subtraction
(= (\? $pred () $bs) ())
(= (\? $pred (cons $a $as) $bs)
  (if (fold-flat or False (map-flat ($pred $a) $bs))
    (\? $pred $as $bs)
    (let $head $a (let $rest (\? $pred $as $bs) (cons $head $rest)))))

(= (\= $a $b) (\? = $a $b))
(= (\== $a $b) (\? == $a $b))
(= (\=a $a $b) (\? =alpha $a $b))

;Unification
(= (\?/ $pred () $bs) $bs)
(= (\?/ $pred (cons $a $as) $bs)
  (if (fold-flat or False (map-flat ($pred $a) $bs))
    (\?/ $pred $as $bs)
    (let $head $a (let $rest (\?/ $pred $as $bs) (cons $head $rest)))))

(= (\=/ $a $b) (\?/ = $a $b))
(= (\==/ $a $b) (\?/ == $a $b))
(= (\=a/ $a $b) (\?/ =alpha $a $b))

;Function Composition

(= (. $f1 $f2 $arg) ($f1 ($f2 $arg)))

(= (.. $f1 $f2 $arg) ($f1 ($f2 $arg)))

(= (.: $f1 $f2 $arg1 $arg2) ($f1 ($f2 $arg1 $arg2)))

(= (&&& $f1 $f2 $arg) (($f1 $arg) ($f2 $arg)))

(= (&^& $f1 $f2 $arg) (superpose (($f1 $arg) ($f2 $arg))))

;Reverse Function Matching
(= (@ $a $b) (let $a $b $a))

(= (head $x) (cons $x $xs))
(= (tail $xs) (cons $x $xs))

(= (mylast $x) (union-atom $xs ($x)))
(= (init $xs) (union-atom $xs ($x)))

(= (rcons $xs $x) (union-atom $xs ($x)))

;Utils

(= (fst ($a $b)) $a)
(= (snd ($a $b)) $b)

(= (first $f ($a $b)) (($f $a) $b))
(= (second $f ($a $b)) ($a ($f $b)))

(= (cns ($a $b)) (cons $a $b))

(= (flip ($a $b)) ($b $a))

;(= (prog1 (cons $x $xs)) $x)
;(= (progn (rcons $xs $x)) $x)
