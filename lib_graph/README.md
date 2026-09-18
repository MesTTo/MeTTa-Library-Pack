# Graph expressions

```metta
!(import! &self (library lib_graph))
!(bind! &tasks (graph-of (lunch) ((wake shower) (shower dress))))
!(graph-reachable &tasks wake)
; (dress shower wake)
!(graph-topological-order &tasks)
; (lunch wake shower dress)
```

A graph is an expression of `(Vertex Neighbours)` pairs. Its vertices and
neighbour sets are canonical, and every neighbour is also a vertex. `graph-of`
adds edge endpoints automatically; its first argument adds isolated vertices.
`graph-vertices` returns an ordinary set, and `graph-edges` returns an ordinary
relation. Sets and Pairs operate directly on those values.

`graph-union` accepts zero or any number of graphs. Use `apply-to` when that
argument collection is computed at runtime. Graph alternatives remain separate
answers under ordinary function application.

The operations are MeTTa equations. Closure folds possible intermediate vertices
and rewrites each neighbour set. Reachability selects one closure row and adds
the origin; cycle detection uses the same closure. A single-origin query thus
computes all-pairs closure. Topological ordering unfolds zero-indegree layers,
each in canonical vertex order. Unknown vertices and cycles produce core
assertion errors whose messages name the relevant vertex.

Variables identify vertices through sharing, without becoming lookup wildcards.
Quote runnable vertices, such as `(+ 1 2)`, to keep them as data. When Python
returns a graph to the engine as a new argument, quote that graph too:

```python
from metta import MeTTa, S, lib

with MeTTa() as context:
    m = context.self
    m += lib.graph
    graph = m.fn.graph_of((), S.quote(((S["+"](1, 2), S.done),))).one()
    assert m.fn.graph_neighbours(S.quote(graph), S.quote(S["+"](1, 2))) == [(S.done,)]
```

The [executable example](../../examples/ch08-data/08-03-the-shipped-libraries/25-graph_lib.metta)
matches the path equation, reconstructs it as a function, and specializes it to
one graph before application. Keep the reconstructed lambda as quoted syntax
until matching has supplied its parameters and body, then explicitly `eval` it.
