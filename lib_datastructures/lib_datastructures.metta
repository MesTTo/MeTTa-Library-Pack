;;; EFFICIENT AMORTIZED O(1) OP FUNCTIONAL QUEUE ;;;

;Enqueue adds 1 to N
(= (enqueue $E (queue $In $Out $N))
   (queue (cons $E $In) $Out (+ $N 1)))

;Normal dequeue subtracts 1
(= (dequeue $E (queue $In (cons $E $Out) $N))
   (queue $In $Out (- $N 1)))

;When out empty, reverse in and subtract 1
(= (dequeue $E (queue $In () $N))
   (let (cons $E $R) (reverse $In)
        (queue () $R (- $N 1))))

;Empty queue
(= (empty-queue) (queue () () 0))

;;; EFFICIENT O(1) LOOKUP SPACE ;;;

;Fast Hashmap-like existence check via repra:
(= (add-unique-or-fail $space $Expression)
   (let $st (s (repra $Expression))
        (if (== () (collapse (once (match $space $st True))))
            (add-atom $space $st)
            (empty))))

;;; FINGER TREE ;;;

;Hinze and Paterson's 2-3 finger tree, the unmeasured variant: push and
;pop at BOTH ends in amortized O(1), concatenation in O(log n), so one
;structure serves as sequence, deque, and staging buffer at once. Digits
;are plain expressions of one to four elements; the middle tree holds
;(FTNode2 ...) and (FTNode3 ...) groups whose recursion carries the
;balance. The measured variant (a size on every node, giving O(log n)
;split and random access) builds on exactly this shape.
;[source: Hinze & Paterson, "Finger trees: a simple general-purpose
;data structure", JFP 16(2), 2006]

(: FTree Type)
(: FTEmpty FTree)
(: FTSingle (-> Atom FTree))
(: FTDeep (-> Expression FTree Expression FTree))

(@doc ft-empty
  (@desc "The empty finger tree; every other tree grows from it with ft-push-front and ft-push-back.")
  (@return "FTEmpty"))
(= (ft-empty) FTEmpty)

(@doc ft-is-empty
  (@desc "Whether a finger tree holds nothing.")
  (@params ((@param "a finger tree")))
  (@return "True or False"))
(= (ft-is-empty $t) (unify $t FTEmpty True False))

;push-front: the four digit widths are disjoint patterns, so no clause
;needs a guard; a full prefix pushes a 3-node into the middle, which is
;where the amortized bound lives.
(= (ft-push-front $x FTEmpty) (FTSingle $x))
(= (ft-push-front $x (FTSingle $y)) (FTDeep ($x) FTEmpty ($y)))
(= (ft-push-front $x (FTDeep ($a) $m $sf)) (FTDeep ($x $a) $m $sf))
(= (ft-push-front $x (FTDeep ($a $b) $m $sf)) (FTDeep ($x $a $b) $m $sf))
(= (ft-push-front $x (FTDeep ($a $b $c) $m $sf)) (FTDeep ($x $a $b $c) $m $sf))
(= (ft-push-front $x (FTDeep ($a $b $c $d) $m $sf))
   (FTDeep ($x $a) (ft-push-front (FTNode3 $b $c $d) $m) $sf))

(= (ft-push-back $x FTEmpty) (FTSingle $x))
(= (ft-push-back $x (FTSingle $y)) (FTDeep ($y) FTEmpty ($x)))
(= (ft-push-back $x (FTDeep $pr $m ($a))) (FTDeep $pr $m ($a $x)))
(= (ft-push-back $x (FTDeep $pr $m ($a $b))) (FTDeep $pr $m ($a $b $x)))
(= (ft-push-back $x (FTDeep $pr $m ($a $b $c))) (FTDeep $pr $m ($a $b $c $x)))
(= (ft-push-back $x (FTDeep $pr $m ($a $b $c $d)))
   (FTDeep $pr (ft-push-back (FTNode3 $a $b $c) $m) ($d $x)))

;A node re-enters the shallower level as a digit when a pop drains one.
(= (ft-node-digit (FTNode2 $a $b)) ($a $b))
(= (ft-node-digit (FTNode3 $a $b $c)) ($a $b $c))

(@doc ft-pop-front
  (@desc "The front element and the remaining tree, as the pair ($x $rest). Popping the empty tree has no answer.")
  (@params ((@param "a nonempty finger tree")))
  (@return "($front $rest)"))
(= (ft-pop-front (FTSingle $x)) ($x FTEmpty))
(= (ft-pop-front (FTDeep ($a) $m $sf)) ($a (ft-borrow-l $m $sf)))
(= (ft-pop-front (FTDeep ($a $b) $m $sf)) ($a (FTDeep ($b) $m $sf)))
(= (ft-pop-front (FTDeep ($a $b $c) $m $sf)) ($a (FTDeep ($b $c) $m $sf)))
(= (ft-pop-front (FTDeep ($a $b $c $d) $m $sf)) ($a (FTDeep ($b $c $d) $m $sf)))

;An emptied prefix borrows a node from the middle, or degrades to a
;shallower tree when the middle is empty too.
(= (ft-borrow-l FTEmpty ($a)) (FTSingle $a))
(= (ft-borrow-l FTEmpty ($a $b)) (FTDeep ($a) FTEmpty ($b)))
(= (ft-borrow-l FTEmpty ($a $b $c)) (FTDeep ($a) FTEmpty ($b $c)))
(= (ft-borrow-l FTEmpty ($a $b $c $d)) (FTDeep ($a $b) FTEmpty ($c $d)))
(= (ft-borrow-l (FTSingle $n) $sf) (FTDeep (ft-node-digit $n) FTEmpty $sf))
(= (ft-borrow-l (FTDeep $p $m $s) $sf)
   (let ($n $rest) (ft-pop-front (FTDeep $p $m $s))
        (FTDeep (ft-node-digit $n) $rest $sf)))

(@doc ft-pop-back
  (@desc "The back element and the remaining tree, as the pair ($x $rest): ft-pop-front's mirror.")
  (@params ((@param "a nonempty finger tree")))
  (@return "($back $rest)"))
(= (ft-pop-back (FTSingle $x)) ($x FTEmpty))
(= (ft-pop-back (FTDeep $pr $m ($a))) ($a (ft-borrow-r $pr $m)))
(= (ft-pop-back (FTDeep $pr $m ($a $b))) ($b (FTDeep $pr $m ($a))))
(= (ft-pop-back (FTDeep $pr $m ($a $b $c))) ($c (FTDeep $pr $m ($a $b))))
(= (ft-pop-back (FTDeep $pr $m ($a $b $c $d))) ($d (FTDeep $pr $m ($a $b $c))))

(= (ft-borrow-r ($a) FTEmpty) (FTSingle $a))
(= (ft-borrow-r ($a $b) FTEmpty) (FTDeep ($a) FTEmpty ($b)))
(= (ft-borrow-r ($a $b $c) FTEmpty) (FTDeep ($a $b) FTEmpty ($c)))
(= (ft-borrow-r ($a $b $c $d) FTEmpty) (FTDeep ($a $b $c) FTEmpty ($d)))
(= (ft-borrow-r $pr (FTSingle $n)) (FTDeep $pr FTEmpty (ft-node-digit $n)))
(= (ft-borrow-r $pr (FTDeep $p $m $s))
   (let ($n $rest) (ft-pop-back (FTDeep $p $m $s))
        (FTDeep $pr $rest (ft-node-digit $n))))

(@doc ft-front
  (@desc "The front element, the tree untouched.")
  (@params ((@param "a nonempty finger tree")))
  (@return "the first element"))
(= (ft-front (FTSingle $x)) $x)
(= (ft-front (FTDeep $pr $m $sf)) (car-atom $pr))

(@doc ft-back
  (@desc "The back element, the tree untouched.")
  (@params ((@param "a nonempty finger tree")))
  (@return "the last element"))
(= (ft-back (FTSingle $x)) $x)
(= (ft-back (FTDeep $pr $m ($a))) $a)
(= (ft-back (FTDeep $pr $m ($a $b))) $b)
(= (ft-back (FTDeep $pr $m ($a $b $c))) $c)
(= (ft-back (FTDeep $pr $m ($a $b $c $d))) $d)

(@doc ft-from-list
  (@desc "A finger tree holding the expression's elements in order.")
  (@params ((@param "an expression, for instance (1 2 3)")))
  (@return "a finger tree"))
(= (ft-from-list $l)
   (if (== $l ()) FTEmpty
       (let $h (car-atom $l)
            (let $r (cdr-atom $l)
                 (ft-push-front $h (ft-from-list $r))))))

(@doc ft-to-list
  (@desc "The elements front to back, as an expression: ft-from-list's inverse.")
  (@params ((@param "a finger tree")))
  (@return "an expression"))
(= (ft-to-list FTEmpty) ())
(= (ft-to-list (FTSingle $x)) ($x))
(= (ft-to-list (FTDeep $p $m $s))
   (let ($x $rest) (ft-pop-front (FTDeep $p $m $s))
        (let $tail (ft-to-list $rest)
             (cons-atom $x $tail))))

;Concatenation, Hinze-Paterson app3: the loose middle elements regroup
;into 2-3 nodes and sink one level, so the whole join costs O(log n).
;ft-nodes carries at most twelve elements (4 + 4 + 4), and the recursion
;peels three at a time, leaving two, three, or four for the base rows.
(= (ft-nodes $l)
   (let $n (size-atom $l)
     (if (== $n 2) (let ($a $b) $l ((FTNode2 $a $b)))
     (if (== $n 3) (let ($a $b $c) $l ((FTNode3 $a $b $c)))
     (if (== $n 4) (let ($a $b $c $d) $l ((FTNode2 $a $b) (FTNode2 $c $d)))
         (let $a (car-atom $l) (let $l1 (cdr-atom $l)
         (let $b (car-atom $l1) (let $l2 (cdr-atom $l1)
         (let $c (car-atom $l2) (let $l3 (cdr-atom $l2)
              (let $more (ft-nodes $l3)
                   (cons-atom (FTNode3 $a $b $c) $more)))))))))))))

(= (ft-push-list-front $l $t)
   (if (== $l ()) $t
       (let $h (car-atom $l)
            (let $r (cdr-atom $l)
                 (ft-push-front $h (ft-push-list-front $r $t))))))

(= (ft-push-list-back $l $t)
   (if (== $l ()) $t
       (let $h (car-atom $l)
            (let $r (cdr-atom $l)
                 (ft-push-list-back $r (ft-push-back $h $t))))))

(= (ft-app3 $l $ts $r)
   (if (ft-is-empty $l) (ft-push-list-front $ts $r)
   (if (ft-is-empty $r) (ft-push-list-back $ts $l)
   (unify $l (FTSingle $x)
          (ft-push-front $x (ft-push-list-front $ts $r))
   (unify $r (FTSingle $y)
          (ft-push-back $y (ft-push-list-back $ts $l))
   (let (FTDeep $pr1 $m1 $sf1) $l
   (let (FTDeep $pr2 $m2 $sf2) $r
        (FTDeep $pr1
                (ft-app3 $m1 (ft-nodes (union-atom (union-atom $sf1 $ts) $pr2)) $m2)
                $sf2))))))))

(@doc ft-concat
  (@desc "Both trees' elements, left then right, in O(log n): the operation finger trees exist to make cheap.")
  (@params ((@param "the left finger tree") (@param "the right finger tree")))
  (@return "one finger tree"))
(= (ft-concat $l $r) (ft-app3 $l () $r))
