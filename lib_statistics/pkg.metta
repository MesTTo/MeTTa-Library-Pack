; The manifest for lib_statistics: what it depends on, and where its
; source is. The library itself is lib.metta beside this file.

!(import! &self (library lib_math))
!(import! &self (library lib_pairs))
!(import! &self (library lib_measure))

!(import! &self (library "lib_statistics/lib.metta"))
