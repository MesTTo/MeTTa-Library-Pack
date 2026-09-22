; The manifest for lib_yaml: what it depends on, and where its
; source is. The library itself is lib.metta beside this file.

!(import! &self (library lib_json))
!(import! &self (library lib_file))

!(import! &self (library "lib_yaml/lib.metta"))
