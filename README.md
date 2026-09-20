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

[Source](lib_combinatorics/lib_combinatorics.metta); heads:

```text
binomial cartesian-power choose2 choose2l chooseK chooseKl factorial permutation-count
permutations range range-step subsets takeK tuples
```

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

[Source](lib_functional/lib_functional.metta); heads:

```text
apply-to chunk drop flatten-deep flatten-once group-by partition pipe repeat scan
sort-by unfold unless unzip while window zip
```

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

[Source](lib_datastructures/lib_datastructures.metta); heads:

```text
FTDeep FTEmpty FTSingle FTree add-unique-or-fail dequeue empty-queue enqueue ft-app3
ft-back ft-borrow-l ft-borrow-r ft-concat ft-empty ft-from-list ft-front ft-is-empty
ft-node-digit ft-nodes ft-pop-back ft-pop-front ft-push-back ft-push-front
ft-push-list-back ft-push-list-front ft-to-list map-empty map-from-pairs map-get
map-get-or map-has map-keys map-max map-min map-pairs map-put map-remove map-size
map-values pq-empty pq-from-pairs pq-insert pq-merge pq-min pq-pairs pq-pop pq-remove
pq-size
```

### lib_dict

Provides mutable dictionaries as spaces of key/value pairs.

[Source](lib_dict/lib_dict.metta); heads:

```text
dict-get dict-has dict-merge dict-pairs dict-pop dict-put dict-remove dict-remove-pair
dict-size dict-update dict-values
```

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

[Source](lib_pairs/lib_pairs.metta); heads:

```text
pairs-group pairs-is pairs-keys pairs-lookup pairs-sort-by-key pairs-sort-by-value
pairs-swap pairs-ungroup pairs-values
```

### lib_sets

Provides ordered, duplicate-free sets with identity-based membership and set operations.

[Source](lib_sets/lib_sets.metta); heads:

```text
set-difference set-disjoint set-insert set-intersection set-is set-member set-of
set-remove set-subset set-symmetric-difference set-union
```

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

[Source](lib_graph/lib_graph.metta); heads:

```text
graph-add-edges graph-add-vertices graph-closure graph-edges graph-is graph-is-acyclic
graph-neighbours graph-of graph-reachable graph-remove-edges graph-remove-vertices
graph-topological-order graph-transpose graph-union graph-vertices
```

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

[Source](lib_spaces/lib_spaces.metta); heads:

```text
find match-count migrateAtoms move-atoms remove-all-atoms space-copy space-drain
space-snapshot space-subtract succeedsPredicate
```

### lib_mm2

Provides add, remove, query and transformation notation over the MORK extension's space.

[Source](lib_mm2/lib_mm2.metta); heads:

```text
? ~> ＋ ＋* －
```

## Text and encoding

### lib_string

Provides text search, splitting, formatting, codepoint conversion and string similarity.

[Source](lib_string/lib_string.metta); heads:

```text
number-to-string parse-number string-center string-chars string-codes string-contains
string-count string-dedent string-edit-distance string-ends-with string-from-chars
string-from-codes string-indent string-index-of string-isub string-join
string-last-index-of string-length string-lines string-lower string-pad-left
string-pad-right string-repeat string-replace string-similarity string-slice
string-split string-split-exact string-starts-with string-template string-trim
string-unlines string-upper string-wrap
```

### lib_unicode

Provides Unicode normalization, case folding, grapheme segmentation and character properties.

[Source](lib_unicode/lib_unicode.metta); heads:

```text
unicode-casefold unicode-codepoint-valid unicode-graphemes unicode-is unicode-map
unicode-normalize unicode-property unicode-version
```

### lib_regex

Provides compiled PCRE2 patterns, matching, typed captures, scans and substitutions.

[Source](lib_regex/lib_regex.metta); heads:

```text
re-captures re-compile re-count re-escape re-find re-fullmatch re-match re-ranges
re-replace re-replace-all re-scan re-split regex_captures regex_find regex_match
regex_replace regex_replace_all regex_split
```

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

[Source](lib_parsing/lib_parsing.metta); heads:

```text
grammar-forms grammar-is grammar-parse grammar-parse-prefix grammar-parser
```

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

[Source](lib_json/lib_json.metta); heads:

```text
dict-space get-keys get-value json-at json-decode json-encode json-lines-decode
json-lines-encode json-lines-read! json-lines-write! json-pretty json-read! json-write!
```

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

[Source](lib_csv/lib_csv.metta); heads:

