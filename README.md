<!--
Purpose: show the MeTTa Library Pack: each library's heads, and a worked example of it quoted from the corpus program that exercises it.
Guarantees: every library directory has an entry, every listed head is spelled in a source of its library or of one it requires, the counts stated here are the entries', each example is the corpus lines its link cites less their comments, and the table of libraries that need a kernel beyond PeTTa is computed from their own sources [tested 2026-09-25T16:13:43+10:00: tests/checks/check_library_readme.py]. Every `metta` fence runs on a fresh engine in a fresh directory [tested 2026-09-25T16:13:44+10:00: tests/checks/check_readme_fences.py]. Upstream PeTTa reads the three spellings "A kernel beyond PeTTa" names as data [measured 2026-09-25T15:36:14+10:00: an equation head with a gap called at another arity, a variadic signature and an annotated arrow, each run by PeTTa at 43705f5 on a stock SWI-Prolog, had its call refused, and the same program with a plain `->` signature answered] [source 2026-09-25T15:46:09+10:00: docs/journal/2026-09-07-sequence-variables-in-the-corpus.md, where upstream answers a gap ask with nothing].
-->

# MeTTa Library Pack

The MeTTa Library Pack supplies 61 libraries for MeTTa programs.

Package handling is not among them. `setup!`, `get-property` and the claim that
backs a `(= (package backing) (prolog ...))` row are the engine's, because a
manifest has to mean the same thing to every MeTTa implementation and a library
only this engine can load cannot carry that.

```metta
!(import! &self (library lib_memo))
```

