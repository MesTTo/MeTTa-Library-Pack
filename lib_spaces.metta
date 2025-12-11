;Migrate atoms to another space:
(: migrateAtoms (-> %Undefined% %Undefined% Expression %Undefined%))
(= (migrateAtoms $FromSpace $ToSpace $Pattern)
   (match $FromSpace $Pattern ((add-atom $FromSpace $Pattern)
                               (remove-atom $FromSpace $Pattern))))

;Like unify-space case of Minimal MeTTa:
(: find (-> %Undefined% Expression %Undefined%))
(= (find $space $pattern)
   (case (match $space $pattern True)
         ((True True)
          (Empty False))))

;Remove all atoms of a space:
(= (remove-all-atoms $space) 
   (collapse (match $space $x (remove-atom $space $x))))

;Efficiently count the amount of particular items in the space without listifying the items:
(: match-count (-> %Undefined% Expression %Undefined%))
(= (match-count $space $pattern)
   (foldall + ((|-> () (match $space $pattern 1))) 0))
