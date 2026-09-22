; The manifest for lib_strategy: what it depends on, and where its
; source is. The library itself is lib.metta beside this file.

!(import! &self (library minimal_metta_lib))

!(import! &self (library "lib_strategy/lib.metta"))