| Section | Libraries |
|---|---:|
| [Data and structures](#data-and-structures) | 9 |
| [Text and encoding](#text-and-encoding) | 11 |
| [Numerics and probability](#numerics-and-probability) | 6 |
| [IO and system](#io-and-system) | 12 |
| [Reasoning and rewriting](#reasoning-and-rewriting) | 6 |
| [Engine services](#engine-services) | 12 |
| [Compatibility and programming idioms](#compatibility-and-programming-idioms) | 5 |

Head lists include each library's own declarations, equations and registered
native names; dependencies have their own entries. Each entry ends with a worked
example quoted from the program in
[MeTTa-Examples](https://github.com/MesTTo/MeTTa-Examples) that exercises the
library, less its comment lines, and its link opens those lines in the program,
with the comments that explain them. The gate runs each example here on a fresh
engine in a fresh directory, and the program it is quoted from with the rest of
the corpus. An example that reads a file from the corpus's `_fixtures/`, or names
a network address, cannot run in a fresh directory, so it is shown as text and
runs only in its program.

## What each library needs

**A default SWI.** Six libraries need SWI packages a default build does not
ship, and each refuses naming the package rather than failing obscurely:

| Library | Needs | SWI package |
|---|---|---|
| `lib_compression` | `library(archive)` | `packages/archive`, plus libarchive headers |
| `lib_unicode` | `library(unicode)` | `packages/utf8proc` |
| `lib_yaml` | `library(yaml)` | `packages/yaml`, plus libyaml |
| `lib_redis`, `lib_tabling`, `lib_uuid` | `library(uuid)` | `packages/clib` built against OSSP uuid |

Every other library imports against any SWI the engine itself runs on.

`lib_gitimport` is the one entry here you never import. The engine boot-loads
it (`engine/metta.pl`), so `git-import!` is already a head on a bare engine --
`!(get-type git-import!)` answers `(-> String Bool)` with nothing imported.
`(library lib_gitimport)` carries no MeTTa source and refuses, which is
correct: there is nothing to add that is not already there.

**A kernel beyond PeTTa.** Upstream PeTTa reads three spellings this engine
gives a meaning as ordinary data: a sequence variable in a pattern, `(:seg $x)`
or `...`; a variadic parameter in a signature, `(-> (:seg T) R)`; and an
annotated arrow, `(-[det]-> A B)`. A program written with one answers nothing
there, or has its call refused. So a library written with one needs a kernel
whose syntax is a superset of PeTTa's, and so does every library that requires
one, since importing it loads the other.

<!-- begin generated superset libraries (tests/checks/check_library_readme.py --write) -->
24 libraries need such a kernel:

| Library | The superset syntax is in |
|---|---|
| `lib_builtin_types` | its own source |
| `lib_combinatorics` | its own source |
| `lib_datastructures` | its own source |
| `lib_dict` | `lib_json`, which it requires |
| `lib_encoding` | its own source |
| `lib_file` | `lib_string`, which it requires |
| `lib_functional` | its own source |
| `lib_graph` | its own source |
| `lib_http` | `lib_file`, which it requires |
| `lib_json` | `lib_string`, which it requires |
| `lib_math` | `lib_combinatorics`, which it requires |
| `lib_pairs` | its own source |
| `lib_parsing` | its own source |
| `lib_random` | its own source |
| `lib_reflect` | `lib_pairs`, which it requires |
| `lib_sets` | its own source |
| `lib_statistics` | its own source |
| `lib_strategy` | its own source |
| `lib_string` | `lib_combinatorics`, which it requires |
| `lib_testing` | `lib_combinatorics`, which it requires |
| `lib_torch` | its own source |
| `lib_uuid` | its own source |
| `lib_vector` | `lib_combinatorics`, which it requires |
| `lib_yaml` | `lib_file`, which it requires |

The other 36 write none of these spellings and require no library that does.
<!-- end generated superset libraries -->

## Data and structures

### lib_combinatorics

Enumerates finite choices, products, permutations and subsets, with exact combinatorial counts.

[Source](lib_combinatorics/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Choices | `choose2`, `choose2l`, `chooseK`, `chooseKl`, `takeK` |
| Products and tuples | `cartesian-power`, `tuples` |
| Permutations | `permutation-count`, `permutations` |
| Ranges | `range`, `range-step` |
| Counts and subsets | `binomial`, `factorial`, `subsets` |

Choose pairs and distinguish an empty choice from no choices ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/11-combinatorics_lib.metta#L5-L30)).

```metta
!(import! &self (library lib_combinatorics))

!(test (sort-atom (collapse (choose2 (a b c)))) ((a b) (a c) (b c)))
!(test (collapse (choose2 (a))) ())
!(test (collapse (choose2 ())) ())

!(test (choose2l (a b c)) ((a b) (a c) (b c)))
!(test (choose2l (a)) ())

!(test (chooseKl (a b c) 2) ((a b) (a c) (b c)))
!(test (chooseKl (a b c d) 3) ((a b c) (a b d) (a c d) (b c d)))
!(test (== (chooseKl (a b c) 2) (choose2l (a b c))) True)

!(test (chooseKl (a b c) 0) (()))
!(test (chooseKl () 2) ())
!(test (chooseKl () 0) (()))
```

### lib_functional

Composes collection transformations, folds, grouping, function application and held loops.

[Source](lib_functional/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Flattening | `flatten-deep`, `flatten-once` |
| Grouping and windows | `chunk`, `group-by`, `partition`, `window` |
| Pairing | `unzip`, `zip` |
| Folds and generation | `scan`, `unfold` |
| Control and application | `apply-to`, `pipe`, `repeat`, `unless`, `while` |
| Other heads | `drop`, `sort-by` |

Zip collections and reject malformed pairs ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/22-functional_lib.metta#L6-L23)).

```metta
!(import! &self (library lib_functional))
!(import! &self (library lib_unicode))

(= (double $x) (* 2 $x))
(= (odd? $x) (== 1 (% $x 2)))
(= (grade $score) (if (> $score 50) pass fail))

!(test (zip (1 2 3) (a b c)) ((1 a) (2 b) (3 c)))
!(test (zip (1 2 3) (a b)) ((1 a) (2 b)))
!(test (zip () (a)) ())
!(test (unzip ((1 a) (2 b))) ((1 2) (a b)))
!(test (unzip (zip (1 2) (a b))) ((1 2) (a b)))
!(test (if-error (catch (unzip (1))) refused fine) refused)
```

### lib_datastructures

Provides immutable sorted maps, priority queues, functional queues and finger trees.

[Source](lib_datastructures/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Finger trees | `FTDeep`, `FTEmpty`, `FTSingle`, `FTree`, `ft-app3`, `ft-back`, `ft-borrow-l`, `ft-borrow-r`, `ft-concat`, `ft-empty`, `ft-from-list`, `ft-front`, `ft-is-empty`, `ft-node-digit`, `ft-nodes`, `ft-pop-back`, `ft-pop-front`, `ft-push-back`, `ft-push-front`, `ft-push-list-back`, `ft-push-list-front`, `ft-to-list` |
| Maps | `map-empty`, `map-from-pairs`, `map-get`, `map-get-or`, `map-has`, `map-keys`, `map-max`, `map-min`, `map-pairs`, `map-put`, `map-remove`, `map-size`, `map-values` |
| Priority queues | `pq-empty`, `pq-from-pairs`, `pq-insert`, `pq-merge`, `pq-min`, `pq-pairs`, `pq-pop`, `pq-remove`, `pq-size` |
| Queues | `dequeue`, `empty-queue`, `enqueue` |
| Other heads | `add-unique-or-fail` |

Build a sorted map from pairs, look keys up, put and remove, and order a priority queue ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/21-datastructures_lib.metta#L6-L45)).

```metta
!(import! &self (library lib_datastructures))

!(bind! &prices (map-from-pairs ((pear 5) (apple 3) (plum 7))))
!(test (map-size &prices) 3)
!(test (map-keys &prices) (apple pear plum))
!(test (map-values &prices) (3 5 7))
!(test (map-pairs &prices) ((apple 3) (pear 5) (plum 7)))

!(test (map-get &prices pear) 5)
!(test (collapse (map-get &prices durian)) ())
!(test (map-get-or &prices durian 0) 0)
!(test (map-has &prices apple) True)
!(test (map-has &prices durian) False)
!(test (map-min &prices) (apple 3))
!(test (map-max &prices) (plum 7))

!(bind! &raised (map-put &prices pear 6))
!(test (map-pairs &raised) ((apple 3) (pear 6) (plum 7)))
!(test (map-pairs &prices) ((apple 3) (pear 5) (plum 7)))
!(test (map-pairs (map-remove &prices pear)) ((apple 3) (plum 7)))
!(test (map-pairs (map-remove &prices durian)) ((apple 3) (pear 5) (plum 7)))
!(test (map-size (map-empty)) 0)
!(test (map-pairs (map-put (map-empty) k v)) ((k v)))

!(test (if-error (catch (map-from-pairs ((k 1) (k 2)))) refused fine) refused)
!(test (if-error (catch (map-get 42 k)) refused fine) refused)

!(bind! &work (pq-from-pairs ((3 sweep) (1 wake) (2 boil))))
!(test (pq-size &work) 3)
!(test (pq-min &work) (1 wake))
!(test (pq-pairs &work) ((1 wake) (2 boil) (3 sweep)))
```

### lib_dict

Provides mutable dictionaries as spaces of key/value pairs.

[Source](lib_dict/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Dictionaries | `dict-get`, `dict-has`, `dict-merge`, `dict-pairs`, `dict-pop`, `dict-put`, `dict-remove`, `dict-remove-pair`, `dict-size`, `dict-update`, `dict-values` |

Update a dictionary and query it as a space ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/12-dict_lib.metta#L5-L33)).

```metta
!(import! &self (library lib_dict))

!(bind! &prices (dict-space ((apple 3) (pear 5))))

!(test (dict-size &prices) 2)
!(test (dict-has &prices apple) True)
!(test (dict-has &prices durian) False)

!(test (sort-atom (collapse (dict-values &prices))) (3 5))
!(test (sort-atom (dict-pairs &prices)) ((apple 3) (pear 5)))

!(test (dict-size (dict-put &prices plum 7)) 3)
!(test (dict-size &prices) 3)
!(test (collapse (match &prices (plum $v) $v)) (7))

!(test (dict-size (dict-put &prices apple 9)) 3)
!(test (collapse (match &prices (apple $v) $v)) (9))
```

### lib_pairs

Projects, sorts, groups and queries expressions of key/value pairs.

[Source](lib_pairs/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Pairs | `pairs-group`, `pairs-is`, `pairs-keys`, `pairs-lookup`, `pairs-sort-by-key`, `pairs-sort-by-value`, `pairs-swap`, `pairs-ungroup`, `pairs-values` |

Read a list of sales as a relation: project it, swap it, sort it stably, group it and look a key up ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/24-pairs_lib.metta#L3-L51)).

```metta
!(import! &self (library lib_pairs))

!(bind! &sales ((sydney 120) (perth 90) (sydney 30)))

!(test (pairs-is &sales) True)
!(test (pairs-is ((a 1) (b))) False)
!(test (pairs-is ()) True)
!(test (pairs-is 7) False)

!(test (pairs-keys &sales) (sydney perth sydney))
!(test (pairs-values &sales) (120 90 30))
!(test (pairs-keys ()) ())

!(test (pairs-swap &sales) ((120 sydney) (90 perth) (30 sydney)))
!(test (pairs-swap (pairs-swap &sales)) ((sydney 120) (perth 90) (sydney 30)))

!(test (pairs-sort-by-key &sales) ((perth 90) (sydney 120) (sydney 30)))
!(test (pairs-sort-by-value &sales) ((sydney 30) (perth 90) (sydney 120)))
!(test (pairs-sort-by-key ((b 1) (a 2) (b 0) (a 1)))
       ((a 2) (a 1) (b 1) (b 0)))

!(test (pairs-group &sales) ((perth (90)) (sydney (120 30))))
!(test (pairs-group ()) ())
!(test (pairs-group ((a 1))) ((a (1))))

!(test (pairs-ungroup (pairs-group &sales)) ((perth 90) (sydney 120) (sydney 30)))
!(test (pairs-ungroup ((a (1 2)) (b ()))) ((a 1) (a 2)))
!(test (pairs-ungroup ()) ())

!(test (collapse (pairs-lookup &sales sydney)) (120 30))
!(test (collapse (pairs-lookup &sales perth)) (90))
!(test (collapse (pairs-lookup &sales darwin)) ())
```

### lib_sets

Provides ordered, duplicate-free sets with identity-based membership and set operations.

[Source](lib_sets/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Sets | `set-difference`, `set-disjoint`, `set-insert`, `set-intersection`, `set-is`, `set-member`, `set-of`, `set-remove`, `set-subset`, `set-symmetric-difference`, `set-union` |

Canonicalize sets and distinguish identity from variable binding ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/23-sets_lib.metta#L3-L28)).

```metta
!(import! &self (library lib_sets))
!(import! &self (library lib_functional))

!(test (set-of (3 1 2 1)) (1 2 3))
!(test (set-of ()) ())
!(test (size-atom (set-of (b a b))) 2)
!(test (== (set-of (2 1)) (set-of (1 2 2))) True)
!(test (set-of (b (x) 2 a 1)) (1 2 a b (x)))

!(test (set-is (1 2 3)) True)
!(test (set-is (2 1)) False)
!(test (set-is (1 1)) False)
!(test (set-is 3) False)

!(test (set-member (1 2 3) 2) True)
!(test (set-member (1 2 3) 4) False)
!(test (set-member (1 2 3) $x) False)
```

### lib_graph

Builds directed graphs and computes reachability, closure, transposition and topological order.

[Source](lib_graph/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Graphs | `graph-add-edges`, `graph-add-vertices`, `graph-closure`, `graph-edges`, `graph-is`, `graph-is-acyclic`, `graph-neighbours`, `graph-of`, `graph-reachable`, `graph-remove-edges`, `graph-remove-vertices`, `graph-topological-order`, `graph-transpose`, `graph-union`, `graph-vertices` |

Build a graph with an isolated vertex and inspect its edges ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/25-graph_lib.metta#L5-L27)).

```metta
!(import! &self (library lib_graph))

!(bind! &tasks (graph-of (lunch) ((wake shower) (shower dress) (wake coffee))))
!(test &tasks ((coffee ()) (dress ()) (lunch ()) (shower (dress)) (wake (coffee shower))))
!(test (graph-of () ()) ())
!(test (graph-of (a) ()) ((a ())))

!(test (graph-is &tasks) True)
!(test (graph-is ((a (b)))) False)
!(test (graph-is ((b ()) (a (b)))) False)
!(test (graph-is ((a ()) (b ()))) True)
!(test (graph-is 7) False)

!(test (graph-vertices &tasks) (coffee dress lunch shower wake))
!(test (graph-edges &tasks) ((shower dress) (wake coffee) (wake shower)))
!(test (graph-edges (graph-of () ())) ())
```

### lib_spaces

Copies, moves, drains, snapshots and counts atoms through space queries.

[Source](lib_spaces/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Space operations | `space-copy`, `space-drain`, `space-snapshot`, `space-subtract` |
| Other heads | `find`, `match-count`, `migrateAtoms`, `move-atoms`, `remove-all-atoms`, `succeedsPredicate` |

Count, find, copy, snapshot and move the atoms of a ledger space ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/20-spaces_lib.metta#L6-L43)).

```metta
!(import! &self (library lib_spaces))

!(add-atom &ledger (entry rent 1200))
!(add-atom &ledger (entry food 300))
!(add-atom &ledger (note "checked"))

!(test (match-count &ledger (entry $what $amount)) 2)
!(test (match-count &ledger (invoice $n)) 0)

!(test (find &ledger (entry rent $amount)) True)
!(test (find &ledger (entry car $amount)) False)
!(test (succeedsPredicate (&ledger entry rent $amount)) True)

!(test (sort-atom (collapse (space-copy &ledger &audit (entry $what $amount)))) (true true))
!(test (match-count &audit (entry $what $amount)) 2)
!(test (match-count &ledger (entry $what $amount)) 2)
!(test (sort-atom (collapse (space-copy &ledger &everything $any))) (true true true))
!(test (space-atom-count &everything) 3)

!(bind! &before (space-snapshot &ledger))
!(test (space-atom-count &before) 3)
!(add-atom &ledger (entry travel 90))
!(test (space-atom-count &before) 3)
!(test (space-atom-count &ledger) 4)

!(test (collapse (move-atoms &ledger &archive (entry travel $amount))) (true))
!(test (collapse (match &archive (entry $what $amount) ($what $amount))) ((travel 90)))
!(test (match-count &ledger (entry travel $amount)) 0)
```

### lib_mm2

Provides add, remove, query and transformation notation over the MORK extension's space.

[Source](lib_mm2/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Space notation | `?`, `~>`, `＋`, `＋*`, `－` |

Add, query and remove atoms in MORK's space; where the backend is not built, which outside the checkout's root it is not found, the example says it skipped ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch19-spaces-backed-by-anything/19-04-a-space-on-mork/01-mm2-operators.metta#L9-L44)).

```metta
!(import! &self (library lib_file))

!(test (repr (catch (require-extension! nosuchseat)))
       "(Error (metta_extension_required nosuchseat unknown) none)")

!(test (require-extension! python) ())

!(if (file-exists "./extensions/mork/mork_ffi/target/release/libmork_ffi.so")
     (import! &self (library lib_mm2))
     (println! "SKIPPED mm2-operators: libmork_ffi.so is not built, see extensions/mork/build.sh"))

!(if (file-exists "./extensions/mork/mork_ffi/target/release/libmork_ffi.so")
     (progn (＋ (edge a b))
            (test (sort-atom (collapse (? (edge $x $y) ($x $y)))) ((a b)))
            (－ (edge a b))
            (test (collapse (? (edge $x $y) ($x $y))) ()))
     True)

!(if (file-exists "./extensions/mork/mork_ffi/target/release/libmork_ffi.so")
     (progn (＋* ((edge a b) (edge b c) (edge c d)))
            (test (sort-atom (collapse (? (edge $x $y) ($x $y))))
                  ((a b) (b c) (c d))))
     True)
```

## Text and encoding

### lib_string

Provides text search, splitting, formatting, codepoint conversion and string similarity.

[Source](lib_string/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Conversion | `number-to-string`, `parse-number`, `string-chars`, `string-codes`, `string-from-chars`, `string-from-codes` |
| Search and comparison | `string-contains`, `string-count`, `string-edit-distance`, `string-ends-with`, `string-index-of`, `string-isub`, `string-last-index-of`, `string-similarity`, `string-starts-with` |
| Splitting and joining | `string-join`, `string-lines`, `string-split`, `string-split-exact`, `string-unlines` |
| Case and layout | `string-center`, `string-dedent`, `string-indent`, `string-lower`, `string-pad-left`, `string-pad-right`, `string-trim`, `string-upper`, `string-wrap` |
| Construction and slicing | `string-length`, `string-repeat`, `string-replace`, `string-slice`, `string-template` |

Measure, slice, split, search and pad text by code point ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/18-string_lib.metta#L7-L38)).

```metta
!(import! &self (library lib_string))

!(test (string-length "a🦊é") 3)
!(test (string-slice "a🦊é" 1 99) "🦊é")
!(test (string-split ",;" "a,b;;c") ("a" "b" "" "c"))
!(test (string-split-exact "::" "::a::::") ("" "a" "" ""))
!(test (string-join " / " ("a" "b")) "a / b")
!(test (string-trim " \ta\r\n") "a")
!(test (string-upper hello) "HELLO")
!(test (string-lower "HELLO") "hello")
!(test (string-starts-with "a🦊é" "a🦊") True)
!(test (string-ends-with "a🦊é" "é") True)
!(test (string-contains "a🦊é" "🦊") True)
!(test (string-index-of "banana" "ana") 1)
!(test (string-last-index-of "banana" "ana") 3)
!(test (string-count "aaaaa" "aa") 2)
!(test (string-count "aaaaa" "aa" True) 4)
!(test (string-replace "aaaaa" "aa" "X") "XXa")
!(test (string-replace "abc" "" "X") "abc")
!(test (string-last-index-of "a🦊" "") 2)
!(test (string-count "a🦊" "") 3)

!(test (string-chars "a🦊") ("a" "🦊"))
!(test (string-from-chars ("ab" c 42)) "abc42")
!(test (string-codes "a🦊") (97 129418))
!(test (string-from-codes (97 129418)) "a🦊")
!(test (string-codes (string-from-codes (97 0 129418))) (97 0 129418))
!(test (string-repeat "ab" 3) "ababab")
!(test (string-pad-left "x" 4 "ab") "abax")
!(test (string-pad-right "x" 4 "ab") "xaba")
!(test (string-center "x" 6 "ab") "abxaba")
```

### lib_unicode

Provides Unicode normalization, case folding, grapheme segmentation and character properties.

[Source](lib_unicode/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Unicode | `unicode-casefold`, `unicode-codepoint-valid`, `unicode-graphemes`, `unicode-is`, `unicode-map`, `unicode-normalize`, `unicode-property`, `unicode-version` |

Normalize text into each form, and casefold where lowercasing is not enough ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/26-unicode_lib.metta#L3-L33)).

```metta
!(import! &self (library lib_unicode))
!(import! &self (library lib_string))

!(test (unicode-version) "16.0.0")

!(test (string-codes (unicode-normalize nfd "é")) (101 769))
!(test (string-codes (unicode-normalize nfc "é")) (233))
!(test (== (unicode-normalize nfc (unicode-normalize nfd "é")) "é") True)
!(test (unicode-normalize nfkc "ﬃ") "ffi")
!(test (unicode-normalize nfkd "2²") "22")
!(test (unicode-normalize nfc "2²") "2²")
!(test (unicode-normalize nfkc-casefold "Straße") "strasse")
!(test (if-error (catch (unicode-normalize nfx "a")) refused fine) refused)

!(test (unicode-casefold "Straße") "strasse")
!(test (string-lower "Straße") "straße")
!(test (== (unicode-casefold "HELLO") (unicode-casefold "hello")) True)
```

### lib_regex

Provides compiled PCRE2 patterns, matching, typed captures, scans and substitutions.

[Source](lib_regex/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Patterns | `re-compile`, `re-escape` |
| Matching and captures | `re-captures`, `re-count`, `re-find`, `re-fullmatch`, `re-match`, `re-ranges`, `re-scan`, `regex_captures`, `regex_find`, `regex_match` |
| Replacement and splitting | `re-replace`, `re-replace-all`, `re-split`, `regex_replace`, `regex_replace_all`, `regex_split` |

Match text, decode named captures and replace matches ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/04-regex_lib.metta#L6-L15)).

```metta
!(import! &self (library lib_regex))

!(test (re-match "(?i)^needle" "Needle in a haystack") True)
!(test (re-match "^x" "abc") False)
!(test (collapse (re-find "\\d+" "a1 b22 c333")) ("1" "22" "333"))
!(test (re-captures "(?<year_I>\\d\\d\\d\\d)-(?<month_I>\\d\\d)" "2017-04-20")
       ((0 "2017-04") (month 4) (year 2017)))
!(test (re-split ":\\s*" "Age: 33") ("Age" ": " "33"))
!(test (re-replace-all "a+" "X" "banana") "bXnXnX")
!(test (re-replace "(?<y>\\d+)" "[$y]" "n 42 n") "n [42] n")
```

### lib_parsing

Builds ordinary parser functions from grammar expressions, preserving ambiguous answers.

[Source](lib_parsing/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Grammars | `grammar-forms`, `grammar-is`, `grammar-parse`, `grammar-parse-prefix`, `grammar-parser` |

Run grammar expressions over text, where a mismatch is no answer, and build a character class from any function ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/27-parsing_lib.metta#L3-L37)).

```metta
!(import! &self (library lib_parsing))
!(import! &self (library lib_unicode))

!(test (grammar-parse (lit "ab") "ab") "ab")
!(test (collapse (grammar-parse (lit "ab") "ax")) ())
!(test (collapse (grammar-parse (lit "ab") "abc")) ())

!(test (grammar-parse (any) "x") "x")
!(test (grammar-parse (char-in "aeiou") "e") "e")
!(test (collapse (grammar-parse (char-in "aeiou") "z")) ())
!(test (grammar-parse (char-not-in "aeiou") "z") "z")
!(test (grammar-parse (digits) "1024") "1024")
!(test (grammar-parse (integer) "-42") -42)
!(test (grammar-parse (number) "3.5") 3.5)
!(test (grammar-parse (nonblanks) "word") "word")
!(test (grammar-parse (blanks) "  ") "  ")
!(test (grammar-parse (blanks) "") "")
!(test (grammar-parse (until ",") "ab") "ab")
!(test (grammar-parse (quoted) "\"a\\nb\"") "a\nb")
!(test (grammar-parse (rest) "whatever") "whatever")
!(test (grammar-parse (eos) "") ())

(= (letter? $c) (unicode-is $c letter))
!(test (grammar-parse (many1 (char-if letter?)) "héllo") ("h" "é" "l" "l" "o"))
!(test (collapse (grammar-parse (char-if letter?) "1")) ())
```

### lib_json

Decodes JSON objects into spaces and provides paths, serialization and JSON Lines.

[Source](lib_json/pkg.metta); heads:

| Feature | Heads |
|---|---|
| JSON Lines | `json-lines-decode`, `json-lines-encode`, `json-lines-read!`, `json-lines-write!` |
| JSON values | `json-at`, `json-decode`, `json-encode`, `json-pretty`, `json-read!`, `json-write!` |
| Object spaces | `dict-space`, `get-keys`, `get-value` |

Query decoded objects and retain duplicate fields ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/05-json_lib.metta#L5-L44)).

```metta
!(import! &self (library lib_json))

!(test (let $d (json-decode "{\"a\":1,\"b\":2}") (collapse (get-keys $d)))
       (a b))
!(test (let $d (json-decode "{\"a\":1,\"b\":2}") (get-value $d a)) 1)
!(test (let $d (json-decode "{\"a\":1}") (collapse (get-value $d missing))) ())

!(test (json-decode "[1,2,3]") (1 2 3))
!(test (json-decode "\"plain\"") "plain")
!(test (json-decode "42") 42)
!(test (json-decode "true") True)
!(test (json-decode "null") Null)

!(test (let $outer (json-decode "{\"c\":{\"d\":2}}")
         (let $inner (get-value $outer c) (get-value $inner d)))
       2)

!(test (json-decode (json-encode (1 2 3))) (1 2 3))
!(test (json-decode (json-encode "text")) "text")
!(test (let $d (json-decode (json-encode (dict-space ((k 1))))) (get-value $d k))
       1)

!(test (let $d (dict-space ((name "ann") (age 3))) (get-value $d name)) "ann")

!(test (json-at (json-decode "{\"rows\":[{\"name\":\"ann\"}]}") (rows 0 name)) "ann")
!(test (collapse (json-at (json-decode "{\"a\":[1],\"a\":[2]}") (a 0))) (1 2))
!(test (collapse (json-at (json-decode "{}") (missing))) ())
!(test (json-at 42 ()) 42)
!(test (json-encode (dict-space ())) "{}")
!(test (let $d (dict-space ((from 1) (internal 2))) (collapse (get-keys $d)))
       (quote (from internal)))
```

### lib_csv

Provides CSV parsing, encoding, streamed rows, live file views and mutable snapshots.

[Source](lib_csv/pkg.metta); heads:

| Feature | Heads |
|---|---|
| CSV | `csv-append!`, `csv-encode`, `csv-parse`, `csv-read!`, `csv-snapshot!`, `csv-space`, `csv-write!` |

Parse and encode CSV text, with its options quoted as data ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/17-csv_lib.metta#L5-L19)).

```metta
!(import! &self (library lib_csv))

!(test (csv-parse "001,\"a,b\"\r\n002,9\r\n") (("001" "a,b") ("002" "9")))
!(test (csv-encode (("001" "a,b") ("002" "9"))) "001,\"a,b\"\r\n002,9\r\n")
!(test (csv-parse "id;value\n001;a\n001;a\n" (quote ((separator ";") (skip 1))))
       (("001" "a") ("001" "a")))
!(test (csv-encode (("001" "a;b")) (quote ((separator ";") (newline "\n")))) "001;\"a;b\"\n")
!(test (csv-parse "") ())
!(test (csv-encode ()) "")
!(test (csv-parse "\n\"\"\n,\n" (quote ((width any)))) (() ("") ("" "")))
!(test (csv-parse "a\"b,c\n" (quote ((quote "")))) (("a\"b" "c")))
!(test (csv-parse (csv-encode (("é🦊" "λ\r\n")) (quote ((separator "🦊") (quote "λ"))))
                 (quote ((separator "🦊") (quote "λ"))))
       (("é🦊" "λ\r\n")))
```

### lib_yaml

Reads and writes single YAML documents using spaces for mappings and expressions for sequences.

[Source](lib_yaml/pkg.metta); heads:

| Feature | Heads |
|---|---|
| YAML | `yaml-decode`, `yaml-encode`, `yaml-read!`, `yaml-write!` |

Decode a YAML document into a space and walk it with lib_json's paths ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/28-yaml_lib.metta#L3-L31)).

```metta
!(import! &self (library lib_yaml))

!(bind! &conf (yaml-decode "name: petta
version: 1.5
tags:
  - prolog
  - metta
limits:
  depth: 3
  strict: true
  note:
  nothing: ~
"))
!(test (collapse (get-keys &conf)) (limits name tags version))
!(test (get-value &conf name) "petta")
!(test (get-value &conf version) 1.5)
!(test (get-value &conf tags) ("prolog" "metta"))
!(test (json-at &conf (tags 0)) "prolog")
!(test (json-at &conf (limits depth)) 3)
!(test (json-at &conf (limits strict)) True)
!(test (json-at &conf (limits note)) "")
!(test (json-at &conf (limits nothing)) Null)
!(test (collapse (get-value &conf missing)) ())
```

### lib_markup

Parses HTML and XML into element expressions and selects attributes, descendants and text.

[Source](lib_markup/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Markup | `markup-attribute`, `markup-parse-html`, `markup-parse-xml`, `markup-select`, `markup-text`, `markup-write` |

Parse XML into element expressions, read them by pattern, and select with XPath-shaped steps ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/29-markup_lib.metta#L3-L45)).

```metta
!(import! &self (library lib_markup))

!(bind! &doc (markup-parse-xml "<order id='7'><item sku='a'>apple</item><item sku='b'>pear</item><note/></order>"))
!(test &doc
       (element order ((attr id "7"))
         ((element item ((attr sku "a")) ("apple"))
          (element item ((attr sku "b")) ("pear"))
          (element note () ()))))
!(test (collapse (let $children (index-atom &doc 3)
                   (let (element item ((attr sku $sku)) ($text)) (superpose $children)
                     ($sku $text))))
       (("a" "apple") ("b" "pear")))

!(test (markup-text &doc) "applepear")
!(test (markup-attribute &doc id) "7")
!(test (collapse (markup-attribute &doc missing)) ())
!(test (markup-text (element p () ())) "")

!(test (collapse (markup-select &doc ((descendant item) (text)))) ("apple" "pear"))
!(test (collapse (markup-select &doc ((descendant item) (attribute sku)))) ("a" "b"))
!(test (markup-select &doc ((descendant item) (index 2) (text))) "pear")
!(test (collapse (markup-select &doc (child item))) ((element item ((attr sku "a")) ("apple"))
                                                    (element item ((attr sku "b")) ("pear"))))
!(test (collapse (markup-select &doc (self order))) (&doc))
!(test (collapse (markup-select &doc (descendant missing))) ())
!(bind! &nested (markup-parse-xml "<a><b><c>deep</c></b><c>shallow</c></a>"))
!(test (collapse (markup-select &nested ((child b) (child c) (text)))) ("deep"))
!(test (collapse (markup-select &nested ((descendant c) (text)))) ("shallow" "deep"))
```

### lib_encoding

Converts text and byte expressions through UTF-8, hexadecimal and Base64.

[Source](lib_encoding/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Base64 | `base64-decode`, `base64-encode` |
| Hexadecimal | `hex-decode`, `hex-encode` |
| UTF-8 | `utf8-decode`, `utf8-encode` |

Count UTF-8 bytes separately from characters ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/30-encoding_lib.metta#L3-L22)).

```metta
!(import! &self (library lib_encoding))
!(import! &self (library lib_string))

!(test (utf8-encode "hi") (104 105))
!(test (utf8-decode (104 105)) "hi")
!(test (utf8-encode "") ())
!(test (utf8-decode ()) "")

!(test (utf8-encode "é") (195 169))
!(test (string-length "é") 1)
!(test (size-atom (utf8-encode "é")) 2)
!(test (size-atom (utf8-encode "🙂")) 4)
!(test (string-length "🙂") 1)
!(test (utf8-decode (utf8-encode "héllo 🙂")) "héllo 🙂")
```

### lib_uri

Parses, builds, resolves and normalizes URIs, with component encoding and query pairs.

[Source](lib_uri/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Queries | `uri-query-build`, `uri-query-parse` |
| URIs | `uri-build`, `uri-contexts`, `uri-decode`, `uri-encode`, `uri-normalize`, `uri-parts`, `uri-resolve` |

Split, build, normalize and resolve URIs ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/39-uri_lib.metta#L3-L37)).

```text
!(import! &self (library lib_uri))
!(import! &self (library lib_pairs))
!(import! &self (library lib_encoding))

!(test (uri-parts "") (("path" "")))
!(test (uri-parts "?#") (("path" "") ("query" "") ("fragment" "")))
!(test (uri-parts "https://User:Pass@[::1]:0012/a%2Fb?q=1#F")
  (("scheme" "https") ("authority" "User:Pass@[::1]:0012") ("path" "/a%2Fb") ("query" "q=1") ("fragment" "F")))
!(test (uri-parts "urn:Example:ABC") (("scheme" "urn") ("path" "Example:ABC")))
!(test (uri-build ()) "")
!(test (uri-build (("query" "") ("fragment" ""))) "?#")
!(test (uri-build (("path" "/x") ("authority" "host:") ("scheme" "http"))) "http://host:/x")
!(test (uri-build (uri-parts "a:b?x#")) "a:b?x#")

!(test (uri-normalize "HTTP://User:Pass@HOST/a/%2e%2e/b?x=%7e#F") "http://User:Pass@host/b?x=~#F")
!(test (uri-normalize "urn:Example:ABC") "urn:Example:ABC")
!(test (uri-normalize "http://HOST/%ff/%c0%af/%2f?#") "http://host/%FF/%C0%AF/%2F?#")
!(test (uri-normalize "../a/./b") "../a/./b")
!(test (uri-normalize "foo:/a/..//b") "foo:/.//b")

!(test (uri-resolve "g" "http://a") "http://a/g")
!(test (uri-resolve "../g" "http://a/b/c/d;p?q") "http://a/b/g")
!(test (uri-resolve "?" "http://a/b?old#f") "http://a/b?")
!(test (uri-resolve "#" "http://a/b?old#f") "http://a/b?old#")
!(test (uri-resolve "" "http://a/b?old#f") "http://a/b?old")
!(test (uri-resolve "//other/x" "http://a/b") "http://other/x")
!(test (uri-resolve "http:g" "http://a/b") "http:g")
!(test (uri-resolve "urn:Example:ABC" "http://a/b") "urn:Example:ABC")
!(test (uri-resolve "g?y/../x" "http://a/b/c/d;p?q") "http://a/b/c/g?y/../x")
!(test (uri-resolve "%2e%2e/g" "http://a/b/") "http://a/b/%2e%2e/g")
```

### lib_uuid

Constructs, validates and inspects UUIDs, including byte conversion and namespace-derived identifiers.

[Source](lib_uuid/pkg.metta); heads:

| Feature | Heads |
|---|---|
| UUIDs | `uuid-bytes`, `uuid-is`, `uuid-name`, `uuid-namespaces`, `uuid-nil`, `uuid-of-bytes`, `uuid-random!`, `uuid-time!`, `uuid-timestamp`, `uuid-variant`, `uuid-version` |

Mint random and time-based UUIDs, and derive name-based ones from a namespace ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/33-uuid_lib.metta#L3-L25)).

```metta
!(import! &self (library lib_crypto))
!(import! &self (library lib_uuid))
!(import! &self (library lib_encoding))
!(import! &self (library lib_string))

!(test (size-atom (crypto-random-bytes 16)) 16)
!(test (uuid-version (uuid-random!)) 4)
!(test (uuid-variant (uuid-random!)) rfc)
!(test (uuid-is (uuid-random!)) True)
!(test (!= (uuid-random!) (uuid-random!)) True)
!(test (uuid-version (uuid-time!)) 1)
!(test (uuid-variant (uuid-time!)) rfc)
!(test (> (uuid-timestamp (uuid-time!)) 0) True)

!(test (uuid-namespaces) (dns url oid x500))
!(test (uuid-name 3 dns "example.com") "9073926b-929f-31c2-abc9-fad77ae3e8eb")
!(test (uuid-name 5 dns "example.com") "cfbff0d1-9375-5685-968c-48ce8b15ae17")
!(test (uuid-name 5 "6ba7b810-9dad-11d1-80b4-00c04fd430c8" "example.com")
       (uuid-name 5 dns "example.com"))
```

## Numerics and probability

### lib_math

Provides exact rational arithmetic, integer roots, modular powers, factors and native real functions.

[Source](lib_math/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Classification and conversion | `math-class`, `math-float`, `math-ratio`, `math-rational`, `math-rationalize`, `math-real` |
| Integer arithmetic | `math-factor-pairs`, `math-gcd`, `math-integer-root`, `math-lcm`, `math-power-mod` |
| Real functions | `math-real-functions`, `math-sqrt` |

Count, take gcds and lcms, keep rationals exact, and take integer roots and modular powers ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/35-math_lib.metta#L3-L39)).

```metta
!(import! &self (library lib_math))

!(test (factorial 20) 2432902008176640000)
!(test (binomial 52 5) 2598960)
!(test (math-gcd ()) 0)
!(test (math-gcd (0 0)) 0)
!(test (math-gcd (-18 24 30)) 6)
!(test (math-gcd (18446744073709551616 36893488147419103232)) 18446744073709551616)
!(test (math-lcm ()) 1)
!(test (math-lcm (-6 8 15)) 120)
!(test (math-lcm (0 5)) 0)

!(test (* (math-rational 1 3) 3) 1)
!(test (math-ratio (math-rational 10 -20)) (-1 2))
!(test (math-class (math-rational 6 3)) integer)
!(test (math-class (math-rational 1 3)) rational)
!(test (math-ratio 0.1) (3602879701896397 36028797018963968))
!(test (math-ratio (math-rational 0.1)) (3602879701896397 36028797018963968))
!(test (math-ratio -0.0) (0 1))
!(test (math-ratio (math-rationalize 0.1)) (1 10))
!(test (math-rationalize 42) 42)
!(test (math-ratio (math-rationalize (math-rational 2 3))) (2 3))

!(test (math-integer-root 2 101) (10 1))
!(test (math-integer-root 3 -28) (-3 -1))
!(test (math-integer-root 1 -42) (-42 0))
!(test (math-integer-root 2 340282366920938463463374607431768211456) (18446744073709551616 0))
!(test (math-power-mod 2 100 1000) 376)
!(test (math-power-mod -2 3 5) 2)
!(test (math-power-mod 42 0 1) 0)
!(test (collapse (math-factor-pairs 1)) ((1 1)))
!(test (collapse (math-factor-pairs 36)) ((1 36) (2 18) (3 12) (4 9) (6 6)))
!(test (once (math-factor-pairs 36)) (1 36))
```

### lib_vector

Provides numeric vector arithmetic, exact intermediate reductions, norms, distances and cosine similarity.

[Source](lib_vector/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Vectors | `vector-add`, `vector-distance`, `vector-divide`, `vector-fill`, `vector-multiply`, `vector-normalize`, `vector-scale`, `vector-subtract` |
| Cosine similarity | `cosine`, `cosine-of-normalized` |
| Other heads | `dot`, `norm`, `random-normal-vector` |

Compute dot products, lengths and directional similarity ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/13-vector_lib.metta#L6-L21)).

```metta
!(import! &self (library lib_vector))

!(test (dot (1.0 2.0) (3.0 4.0)) 11.0)
!(test (dot () ()) 0.0)
!(test (dot (1.0 0.0) (0.0 1.0)) 0.0)

!(test (norm (3.0 4.0)) 5.0)
!(test (norm (1.0 0.0)) 1.0)
!(test (norm ()) 0.0)

!(test (cosine (1.0 0.0) (2.0 0.0)) 1.0)
!(test (cosine (1.0 0.0) (0.0 1.0)) 0.0)
!(test (cosine (1.0 0.0) (-2.0 0.0)) -1.0)
```

### lib_random

Constructs inspectable sampling programs and provides sampling without replacement and shuffling.

[Source](lib_random/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Distributions | `random-bernoulli`, `random-beta`, `random-exponential`, `random-gamma`, `random-lognormal`, `random-normal`, `random-pareto`, `random-triangular`, `random-uniform`, `random-weibull` |
| Selection and shuffling | `random-choice`, `random-sample!`, `random-shuffle!` |

Hold a sampler as an expression and draw from it, reproducibly under a seed ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/36-random_lib.metta#L3-L20)).

```metta
!(import! &self (library lib_random))

!(test (let $sample (random-normal 0 1) (get-metatype $sample)) Expression)
!(test (get-type random-normal) (-> Number Number Expression))
!(test (let $drawn (random-choice ("only")) (eval $drawn)) "only")
!(test (size-atom (let $drawn (random-choice ((+ 1 2))) (eval $drawn))) 3)
!(test (random-shuffle! ()) ())
!(test (with-seed 42 (sort-atom (random-shuffle! (1 1 2 3)))) (1 1 2 3))
!(test (== (with-seed 42 (random-shuffle! (1 2 3 4)))
           (with-seed 42 (random-shuffle! (1 2 3 4)))) True)
!(test (random-sample! () 0) ())
!(test (with-seed 42 (sort-atom (random-sample! (1 1 2 3) 4))) (1 1 2 3))
!(test (let $choice (random-choice ("x")) (collapse (repeat 3 $choice))) ("x" "x" "x"))
!(test (with-seed 42 (size-atom (random-sample! (1 2 3 4 5) 3))) 3)
!(test (with-seed 42 (random-sample! ("x" "x") 2)) ("x" "x"))
!(test (== (with-seed 9 (let $drawn (random-choice (1 2 3 4)) (eval $drawn)))
           (with-seed 9 (let $drawn (random-choice (1 2 3 4)) (eval $drawn)))) True)
```

### lib_measure

Normalizes, ranks, samples and combines weighted alternatives.

[Source](lib_measure/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Ranking and selection | `ws-best`, `ws-choose`, `ws-peak`, `ws-pickmax`, `ws-ranked`, `ws-take`, `ws-top` |
| Sampling | `ws-flip`, `ws-sample!`, `ws-sample-walk` |
| Weights and aggregation | `ws-collapse`, `ws-expect`, `ws-filter`, `ws-merge-into`, `ws-normalize`, `ws-softmax`, `ws-total` |

Total, normalize, rank and collapse weighted alternatives, and take a softmax ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch22-a-reasoner-you-can-serve/22-02-weighted-answers/01-measure.metta#L1-L17)).

```metta
!(import! &self (library lib_measure))

!(test (ws-total ((0.5 a) (0.25 b) (0.25 c))) 1.0)
!(test (ws-normalize ((2.0 a) (2.0 b))) ((0.5 a) (0.5 b)))
!(test (ws-best ((0.2 low) (0.7 high) (0.1 mid))) high)
!(test (ws-top ((0.2 low) (0.7 high) (0.1 mid)) 2) ((0.7 high) (0.2 low)))
!(test (ws-collapse ((0.3 x) (0.4 y) (0.2 x))) ((0.5 x) (0.4 y)))
!(test (ws-expect ((0.5 10) (0.5 20))) 15.0)
!(test (ws-filter ((0.9 keep) (0.05 drop)) 0.1) ((0.9 keep)))
!(test (ws-flip ((cat 0.9) (dog 0.4))) ((0.9 cat) (0.4 dog)))

(= (first-weight $ps) (let $head (car-atom $ps) (index-atom $head 0)))
!(test (ws-best (ws-softmax ((1.0 low) (3.0 high)) 0.1)) high)
!(test (> (first-weight (ws-softmax ((1.0 a) (3.0 b)) 0.1)) 0.0) true)
!(test (< (abs-math (- (first-weight (ws-softmax ((1.0 a) (3.0 b)) 1000.0)) 0.5)) 0.01) true)
```

### lib_statistics

Computes sample statistics, finite probability laws and exact independent weighted-subset posteriors.

[Source](lib_statistics/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Sample statistics | `stats-correlation`, `stats-covariance`, `stats-geometric-mean`, `stats-harmonic-mean`, `stats-mean`, `stats-median`, `stats-mode`, `stats-quantile`, `stats-quantiles`, `stats-ranks`, `stats-regression`, `stats-stdev`, `stats-sum`, `stats-variance` |
| Weighted subsets | `weighted-subset-mass-independent`, `weighted-subset-posterior-independent` |
| Independent combinations | `ws-add-bernoulli-independent`, `ws-average-independent`, `ws-map-independent`, `ws-prob-gt-independent`, `ws-sum-independent` |
| Weighted statistics | `ws-central-moment`, `ws-condition-joint`, `ws-deviation`, `ws-map`, `ws-mass-at-least`, `ws-mass-at-most`, `ws-median`, `ws-quantile`, `ws-support`, `ws-variance` |

Retain small residuals and exact means ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/37-statistics_lib.metta#L3-L21)).

```metta
!(import! &self (library lib_statistics))

!(test (stats-sum ()) 0)
!(test (stats-sum (1 2 3)) 6)
!(test (stats-sum (1.0e308 1 -1.0e308)) 1.0)
!(test (math-class (stats-sum (1.0e308 1.0e308))) infinite)
!(test (stats-mean (1 2 3)) 2)
!(test (math-ratio (stats-mean (1 2))) (3 2))
!(test (stats-mean (1.0e308 1.0e308)) 1.0e308)
!(test (stats-mean (1.0e308 1 -1.0e308)) (math-float (math-rational 1 3)))
!(test (stats-harmonic-mean (40 60)) 48)
!(test (stats-harmonic-mean (40.0 60)) 48.0)
!(test (stats-harmonic-mean (0 7)) 0)
!(test (stats-geometric-mean (54 24 36)) 36.0)
!(test (stats-geometric-mean (0 7)) 0.0)
!(test (stats-geometric-mean (1.0e308 1.0e308)) 1.0e308)
!(test (let* (($big (pow-math 2 2000)) ($small (math-rational 1 $big)))
         (stats-geometric-mean ($big $small))) 1.0)
```

### lib_torch

Exposes PyTorch tensor construction, arithmetic, activations and autograd through Python calls.

[Source](lib_torch/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Tensor construction | `torch-arange`, `torch-ones`, `torch-randn`, `torch-tensor`, `torch-zeros` |
| Arithmetic and reductions | `torch-add`, `torch-div`, `torch-matmul`, `torch-mean`, `torch-mul`, `torch-sub`, `torch-sum` |
| Activations | `torch-relu`, `torch-sigmoid` |
| Autograd | `torch-backward`, `torch-grad`, `torch-requires-grad` |
| Inspection and conversion | `torch-item`, `torch-shape`, `torch-tolist` |

Build tensors through PyTorch where it is importable, and say so where it is not ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch11-python-as-a-notation/10-torch-library-surface.metta#L6-L25)).

```metta
!(import! &self (library lib_torch))

!(add-reduct &torch-status
             (available (if-error (catch (py-call (torch.zeros 1))) no yes)))
!(if (== (match &torch-status (available $v) $v) no)
     (println! "SKIPPED torch-library-surface: torch is not importable from this interpreter")
     True)

!(if (== (match &torch-status (available $v) $v) yes)
     (progn (test (torch-tolist (torch-zeros 3)) (0.0 0.0 0.0))
            (test (torch-tolist (torch-ones 3)) (1.0 1.0 1.0))
            (test (torch-tolist (torch-arange 4)) (0 1 2 3))
            (test (size-atom (torch-tolist (torch-randn 5))) 5))
     True)
```

## IO and system

### lib_file

Provides file and directory operations, paths, byte and text streams, and resource scopes.

[Source](lib_file/pkg.metta); heads:

| Feature | Heads |
|---|---|
| File handles and streams | `file-close!`, `file-exists`, `file-get-size!`, `file-kind`, `file-lines!`, `file-metadata!`, `file-open!`, `file-read-bytes!`, `file-read-exact!`, `file-read-to-string!`, `file-seek!`, `file-space!`, `file-write!`, `file-write-bytes!` |
| Paths | `path-absolute`, `path-extension`, `path-join`, `path-name`, `path-normalize`, `path-parent`, `path-parts`, `path-relative`, `path-resolve`, `path-stem` |
| Directories | `copy-dir!`, `delete-dir!`, `delete-tree!`, `dir-exists`, `dir-glob`, `dir-walk`, `list-dir!`, `make-dir!` |
| File and byte operations | `append-bytes!`, `append-file!`, `copy-file!`, `delete-file!`, `read-bytes!`, `read-file!`, `rename-file!`, `replace-file!`, `same-file`, `write-bytes!`, `write-file!` |
| Links | `make-link!`, `read-link` |
| Standard streams | `stderr`, `stderr!`, `stdin`, `stdin-to-string!`, `stdout` |
| Temporary resources and scopes | `temp-dir!`, `temp-path!`, `with-file`, `with-temp-dir` |
| Other heads | `exit!` |

Mint a fresh directory and write, append and read a text file in it ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/19-file_lib.metta#L6-L21)).

```metta
!(import! &self (library lib_file))

!(bind! &dir (temp-dir! "file-lib"))
!(test (dir-exists &dir) True)
!(test (file-kind &dir) directory)

!(bind! &notes (path-join &dir "notes.txt"))
!(test (write-file! &notes "alpha\nbeta\n") True)
!(test (append-file! &notes "gamma\n") True)
!(test (read-file! &notes) "alpha\nbeta\ngamma\n")
!(test (file-lines! &notes) ("alpha" "beta" "gamma"))
!(test (let $lines (file-space! &notes) (match $lines (line 2 $text) $text)) "beta")
!(test (file-exists &notes) True)
!(test (file-kind &notes) file)
```

### lib_datetime

Provides clocks, calendar records, parsing, formatting and arithmetic with explicit time zones.

[Source](lib_datetime/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Dates | `date-add`, `date-field`, `date-fields`, `date-timestamp`, `date-weekday`, `date-year-day` |
| Formatting | `format-date`, `format_date`, `format-datetime` |
| Calendar properties | `day-of-week`, `day_of_week`, `leap-year`, `month-days` |
| Other heads | `now`, `parse-date`, `timestamp-date` |

Read the clock, format and parse dates with explicit offsets, and inspect calendar fields ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/07-datetime.metta#L5-L60)).

```metta
!(import! &self (library lib_datetime))

!(test (let $ts (now) (< 1735689600 $ts)) True)
!(test (let $ts (now)
         (== (format-date $ts "%Y-%m-%d") (format-date $ts "%Y-%m-%d")))
       True)

!(let* (($ts 1766188800)
        ($dow (day-of-week $ts)))
    ($dow))
!(test (day-of-week 1766188800) Saturday)

!(let* (($ts1 1735689600)
        ($ts2 1736294400)
        ($diff (- $ts2 $ts1)))
    ($diff))
!(test (- 1736294400 1735689600) 604800)

!(let* (($ts 1735725045)
        ($time-only (format-date $ts "%H:%M:%S")))
    ($time-only))
!(test (format-date 1735689600 "%B") January)

!(test (format_date 1735689600 "%B") January)
!(test (day_of_week 1766188800) Saturday)
!(test (format-datetime 1735689600 "%Y-%m-%d %H:%M" -3600) "2025-01-01 01:00")
!(test (parse-date "2025-01-01T00:00:00Z") 1735689600.0)
!(test (parse-date "Wed, 01 Jan 2025 00:00:00 GMT" rfc_1123) 1735689600.0)

!(test (date-timestamp (date 2025 1 1)) 1735689600.0)
!(test (timestamp-date 1735689600.25 -3600) (date 2025 1 1 1 0 0.25 -3600 - -))
!(test (date-timestamp (timestamp-date -0.25 UTC)) -0.25)
!(test (date-field (date 2025 1 1) year) 2025)
!(test (date-field (date 2025 1 1) date) (date 2025 1 1))
!(test (collapse (date-field (date 2025 1 1) time_zone)) ())
!(test (collapse (date-fields (date 2025 1 1)))
       ((year 2025) (month 1) (day 1) (hour 0) (minute 0) (second 0)
        (utc_offset 0) (date (date 2025 1 1)) (time (time 0 0 0))))
!(test (date-weekday (date 2025 1 1)) 3)
!(test (date-year-day (date 2024 12 31)) 366)
!(test (leap-year 2000) True)
!(test (leap-year 1900) False)
!(test (month-days 2024 2) 29)
!(test (month-days 2025 2) 28)
```

### lib_system

Reads and changes the environment and working directory, and reports host platform properties.

[Source](lib_system/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Environment | `env-all`, `env-get`, `env-set!`, `env-unset!` |
| Platform | `platform-info`, `platform-keys` |
| Working directory | `change-directory!`, `working-directory` |

Read, set and unset environment variables, and read the environment as a relation ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/31-system_lib.metta#L3-L35)).

```metta
!(import! &self (library lib_system))
!(import! &self (library lib_pairs))
!(import! &self (library lib_string))

!(test (collapse (env-get "NO_SUCH_VARIABLE_HERE")) ())
!(test (if (== () (collapse (env-get "NO_SUCH_VARIABLE_HERE"))) unset set) unset)

!(test (env-set! "METTA_SYSTEM_EXAMPLE" "on") True)
!(test (env-get "METTA_SYSTEM_EXAMPLE") "on")
!(test (env-set! "METTA_SYSTEM_EXAMPLE" "") True)
!(test (env-get "METTA_SYSTEM_EXAMPLE") "")
!(test (if (== () (collapse (env-get "METTA_SYSTEM_EXAMPLE"))) unset set) set)
!(test (env-unset! "METTA_SYSTEM_EXAMPLE") True)
!(test (collapse (env-get "METTA_SYSTEM_EXAMPLE")) ())
!(test (env-unset! "METTA_SYSTEM_EXAMPLE") True)

!(test (env-set! "METTA_SYSTEM_EXAMPLE" "listed") True)
!(test (pairs-is (env-all)) True)
!(test (collapse (pairs-lookup (env-all) "METTA_SYSTEM_EXAMPLE")) ("listed"))
!(test (collapse (pairs-lookup (env-all) "NO_SUCH_VARIABLE_HERE")) ())
!(test (env-unset! "METTA_SYSTEM_EXAMPLE") True)
```

### lib_process

Starts programs with argument vectors and captures output, signals processes or waits for completion.

[Source](lib_process/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Processes | `process-run!`, `process-run-input!`, `process-signal!`, `process-signals`, `process-start!`, `process-status`, `process-wait!` |

Run a program with an argument vector and read its exit code and both streams ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/32-process_lib.metta#L4-L32)).

```metta
!(import! &self (library lib_process))

!(test (process-run! "echo" ("hi")) (process-result 0 "hi\n" ""))
!(test (process-run! "echo" ("one" "two")) (process-result 0 "one two\n" ""))
!(test (process-run! "true" ()) (process-result 0 "" ""))

!(test (process-run! "false" ()) (process-result 1 "" ""))
!(test (index-atom (process-run! "sh" ("-c" "exit 7")) 1) 7)

!(test (process-run! "sh" ("-c" "echo out; echo err 1>&2; exit 3"))
       (process-result 3 "out\n" "err\n"))

!(test (process-run! "echo" ("; echo hacked")) (process-result 0 "; echo hacked\n" ""))
!(test (process-run! "sh" ("-c" "echo shell")) (process-result 0 "shell\n" ""))

!(test (process-run-input! "cat" () "fed") (process-result 0 "fed" ""))
!(test (process-run-input! "wc" ("-c") "1234") (process-result 0 "4\n" ""))
```

### lib_cli

Parses typed command-line options, renders help and reads the process argument vector.

[Source](lib_cli/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Command line | `cli-arguments!`, `cli-help`, `cli-parse`, `cli-types` |

Declare typed options once and parse argument vectors against them ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/44-cli_lib.metta#L3-L20)).

```metta
!(import! &self (library lib_string))
!(import! &self (library lib_cli))

(: cli-main (-> Expression Symbol Expression))
(= (cli-main $arguments $duplicates)
   (cli-parse (((opt count) (type integer) (shortflags (n)) (longflags (count count2)) (default 1) (meta "N") (help "Item count"))
               ((opt verbose) (type boolean) (shortflags (v)) (longflags (verbose)) (default False))
               ((opt name) (shortflags (s)) (longflags (name)) (default "guest")))
              $arguments $duplicates))
(= (cli-plus $increment $text) (+ $increment (parse-number $text)))

!(test (cli-types) (boolean integer float atom string metta))
!(test (cli-main () keeplast) (((count 1) (verbose False) (name "guest")) ()))
!(test (cli-main ("--count" "3" "file") keeplast)
       (((verbose False) (name "guest") (count 3)) ("file")))
!(test (cli-main ("-n4" "--name=π🙂" "-v" "input") keeplast)
       (((count 4) (name "π🙂") (verbose True)) ("input")))
```

### lib_logging

Emits structured log events with topic controls and optional MeTTa handlers.

[Source](lib_logging/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Logging | `log!`, `log-enabled`, `log-format`, `log-levels`, `log-to!`, `log-topic!`, `log-topics` |

Enable a topic, format events, and capture them through a handler ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/34-logging_lib.metta#L3-L30)).

```metta
!(import! &self (library lib_logging))

(: record-log (-> String Expression Bool))
(= (record-log $label $event) (add-atom &log-records (captured $label $event)))

!(test (log-levels) (debug informational warning error))
!(test (log-enabled "library-example") False)
!(test (log-topics) ())
!(test (log-to! missing-handler "library-example" error (+ 1 2)) ())
!(test (log-format "library-example" debug (+ 1 2)) "library-example [debug] (+ 1 2)")
!(test (log-topic! "library-example" True) ())
!(test (log-enabled "library-example") True)
!(test (log-topics) ((log-topic "library-example" True)))

!(test (log! "library-example" informational "hello") ())
!(test (log-to! (record-log "first") "library-example" debug (+ 1 2)) ())
!(test (match &log-records (captured "first" (log-event $topic $level $payload))
             (size-atom $payload)) 3)
!(test (match &log-records (captured "first" (log-event $topic $level $payload))
             (== (quote $payload) (quote (+ 1 2)))) True)
!(test (log-to! (record-log "second") "library-example" informational (loaded "data.csv")) ())
!(test (log-to! (|-> ($event) True) "library-example" warning (retry 2)) ())
!(test (log-to! (|-> ($event) True) "library-example" error (failed "input")) ())
!(test (size-atom (collapse (get-atoms &log-records))) 2)
```

### lib_compression

Compresses bytes and files with gzip or zlib and inspects, reads or extracts archives.

[Source](lib_compression/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Archives | `archive-entries!`, `archive-extract!`, `archive-read!` |
| Compression | `compress-bytes`, `compress-file!`, `compression-formats`, `decompress-bytes`, `decompress-file!` |

Compress and decompress bytes with gzip and zlib ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/41-compression_lib.metta#L5-L20)).

```metta
!(import! &self (library lib_file))
!(import! &self (library lib_compression))

!(test (compression-formats) (gzip zlib))
!(test (path-join "one" "two") "one/two")
!(bind! &bytes (0 128 255 10))
!(bind! &gzip (compress-bytes gzip 6 &bytes))
!(bind! &zlib (compress-bytes zlib 6 &bytes))
!(test (car-atom &gzip) 31)
!(test (car-atom (cdr-atom &gzip)) 139)
!(test (decompress-bytes gzip &gzip) &bytes)
!(test (decompress-bytes zlib &zlib) &bytes)
!(test (decompress-bytes gzip (compress-bytes gzip 0 ())) ())
!(test (decompress-bytes zlib (compress-bytes zlib 9 ())) ())
!(test (decompress-bytes gzip (compress-bytes gzip 9 (1 1 1 1 1))) (1 1 1 1 1))
!(test (decompress-bytes zlib (compress-bytes zlib 0 (1 2 3))) (1 2 3))
```

### lib_crypto

Provides hashes, HMACs, password records and cryptographic random values.

[Source](lib_crypto/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Hashes | `crypto-hash`, `crypto_hash`, `crypto-hash-bytes`, `crypto-hash-file!` |
| HMACs | `crypto-hmac`, `crypto-hmac-bytes` |
| Passwords | `crypto-password-hash`, `crypto-password-verify` |
| Random values | `crypto-random-bytes`, `crypto-random-hex`, `crypto_random_hex`, `crypto-random-integer` |

Hash text and bytes, key a fact by its digest, and authenticate with an HMAC ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/06-crypto_lib.metta#L5-L27)).

```metta
!(import! &self (library lib_crypto))

!(test (crypto-hash sha256 "hello")
       "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
!(test (crypto-hash sha512 "hello")
       "9b71d224bd62f3785d96d46ad3ea3d73319bfbc2890caadae2dff72519673ca72323c3d99ba5c11d7c7acc6e14b8c5da0c4663475c2e5c3adef46f73bcdec043")

(= (content-key $text) (crypto-hash sha256 $text))
!(test (content-key "hello")
       "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")

!(test (crypto_hash sha256 "hello")
       "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
!(test (crypto-hash-bytes sha256 (104 101 108 108 111))
       "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
!(test (crypto-hash-bytes sha256 ())
       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
!(test (crypto-hmac sha256 "Jefe" "what do ya want for nothing?")
       "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
!(test (crypto-hmac-bytes sha256 (195 169) (0 255))
       "6a96aac37f1ab07208ddcd8a71292bd9fc92722a85ca984fa3adcd07fede237d")
```

### lib_http

Provides streaming HTTP clients and scoped HTTP servers with MeTTa request handlers.

[Source](lib_http/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Servers | `http-server-start!`, `http-server-stop!`, `http-server-url`, `with-http-server` |
| Clients and messages | `http-header`, `http-methods`, `http-open!`, `http-request!`, `with-http` |

Route requests to MeTTa equations on a loopback server and read the responses ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/38-http_lib.metta#L5-L43)).

```metta
!(import! &self (library lib_http))
!(import! &self (library lib_encoding))

(: library-http (-> Expression Expression))
(= (library-http (http-request $method "/" $target $fields $body))
   (http-response 200 (("X-Reply" "one") ("X-Reply" "two")) (0 128 255)))
(= (library-http (http-request $method "/echo" $target $fields $body))
   (http-response 201 (("Content-Type" "text/plain; charset=UTF-8")
                       ("X-Method" (repr $method)) ("X-Target" $target)) $body))
(= (library-http (http-request $method "/absent" $target $fields $body))
   (http-response 404 () ()))
(= (library-http (http-request $method "/redirect" $target $fields $body))
   (http-response 307 (("Location" "/")) ()))
(= (library-http (http-request $method "/empty" $target $fields $body)) (empty))
(= (library-http (http-request $method "/broken" $target $fields $body)) (broken-response 7))

(: read-http (-> Expression Expression))
(= (read-http (http-response $status $fields $handle)) (file-read-bytes! $handle))
(: ping-http (-> Expression Expression))
(= (ping-http $server)
   (http-request! get (http-server-url $server) ()))

!(test (http-methods) (delete get head post put patch options))
!(bind! &server (http-server-start! "127.0.0.1" 0 library-http ((workers 2))))
!(bind! &url (http-server-url &server))
!(bind! &echo (string-join "" (&url "echo?q=one%20two")))
!(bind! &response (http-request! get &url ((timeout 5))))
!(test (let (http-response $code $fields $bytes) &response $code) 200)
!(test (let (http-response $code $fields $bytes) &response $bytes) (0 128 255))
!(test (let (http-response $code $fields $bytes) &response
         (http-header $fields "Content-Type")) "application/octet-stream")
!(test (let (http-response $code $fields $bytes) &response
         (http-header $fields "CONTENT-LENGTH")) 3)
!(test (let (http-response $code $fields $bytes) &response
         (collapse (http-header $fields "x-reply"))) ("one" "two"))
!(test (let (http-response $code $fields $bytes) &response
         (collapse (http-header $fields "missing"))) ())
```

### lib_socket

Provides TCP listeners and connections, UDP datagrams and scoped socket ownership.

[Source](lib_socket/pkg.metta); heads:

| Feature | Heads |
|---|---|
| TCP | `tcp-accept!`, `tcp-connect!`, `tcp-listen!` |
| UDP | `udp-bind!`, `udp-receive!`, `udp-send!` |
| Socket inspection and lifetime | `socket-endpoint`, `socket-kind`, `socket-shutdown!`, `socket-wait!`, `with-socket` |

Listen, connect and exchange bytes over loopback TCP, then close every handle ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/40-socket_lib.metta#L5-L43)).

```metta
!(import! &self (library lib_file))
!(import! &self (library lib_socket))

(: socket-answers (-> Number Number))
(= (socket-answers $handle) (superpose (1 2)))

!(test (path-join "one" "two") "one/two")
!(test (socket-wait! () infinite) ())
!(bind! &listener (tcp-listen! (endpoint ipv4 "127.0.0.1" 0) 8))
!(bind! &address (socket-endpoint &listener local))
!(test (socket-kind &listener) listener)
!(test (let (endpoint $family $host $port) &address $family) ipv4)
!(test (let (endpoint $family $host $port) &address $host) "127.0.0.1")
!(test (let (endpoint $family $host $port) &address (> $port 0)) True)
!(test (socket-wait! (&listener) 0) ())
!(bind! &client (tcp-connect! &address))
!(test (socket-wait! (&listener) infinite) (&listener))
!(bind! &accepted (tcp-accept! &listener))
!(test (socket-kind &client) tcp)
!(test (socket-kind &accepted) tcp)
!(test (socket-endpoint &accepted local) &address)
!(test (socket-endpoint &client peer) &address)
!(test (socket-endpoint &accepted peer) (socket-endpoint &client local))

!(test (file-write-bytes! &client (0 128 255 10)) True)
!(test (socket-wait! (&accepted &accepted) infinite) (&accepted &accepted))
!(test (file-read-bytes! &accepted 2) (0 128))
!(test (file-read-bytes! &accepted 2) (255 10))
!(test (socket-shutdown! &client write) True)
!(test (file-read-bytes! &accepted) ())
!(test (file-write-bytes! &accepted (42)) True)
!(test (file-read-bytes! &client 1) (42))
!(test (socket-shutdown! &accepted both) True)
!(test (file-close! &listener) True)
!(test (file-close! &client) True)
!(test (file-close! &accepted) True)
!(test (file-close! &accepted) True)
```

### lib_database

Persists atom syntax in journaled stores with explicit handles, synchronization and scoped cleanup.

[Source](lib_database/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Database stores | `database-add!`, `database-atoms`, `database-close!`, `database-open!`, `database-remove!`, `database-sync!`, `with-database` |

Open a store, add and remove atoms, and select them back with segment patterns ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/42-database_lib.metta#L5-L28)).

```metta
!(import! &self (library lib_file))
!(import! &self (library lib_database))

!(test (path-join "store" "journal.pl") "store/journal.pl")
!(bind! &work (temp-dir! "database-lib"))
!(bind! &first-path (path-join &work "first"))
!(bind! &second-path (path-join &work "second"))
!(bind! &first (database-open! &first-path none))
!(bind! &second (database-open! &second-path close))
!(test (database-atoms &first) ())
!(test (if-error (catch (database-open! &first-path flush)) refused fine) refused)

!(test (database-add! &first (item apple 3)) True)
!(test (database-add! &first (item pear 5)) True)
!(test (database-add! &first (item apple 3)) True)
!(test (collapse (let ((:seg $before) (item $name $price) (:seg $after))
          (database-atoms &first) (quote ($name $price)))) ((apple 3) (pear 5) (apple 3)))
!(test (collapse (let ((:seg $before) (item $name 3) (:seg $after))
          (database-atoms &first) (quote $name))) (apple apple))
!(test (database-remove! &first (item apple 3)) True)
!(test (collapse (let ((:seg $before) (item $name $price) (:seg $after))
          (database-atoms &first) (quote ($name $price)))) ((pear 5) (apple 3)))
```

### lib_redis

Attaches shared Redis-backed spaces with cross-process change notifications.

[Source](lib_redis/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Redis spaces | `redis-attach`, `redis-detach` |

Share a space through Redis, skipping where no server answers ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch19-spaces-backed-by-anything/19-01-spaces-of-your-own/06-a-shared-space-on-redis.metta#L17-L36)).

```metta
!(add-reduct &redis-status
             (available (if-error (catch (import! &self (library lib_redis)))
                                  no yes)))
!(if (== (match &redis-status (available $v) $v) yes)
     (add-reduct &redis-status
                 (attached (if-error (catch (redis-attach &shared "127.0.0.1:6379"))
                                     no yes)))
     (add-atom &redis-status (attached no)))
!(if (== (match &redis-status (attached $v) $v) no)
     (println! "SKIPPED a-shared-space-on-redis: no Redis provider or no server at 127.0.0.1:6379")
     True)

!(if (== (match &redis-status (attached $v) $v) yes)
     (progn (add-atom &shared (city paris france))
            (add-atom &shared (city lyon france))
            (add-atom &shared (city berlin germany))
            (test (sort-atom (collapse (match &shared (city $c france) $c)))
                  (lyon paris)))
     True)
```

## Reasoning and rewriting

### lib_constraints

Exposes rational CLP(Q) constraints and Boolean CLP(B) constraints, labeling and tautology checks.

[Source](lib_constraints/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Boolean constraints | `clpb`, `clpb-labeling`, `clpb-taut` |
| Rational constraints | `clpq`, `clpq-entailed` |

Solve over the rationals, ask what is entailed, and label a Boolean formula ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch05-equations-and-evaluation/05-04-arithmetic-that-runs-backwards/03-constraint_domains.metta#L14-L59)).

```metta
!(import! &self (library lib_constraints))

!(test (let True (clpq (= (* 2 $x) 1)) (repr $x)) "1r2")
!(test (let True (clpq (= (* 2 $x) 1)) (* 2 $x)) 1)

!(test (collapse (let True (clpq (>= $a 0)) (clpq-entailed (>= $a 0)))) (True))
!(test (collapse (let True (clpq (>= $b 0)) (clpq-entailed (>= $b 5)))) (False))

!(test (collapse (let True (clpq (= $c 1)) (clpq (= $c 2)))) ())

!(test (collapse (let True (clpq (= $d 1))
                   (let True (clpq (= $e 2))
                     (clpq (=\= $d $e)))))
       (True))

!(test (let True (clpq (>= $f 0))
         (let True (clpq (=< $f 3))
           (repr (residual-goals $f))))
       "(({} (, (>= $_0 0) (=< $_0 3))))")

!(test (collapse (let True (clpb (card (1) ($m $n))) (clpb-labeling ($m $n))))
       ((0 1) (1 0)))
```

### lib_nars

Provides NARS truth functions, inference rules and bounded derivation and query operations.

[Source](lib_nars/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Configuration | `NARS.Config.BeliefQueueSize`, `NARS.Config.MaxSteps`, `NARS.Config.TaskQueueSize` |
| Derivation and queries | `NARS.Derive`, `NARS.Query` |
| Truth functions | `Truth_Abduction`, `Truth_Analogy`, `Truth_Comparison`, `Truth_DecomposeNNN`, `Truth_DecomposeNPP`, `Truth_DecomposePNN`, `Truth_DecomposePNP`, `Truth_DecomposePPP`, `Truth_Deduction`, `Truth_Difference`, `Truth_Eternalize`, `Truth_Exemplification`, `Truth_Expectation`, `Truth_Induction`, `Truth_Intersection`, `Truth_Negation`, `Truth_Resemblance`, `Truth_Revision`, `Truth_StructuralDeduction`, `Truth_StructuralDeductionNegated`, `Truth_StructuralIntersection`, `Truth_Union`, `Truth_c2w`, `Truth_or`, `Truth_w2c` |
| Stamps | `StampConcat`, `StampDisjoint` |
| Ranking | `ConfidenceRank`, `PriorityRank`, `PriorityRankNeg` |
| Other heads | `BestCandidate`, `LimitSize`, `\|-` |

Call NARS's truth functions directly: evidence and confidence, deduction, abduction and induction ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch22-a-reasoner-you-can-serve/22-02-weighted-answers/16-nars_truth_functions.metta#L7-L38)).

```metta
!(import! &self (library lib_nars))

!(test (Truth_w2c 9.0) 0.9)
!(test (Truth_w2c 0.0) 0.0)
!(test (Truth_w2c 1.0) 0.5)
!(test (< (abs-math (- (Truth_c2w 0.9) 9.0)) 1.0e-9) True)
!(test (Truth_c2w 0.0) 0.0)
!(test (< (abs-math (- (Truth_w2c (Truth_c2w 0.75)) 0.75)) 1.0e-9) True)

!(test (Truth_Deduction (stv 1.0 0.9) (stv 1.0 0.9)) (stv 1.0 0.81))
!(test (Truth_Deduction (stv 0.5 0.9) (stv 1.0 0.9)) (stv 0.5 0.405))

!(test (Truth_Abduction (stv 1.0 0.9) (stv 1.0 0.9))
       (stv 1.0 0.44751381215469616))
!(test (Truth_Induction (stv 1.0 0.9) (stv 1.0 0.9))
       (stv 1.0 0.44751381215469616))

!(test (== (Truth_Induction (stv 0.5 0.9) (stv 1.0 0.8))
           (Truth_Abduction (stv 1.0 0.8) (stv 0.5 0.9)))
       True)
```

### lib_pln

Provides legacy PLN truth formulas, inference rules and bounded derivation and query operations.

[Source](lib_pln/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Configuration | `PLN.Config.BeliefQueueSize`, `PLN.Config.MaxSteps`, `PLN.Config.TaskQueueSize` |
| Derivation and queries | `PLN.Derive`, `PLN.Query` |
| Truth functions | `Truth_Abduction`, `Truth_Deduction`, `Truth_Induction`, `Truth_ModusPonens`, `Truth_Negation`, `Truth_Revision`, `Truth_SymmetricModusPonens`, `Truth_c2w`, `Truth_equivalenceToImplication`, `Truth_evaluationImplication`, `Truth_inversion`, `Truth_transitiveSimilarity`, `Truth_w2c` |
| Stamps | `StampConcat`, `StampDisjoint` |
| Tuples | `TupleConcat`, `TupleCount` |
| Ranking | `ConfidenceRank`, `PriorityRank`, `PriorityRankNeg` |
| Sorting | `InsertSorted`, `InsertionSort` |
| Other heads | `/safe`, `BestCandidate`, `Consistency_ImplicationImplicantConjunction`, `ElementOf`, `LimitSize`, `STV`, `SyllogisticRuleGuard`, `SymmetricModusPonensRuleGuard`, `Test2`, `TransitiveSimilarityStrength`, `Unique`, `Without`, `and5`, `clamp`, `conditional-probability-consistency`, `invert`, `largest-intersection-probability`, `min5`, `negate`, `simpleDeductionStrength`, `smallest-intersection-probability`, `\|-` |

Compile PLN implications into equations and query the truth values they derive ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch22-a-reasoner-you-can-serve/22-02-weighted-answers/05-pln_direct.metta#L1-L56)).

```metta
!(import! &self (library lib_pln))

(: => (-> Atom Atom %Undefined% %Undefined%))
(: premise-truth (-> Atom %Undefined%))
(= (premise-truth $p) (let (stv $s $conf) (reduce $p) (stv $s $conf)))

(= (=> (cons , $args) $C $stvImp)
       (progn (cut)
         (add-atom &self
           (= $C (let $premises (map-atom $args $p (premise-truth $p))
                   (Truth_ModusPonens (foldl-atom $premises (stv 1.0 1.0) Truth_ModusPonens)
                         $stvImp))))))
(= (=> $A $C $stvImp)
   (add-atom &self (= $C (Truth_ModusPonens $A $stvImp))))

(: ? (-> Atom %Undefined%))
(= (? $term)
   (let $answers (collapse ($term (progn (reduce $term) ;ensures binding to specific answer, then combines evidence for all derived variants:
                                         (let $evidence (collapse (reduce $term))
                                           (foldl-atom $evidence (stv 0.5 0.0) Truth_Revision)))))
     (unique-atom $answers)))

!(=> (, (father $a $b) (father $b $c)) (grandfather $a $c) (stv 1.0 0.9))
!(=> (, (father $a $b) (mother $b $c)) (grandfather $a $c) (stv 1.0 0.9))
!(=> (grandfather $a $x) (old $a) (stv 1.0 0.9))

(= (father a b) (stv 1.0 0.9))
(= (father b c) (stv 1.0 0.9))

(= (father a y) (stv 1.0 0.9))
(= (mother y c) (stv 0.0 0.9))

!(test (? (grandfather a c))
       (noeval (((grandfather a c) (stv 0.51 0.8432620011567381)))))
!(test (? (grandfather $who c))
       (noeval (((grandfather a c) (stv 0.51 0.8432620011567381)))))
!(test (? (old $who))
       (noeval (((old a) (stv 0.5198 0.7923434575206812)))))
```

### lib_pln2

Provides Beta and moment formulas with explicit evidence scales and checked independent support sets.

[Source](lib_pln2/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Beta distributions | `pln2-beta-moments`, `pln2-beta-update` |
| Confidence and moments | `pln2-confidence-count`, `pln2-count-confidence`, `pln2-moments-stv`, `pln2-stv-moments` |
| Independent support | `pln2-product-independent`, `pln2-require-independent-supports`, `pln2-total-probability-independent` |

Map confidence to evidence at a chosen scale, update a Beta, and propagate independent moments ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch22-a-reasoner-you-can-serve/22-02-weighted-answers/10-pln2-ctv.metta#L9-L37)).

```metta
!(import! &self (library lib_pln2))

!(test (pln2-confidence-count 0.5 20.0) 20.0)
!(test (pln2-count-confidence 20.0 20.0) 0.5)

!(test (pln2-beta-moments (beta 2.0 3.0)) (moments 0.4 0.04))
!(test (pln2-beta-update (beta 2.0 3.0) 4 1) (beta 6.0 4.0))

!(test
  (pln2-product-independent
    (supported (moments 0.5 0.1) (sensor-a))
    (supported (moments 0.4 0.05) (sensor-b)))
  (supported (moments 0.2 0.0335) (sensor-a sensor-b)))

(= (supported-mean (supported (moments $mean $_variance) $_support)) $mean)
(= (supported-variance (supported (moments $_mean $variance) $_support)) $variance)
(= (conditional-result)
   (pln2-total-probability-independent
     (supported (moments 0.8 0.02) (positive-conditional))
     (supported (moments 0.2 0.03) (negative-conditional))
     (supported (moments 0.6 0.04) (condition))))
!(test (< (abs-math (- (supported-mean (conditional-result)) 0.56)) 1.0e-12) true)
!(test (< (abs-math (- (supported-variance (conditional-result)) 0.0284)) 1.0e-12) true)
```

### lib_soft

Scores structural similarity between terms and queries spaces for weighted matches.

[Source](lib_soft/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Structural similarity | `soft-aggregation`, `soft-best`, `soft-fold`, `soft-match`, `soft-score`, `soft-score-by`, `soft-symbol?`, `soft-walk` |
| Symbol similarity | `sym-sim` |

Score terms by structural similarity and query a space for its best soft match ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch22-a-reasoner-you-can-serve/22-02-weighted-answers/02-soft.metta#L1-L39)).

```metta
!(import! &self (library lib_measure))
!(import! &self (library lib_soft))

(similar cat feline 0.8)
(similar dog wolf 0.7)
!(test (sym-sim cat cat) 1.0)
!(test (sym-sim cat feline) 0.8)
!(test (sym-sim feline cat) 0.8)
!(test (sym-sim cat dog) 0.0)

!(test (soft-score (likes cat fish) (likes cat fish)) 1.0)
!(test (soft-score (likes feline fish) (likes cat fish)) 0.8)
!(test (soft-score (likes feline wolf) (likes cat dog)) 0.7)
!(test (soft-score (likes cat) (likes cat fish)) 0.0)
!(test (soft-score (likes cat fish) (hates cat fish)) 0.0)
!(test (soft-score 3 3) 1.0)
!(test (soft-score 3 4) 0.0)

!(test (soft-score (= (likes cat $f) $body) (= (likes feline fish) tasty)) 0.8)
!(test (soft-score (likes cat (+ 1 2)) (likes feline (+ 1 2))) 0.8)

!(test (soft-score $x anything) 1.0)
!(test (let $probe (soft-score (likes $who fish) (likes cat fish)) ($probe $who)) (1.0 cat))

!(add-atom &zoo (likes cat fish))
!(add-atom &zoo (likes dog bones))
!(add-atom &zoo (likes bird seeds))
!(test (collapse (soft-match &zoo (likes feline fish) 0.5)) ((0.8 (likes cat fish))))
!(test (soft-best &zoo (likes feline fish)) (likes cat fish))
```

### lib_strategy

Composes term rewrites through choice, repetition, traversal and typed strategy application.

[Source](lib_strategy/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Typed strategies | `TP`, `TU`, `strategy-typed-apply`, `strategy-typed-tp`, `strategy-typed-tu` |
| Strategy application | `strategy-all`, `strategy-all-tail`, `strategy-apply`, `strategy-choice-tail`, `strategy-eval`, `strategy-one`, `strategy-repeat` |
| Traversal | `all`, `alltd`, `bottomup`, `innermost`, `one`, `stratego-all`, `stratego-one`, `topdown` |
| Other heads | `choice`, `fail`, `gtry`, `seq`, `try`, `◁` |

Compose rewrites with seq, choice, try and repeat ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch20-extending-the-engine/20-02-metta-written-in-metta/11-strategy.metta#L9-L57)).

```metta
!(import! &self (library lib_strategy))

(= (strategy-step strategy-a) strategy-b)
(= (strategy-step strategy-b) strategy-c)
(= (strategy-step strategy-c) (empty))
(= (strategy-step $x) (empty))
(= (strategy-fail $x) (empty))
(= (strategy-mark $x) (marked $x))
(= (strategy-only-a strategy-a) A)
(= (strategy-only-a $x) (empty))
(= (strategy-none $x) (empty))
(= (strategy-many strategy-a) A1)
(= (strategy-many strategy-a) A2)
(= (strategy-right strategy-a) WRONG)

(strategy-policy fast (seq strategy-step strategy-step))

(= (strategy-cap strategy-a) A)
(= (strategy-cap $x) (empty))
(= (strategy-fold strategy-a) A)
(= (strategy-fold (h A)) done)
(= (strategy-fold $x) (empty))

!(test (id strategy-a) strategy-a)
!(test (strategy-apply id strategy-a) strategy-a)

!(test (collapse (fail strategy-a)) ())

!(test (seq strategy-step strategy-step strategy-a) strategy-c)

!(test (choice strategy-fail strategy-step strategy-a) strategy-b)
!(test (choice strategy-step strategy-fail strategy-a) strategy-b)
!(test (collapse (choice strategy-many strategy-right strategy-a)) (A1 A2))

!(test (try strategy-fail strategy-a) strategy-a)
!(test (gtry strategy-fail strategy-a) strategy-a)

!(test (strategy-repeat strategy-step strategy-a) strategy-c)
```

## Engine services

### lib_builtin_types

Declares builtin types for engine reflection and optional typed dispatch on import.

[Source](lib_builtin_types/pkg.metta); declared heads:

| Feature | Heads |
|---|---|
| Arithmetic and comparison operators | `!=`, `#*`, `#+`, `#-`, `#//`, `#<`, `#=`, `#=<`, `#>`, `#>=`, `#\=`, `#div`, `#max`, `#min`, `#mod`, `%`, `*`, `+`, `-`, `/`, `<`, `<=`, `==`, `>`, `>=` |
| Numeric functions | `abs-math`, `acos-math`, `asin-math`, `atan-math`, `ceil-math`, `cos-math`, `exp`, `exp-math`, `floor-math`, `isinf-math`, `isnan-math`, `log-math`, `max`, `min`, `pow-math`, `round-math`, `sin-math`, `sqrt-math`, `tan-math`, `trunc-math` |
| Types | `DontEvalType`, `Error`, `Kwargs`, `Predicate` |
| Atom updates and rules | `add-atom`, `add-atoms`, `add-reduct`, `add-reducts`, `add-translator-rule!`, `add-typing-rule!`, `remove-atom`, `remove-translator-rule!`, `remove-typing-rule!` |
| Atom inspection and transformation | `alpha-unique-atom`, `atom_chars`, `atom_concat`, `atom-subst`, `car-atom`, `cdr-atom`, `cons-atom`, `decons-atom`, `filter-atom`, `foldl-atom`, `index-atom`, `intersection-atom`, `is-alpha-member`, `is-expr`, `is-ground`, `is-member`, `is-space`, `is-var`, `map-atom`, `max-atom`, `min-atom`, `size-atom`, `sort-atom`, `subtraction-atom`, `union-atom`, `unique-atom` |
| Reflection and state | `change-state!`, `context-space`, `get-atoms`, `get-metatype`, `get-state`, `get-type`, `new-space`, `new-state` |
| Evaluation | `collapse`, `eval`, `eval-one`, `evalc`, `noeval`, `quote`, `reduce`, `super`, `superpose` |
| Assertions and tests | `assert`, `assert-answers`, `assert-includes-answers`, `assertaPredicate`, `assertzPredicate`, `test`, `test-no-answer` |
| Prolog predicates | `callPredicate`, `retractPredicate`, `translatePredicate` |
| Python | `py-atom`, `py-call`, `py-dict`, `py-dot`, `py-iter`, `py-list`, `py-tuple` |
| Imports and registration | `git-import!`, `import!`, `import_prolog_function`, `library`, `register-token!`, `require-extension!`, `unregister-token!` |
| Text and IO | `format-args`, `format-time`, `parse`, `parse-command`, `println!`, `read-form!`, `readln!`, `repr`, `repra`, `sort-strings`, `sread` |
| Random values | `random-float`, `random-int`, `with-seed` |
| Function application | `call`, `id`, `\|->` |
| Control and logic | `and`, `and-then`, `case`, `catch`, `chain`, `cut`, `if`, `if-decons-expr`, `implies`, `let`, `not`, `on-unwind`, `once`, `or`, `or-else`, `prog1`, `progn`, `switch`, `timeout`, `transaction`, `with_mutex`, `xor` |
| Time | `current-time`, `elapsed`, `sleep` |
| Collections | `append`, `cons`, `decons`, `exclude-item`, `first`, `foldall`, `foldl`, `forall`, `include`, `last`, `length`, `list_to_set`, `maplist`, `member`, `msort`, `reverse`, `second-from-pair`, `sort` |
| Other heads | `argv`, `bind!`, `copy_term`, `exists_file`, `hyperpose`, `match`, `metta`, `nop`, `sealed`, `term_hash` |

Read the declared types of the arithmetic and comparison builtins ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch09-types/02-builin_types.metta#L1-L23)).

```metta
!(import! &self (library lib_builtin_types))

!(test (get-type +) (-> Number Number Number))
!(test (get-type -) (-> Number Number Number))
!(test (get-type *) (-> Number Number Number))
!(test (get-type /) (-> Number Number Number))
!(test (get-type %) (-> Number Number Number))

!(test (get-type <) (-> Number Number Bool))
!(test (get-type <=) (-> Number Number Bool))
!(test (get-type >) (-> Number Number Bool))
!(test (get-type >=) (-> Number Number Bool))

!(test (get-type ==) (-> $a $b Bool))
!(test (get-type !=) (-> $a $b Bool))
```

### lib_derived

Installs an equation and translator rule deriving `once` from `take`.

[Source](lib_derived/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Evaluation | `once` |

Swap `once` for its equation over `take`, and put the compiler's clause back ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch20-extending-the-engine/20-01-translator-rules/08-derived_forms.metta#L11-L34)).

```metta
!(test (once (superpose (1 2 3))) 1)

!(import! &self (library lib_derived))

!(test (once (superpose (1 2 3))) 1)
!(test (collapse (once (superpose (1 2 3)))) (1))
!(test (collapse (once (empty))) ())

!(bind! &seen (new-space))
(= (noisy $x) (let $_ (add-atom &seen (saw $x)) $x))

!(test (once (superpose ((noisy a) (noisy b)))) a)
!(test (collapse (get-atoms &seen)) ((saw a)))

!(remove-translator-rule! once)

!(test (once (superpose (1 2 3))) 1)
```

### lib_doc

Preserves the former documentation import as a no-op because documentation now belongs to the engine.

[Source](lib_doc/pkg.metta); heads: none.

| Feature | Heads |
|---|---|
| Documentation import | None |

Document functions with `@doc` atoms and query them as data ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/08-doc_lib.metta#L6-L37)).

```metta
!(import! &self (library lib_doc))

(@doc greet (@desc "Greets somebody by name"))
(= (greet $who) $who)

(@doc add-two
      (@desc "Adds two numbers")
      (@params ((@param "the first") (@param "the second")))
      (@return "their sum"))
(= (add-two $a $b) (+ $a $b))

!(test (get-doc greet) (@doc greet (@desc "Greets somebody by name")))

!(test (get-doc add-two)
       (@doc add-two
             (@desc "Adds two numbers")
             (@params ((@param "the first") (@param "the second")))
             (@return "their sum")))

!(test (collapse (get-doc greet-nobody)) ())

!(test (collapse (get-doc missing)) ())

!(test (collapse (undocumented)) ())
```

### lib_import

Loads Prolog functions and exposes source import ownership, inspection and withdrawal.

[Source](lib_import/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Function imports | `import_prolog_functions_from_file`, `import_prolog_functions_from_module` |
| Module loading | `use-module!`, `use_module_global` |
| Other heads | `consult_global`, `imports`, `static-import!`, `unimport!` |

Load a Prolog file and register its predicate as a function ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch20-extending-the-engine/20-03-prolog-underneath/02-prologimport.metta#L30-L36)).

```text
!(import! &self (library lib_import))

!(import_prolog_functions_from_file "./examples/ch20-extending-the-engine/20-03-prolog-underneath/_fixtures/prologimport_example.pl" (myfunc))

!(test (myfunc 41) 42)
```

### lib_gitimport

Implements the engine's resident Git import operation and pinned dependency acquisition in Prolog.

[Source](lib_gitimport/lib_gitimport.pl); heads:

| Feature | Heads |
|---|---|
| Git imports | `git-import!` |

Acquire a repository, import the library it holds, and call it ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch20-extending-the-engine/20-04-modules-and-the-catalog/06-git_import.metta#L6-L14)).

```text
!(import! &self (library lib_import))
!(import_prolog_functions_from_file "./examples/ch20-extending-the-engine/20-04-modules-and-the-catalog/_fixtures/git_fixture.pl"
                                    (git_fixture_url))

!(git-import! (git_fixture_url "./repos"))

!(import! &self (library metta_fixture_lib fixture))

!(test (fixture-answer 14) 42)
```

### lib_memo

Controls explicit and automatic memoization, configuration, invalidation and statistics.

[Source](lib_memo/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Clearing | `clear-memoize`, `clear-memoize-stats` |
| Configuration and inspection | `config-memoize`, `get-memoize-config`, `get-memoize-stats`, `is-memoized` |
| Memoization | `invalidate-memoize`, `memoize`, `memoize-exact` |

Memoize a function exactly and read its configuration and counters ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch18-performance/18-02-memoisation-and-tabling/17-memo_controls.metta#L4-L41)).

```metta
!(import! &self (library lib_memo))

(: sq (-> Number Number))
(= (sq $x) (* $x $x))

!(memoize-exact sq)
!(test (is-memoized sq) True)
!(test (sq 9) 81)
!(test (sq 9) 81)

!(test (size-atom (get-memoize-config)) 6)
!(test (index-atom (car-atom (get-memoize-config)) 0) strategy)

!(test (size-atom (get-memoize-stats)) 2)
!(test (get-memoize-stats sq) ((entries 1) (answers 1)))

!(test (sq 4) 16)
!(test (get-memoize-stats sq) ((entries 2) (answers 2)))

!(clear-memoize-stats)
!(test (get-memoize-stats) ())
!(test (sq 9) 81)
!(test (get-memoize-stats) ((cache_hit 1)))
!(test (get-memoize-stats sq) ((entries 2) (answers 2)))
```

### lib_tabling

Controls Prolog answer tables whose reuse can discard answer order and duplicates.

[Source](lib_tabling/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Answer tables | `metta_table_clear`, `metta_table_clear_all`, `metta_table_statistics`, `table-clear`, `table-clear-all`, `table-stats` |
| Declarations | `metta_tabled_decl`, `metta_untabled_decl`, `tabled`, `untabled` |
| Other heads | `injectPrologCode` |

Table a doubly recursive function so each call is computed once ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch18-performance/18-02-memoisation-and-tabling/09-tabling_fib.metta#L1-L13)).

```metta
!(import! &self (library lib_tabling))

(= (fib $N)
   (if (< $N 2)
       $N
       (+ (fib (- $N 1))
          (fib (- $N 2)))))

!(tabled (fib $N))

!(test (fib 30) 832040)
```

### lib_thread

Provides parallel collection operations, futures, channels, pools, timers, resource scopes and blocking space queries.

[Source](lib_thread/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Channels | `channel`, `channel-close`, `channel_close`, `channel_new`, `channel_recv`, `channel_send`, `channel-size`, `channel_size`, `channel_try_recv`, `recv`, `send`, `try-recv` |
| Pools | `pool`, `pool_create`, `pool-destroy`, `pool_destroy`, `pool-stats`, `pool_stats`, `pool_submit`, `submit` |
| Threads and futures | `await`, `cancel`, `settled?`, `spawn`, `thread_await`, `thread_cancel`, `thread-count`, `thread_count`, `thread_settled`, `thread_spawn` |
| Timers | `after`, `every`, `timer_after`, `timer_every` |
| Scopes | `scope`, `scope_body`, `scope-defer`, `scope_defer` |
| Parallel combinators | `par-any`, `par_any`, `par-filter`, `par_filter`, `par-forall`, `par_forall`, `par-map`, `par_map`, `par-race`, `par_race` |
| Space queries | `await-atom`, `drop-space`, `peek-atom`, `space_await`, `space_await_where`, `space_drop`, `space_take`, `space_take_where`, `take-atom` |
| Other heads | `capture`, `cpu-count`, `cpu_count`, `with-lock`, `with_lock` |

Map, filter and race in parallel, and await futures ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch17-concurrency-and-the-loop/01-thread_lib.metta#L5-L38)).

```metta
!(import! &self (library lib_thread))

(= (inc $x) (+ $x 1))
(= (big? $x) (> $x 2))
(= (slow $x) (let $_ (sleep 1) $x))

!(test (par-map inc (1 2 3 4)) (2 3 4 5))
!(test (par-map inc ()) ())
!(test (par-filter big? (1 2 3 4 5)) (3 4 5))
!(test (par-forall big? (3 4 5)) True)
!(test (par-forall big? (1 4 5)) False)

!(test (par-any big? (1 2 9)) True)
!(test (par-any big? (1 2)) False)

!(test (par-race ((slow 1) (inc 41))) 42)
!(test (par-race ((superpose ()) (inc 41))) 42)

!(test (let $f (spawn (inc 41)) (await $f)) 42)
!(test (let $a (spawn (slow 1)) (let $b (spawn (slow 2)) (+ (await $a) (await $b)))) 3)
!(test (let $f (spawn (inc 1)) (let $_ (await $f) (await $f))) 2)
```

### lib_observe

Runs source while returning queryable trace, coverage and diagnostic events.

[Source](lib_observe/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Observation | `observe-source`, `trace-source` |

Trace one function through a run and match the events it recorded ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch20-extending-the-engine/20-05-observing-execution/01-filtered-trace.metta#L2-L13)).

```metta
!(import! &self (library lib_observe))
(= (trace-increment $x) (+ $x 1))
(= (trace-outer $x) (trace-increment $x))
!(bind! &trace (trace-source &self "!(trace-outer 4)" (trace-increment) 10))
!(test (match &trace (trace-event $seq $time $depth call (trace-increment 4) $answer) $depth) 1)
!(test (match &trace (trace-event $seq $time $depth exit (trace-increment 4) $answer) $answer) 5)
!(test (match &trace (trace-event 0 $time $depth call (trace-increment 4) $answer) $depth) 1)
!(test (match &trace (trace-stopped $reason) $reason) False)
!(test (space-atom-count &trace) 3)
```

### lib_reflect

Enumerates engine operations, arities and origins and inspects or substitutes literal terms.

[Source](lib_reflect/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Engine operations | `engine-arity`, `engine-builtin`, `engine-extension-point`, `engine-function`, `engine-knows`, `engine-origin`, `engine-special-form`, `engine-surface-counts`, `engine-user-function` |
| Terms | `atom-replace`, `atom-variables` |
| Surface exports | `surface-counts`, `surface-json` |
| Other heads | `arity-of`, `builtins`, `extension-points`, `functions`, `knows?`, `origin-of`, `special-forms`, `user-functions` |

Ask the engine what it knows, at what arity, where it was defined, and in which list ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/14-reflect_lib.metta#L7-L46)).

```metta
!(import! &self (library lib_reflect))

(= (mine $x) $x)

!(test (knows? car-atom) True)
!(test (knows? mine) True)
!(test (knows? no-such-name-anywhere) False)

!(test (collapse (arity-of car-atom)) (2))
!(test (collapse (arity-of cons-atom)) (3))
!(test (collapse (arity-of no-such-name-anywhere)) ())

!(test (once (car-atom (origin-of car-atom))) origin)
!(test (car-atom (origin-of mine)) origin)
!(test (collapse (origin-of no-such-name-anywhere)) ())

!(test (> (size-atom (collapse (builtins))) 100) True)
!(test (> (size-atom (collapse (special-forms))) 10) True)
!(test (is-member mine (collapse (user-functions))) True)
!(test (is-member car-atom (collapse (user-functions))) False)
!(test (is-member car-atom (collapse (functions))) True)
!(test (is-member case (collapse (builtins))) False)
!(test (is-member case (collapse (special-forms))) True)
!(test (is-member let (collapse (builtins))) True)
!(test (is-member let (collapse (special-forms))) True)
```

### lib_conformance

Checks a foreign space provider's declared capabilities, matching and exact pushdown claims.

[Source](lib_conformance/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Provider conformance | `check-space-provider`, `metta_check_space_provider` |

Check a foreign space provider's declared capabilities and its matching ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/09-conformance.metta#L8-L30)).

```text
!(import! &self (library lib_conformance))

!(import_prolog_functions_from_file "./examples/ch08-data/08-03-the-shipped-libraries/_fixtures/demo_provider.pl" ())

!(test (check-space-provider &demo_provider)
       ("match: declared, seam:foreign_match/3 has clauses"
        "enumerate: declared, seam:foreign_atoms/2 has clauses"
        "match: over-approximation holds over 2 atoms and their pattern families"
        "source: repeated, two enumerations agree"
        "round trip: not asked, the provider does not declare add, remove and enumerate together"
        "pushdown: 0 of 2 patterns claimed exact, and are"
        "plan: not declared, so a conjunction takes the engine's split"))

!(test (sort-atom (collapse (match &demo_provider (edge a $y) $y))) (b))
```

### lib_testing

Reexports `lib_combinatorics` generators for property checks with core assertions, adding no new callable heads.

[Source](lib_testing/pkg.metta); reexported heads:

| Feature | Heads |
|---|---|
| Choices | `choose2`, `choose2l`, `chooseK`, `chooseKl`, `takeK` |
| Products and tuples | `cartesian-power`, `tuples` |
| Permutations | `permutation-count`, `permutations` |
| Ranges | `range`, `range-step` |
| Counts and subsets | `binomial`, `factorial`, `subsets` |

Enumerate finite domains and products, and check a property over each with forall ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/43-testing_lib.metta#L3-L40)).

```metta
!(import! &self (library lib_combinatorics))
!(import! &self (library lib_testing))

!(test (collapse (range -2 3)) (-2 -1 0 1 2))
!(test (collapse (range 3 4)) (3))
!(test (collapse (range 3 3)) ())
!(test (collapse (range 100000000000000000000 100000000000000000003))
       (100000000000000000000 100000000000000000001 100000000000000000002))
!(test (collapse (superpose (a a "π"))) (a a "π"))
!(test (collapse (superpose ())) ())
!(test (size-atom (index-atom (quote ((+ 1 2))) 0)) 3)
!(test (collapse (index-atom (()) 0)) (()))
!(test (let $items (collapse (range 1 4))
         (collapse (index-atom $items (range 0 (size-atom $items))))) (1 2 3))

!(test (collapse (cartesian-power (0 1) 0)) (()))
!(test (collapse (cartesian-power (0 1) 2)) ((0 0) (0 1) (1 0) (1 1)))
!(test (collapse (cartesian-power (a a) 2)) ((a a) (a a) (a a) (a a)))
!(test (collapse (cartesian-power () 0)) (()))
!(test (collapse (cartesian-power () 2)) ())
!(test (collapse (let* (($population (collapse (range 0 2)))
                       ($length (range 0 3)))
                  (cartesian-power $population $length)))
       (() (0) (1) (0 0) (0 1) (1 0) (1 1)))
!(test (collapse (cartesian-power (0 1) (range 2 2))) ())
!(test (let $choice (index-atom ((row $x $x)) 0)
         (let $pair (map-atom (1 2) $ignored (copy_term (quote $choice)))
           (=alpha $pair ((row $a $a) (row $b $b))))) True)
!(test (collapse (cartesian-power (() (a)) 1)) ((()) ((a))))

!(forall (range -3 4) (|-> ($x) (test (>= (* $x $x) 0) True)))
!(forall (cartesian-power (0 1) (range 0 4))
   (|-> ($xs) (test (reverse (reverse $xs)) $xs)))
```

## Compatibility and programming idioms

### lib_he

Provides Hyperon-Experimental compatibility equations for equality, errors, evaluation and types that can shadow engine operations.

[Source](lib_he/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Assertions | `assertAlphaEqual`, `assertAlphaEqualToResult`, `assertEqual`, `assertEqualToResult` |
| Conditionals | `if-equal`, `if-equal2`, `if-error` |
| Type matching | `match-type-or`, `match-types` |
| Other heads | `add-reduct`, `evalc`, `for-each-in-atom`, `get-type-space`, `is-function`, `noreduce-eq`, `return-on-error`, `unify`, `unquote` |

Use Hyperon-Experimental's assertions, which compare answer by answer ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch12-testing/01-he_assert.metta#L3-L14)).

```metta
!(import! &self (library lib_he))

!(test (assertEqual (+ 1 2) (- 6 3)) True)
!(test (assertAlphaEqual (h $x $y) (h $a $b)) True)
!(test (assertAlphaEqual (quote (+ $x $y)) (quote (+ $a $b))) True)

!(test (assertEqualToResult (+ 1 2) 3) True)
!(test (collapse (assertEqualToResult (superpose (1 1)) 1)) (true true))
(= (adder) ($x))
!(test (assertAlphaEqualToResult (adder) ($y)) True)
```

### minimal_metta_lib

Provides minimal MeTTa's instruction set, the evaluation and binding operations hyperon's minimal interpreter is written in, with switch, reduce and a Turing machine written over them.

[Source](minimal_metta_lib/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Instructions | `collapse-bind`, `function`, `superpose-bind`, `unify-mod` |
| Derived forms | `if-partial`, `mm-reduce`, `mm-subst`, `mm-switch`, `mm-switch-internal` |
| Turing machine | `mm-move`, `mm-read`, `mm-tm`, `mm-tm-body` |

Run minimal MeTTa's instructions: function and return, chain, unify-mod, and the switch written in them ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch20-extending-the-engine/20-02-metta-written-in-metta/04-minimal_metta.metta#L14-L74)).

```metta
!(import! &self (library minimal_metta_lib))

!(test (function (return 42)) 42)
!(test (function (chain (+ 1 2) $x (return $x))) 3)

!(test (return 7) (return 7))

!(test (function (foo bar)) (Error (function (foo bar)) NoReturn))

!(test (unify-mod $a Empty then else) then)

!(test (unify-mod $a (:= Empty) then else) else)

!(test (unify-mod (:= a b) (:= $x $y) then else) then)

!(test (unify-mod (A B C D E) (A ... D ...) matched nomatch) matched)

!(test (unify-mod (p 5) (p $x) (got $x) else) (got 5))

!(test (mm-switch 1 ((1 one) (2 two))) one)
!(test (mm-switch 2 ((1 one) (2 two))) two)
!(test (mm-switch (p 5) (((p $x) (got $x)))) (got 5))

!(test (collapse (mm-switch 9 ((1 one) (2 two)))) ())
```

### lib_patrick

Provides function composition, reverse matching, a translated loop and indexed iteration.

[Source](lib_patrick/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Function and iteration idioms | `@`, `compose`, `for`, `iterate` |

Name and destructure an argument at once, filter with `for`, and fold with `iterate` ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-01-atoms-lists-and-folds/11-patrick.metta#L1-L19)).

```metta
!(import! &self (library lib_patrick))

(= (mirror $A)
   (let $A (@ $L (cons $head $tail))
        (append (reverse $L) $tail)))

!(test (mirror (h a n n e s)) (s e n n a h a n n e s))

!(test (collapse (for $x (1 2 3 4 5 6)
                      (if (> $x 3) $x)))
       (4 5 6))

!(test (iterate 0 10
                1 (|-> ($i $x)
                       (+ $x $i)))
       46)
```

### lib_roman

Provides tracing, flat and nested maps and folds, predicate-based set operations and function combinators.

[Source](lib_roman/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Folds | `fold-flat`, `fold-nested`, `foldr-flat` |
| Maps | `map-flat`, `map-nested` |
| Tracing | `traceid`, `tracem` |
| Other heads | `&&&`, `&^&`, `.`, `..`, `.:`, `/==\`, `/=\`, `/=a\`, `/?\`, `@`, `\=`, `\=/`, `\==`, `\==/`, `\=a`, `\=a/`, `\?`, `\?/`, `cns`, `first`, `flip`, `fst`, `head`, `init`, `mylast`, `rcons`, `second`, `snd`, `tail` |

Map and fold flat and nested, intersect and subtract collections, and compose functions ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-01-atoms-lists-and-folds/15-roman.metta#L1-L30)).

```metta
!(import! &self (library lib_roman))
!(test (map-flat (+ 1) (1 2 3)) (2 3 4))
!(test (map-nested (+ 1) (1 (2 3))) (2 (3 4)))

!(test (fold-flat + 0 (1 2 3)) 6)
!(test (foldr-flat cons () (1 (2 3) 4)) (1 (2 3) 4))
!(test (fold-nested + 0 (1 (2 3))) 6)

!(test (/=\ (1 2 $a) (2 3 4)) (2 2))
!(test (/==\ (1 2 3) (2 3 4)) (2 3))
!(test (/=a\ (1 2 $a) (2 $a 4)) (2 $a))

!(test (\= (1 2 3) ($a 3 4)) (2))
!(test (\== (1 2 3) (2 3 4)) (1))
!(test (\=a (1 2 $a) (2 $a 4)) (1))

!(test (\=/ (1 2 3) ($a 3 4)) (2 1 3 4))
!(test (\==/ (1 2 3) (2 3 4)) (1 2 3 4))
!(test (\=a/ (1 2 $a) (2 $a 4)) (1 2 $a 4))

!(test (. (+ 1) (* 2) 1) 3)
!(test (.: (+ 1) + 2 3) 6)
!(test (&&& (+ 2) (* 2) 1) (3 2))

(= (mfail $x) (empty))
!(test (collapse (&^& (+ 1) (mfail) 1)) (2))
```

### lib_zar

Provides predicate-style Prolog consultation, module loading and named function imports.

[Source](lib_zar/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Function imports | `import_prolog_functions_from_file_pred`, `import_prolog_functions_from_module_pred` |
| Consultation and modules | `consult_file`, `use_module_file` |

Consult a Prolog file and use a module by path, then register their functions ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch20-extending-the-engine/20-03-prolog-underneath/05-the-module-doors.metta#L14-L32)).

```text
!(import! &self (library lib_import))
!(import! &self (library lib_zar))
!(import! &self (library lib_file))

!(test (consult_file "./examples/ch20-extending-the-engine/20-03-prolog-underneath/_fixtures/rung_functions.pl")
       True)
!(test (import_prolog_functions (noeval (rung_double rung_greeting))) True)
!(test (rung_double 21) 42)

!(test (use_module_file "./examples/ch20-extending-the-engine/20-03-prolog-underneath/_fixtures/rung_module.pl")
       True)
!(test (import_prolog_functions (noeval (rung_module_triple))) True)
!(test (rung_module_triple 14) 42)
```
