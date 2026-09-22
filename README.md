<!--
Purpose: show the MeTTa Library Pack through its library roster, exported heads and shipped examples.
Guarantees: every library directory has an entry, every listed head occurs in its source or named reexport, and worked examples quote shipped forms with comment lines removed [source: WORKTREE, lib/lib_*/* and examples/ch08-data/08-03-the-shipped-libraries/].
-->

# MeTTa Library Pack

The MeTTa Library Pack supplies 61 libraries for MeTTa programs.

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
| [Engine services](#engine-services) | 13 |
| [Compatibility and programming idioms](#compatibility-and-programming-idioms) | 4 |

Head lists include each library's own declarations, equations and registered native names; dependencies have their own entries.

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

Choose pairs and distinguish an empty choice from no choices ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/11-combinatorics_lib.metta)).

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

Zip collections and reject malformed pairs ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/22-functional_lib.metta)).

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

### lib_dict

Provides mutable dictionaries as spaces of key/value pairs.

[Source](lib_dict/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Dictionaries | `dict-get`, `dict-has`, `dict-merge`, `dict-pairs`, `dict-pop`, `dict-put`, `dict-remove`, `dict-remove-pair`, `dict-size`, `dict-update`, `dict-values` |

Update a dictionary and query it as a space ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/12-dict_lib.metta)).

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

### lib_sets

Provides ordered, duplicate-free sets with identity-based membership and set operations.

[Source](lib_sets/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Sets | `set-difference`, `set-disjoint`, `set-insert`, `set-intersection`, `set-is`, `set-member`, `set-of`, `set-remove`, `set-subset`, `set-symmetric-difference`, `set-union` |

Canonicalize sets and distinguish identity from variable binding ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/23-sets_lib.metta)).

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

Build a graph with an isolated vertex and inspect its edges ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/25-graph_lib.metta)).

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

### lib_mm2

Provides add, remove, query and transformation notation over the MORK extension's space.

[Source](lib_mm2/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Space notation | `?`, `~>`, `＋`, `＋*`, `－` |

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

### lib_unicode

Provides Unicode normalization, case folding, grapheme segmentation and character properties.

[Source](lib_unicode/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Unicode | `unicode-casefold`, `unicode-codepoint-valid`, `unicode-graphemes`, `unicode-is`, `unicode-map`, `unicode-normalize`, `unicode-property`, `unicode-version` |

### lib_regex

Provides compiled PCRE2 patterns, matching, typed captures, scans and substitutions.

[Source](lib_regex/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Patterns | `re-compile`, `re-escape` |
| Matching and captures | `re-captures`, `re-count`, `re-find`, `re-fullmatch`, `re-match`, `re-ranges`, `re-scan`, `regex_captures`, `regex_find`, `regex_match` |
| Replacement and splitting | `re-replace`, `re-replace-all`, `re-split`, `regex_replace`, `regex_replace_all`, `regex_split` |

Match text, decode named captures and replace matches ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/04-regex_lib.metta)).

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

Compose recursive grammars as ordinary equations ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/27-parsing_lib.metta)).

```metta
!(import! &self (library lib_parsing))

(= (sum) (alt (integer) (between (lit "(") (sep-by (ref sum) (lit "+")) (lit ")"))))
!(test (grammar-parse (ref sum) "7") 7)
!(test (grammar-parse (ref sum) "(1+2)") (1 2))
!(test (grammar-parse (ref sum) "(1+(2+3))") (1 (2 3)))
!(test (collapse (grammar-parse (ref sum) "(1+)")) ())
```

### lib_json

Decodes JSON objects into spaces and provides paths, serialization and JSON Lines.

[Source](lib_json/pkg.metta); heads:

| Feature | Heads |
|---|---|
| JSON Lines | `json-lines-decode`, `json-lines-encode`, `json-lines-read!`, `json-lines-write!` |
| JSON values | `json-at`, `json-decode`, `json-encode`, `json-pretty`, `json-read!`, `json-write!` |
| Object spaces | `dict-space`, `get-keys`, `get-value` |

Query decoded objects and retain duplicate fields ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/05-json_lib.metta)).

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

### lib_yaml

Reads and writes single YAML documents using spaces for mappings and expressions for sequences.

[Source](lib_yaml/pkg.metta); heads:

| Feature | Heads |
|---|---|
| YAML | `yaml-decode`, `yaml-encode`, `yaml-read!`, `yaml-write!` |

### lib_markup

Parses HTML and XML into element expressions and selects attributes, descendants and text.

[Source](lib_markup/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Markup | `markup-attribute`, `markup-parse-html`, `markup-parse-xml`, `markup-select`, `markup-text`, `markup-write` |

### lib_encoding

Converts text and byte expressions through UTF-8, hexadecimal and Base64.

[Source](lib_encoding/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Base64 | `base64-decode`, `base64-encode` |
| Hexadecimal | `hex-decode`, `hex-encode` |
| UTF-8 | `utf8-decode`, `utf8-encode` |

Count UTF-8 bytes separately from characters ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/30-encoding_lib.metta)).

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

### lib_uuid

Constructs, validates and inspects UUIDs, including byte conversion and namespace-derived identifiers.

[Source](lib_uuid/pkg.metta); heads:

| Feature | Heads |
|---|---|
| UUIDs | `uuid-bytes`, `uuid-is`, `uuid-name`, `uuid-namespaces`, `uuid-nil`, `uuid-of-bytes`, `uuid-random!`, `uuid-time!`, `uuid-timestamp`, `uuid-variant`, `uuid-version` |

## Numerics and probability

### lib_math

Provides exact rational arithmetic, integer roots, modular powers, factors and native real functions.

[Source](lib_math/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Classification and conversion | `math-class`, `math-float`, `math-ratio`, `math-rational`, `math-rationalize`, `math-real` |
| Integer arithmetic | `math-factor-pairs`, `math-gcd`, `math-integer-root`, `math-lcm`, `math-power-mod` |
| Real functions | `math-real-functions`, `math-sqrt` |

### lib_vector

Provides numeric vector arithmetic, exact intermediate reductions, norms, distances and cosine similarity.

[Source](lib_vector/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Vectors | `vector-add`, `vector-distance`, `vector-divide`, `vector-fill`, `vector-multiply`, `vector-normalize`, `vector-scale`, `vector-subtract` |
| Cosine similarity | `cosine`, `cosine-of-normalized` |
| Other heads | `dot`, `norm`, `random-normal-vector` |

Compute dot products, lengths and directional similarity ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/13-vector_lib.metta)).

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

### lib_measure

Normalizes, ranks, samples and combines weighted alternatives.

[Source](lib_measure/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Ranking and selection | `ws-best`, `ws-choose`, `ws-peak`, `ws-pickmax`, `ws-ranked`, `ws-take`, `ws-top` |
| Sampling | `ws-flip`, `ws-sample!`, `ws-sample-walk` |
| Weights and aggregation | `ws-collapse`, `ws-expect`, `ws-filter`, `ws-merge-into`, `ws-normalize`, `ws-softmax`, `ws-total` |

### lib_statistics

Computes sample statistics, finite probability laws and exact independent weighted-subset posteriors.

[Source](lib_statistics/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Sample statistics | `stats-correlation`, `stats-covariance`, `stats-geometric-mean`, `stats-harmonic-mean`, `stats-mean`, `stats-median`, `stats-mode`, `stats-quantile`, `stats-quantiles`, `stats-ranks`, `stats-regression`, `stats-stdev`, `stats-sum`, `stats-variance` |
| Weighted subsets | `weighted-subset-mass-independent`, `weighted-subset-posterior-independent` |
| Independent combinations | `ws-add-bernoulli-independent`, `ws-average-independent`, `ws-map-independent`, `ws-prob-gt-independent`, `ws-sum-independent` |
| Weighted statistics | `ws-central-moment`, `ws-condition-joint`, `ws-deviation`, `ws-map`, `ws-mass-at-least`, `ws-mass-at-most`, `ws-median`, `ws-quantile`, `ws-support`, `ws-variance` |

Retain small residuals and exact means ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/37-statistics_lib.metta)).

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

### lib_datetime

Provides clocks, calendar records, parsing, formatting and arithmetic with explicit time zones.

[Source](lib_datetime/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Dates | `date-add`, `date-field`, `date-fields`, `date-timestamp`, `date-weekday`, `date-year-day` |
| Formatting | `format-date`, `format_date`, `format-datetime` |
| Calendar properties | `day-of-week`, `day_of_week`, `leap-year`, `month-days` |
| Other heads | `now`, `parse-date`, `timestamp-date` |

Round-trip timestamps with explicit offsets and inspect calendar fields ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/07-datetime.metta)).

```metta
!(import! &self (library lib_datetime))

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

### lib_process

Starts programs with argument vectors and captures output, signals processes or waits for completion.

[Source](lib_process/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Processes | `process-run!`, `process-run-input!`, `process-signal!`, `process-signals`, `process-start!`, `process-status`, `process-wait!` |

### lib_cli

Parses typed command-line options, renders help and reads the process argument vector.

[Source](lib_cli/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Command line | `cli-arguments!`, `cli-help`, `cli-parse`, `cli-types` |

### lib_logging

Emits structured log events with topic controls and optional MeTTa handlers.

[Source](lib_logging/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Logging | `log!`, `log-enabled`, `log-format`, `log-levels`, `log-to!`, `log-topic!`, `log-topics` |

### lib_compression

Compresses bytes and files with gzip or zlib and inspects, reads or extracts archives.

[Source](lib_compression/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Archives | `archive-entries!`, `archive-extract!`, `archive-read!` |
| Compression | `compress-bytes`, `compress-file!`, `compression-formats`, `decompress-bytes`, `decompress-file!` |

### lib_crypto

Provides hashes, HMACs, password records and cryptographic random values.

[Source](lib_crypto/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Hashes | `crypto-hash`, `crypto_hash`, `crypto-hash-bytes`, `crypto-hash-file!` |
| HMACs | `crypto-hmac`, `crypto-hmac-bytes` |
| Passwords | `crypto-password-hash`, `crypto-password-verify` |
| Random values | `crypto-random-bytes`, `crypto-random-hex`, `crypto_random_hex`, `crypto-random-integer` |

### lib_http

Provides streaming HTTP clients and scoped HTTP servers with MeTTa request handlers.

[Source](lib_http/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Servers | `http-server-start!`, `http-server-stop!`, `http-server-url`, `with-http-server` |
| Clients and messages | `http-header`, `http-methods`, `http-open!`, `http-request!`, `with-http` |

### lib_socket

Provides TCP listeners and connections, UDP datagrams and scoped socket ownership.

[Source](lib_socket/pkg.metta); heads:

| Feature | Heads |
|---|---|
| TCP | `tcp-accept!`, `tcp-connect!`, `tcp-listen!` |
| UDP | `udp-bind!`, `udp-receive!`, `udp-send!` |
| Socket inspection and lifetime | `socket-endpoint`, `socket-kind`, `socket-shutdown!`, `socket-wait!`, `with-socket` |

### lib_database

Persists atom syntax in journaled stores with explicit handles, synchronization and scoped cleanup.

[Source](lib_database/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Database stores | `database-add!`, `database-atoms`, `database-close!`, `database-open!`, `database-remove!`, `database-sync!`, `with-database` |

### lib_redis

Attaches shared Redis-backed spaces with cross-process change notifications.

[Source](lib_redis/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Redis spaces | `redis-attach`, `redis-detach` |

## Reasoning and rewriting

### lib_constraints

Exposes rational CLP(Q) constraints and Boolean CLP(B) constraints, labeling and tautology checks.

[Source](lib_constraints/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Boolean constraints | `clpb`, `clpb-labeling`, `clpb-taut` |
| Rational constraints | `clpq`, `clpq-entailed` |

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

### lib_pln2

Provides Beta and moment formulas with explicit evidence scales and checked independent support sets.

[Source](lib_pln2/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Beta distributions | `pln2-beta-moments`, `pln2-beta-update` |
| Confidence and moments | `pln2-confidence-count`, `pln2-count-confidence`, `pln2-moments-stv`, `pln2-stv-moments` |
| Independent support | `pln2-product-independent`, `pln2-require-independent-supports`, `pln2-total-probability-independent` |

### lib_soft

Scores structural similarity between terms and queries spaces for weighted matches.

[Source](lib_soft/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Structural similarity | `soft-aggregation`, `soft-best`, `soft-fold`, `soft-match`, `soft-score`, `soft-score-by`, `soft-symbol?`, `soft-walk` |
| Symbol similarity | `sym-sim` |

### lib_strategy

Composes term rewrites through choice, repetition, traversal and typed strategy application.

[Source](lib_strategy/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Typed strategies | `TP`, `TU`, `strategy-typed-apply`, `strategy-typed-tp`, `strategy-typed-tu` |
| Strategy application | `strategy-all`, `strategy-all-tail`, `strategy-apply`, `strategy-choice-tail`, `strategy-eval`, `strategy-one`, `strategy-repeat` |
| Traversal | `all`, `alltd`, `bottomup`, `innermost`, `one`, `stratego-all`, `stratego-one`, `topdown` |
| Other heads | `choice`, `fail`, `gtry`, `seq`, `try`, `◁` |

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

### lib_derived

Installs an equation and translator rule deriving `once` from `take`.

[Source](lib_derived/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Evaluation | `once` |

### lib_doc

Preserves the former documentation import as a no-op because documentation now belongs to the engine.

[Source](lib_doc/pkg.metta); heads: none.

| Feature | Heads |
|---|---|
| Documentation import | None |

### lib_import

Loads Prolog functions and exposes source import ownership, inspection and withdrawal.

[Source](lib_import/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Function imports | `import_prolog_functions_from_file`, `import_prolog_functions_from_module` |
| Module loading | `use-module!`, `use_module_global` |
| Other heads | `consult_global`, `imports`, `static-import!`, `unimport!` |

### lib_gitimport

Implements the engine's resident Git import operation and pinned dependency acquisition in Prolog.

[Source](lib_gitimport/lib_gitimport.pl); heads:

| Feature | Heads |
|---|---|
| Git imports | `git-import!` |

### lib_package

Interprets package declarations, prepares dependencies and registers Prolog backings through the resident package service.

[Source](lib_package/pkg.metta) / [Prolog](lib_package/lib_package.pl); heads:

| Feature | Heads |
|---|---|
| Packages | `get-property`, `package-prolog`, `setup!` |

### lib_memo

Controls explicit and automatic memoization, configuration, invalidation and statistics.

[Source](lib_memo/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Clearing | `clear-memoize`, `clear-memoize-stats` |
| Configuration and inspection | `config-memoize`, `get-memoize-config`, `get-memoize-stats`, `is-memoized` |
| Memoization | `invalidate-memoize`, `memoize`, `memoize-exact` |

### lib_tabling

Controls Prolog answer tables whose reuse can discard answer order and duplicates.

[Source](lib_tabling/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Answer tables | `metta_table_clear`, `metta_table_clear_all`, `metta_table_statistics`, `table-clear`, `table-clear-all`, `table-stats` |
| Declarations | `metta_tabled_decl`, `metta_untabled_decl`, `tabled`, `untabled` |
| Other heads | `injectPrologCode` |

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

### lib_observe

Runs source while returning queryable trace, coverage and diagnostic events.

[Source](lib_observe/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Observation | `observe-source`, `trace-source` |

### lib_reflect

Enumerates engine operations, arities and origins and inspects or substitutes literal terms.

[Source](lib_reflect/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Engine operations | `engine-arity`, `engine-builtin`, `engine-extension-point`, `engine-function`, `engine-knows`, `engine-origin`, `engine-special-form`, `engine-surface-counts`, `engine-user-function` |
| Terms | `atom-replace`, `atom-variables` |
| Surface exports | `surface-counts`, `surface-json` |
| Other heads | `arity-of`, `builtins`, `extension-points`, `functions`, `knows?`, `origin-of`, `special-forms`, `user-functions` |

### lib_conformance

Checks a foreign space provider's declared capabilities, matching and exact pushdown claims.

[Source](lib_conformance/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Provider conformance | `check-space-provider`, `metta_check_space_provider` |

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

Check finite domains and count answer multiplicities ([source](https://github.com/MesTTo/MeTTa-Examples/blob/main/ch08-data/08-03-the-shipped-libraries/43-testing_lib.metta)).

```metta
!(import! &self (library lib_combinatorics))
!(import! &self (library lib_testing))

!(forall (range -3 4) (|-> ($x) (test (>= (* $x $x) 0) True)))
!(forall (cartesian-power (0 1) (range 0 4))
   (|-> ($xs) (test (reverse (reverse $xs)) $xs)))
!(test (forall (range 0 5) (<= 0)) True)
!(test (foldall (|-> ($value $count) (+ $count 1)) (superpose (a a b)) 0) 3)
!(test (forall (superpose ()) (|-> ($x) False)) True)
!(test (foldall (|-> ($value $count) (+ $count 1)) (superpose ()) 0) 0)
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

### lib_patrick

Provides function composition, reverse matching, a translated loop and indexed iteration.

[Source](lib_patrick/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Function and iteration idioms | `@`, `compose`, `for`, `iterate` |

### lib_roman

Provides tracing, flat and nested maps and folds, predicate-based set operations and function combinators.

[Source](lib_roman/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Folds | `fold-flat`, `fold-nested`, `foldr-flat` |
| Maps | `map-flat`, `map-nested` |
| Tracing | `traceid`, `tracem` |
| Other heads | `&&&`, `&^&`, `.`, `..`, `.:`, `/==\`, `/=\`, `/=a\`, `/?\`, `@`, `\=`, `\=/`, `\==`, `\==/`, `\=a`, `\=a/`, `\?`, `\?/`, `cns`, `first`, `flip`, `fst`, `head`, `init`, `mylast`, `rcons`, `second`, `snd`, `tail` |

### lib_zar

Provides predicate-style Prolog consultation, module loading and named function imports.

[Source](lib_zar/pkg.metta); heads:

| Feature | Heads |
|---|---|
| Function imports | `import_prolog_functions_from_file_pred`, `import_prolog_functions_from_module_pred` |
| Consultation and modules | `consult_file`, `use_module_file` |
