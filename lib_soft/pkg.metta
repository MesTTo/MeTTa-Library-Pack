; The manifest for lib_soft: what it depends on, and where its
; source is. The library itself is lib.metta beside this file.

!(import! &self (library lib_import))

!(import! &self (library "lib_soft/lib.metta"))
