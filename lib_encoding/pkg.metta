; The manifest for lib_encoding: what it depends on, and where its
; source is. The library itself is lib.metta beside this file.


!(import! &self (library lib_string))
!(import! &self (library lib_functional))

!(import! &self (library "lib_encoding/lib.metta"))