```text
csv-append! csv-encode csv-parse csv-read! csv-snapshot! csv-space csv-write!
```

### lib_yaml

Reads and writes single YAML documents using spaces for mappings and expressions for sequences.

[Source](lib_yaml/lib_yaml.metta); heads:

```text
yaml-decode yaml-encode yaml-read! yaml-write!
```

### lib_markup

Parses HTML and XML into element expressions and selects attributes, descendants and text.

[Source](lib_markup/lib_markup.metta); heads:

```text
markup-attribute markup-parse-html markup-parse-xml markup-select markup-text
markup-write
```

### lib_encoding

Converts text and byte expressions through UTF-8, hexadecimal and Base64.

[Source](lib_encoding/lib_encoding.metta); heads:

```text
base64-decode base64-encode hex-decode hex-encode utf8-decode utf8-encode
```

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

[Source](lib_uri/lib_uri.metta); heads:

```text
uri-build uri-contexts uri-decode uri-encode uri-normalize uri-parts uri-query-build
uri-query-parse uri-resolve
```

### lib_uuid

Constructs, validates and inspects UUIDs, including byte conversion and namespace-derived identifiers.

[Source](lib_uuid/lib_uuid.metta); heads:

```text
uuid-bytes uuid-is uuid-name uuid-namespaces uuid-nil uuid-of-bytes uuid-random!
uuid-time! uuid-timestamp uuid-variant uuid-version
```

## Numerics and probability

### lib_math

Provides exact rational arithmetic, integer roots, modular powers, factors and native real functions.

[Source](lib_math/lib_math.metta); heads:

```text
math-class math-factor-pairs math-float math-gcd math-integer-root math-lcm
math-power-mod math-ratio math-rational math-rationalize math-real math-real-functions
math-sqrt
```

### lib_vector

Provides numeric vector arithmetic, exact intermediate reductions, norms, distances and cosine similarity.

[Source](lib_vector/lib_vector.metta); heads:

```text
cosine cosine-of-normalized dot norm random-normal-vector vector-add vector-distance
vector-divide vector-fill vector-multiply vector-normalize vector-scale vector-subtract
```

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

[Source](lib_random/lib_random.metta); heads:

```text
random-bernoulli random-beta random-choice random-exponential random-gamma
random-lognormal random-normal random-pareto random-sample! random-shuffle!
random-triangular random-uniform random-weibull
```

### lib_measure

Normalizes, ranks, samples and combines weighted alternatives.

[Source](lib_measure/lib_measure.metta); heads:

```text
ws-best ws-choose ws-collapse ws-expect ws-filter ws-flip ws-merge-into ws-normalize
ws-peak ws-pickmax ws-ranked ws-sample! ws-sample-walk ws-softmax ws-take ws-top
ws-total
```

### lib_statistics

Computes sample statistics, finite probability laws and exact independent weighted-subset posteriors.

[Source](lib_statistics/lib_statistics.metta); heads:

```text
stats-correlation stats-covariance stats-geometric-mean stats-harmonic-mean stats-mean
stats-median stats-mode stats-quantile stats-quantiles stats-ranks stats-regression
stats-stdev stats-sum stats-variance weighted-subset-mass-independent
weighted-subset-posterior-independent ws-add-bernoulli-independent
ws-average-independent ws-central-moment ws-condition-joint ws-deviation ws-map
ws-map-independent ws-mass-at-least ws-mass-at-most ws-median ws-prob-gt-independent
ws-quantile ws-sum-independent ws-support ws-variance
```

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

[Source](lib_torch/lib_torch.metta); heads:

```text
torch-add torch-arange torch-backward torch-div torch-grad torch-item torch-matmul
torch-mean torch-mul torch-ones torch-randn torch-relu torch-requires-grad torch-shape
torch-sigmoid torch-sub torch-sum torch-tensor torch-tolist torch-zeros
```

## IO and system

### lib_file

Provides file and directory operations, paths, byte and text streams, and resource scopes.

[Source](lib_file/lib_file.metta); heads:

```text
append-bytes! append-file! copy-dir! copy-file! delete-dir! delete-file! delete-tree!
dir-exists dir-glob dir-walk exit! file-close! file-exists file-get-size! file-kind
file-lines! file-metadata! file-open! file-read-bytes! file-read-exact!
file-read-to-string! file-seek! file-space! file-write! file-write-bytes! list-dir!
make-dir! make-link! path-absolute path-extension path-join path-name path-normalize
path-parent path-parts path-relative path-resolve path-stem read-bytes! read-file!
read-link rename-file! replace-file! same-file stderr stderr! stdin stdin-to-string!
stdout temp-dir! temp-path! with-file with-temp-dir write-bytes! write-file!
```

