; The manifest for lib_graph: what it depends on, and where its
; source is. The library itself is lib.metta beside this file.

!(import! &self (library lib_sets))
!(import! &self (library lib_pairs))

!(import! &self (library "lib_graph/lib.metta"))
