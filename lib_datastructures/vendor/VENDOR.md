# The map and queue algorithms

`structures.pl` holds two of SWI-Prolog's own data structures, adapted so that
their nodes are MeTTa expressions. The algorithms are unchanged; the node syntax
is not.

| Structure | Pinned source | License and changes |
|---|---|---|
| AVL sorted map | [SWI 10.1.13 assoc.pl](https://github.com/SWI-Prolog/swipl-devel/blob/fc7ef84b949378b729052c3ade79c90ce5416abb/library/assoc.pl), installed copy sha256 `8cf114b4886b8841c919812cd54fb5521f5b8ced0cbfec096af251ea54f86e1d` | BSD-2-Clause, reproduced in `SWI-LICENSE`. `t(Key,Value,Balance,Left,Right)` is written `['MapNode',Key,Value,Balance,Left,Right]` and the empty tree `t` is written `'MapEmpty'`. The insert, delete, adjust, rebalance and rotation clauses and both balance tables are otherwise the upstream text. The SSU `=>` rules are written as ordinary clauses with the same dispatch on `compare/3`, which is equivalent for a bound first argument. `list_to_assoc/2`'s sorted build is replaced by a fold over `map_insert/4`, and the duplicate-key refusal moved to the public head. |
| Pairing-heap priority queue | [SWI 10.1.13 heaps.pl](https://github.com/SWI-Prolog/swipl-devel/blob/fc7ef84b949378b729052c3ade79c90ce5416abb/library/heaps.pl), installed copy sha256 `521285cc586352e3111855a3ee23d1fb0fd57a4fc55a075d17f30c9657000621` | BSD-2-Clause, reproduced in `SWI-LICENSE`. `heap(Tree,Size)` is written `['PqHeap',Tree,Size]`, `t(Value,Priority,Children)` is written `['PqNode',Value,Priority,Children]` and `nil` is written `'PqNil'`. `meld/3`, `pairing/2`, the add, the pop, the merge, the linear named deletion and the sorted listing are otherwise the upstream text, including the `@<` comparison and upstream's own note that a named deletion is linear. |

The change is what makes these values usable. A MeTTa expression is a list in
this engine, so a list-shaped node is a value every position accepts: `bind!`
stores one, a program prints and compares one, and a pattern can walk one. The
host's own compound crosses into MeTTa and back unchanged, but substituting one
into a written form leaves the form unreduced, because the translator reads the
compound as a nested call. That is measured rather than assumed
[tested: lib_datastructures:a_map_survives_bind; commit=WORKTREE].

Because the adaptation is mechanical, the check is a differential against the
sources: for generated key sequences and insertion orders,
`tests/prolog/suites/libraries/lib_datastructures.plt` asserts that the map
answers exactly what `library(assoc)` answers at every step, deletions included,
and the queue exactly what `library(heaps)` answers. Re-run it after any change
here, and advance the pinned revisions above when the host's libraries move.
