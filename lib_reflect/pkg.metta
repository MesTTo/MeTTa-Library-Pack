; The manifest for lib_reflect: what it depends on, and where its
; source is. The library itself is lib.metta beside this file.

!(import! &self (library lib_import))
!(import! &self (library lib_json))
!(import! &self (library lib_pairs))
!(import! &self (library lib_strategy))

!(import! &self (library "lib_reflect/lib.metta"))
