; Purpose: provide UUID's namespace relation and its shared field layout.
; Guarantees: the four RFC namespaces are literal values; the native layout
; supplies the same field widths to validation and formatting.
; [tested: lib_uuid:standard_names_agree_with_ossp, lib_uuid:generated_bytes_round_trip_every_position; commit=WORKTREE].

!(import_prolog_functions_from_file (library "lib_uuid/lib_uuid.pl") (uuid-layout))
(: uuid-layout (-> Expression))
(@doc uuid-layout
  (@desc "Hex digit widths shared by strict native validation and MeTTa formatting. Private UUID value.")
  (@params ()) (@return "Widths"))

(: uuid-namespace-table (-> Expression))
(= (uuid-namespace-table)
   (quote ((dns "6ba7b810-9dad-11d1-80b4-00c04fd430c8")
           (url "6ba7b811-9dad-11d1-80b4-00c04fd430c8")
           (oid "6ba7b812-9dad-11d1-80b4-00c04fd430c8")
           (x500 "6ba7b814-9dad-11d1-80b4-00c04fd430c8"))))
(@doc uuid-namespace-table
  (@desc "RFC namespace names and their UUID Strings as literal pairs. Listing and lookup share this relation. Private UUID recipe.")
  (@params ()) (@return "Namespaces"))
