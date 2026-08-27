;Every operator below is a notation over &mork, so this file is the on-demand
;half of a seat whose other half loads at boot: MORK's provider is
;extensions/mork, and without it these five names reach builtins that do not
;exist. Say so once, by name, rather than five times at call time -- the
;pg_stat_statements shape, and the engine's own door for it.
!(require-extension! mork)

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
