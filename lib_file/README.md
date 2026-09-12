Files, directories, paths, links, traversal and scopes. Text and bytes read and
write whole or through handles, publication is one rename, a directory walk and
a glob answer one path per answer, and a scope releases its handle or temporary
directory on every exit. Import it with `!(import! &self (library lib_file))`.

```metta
!(import! &self (library lib_file))
!(replace-file! "report.txt" "one line\n")   ; publish by rename
!(write-bytes! "blob.bin" (0 1 255))         ; bytes are integers 0 to 255
!(collapse (dir-glob "src" "**/*.metta"))    ; every source below src
!(with-file "report.txt" "r" file-read-to-string!)  ; the handle closes after
```

A missing file is an error rather than a failure, so it can never be mistaken
for an empty file. Every refusal names the operation and its remedy:
`file-not-found`, `file-permission-denied`, `file-already-exists`,
`file-kind-mismatch`, `file-handle-kind`, `file-overlap`,
`file-name-not-a-path`, `standard-stream-not-closable` and
`file-operation-failed` for anything the host reports otherwise.

| Family | Heads |
|---|---|
| Whole-file text | `read-file!`, `write-file!`, `append-file!`, `replace-file!`, `file-lines!`, `file-space!` |
| Whole-file bytes | `read-bytes!`, `write-bytes!`, `append-bytes!` |
| Handles | `file-open!`, `file-close!`, `file-read-to-string!`, `file-read-exact!`, `file-write!`, `file-read-bytes!`, `file-write-bytes!`, `file-seek!`, `file-get-size!` |
| Scopes | `with-file`, `with-temp-dir` |
| Directories and trees | `make-dir!`, `delete-dir!`, `list-dir!`, `dir-walk`, `dir-glob`, `copy-dir!`, `delete-tree!` |
| Files and identity | `copy-file!`, `rename-file!`, `delete-file!`, `file-exists`, `dir-exists`, `file-kind`, `same-file`, `file-metadata!` |
| Links | `make-link!`, `read-link` |
| Paths | `path-join`, `path-parent`, `path-name`, `path-extension`, `path-stem`, `path-parts`, `path-normalize`, `path-absolute`, `path-relative`, `path-resolve` |
| Temporary names | `temp-path!`, `temp-dir!` |
| Process streams | `stdin`, `stdout`, `stderr`, `stderr!`, `stdin-to-string!`, `exit!` |

**Text and bytes are different doors.** A handle carries UTF-8 text unless
`file-open!`'s options include `b`, and then it carries bytes: the text
operations refuse a binary handle and the byte operations refuse a text one,
each by name. The host's stream type check is loose, so without that refusal a
text read would decode octets as characters. Bytes are an ordinary expression
of integers 0 to 255, validated before a destination is opened, so an invalid
byte cannot truncate a file.

**`write-file!` writes in place; `replace-file!` publishes.** The first
truncates the file the path names, which is what an open handle or a hard link
keeps seeing. The second writes a staging file beside the destination, closes
it, and renames it over the path, so a reader sees the old file or the complete
new one and a failed write, close or rename leaves the old one untouched.
`copy-file!` and `copy-dir!` publish the same way. Publication is atomic
VISIBILITY under the host's rename; it is not crash durability, and the staging
name is not proof against another process creating the destination first.

**`rename-file!` is the host's rename and never copies.** A file replaces an
existing file and a directory replaces an existing empty directory. A same-file
rename, a kind mismatch, a nonempty destination directory and a destination on
another filesystem all raise, so a rename that cannot be one is never quietly
turned into a copy and a delete.

**A walk and a glob report links and do not follow them.** `dir-walk` answers
every descendant, depth first, with each directory's names in codepoint order,
the same order `list-dir!` answers. A symbolic link is reported; it is entered
only under `(follow-links True)`, and then a link whose target is a directory
already on the current chain is reported and still not entered, so a cycle
cannot loop. `dir-glob` takes a relative pattern of `/`-separated components: a
literal component is joined without listing a directory, a component holding
`* ? [ ] { } \` lists one directory and filters it with the host's wildcard
grammar, and `**` matches zero or more directory levels. A wildcard skips names
beginning with a dot unless `(hidden True)` or the component itself begins with
one. Each path is answered once, however many `**` components could reach it.
Work is proportional to the entries examined and the pattern states kept alive,
not to the answers: a pattern with no matches can still scan.

**Four path operations, four contracts.** `path-normalize` is lexical and
resolves `..` without asking the filesystem, so it can change a path's meaning
across a link; `path-absolute` anchors a relative path at the working
directory; `path-relative` writes the way from one place to another; and
`path-resolve` replaces every link on the way with what it points to, keeping a
loop or a missing component as written. The four translate CPython 3.14.7's
`posixpath.normpath`, `abspath`, `relpath` and non-strict `realpath`
([823f0323ee](https://github.com/python/cpython/blob/823f0323ee6ec1402088b73bce1a38473cac36dc/Lib/posixpath.py)),
and the Python tests compare them against that module over generated paths.
`path-parts`, `path-stem`, `path-name`, `path-parent` and `path-extension` keep
the library's existing SWI conventions, so `.env` has extension `env` and an
empty stem.

**A scope takes a function.** `with-file` and `with-temp-dir` apply it to the
handle or directory they acquired and answer every result: the resource stays
open while alternatives remain and is released when the answers are exhausted,
when the caller stops after one, and when the body raises. The function is a
name, a lambda or a partial application, as `par-map` takes. A handle that
escapes a scope is closed, so it refuses by name rather than reading a closed
stream.

`file-kind` classifies without following the entry: `link` for a symbolic link,
dangling included, then `directory`, `file`, `other` for a FIFO, socket or
device, and `missing`. `file-exists` and `dir-exists` follow links, so a
dangling link is neither. `delete-tree!` unlinks a link root without touching
its target, and removes a directory with everything under it.

`temp-path!` and `temp-dir!` create exclusively, so two runners cannot mint the
same name; the prefix names the file or directory and may not contain a
separator, because the host pastes it into the path unchecked.

The [example](../../examples/ch08-data/08-03-the-shipped-libraries/19-file_lib.metta)
calls every head. Its [Python twin](../../extensions/python/examples/language-feature-examples/ch08-data/08-03-the-shipped-libraries/19-file_lib.py)
proves the same claims. `tests/prolog/suites/libraries/lib_file_surface.plt`
covers byte round trips of all 256 values, handle-kind refusals, staged
publication with an injected close failure, the rename shapes, tree copy with
links and refused special entries, traversal order and cycles, the glob
grammar, the CPython path goldens, kinds, links and the scope exits;
`extensions/python/tests/ch08_data/test_file_lib.py` compares the path
operations, the walk and the glob with `posixpath`, `os.walk`, `glob` and
`pathlib`.

Migration: `file-close!` now raises when the host reports a failed close, where
it used to answer True; closing an already-closed handle stays silent.
`list-dir!` answers names sorted by codepoint rather than in directory order.
`file-space!` allocates through `new-space`, so an empty file answers a
registered space. `temp-path!` refuses a prefix holding a separator, as
`temp-dir!` already did.
