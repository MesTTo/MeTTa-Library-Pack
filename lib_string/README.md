String operations preserve Unicode codepoints and embedded NUL. The library
provides literal search, splitting, replacement, line layout, named templates
and two distinct similarity calculations. Import it with
`!(import! &self (library lib_string))`.

```metta
!(string-split-exact "::" "a::b::::c") ; ("a" "b" "" "c")
!(string-count "aaaaa" "aa" True)     ; 4 overlapping occurrences
!(string-wrap "one two three" 7)      ; "one two\nthree"
!(string-edit-distance "kitten" "sitting") ; 3
!(string-template "Hello {Name}!" (quote ((Name "Ada")))) ; "Hello Ada!"
```

Text inputs accept a String, Symbol or Number. Results containing text are
Strings; characters are one-character Strings and scalar codes are integers.
Indexes, slices and padding widths count codepoints. Combining sequences and
display widths remain distinct from codepoint counts. Unicode normalization
is explicit and does not happen during a text comparison.

| Operation | Boundary behavior |
|---|---|
| `string-slice` | Half-open interval. Negative endpoints clamp to zero; reversed or beyond-end intervals return empty text. |
| `string-split` | Every character in the separator set splits. Preserve empty fields; an empty set returns the whole input. |
| `string-split-exact` | The complete separator splits at nonoverlapping occurrences. Preserve empty fields and refuse an empty separator. |
| `string-index-of`, `string-last-index-of` | Return zero-based first/last positions or -1. Empty patterns return 0/input length. Last-index includes overlapping occurrences. |
| `string-count` | Nonoverlapping by default; a third Bool enables overlap. An empty pattern counts length+1 boundaries. |
| `string-replace` | Replace nonoverlapping occurrences. Preserve the existing identity behavior for an empty pattern. |
| `string-trim` | Strip ASCII space, tab, LF and CR at both ends. NUL remains data. |
| `string-repeat`, padding | Negative repeat counts give empty text. Padding never shortens; an empty filler leaves input unchanged. Repeat and truncate multicharacter fillers. |
| `string-center` | Split required padding between both sides, with the odd character on the right. Restart the filler on each side. |
| `string-from-chars` | Preserve the existing acceptance of arbitrary text items, including multicharacter Strings, Symbols and Numbers. |
| `string-from-codes` | Require a proper list of Unicode scalar integers, including 0 and excluding surrogates. |
| `parse-number` | Use host numeric syntax. Ordinary nonnumbers give no answer; unexpected exceptions propagate. |

Literal search, count, exact split and replacement share KMP traversal. After
text coercion, they take time linear in all supplied text plus returned output,
including the replacement argument even when it is unused. Search state
takes O(m) storage for m pattern codepoints beyond converted inputs. Returned
text or fields occupy their own output storage. Character-set membership uses
native hash sets.
Joining concatenates all pieces once. Repeat and padding take space
proportional to the requested output.

Line operations split only on LF and preserve CR as data. `string-lines`
omits one terminal empty component, and empty input gives an empty expression.
`string-unlines` appends LF to every supplied line. `string-dedent` removes
the shared literal space/tab prefix of nonblank lines and empties blank lines.
`string-indent` prefixes nonblank lines while preserving space/tab-only lines.
Both indentation operations preserve a terminal LF. Tabs are not expanded.

`string-wrap` uses a positive width and optional `left`, `right`, `center` or
`justify` alignment. It collapses ASCII space, tab, CR and LF between words.
Words longer than the width remain whole, so width is a wrapping target.
The last justified line aligns left. No terminal LF is added.

`string-template` uses SWI's `{Name}` and `{Name,Default}` grammar. Each binding
is a `(Name Value)` pair; names must be Prolog variable identifiers and unique.
The engine's console renderer handles values. A missing name without a default
raises; unrecognized brace syntax remains literal, including `{@Goal}`.
Quote a literal binding expression to preserve its values. Existing positional
formatting remains available through `format-args`.

`string-edit-distance` gives exact unit-cost Levenshtein distance through
RapidFuzz's bit-vector implementation. `string-similarity` returns
`1 - distance / max(lengths)` and gives two empty Strings a score of 1.
Neither operation normalizes text or uses a score cutoff.

`string-isub` uses SWI's ontology-label score. It repeatedly removes common
substrings, then combines matched proportions, unmatched proportions and a
prefix bonus. Its optional expression accepts unique pairs:

| Option | Default | Meaning |
|---|---|---|
| `(normalize Bool)` | `False` | Lowercase through the host and remove dot, underscore and ASCII space. |
| `(zero-to-one Bool)` | `False` | Map the usual [-1,1] score to [0,1]. |
| `(substring-threshold Number)` | `2` | Count only common substrings longer than this nonnegative integer. Use 0 for short labels. |

Both empty inputs score 1; one empty input scores 0 under either range option.
The threshold can exclude an entire short identical label, so ISub identity
scores depend on the chosen threshold. Normalization here is label cleanup,
not Unicode normalization. Invalid or repeated options raise.

The [provider record](vendor/VENDOR.md) pins RapidFuzz, Boost KMP and the SWI
adaptations and includes their licenses. The String object builds at first
import with SWI development tools and a C++11 compiler; source distributions
and wheels carry all inputs. Missing dependencies raise `string_native_build`
with install and prebuild instructions. Every declared vendor header and the
manifest participate in cache invalidation, including missing files. Temporary
native buffers are call-owned. Owned loops deliver pending signals while
walking; RapidFuzz delivers them after its synchronous calculation returns.

The [example](../../examples/ch08-data/08-03-the-shipped-libraries/18-string_lib.metta)
calls all 34 heads and all 37 typed arities. Its
[Python twin](../../extensions/python/examples/language-feature-examples/ch08-data/08-03-the-shipped-libraries/18-string_lib.py)
checks the same claims through values and function calls. Generated tests cover
Unicode, NUL, edit-distance goldens and line transformations. Native tests
compare SWI layout and ISub results and exercise refusals and cancellation.

Migration: splitting, trimming, wrapping, lines and ISub preserve embedded NUL
instead of treating it as a terminator or implicit separator. `parse-number`
continues to fail on ordinary nonnumbers and now propagates other exceptions.
