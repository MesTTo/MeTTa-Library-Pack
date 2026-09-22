; The manifest for lib_uuid: what it depends on, and where its
; source is. The library itself is lib.metta beside this file.


!(import! &self (library lib_encoding))
!(import! &self (library lib_crypto))
!(import! &self (library lib_pairs))

!(import! &self (library "lib_uuid/lib.metta"))
