; Purpose: derive directed graphs from canonical relation and set expressions.
; Guarantees: graph operations preserve literal vertices and variable identity;
; unknown vertices and cycles in topological ordering produce named refusals.
; [tested: lib_graph, extensions/python/tests/ch08_data/test_graph_lib.py; commit=WORKTREE].
; Decides: closure folds intermediate vertices; reachability and cycle detection
; share that recipe. Topological ordering unfolds canonical zero-indegree layers.
; A single-origin query computes all-pairs closure before selecting its row.

!(import! &self (library lib_sets))
!(import! &self (library lib_pairs))
!(import! &self (library "_support/graph.metta"))

(: graph-add-edges (-> Expression Expression Expression))
(= (graph-add-edges $graph $edges)
   (let* (($vertices (graph-vertices (quote $graph)))
          ($before (graph-edges (quote $graph)))
          ($size (collections-size $edges))
          ($combined (union-atom $before $edges)))
     (graph-of (quote $vertices) (quote $combined))))
(@doc graph-add-edges
  (@desc "Add edges written (From To), including their endpoints as vertices. Duplicates do not change the graph.")
  (@params ((@param "Graph") (@param "Edges")))
  (@return "Bigger"))

(: graph-add-vertices (-> Expression Expression Expression))
(= (graph-add-vertices $graph $vertices)
   (let* (($before (graph-vertices (quote $graph)))
          ($edges (graph-edges (quote $graph)))
          ($size (collections-size $vertices))
          ($combined (union-atom $before $vertices)))
     (graph-of (quote $combined) (quote $edges))))
(@doc graph-add-vertices
  (@desc "Add vertices, retaining existing edges. A new vertex has no neighbours.")
  (@params ((@param "Graph") (@param "Vertices")))
  (@return "Bigger"))

; The intermediate-vertex invariant is Warshall's: after visiting Via, each row
; includes paths through it. The reference supplies a ground-graph oracle:
; https://github.com/SWI-Prolog/swipl-devel/blob/fc7ef84b949378b729052c3ade79c90ce5416abb/library/ugraphs.pl#L337
(: graph-closure (-> Expression Expression))
(= (graph-closure $graph)
   (let* (($checked (graph-checked $graph)) ($vertices (pairs-keys (quote $checked))))
     (foldl-atom (quote $vertices) $checked $closed $via
       (let $after (pairs-lookup (quote $closed) (quote $via))
         (map-atom $closed $row
           (let ($from $before) (quote $row)
             (if (set-member (quote $before) (quote $via))
               (let $joined (set-union (quote $before) (quote $after))
                 (quote ($from $joined))) (quote $row))))))))
(@doc graph-closure
  (@desc "The transitive closure: an edge for every path of one or more steps. Fold intermediate vertices and rewrite neighbour sets with set union. A vertex on a cycle reaches itself.")
  (@params ((@param "Graph")))
  (@return "Closure"))

(: graph-edges (-> Expression Expression))
(= (graph-edges $graph) (pairs-ungroup (graph-checked $graph)))
(@doc graph-edges
  (@desc "Every edge as a (From To) pair, ordered by tail and then head. The result is an ordinary relation for Pairs operations.")
  (@params ((@param "Graph")))
  (@return "Edges"))

(: graph-is (-> %Undefined% Bool))
(= (graph-is $graph)
   (if (== (get-metatype $graph) Expression)
     (let $verdict
       (catch
         (let $finite (collections-size $graph)
           (if (pairs-is (quote $graph))
             (let $vertices (pairs-keys (quote $graph))
               (if (set-is (quote $vertices))
                 (forall (index-atom $graph (range 0 (size-atom $graph)))
                   (|-> ($row)
                     (let $neighbours (index-atom $row 1)
                       (if (set-is (quote $neighbours))
                         (set-subset (quote $neighbours) (quote $vertices)) False))))
                 False)) False)))
       (if-error $verdict False $verdict)) False))
(@doc graph-is
  (@desc "Whether a finite expression consists of (Vertex Neighbours) rows with canonical vertex and neighbour sets, and every neighbour identical to a vertex. Variables are never unified with different vertices.")
  (@params ((@param "Value")))
  (@return "Answer"))

(: graph-is-acyclic (-> Expression Bool))
(= (graph-is-acyclic $graph)
   (let $cyclic (graph-cyclic-vertices $graph) (== $cyclic ())))
(@doc graph-is-acyclic
  (@desc "Whether no vertex reaches itself through one or more edges. This shares closure with reachability and the ordering's cycle refusal.")
  (@params ((@param "Graph")))
  (@return "Answer"))

(: graph-neighbours (-> Expression %Undefined% Expression))
(= (graph-neighbours $graph $vertex)
   (let* (($checked (graph-checked $graph))
          ($vertices (pairs-keys (quote $checked)))
          ($known (assertEqualMsg
                    (set-member (quote $vertices) (quote $vertex))
                    True (quote (unknown-vertex $vertex)))))
     (pairs-lookup (quote $checked) (quote $vertex))))
(@doc graph-neighbours
  (@desc "The vertex's outgoing neighbours as a set. An absent vertex raises with (unknown-vertex Vertex), including a fresh variable distinct from every stored vertex. An existing sink returns the empty set.")
  (@params ((@param "Graph") (@param "Vertex")))
  (@return "Neighbours"))

