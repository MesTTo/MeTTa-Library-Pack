; The manifest for lib_random: what it depends on, and where its
; source is. The library itself is lib.metta beside this file.

!(import! &self (library lib_math))
!(import! &self (library lib_functional))

!(import! &self (library "lib_random/lib.metta"))
