; Purpose: expose text files, directories, lexical paths and standard streams.
; [tested: lib_file_surface; commit=WORKTREE]
;Files. The handle-based half is MeTTa HE's surface exactly, names, argument
;order and option letters, because HE already specified it.
;
;(file-open! $path $options) answers a handle. The options are HE's letters:
;r read, w write, c create if absent, a append, t truncate. 'c' demands 'w'
;or 'a', so "rc" is refused loudly rather than quietly opening for reading.
;(file-read-to-string! $h) reads from the cursor to the end,
;(file-read-exact! $h $n) reads at most $n characters, (file-write! $h $text)
;writes, (file-seek! $h $pos) moves the cursor, and (file-get-size! $h) gives
;the size of the file rather than of what is left.
;
;(file-close! $h) is NOT in HE's stdlib. A process that opens files and never
;closes them leaks descriptors until it dies, so it is here; closing twice is
;not an error, because a cleanup path should not have to check first.
;
;The rest are convenience, named so they cannot be mistaken for HE's:
;(read-file! $path), (write-file! $path $text), (append-file! $path $text),
;(file-lines! $path) as an expression of strings, (delete-file! $path) and
;(list-dir! $path).
;
;(file-space! $path) is the mettafied one: the file's lines become
;(line Number Text) atoms in a space, so the file is queryable with match
;rather than being one long string you then take apart.
;
;    (let $log (file-space! "app.log")
;      (match $log (line $n $text) ($n $text)))
;
;A missing file is an ERROR rather than a failure, so it can never be mistaken
;for an empty file.

!(import! &self (library lib_string))
!(import_prolog_functions_from_file (library lib_file.pl)
  (file-open! file-read-to-string! file-read-exact! file-write!
   file-seek! file-get-size! file-close!
   read-file! write-file! append-file! file-lines! file-space!
   delete-file! temp-path! list-dir! file-exists dir-exists
   make-dir! delete-dir! copy-file! file-metadata!
   path-join path-parent path-name path-extension
   stderr! stdin-to-string! exit!))

; make-dir! creates missing parents. delete-dir! removes an empty directory.
; copy-file! copies bytes to a destination filename, replacing an existing
; file only after the complete copy succeeds. A directory destination and
; copying a file onto itself are errors.
; file-metadata! creates a snapshot space with (kind file|directory),
; (modified UnixSeconds), and (size Bytes) for files.
; path operations are lexical and follow SWI's POSIX path conventions.
; stderr! writes exactly the supplied text. stdin-to-string! consumes stdin
; through EOF. Neither closes the process-owned standard stream.
; exit! terminates the ENTIRE PROCESS with status 0 through 255, including
; an embedding host. MeTTa catch does not turn exit into a local return.

(@doc make-dir! (@desc "Create a directory and missing parents; an existing directory succeeds") (@params ((@param "directory path"))) (@return "Bool"))
(@doc delete-dir! (@desc "Remove an empty directory; missing or nonempty directories raise") (@params ((@param "directory path"))) (@return "Bool"))
(@doc copy-file! (@desc "Copy bytes to a destination filename with staged replacement; copying onto the source raises") (@params ((@param "source file") (@param "destination filename"))) (@return "Bool"))
(@doc file-metadata! (@desc "Snapshot kind, modified Unix time and file size as queryable atoms in a new space") (@params ((@param "file or directory path"))) (@return "Space"))
(@doc path-join (@desc "Join lexical paths; an absolute second path replaces the first") (@params ((@param "directory") (@param "name"))) (@return "String"))
(@doc path-parent (@desc "Lexical parent directory; a bare filename has parent dot") (@params ((@param "path"))) (@return "String"))
(@doc path-name (@desc "Lexical final path component") (@params ((@param "path"))) (@return "String"))
(@doc path-extension (@desc "Text after the final dot in the filename, without the dot; empty when absent") (@params ((@param "path"))) (@return "String"))
(@doc stderr! (@desc "Write text to stderr and flush, without adding a newline") (@params ((@param "text"))) (@return "Bool"))
(@doc stdin-to-string! (@desc "Consume standard input through EOF as UTF-8 text") (@return "String"))
(@doc exit! (@desc "Terminate the entire process with integer status 0 through 255; not an application-level return") (@params ((@param "process status"))))

;(file-exists $path) and (dir-exists $path) answer True or False. They have no
;! because they change nothing.
(@doc temp-path!
      (@desc "A unique fresh path in the system temporary directory, created exclusively so concurrent runners cannot mint the same name; the caller owns the file")
      (@params ((@param "a name prefix for the path")))
      (@return "String"))
(@doc file-exists
      (@desc "True when a regular file exists at the path, False otherwise")
      (@params ((@param "the path")))
      (@return "Bool"))
(@doc dir-exists
      (@desc "True when a directory exists at the path, False otherwise")
      (@params ((@param "the path")))
      (@return "Bool"))
