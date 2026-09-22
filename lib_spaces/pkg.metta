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

;Bulk operations over a whole space, written over the operations the engine
;already publishes: a match answers once per atom, and add-atom and remove-atom
;are what a write is. Each one answers once per atom it touched, so the count
;of answers is the count of work done.

;Copy the atoms a pattern matches into another space, leaving the source as it
;was. The wildcard pattern copies everything, which is what merging two spaces
;is: (space-copy &from &to $any).
(: space-copy (-> SpaceType SpaceType Atom %Undefined%))
(= (space-copy $from $to $pattern)
   (match $from $pattern (add-atom $to $pattern)))

;What migrateAtoms' NAME promises: the matched atoms are added to the
;destination and then removed from the source. migrateAtoms itself is upstream's
;equation byte for byte and names the source on both sides, so it drains rather
;than moves; that behaviour is the arbiter's and stays. Use this one to move.
(: move-atoms (-> SpaceType SpaceType Atom %Undefined%))
(= (move-atoms $from $to $pattern)
   (match $from $pattern
     (let $added (add-atom $to $pattern)
       (remove-atom $from $pattern))))

;Remove the atoms a pattern matches and answer them, so a caller sees what
;left rather than a count of removals.
(: space-drain (-> SpaceType Atom %Undefined%))
(= (space-drain $space $pattern)
   (match $space $pattern
     (let $gone (remove-atom $space $pattern) $pattern)))

;A fresh space holding a copy of every atom, so a program can keep what a
;space held while the space goes on changing. The copy is a SNAPSHOT: later
;writes to either space are the other's business.
(: space-snapshot (-> SpaceType SpaceType))
(= (space-snapshot $space)
   (let $fresh (new-space)
     (let $copied (collapse (space-copy $space $fresh $any)) $fresh)))

;Remove from a space every atom another space holds. An atom the space does not
;hold is an ordinary answer, as remove-atom's own verdict is.
(: space-subtract (-> SpaceType SpaceType %Undefined%))
(= (space-subtract $space $removals)
   (match $removals $atom (remove-atom $space $atom)))

(@doc space-copy
  (@desc "Copy the atoms matching a pattern into another space, leaving the source unchanged; one answer per atom copied. A bare variable pattern copies the whole space, which is how two spaces merge.")
  (@params ((@param "the source space") (@param "the destination space") (@param "the pattern to copy")))
  (@return "the destination write's verdict, once per atom"))
(@doc move-atoms
  (@desc "Add the atoms matching a pattern to another space and remove them from the source; one answer per atom moved. This is what migrateAtoms' name promises; migrateAtoms keeps upstream's own equation, which drains the source instead.")
  (@params ((@param "the source space") (@param "the destination space") (@param "the pattern to move")))
  (@return "the removal's verdict, once per atom"))
(@doc space-drain
  (@desc "Remove the atoms matching a pattern and answer each removed atom, so a caller sees what left.")
  (@params ((@param "the space") (@param "the pattern to remove")))
  (@return "each removed atom"))
(@doc space-snapshot
  (@desc "A fresh space holding a copy of every atom, so what a space holds now survives later writes to it. The two spaces are independent from that point.")
  (@params ((@param "the space to copy")))
  (@return "the new space"))
(@doc space-subtract
  (@desc "Remove from a space every atom another space holds; one answer per atom attempted, including an atom the space did not hold.")
  (@params ((@param "the space to remove from") (@param "the space whose atoms to remove")))
  (@return "the removal's verdict, once per atom"))
