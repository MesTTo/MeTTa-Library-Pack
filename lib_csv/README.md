# CSV text, files and spaces

Fields stay Strings. Leading zeroes, whitespace, duplicates, Unicode, NUL
and quoted CR, LF and CRLF remain data. Writers require String fields;
convert other values explicitly. A blank record has zero fields, while
`""` in CSV represents one empty field. Empty input has no records.

```metta
!(import! &self (library lib_csv))
!(csv-parse "id;value\n001;a\n001;a\n" (quote ((separator ";") (skip 1))))
; (("001" "a") ("001" "a"))
!(csv-encode (("001" "a,b") ("002" "9")))
; "001,\"a,b\"\r\n002,9\r\n"
```

| Head | Default call | Result |
|---|---|---|
| `csv-parse` | `(csv-parse Text)` | One expression containing all field lists. |
| `csv-encode` | `(csv-encode Rows)` | One String containing every record. |
| `csv-read!` | `(csv-read! Path)` | One field list per answer, in file order. |
| `csv-write!` | `(csv-write! Path Rows)` | Atomically replace the file and return `True`. |
| `csv-append!` | `(csv-append! Path Rows)` | Atomically append the rows and return `True`; create a missing file. |
| `csv-space` | `(csv-space Path)` | A live read-only space of `(row Field...)` atoms. |
| `csv-snapshot!` | `(csv-snapshot! Path)` | A fresh mutable space of `(row Number Field...)` atoms. |

Every head also accepts a final `Options` argument. Options are a proper
expression of unique `(Name Value)` pairs. Quote literal option data so an
option name is not evaluated as a function. For example,
`(csv-parse "a\"b,c\n" (quote ((quote ""))))` disables quoting. The parameter
evaluates, so an ordinary function may compute and return the options.

| Option | Default | Contract |
|---|---|---|
| `(separator String)` | `","` | One Unicode scalar other than CR or LF. |
| `(quote String)` | `"\""` | One scalar, distinct from the separator and CR/LF; `""` disables quoting. |
| `(newline String)` | `"\r\n"` | Output terminator: CRLF, LF or CR. Readers recognize all three. |
| `(width Value)` | `infer` | Infer the first record's width, accept any width with `any`, or require a nonnegative integer width. |
| `(skip Number)` | `0` | Skip this many logical records when reading; skipped records still establish and validate width. Writers retain all supplied rows. |

An embedded quote is doubled. With quoting disabled, encoding refuses fields
that require escaping, including a singleton empty field. Unknown, repeated,
malformed and unbound options raise errors. No header or type guessing occurs.
The grammar adapts SWI's CSV field and quoting rules; [VENDOR.md](support/VENDOR.md)
pins the source and records the changes.

Each stream or live query opens its own file and closes it on exhaustion,
early termination or cancellation. Only consumed records are validated.
Malformed quoting, invalid UTF-8 and width errors name the logical record.
Missing files, permissions and I/O failures retain distinct errors and remedies.
Live descriptors are values; a later query reads the file's later contents.

Snapshots read once. Their one-based record numbers include skipped headers.
Native spaces are unordered bags; sort on that number to reconstruct file
order across different row widths. A snapshot can be edited through the
ordinary space operations. Creation or filling failures release the new space;
a cleanup failure reports the original failure as well. A successfully returned
snapshot follows ordinary engine space ownership.

Writes stage beside the destination, validate fields and widths, close the
stage, then publish it with one rename. Append first validates the old file
and copies its bytes unchanged. A nonempty append adds a terminator after a
valid unterminated final record. An empty append keeps existing bytes unchanged.
Failures before publication preserve the destination. A staging-cleanup error
states whether publication already occurred.

Writers coordinate through an absolute-path mutex and an advisory lock on
`Path.metta-csv.lock`. The lock file remains because removing it can split
waiting writers between different lock files. The protocol covers callers
using the same path. It provides neither coordination with other writers nor
crash durability. Readers observe a complete old or new file.

Parsing takes time proportional to consumed bytes. Streaming auxiliary storage
holds the current record and read buffer. Text parsing retains its returned
rows; snapshots retain their stored atoms. Append takes time proportional to
old and new bytes, so append related rows in one batch. Run
`swipl --on-error=status -q -s tests/prolog/lib_csv_stream_bench.pl` from the
repository root to compare discarded answers, materialized answers and append
validation with matching counts and checksums.

In Python, `m.fn["csv-read!"](path)` completes the effect at the call boundary.
Use `with m.answers(S["csv-read!"](path)) as rows:` for demand-driven reads
and explicit cursor cleanup. Use `G(text)` for fields and
`S.quote(((S.separator, G(";")),))` for literal options.

The [shipped example](../../examples/ch08-data/08-03-the-shipped-libraries/17-csv_lib.metta)
calls every head at both arities. The [Python twin](../../extensions/python/examples/language-feature-examples/ch08-data/08-03-the-shipped-libraries/17-csv_lib.py)
checks the same claims. Native and Python tests additionally cover malformed
input, failure injection, concurrent writers and generated Unicode dialects.

Migration: blank records now have zero fields. The previous physical-line
reader represented them as one empty field and normalized embedded CRLF.
Quote an empty field in the file to represent a singleton empty String.
Use `(width any)` when records intentionally have different widths.
