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
   delete-file! list-dir! file-exists dir-exists))

;(file-exists $path) and (dir-exists $path) answer True or False. They have no
;! because they change nothing.
(@doc file-exists
      (@desc "True when a regular file exists at the path, False otherwise")
      (@params ((@param "the path")))
      (@return "Bool"))
(@doc dir-exists
      (@desc "True when a directory exists at the path, False otherwise")
      (@params ((@param "the path")))
      (@return "Bool"))
