; The manifest for lib_mm2. Every row is an equation on the reserved head
; `package`, so any implementation that can read atoms reads this file
; without evaluating it: the requirements are data, not an instruction that
; only one engine understands.
;
; A requirement naming a library resolves through the catalogs in force; one
; shaped like a path resolves beside this file. `lib.metta` is this library's
; own MeTTa source, and its `(= (package backing) ...)` rows name the host
; artifacts that supply the heads MeTTa does not define.

(= (package requires) "lib.metta")
