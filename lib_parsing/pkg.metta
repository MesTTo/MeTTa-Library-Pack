; The manifest for lib_parsing: what it depends on, and where its
; source is. The library itself is lib.metta beside this file.

!(import! &self (library lib_pairs))
!(import! &self (library lib_string))

!(import! &self (library "lib_parsing/lib.metta"))
