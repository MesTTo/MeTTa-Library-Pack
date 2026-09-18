# Immutable collections

```metta
!(import! &self (library lib_datastructures))
!(let $prices (map-from-pairs ((pear 5) (apple 3)))
   (let (SortedMap $rows) $prices (pairs-lookup $rows pear)))
; 5
```

A map is `(SortedMap Rows)`, where Rows is an ordinary expression of distinct
`(Key Value)` pairs in term order. A priority queue is `(PriorityQueue Rows)`;
its pairs are ordered by priority and may repeat. You can inspect either value
with patterns, pass its rows to Pairs operations, and reconstruct it with the
corresponding `*-from-pairs` constructor. Mutable dictionaries instead use
`lib_dict` and a queryable Space.

Map construction rejects duplicate keys. `map-put` replaces the value at an
identical key, while `map-remove` returns an unchanged value when the key is
absent. A variable key identifies that variable; it does not match every key.
An absent lookup or an empty minimum has no answer. `map-get-or` supplies a
default explicitly. Quote terms that should be stored as literal programs.
From Python, use `S.quote(mapping)` when passing a returned collection that
contains runnable syntax to a new call; a bound MeTTa variable already carries
its literal value. The collection follows the ordinary expression semantics.

```metta
!(import! &self (library lib_datastructures))
!(pq-pairs (pq-merge (pq-from-pairs ((1 first) (2 later)))
                    (pq-from-pairs ((1 second)))))
; ((1 first) (1 second) (2 later))
```

Queue ties retain construction and insertion order. Merge retains left-to-right
argument order among ties and accepts zero or any number of queues. `pq-pop`
returns `(Priority Value Rest)`; `pq-remove` removes the first identical entry
and leaves other occurrences intact. Both have no answer when no entry exists.

These operations are MeTTa equations over Pairs and core collection forms.
Match an equation to recover or specialize its recipe, then evaluate that
recipe as an ordinary function. Validation walks the relation; construction
and insertion use sorting, and the stable priority sort may take quadratic
work. The former native AVL and pairing-heap representation and its internal
tie order are replaced by the pair representation above.

The existing functional queue and 2-3 finger tree remain MeTTa definitions.
Use the finger tree for both-end access and concatenation. Its node widths
express the balance invariant and are visible to ordinary patterns too.