### lib_datetime

Provides clocks, calendar records, parsing, formatting and arithmetic with explicit time zones.

[Source](lib_datetime/lib_datetime.metta); heads:

```text
date-add date-field date-fields date-timestamp date-weekday date-year-day day-of-week
day_of_week format-date format-datetime format_date leap-year month-days now parse-date
timestamp-date
```

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

[Source](lib_system/lib_system.metta); heads:

```text
change-directory! env-all env-get env-set! env-unset! platform-info platform-keys
working-directory
```

### lib_process

Starts programs with argument vectors and captures output, signals processes or waits for completion.

[Source](lib_process/lib_process.metta); heads:

```text
process-run! process-run-input! process-signal! process-signals process-start!
process-status process-wait!
```

### lib_cli

Parses typed command-line options, renders help and reads the process argument vector.

[Source](lib_cli/lib_cli.metta); heads:

```text
cli-arguments! cli-help cli-parse cli-types
```

### lib_logging

Emits structured log events with topic controls and optional MeTTa handlers.

[Source](lib_logging/lib_logging.metta); heads:

```text
log! log-enabled log-format log-levels log-to! log-topic! log-topics
```

### lib_compression

Compresses bytes and files with gzip or zlib and inspects, reads or extracts archives.

[Source](lib_compression/lib_compression.metta); heads:

```text
archive-entries! archive-extract! archive-read! compress-bytes compress-file!
compression-formats decompress-bytes decompress-file!
```

### lib_crypto

Provides hashes, HMACs, password records and cryptographic random values.

[Source](lib_crypto/lib_crypto.metta); heads:

```text
crypto-hash crypto-hash-bytes crypto-hash-file! crypto-hmac crypto-hmac-bytes
crypto-password-hash crypto-password-verify crypto-random-bytes crypto-random-hex
crypto-random-integer crypto_hash crypto_random_hex
```

### lib_http

Provides streaming HTTP clients and scoped HTTP servers with MeTTa request handlers.

[Source](lib_http/lib_http.metta); heads:

```text
http-header http-methods http-open! http-request! http-server-start! http-server-stop!
http-server-url with-http with-http-server
```

### lib_socket

Provides TCP listeners and connections, UDP datagrams and scoped socket ownership.

[Source](lib_socket/lib_socket.metta); heads:

```text
socket-endpoint socket-kind socket-shutdown! socket-wait! tcp-accept! tcp-connect!
tcp-listen! udp-bind! udp-receive! udp-send! with-socket
```

### lib_database

Persists atom syntax in journaled stores with explicit handles, synchronization and scoped cleanup.

[Source](lib_database/lib_database.metta); heads:

```text
database-add! database-atoms database-close! database-open! database-remove!
database-sync! with-database
```

### lib_redis

Attaches shared Redis-backed spaces with cross-process change notifications.

[Source](lib_redis/lib_redis.metta); heads:

```text
redis-attach redis-detach
```

## Reasoning and rewriting

### lib_constraints

Exposes rational CLP(Q) constraints and Boolean CLP(B) constraints, labeling and tautology checks.

[Source](lib_constraints/lib_constraints.metta); heads:

```text
clpb clpb-labeling clpb-taut clpq clpq-entailed
```

### lib_nars

Provides NARS truth functions, inference rules and bounded derivation and query operations.

[Source](lib_nars/lib_nars.metta); heads:

```text
BestCandidate ConfidenceRank LimitSize NARS.Config.BeliefQueueSize NARS.Config.MaxSteps
NARS.Config.TaskQueueSize NARS.Derive NARS.Query PriorityRank PriorityRankNeg
StampConcat StampDisjoint Truth_Abduction Truth_Analogy Truth_Comparison
Truth_DecomposeNNN Truth_DecomposeNPP Truth_DecomposePNN Truth_DecomposePNP
Truth_DecomposePPP Truth_Deduction Truth_Difference Truth_Eternalize
Truth_Exemplification Truth_Expectation Truth_Induction Truth_Intersection
Truth_Negation Truth_Resemblance Truth_Revision Truth_StructuralDeduction
Truth_StructuralDeductionNegated Truth_StructuralIntersection Truth_Union Truth_c2w
Truth_or Truth_w2c |-
```

### lib_pln

