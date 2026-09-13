; Purpose: share graph shape validation and the cycle-vertex projection.
; Guarantees: graph checks preserve identity; cycle vertices have nonempty
; paths back to themselves [tested: lib_graph; commit=WORKTREE].

(: graph-checked (-> Atom Expression))
(= (graph-checked $graph)
   (let* (($finite (collections-size $graph))
          ($valid (assertEqualMsg (graph-is (quote $graph)) True
                    (quote (invalid-graph $graph)))))
     (quote $graph)))

(: graph-cyclic-vertices (-> Atom Expression))
(= (graph-cyclic-vertices $graph)
   (let $closed (graph-closure (quote $graph))
     (pairs-keys
       (filter-atom $closed $row
         (let ($vertex $neighbours) (quote $row)
           (set-member (quote $neighbours) (quote $vertex)))))))
