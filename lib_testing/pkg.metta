; The manifest for lib_testing: what it depends on, and where its
; source is. The library itself is lib.metta beside this file.

!(import! &self (library lib_combinatorics))

!(import! &self (library "lib_testing/lib.metta"))