Provides legacy PLN truth formulas, inference rules and bounded derivation and query operations.

[Source](lib_pln/lib_pln.metta); heads:

```text
/safe BestCandidate ConfidenceRank Consistency_ImplicationImplicantConjunction ElementOf
InsertSorted InsertionSort LimitSize PLN.Config.BeliefQueueSize PLN.Config.MaxSteps
PLN.Config.TaskQueueSize PLN.Derive PLN.Query PriorityRank PriorityRankNeg STV
StampConcat StampDisjoint SyllogisticRuleGuard SymmetricModusPonensRuleGuard Test2
TransitiveSimilarityStrength Truth_Abduction Truth_Deduction Truth_Induction
Truth_ModusPonens Truth_Negation Truth_Revision Truth_SymmetricModusPonens Truth_c2w
Truth_equivalenceToImplication Truth_evaluationImplication Truth_inversion
Truth_transitiveSimilarity Truth_w2c TupleConcat TupleCount Unique Without and5 clamp
conditional-probability-consistency invert largest-intersection-probability min5 negate
simpleDeductionStrength smallest-intersection-probability |-
```

### lib_pln2

Provides Beta and moment formulas with explicit evidence scales and checked independent support sets.

[Source](lib_pln2/lib_pln2.metta); heads:

```text
pln2-beta-moments pln2-beta-update pln2-confidence-count pln2-count-confidence
pln2-moments-stv pln2-product-independent pln2-require-independent-supports
pln2-stv-moments pln2-total-probability-independent
```

### lib_soft

Scores structural similarity between terms and queries spaces for weighted matches.

[Source](lib_soft/lib_soft.metta); heads:

```text
soft-aggregation soft-best soft-fold soft-match soft-score soft-score-by soft-symbol?
soft-walk sym-sim
```

### lib_strategy

Composes term rewrites through choice, repetition, traversal and typed strategy application.

[Source](lib_strategy/lib_strategy.metta); heads:

```text
TP TU all alltd bottomup choice fail gtry innermost one seq stratego-all stratego-one
strategy-all strategy-all-tail strategy-apply strategy-choice-tail strategy-eval
strategy-one strategy-repeat strategy-typed-apply strategy-typed-tp strategy-typed-tu
topdown try ◁
```

## Engine services

### lib_builtin_types

Declares builtin types for engine reflection and optional typed dispatch on import.

[Source](lib_builtin_types/lib_builtin_types.metta); declared heads:

```text
!= #* #+ #- #// #< #= #=< #> #>= #\= #div #max #min #mod % * + - / < <= == > >=
DontEvalType Error Kwargs Predicate abs-math acos-math add-atom add-atoms add-reduct
add-reducts add-translator-rule! add-typing-rule! alpha-unique-atom and and-then append
argv asin-math assert assert-answers assert-includes-answers assertaPredicate
assertzPredicate atan-math atom-subst atom_chars atom_concat bind! call callPredicate
car-atom case catch cdr-atom ceil-math chain change-state! collapse cons cons-atom
context-space copy_term cos-math current-time cut decons decons-atom elapsed eval
eval-one evalc exclude-item exists_file exp exp-math filter-atom first floor-math
foldall foldl foldl-atom forall format-args format-time get-atoms get-metatype get-state
get-type git-import! hyperpose id if if-decons-expr implies import!
import_prolog_function include index-atom intersection-atom is-alpha-member is-expr
is-ground is-member is-space is-var isinf-math isnan-math last length let library
list_to_set log-math map-atom maplist match max max-atom member metta min min-atom msort
new-space new-state noeval nop not on-unwind once or or-else parse parse-command
pow-math println! prog1 progn py-atom py-call py-dict py-dot py-iter py-list py-tuple
quote random-float random-int read-form! readln! reduce register-token! remove-atom
remove-translator-rule! remove-typing-rule! repr repra require-extension!
retractPredicate reverse round-math sealed second-from-pair sin-math size-atom sleep
sort sort-atom sort-strings sqrt-math sread subtraction-atom super superpose switch
tan-math term_hash test test-no-answer timeout transaction translatePredicate trunc-math
union-atom unique-atom unregister-token! with-seed with_mutex xor |->
```

### lib_derived

Installs an equation and translator rule deriving `once` from `take`.

[Source](lib_derived/lib_derived.metta); heads:

```text
once
```

### lib_doc

Preserves the former documentation import as a no-op because documentation now belongs to the engine.

[Source](lib_doc/lib_doc.metta); heads: none.

### lib_import

