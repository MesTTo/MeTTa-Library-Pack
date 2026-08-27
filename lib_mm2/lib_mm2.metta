;Add
(: ＋ (-> Atom %Undefined%))
(= (＋ $x)
   (add-atom &mork $x))

;Bulk add: a whole list of atoms in one FFI crossing, MORK parsing the
;batch itself. Measured beside per-atom adds at twenty thousand atoms:
;76.7k against 69.8k atoms per second, the queue already amortizing most
;of the difference.
(: ＋* (-> Atom %Undefined%))
(= (＋* $atoms)
   (mork-add-atoms &mork $atoms))

;Remove
(: － (-> Atom %Undefined%))
(= (－ $x)
   (remove-atom &mork $x))

;Query
(: ? (-> Atom Atom %Undefined%))
(= (? $x $y)
   (match &mork $x $y))

;Transform
(: ~> (-> Atom Atom %Undefined%))
(= (~> $head $body)
   ((add-atom &mork (exec 0 $head $body))
    (mm2-exec &mork 1)))