(: graph-of (-> Expression Expression Expression))
(= (graph-of $vertices $edges)
   (let* (($size (collections-size $vertices))
          ($sides (unzip (quote $edges)))
          ($from (index-atom $sides 0)) ($to (index-atom $sides 1))
          ($combined (flatten-once (quote ($vertices $from $to))))
          ($all (set-of (quote $combined))))
     (map-atom $all $vertex
       (let* (($outgoing (filter-atom $edges $edge
                          (let ($from $to) (quote $edge) (== $from $vertex))))
              ($targets (pairs-values (quote $outgoing)))
              ($neighbours (set-of (quote $targets))))
         (quote ($vertex $neighbours))))))
(@doc graph-of
  (@desc "Build canonical (Vertex Neighbours) rows from (From To) edges and extra isolated vertices. Every endpoint becomes a vertex; duplicate edges collapse. Quote runnable vertices and rows to keep them as data.")
  (@params ((@param "Vertices") (@param "Edges")))
  (@return "Graph"))

(: graph-reachable (-> Expression %Undefined% Expression))
(= (graph-reachable $graph $vertex)
   (let $neighbours (graph-neighbours (graph-closure (quote $graph)) (quote $vertex))
     (set-insert (quote $neighbours) (quote $vertex))))
(@doc graph-reachable
  (@desc "Every reachable vertex, including the origin, as a set. Select the origin's closure row and insert the origin. The recipe is an ordinary equation that matching can reconstruct or specialize.")
  (@params ((@param "Graph") (@param "Vertex")))
  (@return "Reachable"))

(: graph-remove-edges (-> Expression Expression Expression))
(= (graph-remove-edges $graph $edges)
   (let* (($vertices (graph-vertices (quote $graph)))
          ($before (graph-edges (quote $graph)))
          ($sides (unzip (quote $edges)))
          ($removed (set-of (quote $edges)))
          ($remaining (set-difference (quote $before) (quote $removed))))
     (graph-of (quote $vertices) (quote $remaining))))
(@doc graph-remove-edges
  (@desc "Remove the named edges, retaining every vertex. Absent edges change nothing; malformed edge expressions refuse.")
  (@params ((@param "Graph") (@param "Edges")))
  (@return "Smaller"))

(: graph-remove-vertices (-> Expression Expression Expression))
(= (graph-remove-vertices $graph $vertices)
   (let* (($checked (graph-checked $graph))
          ($removed (set-of (quote $vertices)))
          ($remaining (filter-atom $checked $row
                        (let ($vertex $neighbours) (quote $row)
                          (not (set-member (quote $removed) (quote $vertex)))))))
     (map-atom $remaining $row
       (let ($vertex $before) (quote $row)
         (let $neighbours (set-difference (quote $before) (quote $removed))
           (quote ($vertex $neighbours)))))))
(@doc graph-remove-vertices
  (@desc "Remove vertices and every incident edge. Compare identity without binding variables; removing an absent vertex changes nothing.")
  (@params ((@param "Graph") (@param "Vertices")))
  (@return "Smaller"))

(: graph-topological-order (-> Expression Expression))
(= (graph-topological-order $graph)
   (let $checked (graph-checked $graph)
     (flatten-once
       (unfold
         (|-> ($remaining)
           (if (== $remaining ()) (empty)
             (let* (($vertices (pairs-keys (quote $remaining)))
                    ($targets (pairs-values (pairs-ungroup (quote $remaining))))
                    ($incoming (set-of (quote $targets)))
                    ($roots (set-difference (quote $vertices) (quote $incoming))))
               (if (== $roots ())
                 (let $vertex (index-atom (graph-cyclic-vertices $remaining) 0)
                   (assertEqualMsg False True (quote (cyclic-graph $vertex))))
                 (let $next (graph-remove-vertices (quote $remaining) (quote $roots))
                   (quote ($roots $next))))))) (quote $checked)))))
(@doc graph-topological-order
  (@desc "Unfold zero-indegree layers and concatenate them. Each layer is in canonical vertex order; every edge's tail precedes its head. A cycle raises with (cyclic-graph Vertex), naming a vertex actually on a cycle.")
  (@params ((@param "Graph")))
  (@return "Order"))

(: graph-transpose (-> Expression Expression))
(= (graph-transpose $graph)
   (let* (($vertices (graph-vertices (quote $graph)))
          ($edges (pairs-swap (graph-edges (quote $graph)))))
     (graph-of (quote $vertices) (quote $edges))))
(@doc graph-transpose
  (@desc "Reverse every edge, retaining all vertices. Union with this transpose gives the graph's undirected reading.")
  (@params ((@param "Graph")))
  (@return "Transposed"))

(: graph-union (-> (:seg Expression) Expression))
(= (graph-union (:seg $graphs))
   (foldl-atom (quote $graphs) () $result $graph
     (let* (($vertices (graph-vertices (quote $graph)))
            ($edges (graph-edges (quote $graph))))
       (graph-add-edges
         (graph-add-vertices (quote $result) (quote $vertices)) (quote $edges)))))
(@doc graph-union
  (@desc "Unite zero or more graphs. Zero returns the empty graph, one preserves its input, and duplicates do not change the result. apply-to supplies a runtime collection of graph arguments.")
  (@params ((@param "Graphs")))
  (@return "Union"))

(: graph-vertices (-> Expression Expression))
(= (graph-vertices $graph) (pairs-keys (graph-checked $graph)))
(@doc graph-vertices
  (@desc "Every vertex in canonical term order. The expression is a set and accepts ordinary Sets operations.")
  (@params ((@param "Graph")))
  (@return "Vertices"))