Loads Prolog functions and exposes source import ownership, inspection and withdrawal.

[Source](lib_import/lib_import.metta); heads:

```text
consult_global import_prolog_functions_from_file import_prolog_functions_from_module
imports static-import! unimport! use-module! use_module_global
```

### lib_gitimport

Implements the engine's resident Git import operation and pinned dependency acquisition in Prolog.

[Source](lib_gitimport/lib_gitimport.pl); heads:

```text
git-import!
```

### lib_package

Interprets package declarations, prepares dependencies and registers Prolog backings through the resident package service.

[Source](lib_package/lib_package.metta) / [Prolog](lib_package/lib_package.pl); heads:

```text
get-property package-prolog setup!
```

### lib_memo

Controls explicit and automatic memoization, configuration, invalidation and statistics.

[Source](lib_memo/lib_memo.metta); heads:

```text
clear-memoize clear-memoize-stats config-memoize get-memoize-config get-memoize-stats
invalidate-memoize is-memoized memoize memoize-exact
```

### lib_tabling

Controls Prolog answer tables whose reuse can discard answer order and duplicates.

[Source](lib_tabling/lib_tabling.metta); heads:

```text
injectPrologCode metta_table_clear metta_table_clear_all metta_table_statistics
metta_tabled_decl metta_untabled_decl table-clear table-clear-all table-stats tabled
untabled
```

### lib_thread

Provides parallel collection operations, futures, channels, pools, timers, resource scopes and blocking space queries.

[Source](lib_thread/lib_thread.metta); heads:

```text
after await await-atom cancel capture channel channel-close channel-size channel_close
channel_new channel_recv channel_send channel_size channel_try_recv cpu-count cpu_count
drop-space every par-any par-filter par-forall par-map par-race par_any par_filter
par_forall par_map par_race peek-atom pool pool-destroy pool-stats pool_create
pool_destroy pool_stats pool_submit recv scope scope-defer scope_body scope_defer send
settled? space_await space_await_where space_drop space_take space_take_where spawn
submit take-atom thread-count thread_await thread_cancel thread_count thread_settled
thread_spawn timer_after timer_every try-recv with-lock with_lock
```

### lib_observe

Runs source while returning queryable trace, coverage and diagnostic events.

[Source](lib_observe/lib_observe.metta); heads:

```text
observe-source trace-source
```

### lib_reflect

Enumerates engine operations, arities and origins and inspects or substitutes literal terms.

[Source](lib_reflect/lib_reflect.metta); heads:

```text
arity-of atom-replace atom-variables builtins engine-arity engine-builtin
engine-extension-point engine-function engine-knows engine-origin engine-special-form
engine-surface-counts engine-user-function extension-points functions knows? origin-of
special-forms surface-counts surface-json user-functions
```

### lib_conformance

Checks a foreign space provider's declared capabilities, matching and exact pushdown claims.

[Source](lib_conformance/lib_conformance.metta); heads:

```text
check-space-provider metta_check_space_provider
```

### lib_testing

Reexports `lib_combinatorics` generators for property checks with core assertions, adding no new callable heads.

[Source](lib_testing/lib_testing.metta); reexported heads:

```text
binomial cartesian-power choose2 choose2l chooseK chooseKl factorial permutation-count
permutations range range-step subsets takeK tuples
```

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

[Source](lib_he/lib_he.metta); heads:

```text
add-reduct assertAlphaEqual assertAlphaEqualToResult assertEqual assertEqualToResult
evalc for-each-in-atom get-type-space if-equal if-equal2 if-error is-function
match-type-or match-types noreduce-eq return-on-error unify unquote
```

### lib_patrick

Provides function composition, reverse matching, a translated loop and indexed iteration.

[Source](lib_patrick/lib_patrick.metta); heads:

```text
@ compose for iterate
```

### lib_roman

Provides tracing, flat and nested maps and folds, predicate-based set operations and function combinators.

[Source](lib_roman/lib_roman.metta); heads:

```text
&&& &^& . .. .: /==\ /=\ /=a\ /?\ @ \= \=/ \== \==/ \=a \=a/ \? \?/ cns first flip
fold-flat fold-nested foldr-flat fst head init map-flat map-nested mylast rcons second
snd tail traceid tracem
```

### lib_zar

Provides predicate-style Prolog consultation, module loading and named function imports.

[Source](lib_zar/lib_zar.metta); heads:

```text
consult_file import_prolog_functions_from_file_pred
import_prolog_functions_from_module_pred use_module_file
```
