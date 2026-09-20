; Purpose: document the default package interpreter and its explicit setup door.
; Guarantees: package policy is implemented by the adjacent Prolog library;
; required libraries may supply package-load to interpret their argument record.
; [tested: lib_package; commit=561cfeaa23b27fc84f86a9bcccf6ccf8b9d2e73f].
(= (package version) "1.0.0")

(@doc setup!
  (@desc "Prepare a package and its requirements explicitly. Reuse setup only while its performed rows and backing artifacts remain current; publish performed.metta and the transitive lock.metta under an OS directory lock.")
  (@params ((@param "Package path or (library Name)")))
  (@return "Bool"))

(@doc package-load
  (@desc "A required packaging library can define this equation to replace the default interpreter. Arguments are the canonical source path, home space and the source's own package rows. Requires have already loaded under the engine's ceiling and budget.")
  (@params ((@param "Canonical path") (@param "Home space") (@param "Package argument rows")))
  (@return "Any successful result"))

(@doc get-property
  (@desc "The two-argument package surface answers (get-property perform claims), package keys at a loaded home, and available alternative backing rows. The one-argument head reflection surface remains available.")
  (@params ((@param "perform, a home space, or a loaded package path") (@param "claims, available, or a package key")))
  (@return "One property value per answer"))
