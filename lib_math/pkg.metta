; The manifest for lib_math: what it depends on, and where its
; source is. The library itself is lib.metta beside this file.

!(import! &self (library lib_vector))
!(import! &self (library lib_combinatorics))

!(import! &self (library "lib_math/lib.metta"))
