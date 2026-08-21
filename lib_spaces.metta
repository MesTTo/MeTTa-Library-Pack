;Migrate atoms to another space:
(: migrateAtoms (-> %Undefined% %Undefined% Atom %Undefined%))
(= (migrateAtoms $FromSpace $ToSpace $Pattern)
   (match $FromSpace $Pattern ((add-atom $FromSpace $Pattern)
                               (remove-atom $FromSpace $Pattern))))

;Like unify-space case of Minimal MeTTa:
(: find (-> %Undefined% Atom %Undefined%))
(= (find $space $pattern)
   (case (match $space $pattern True)
         ((True True)
          (Empty False))))

;Check whether a predicate succeeds
(: succeedsPredicate (-> Atom Bool))
(= (succeedsPredicate $pattern)
   (noeval (case (translatePredicate (catch (Predicate $pattern) $_ fail))
                 (($item True)
                  (Empty False)))))
;The two variables the expansion writes and the head does not are BINDERS of
;the expansion: `$_` is catch's ball pattern and `$item` is the case branch's
;pattern. Neither ever takes a value from the term being rewritten, so neither
;is an extra variable in the sense the termination analysis means, and the
;rule says so rather than leaving the shipped set NOT ESTABLISHED.
!(add-translator-rule! succeedsPredicate
   ((extra-variables-exempt "the catch ball pattern and the case branch pattern are binders of the expansion, so neither takes a value from the term being rewritten")))

;Remove all atoms of a space:
(= (remove-all-atoms $space) 
   (collapse (match $space $x (remove-atom $space $x))))

;Efficiently count the amount of particular items in the space without listifying the items:
(: match-count (-> %Undefined% Atom %Undefined%))
(= (match-count $space $pattern)
   (foldall + (match $space $pattern 1) 0))
