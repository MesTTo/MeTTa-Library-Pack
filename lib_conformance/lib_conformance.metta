;Prove a foreign space provider before its users find out.
;
;`metta.testing.check_space_provider` takes a Python OBJECT, and a Prolog
;provider is a set of multifile clauses with no object to pass. So the
;conformance kit covered the seam's convenient tier and not the one
;EXTENDING.md recommends for speed, which is the tier whose authors are, by
;construction, the ones optimising rather than following the default path.
;
;The checks are the same ones, asked of a space NAME:
;
;  (check-space-provider &mine)
;
;answers the checks it ran, one per line, and RAISES on the first violation
;naming the space and the atom. Three things are checked. Every capability the
;space declares has a hook with clauses behind it. Match over-approximates
;rather than under-approximates, which is the seam's central soundness claim,
;tested by matching every atom the provider holds against itself. And an
;`exact` pushdown claim is true, which is the one claim that costs answers.

!(import! &self (library lib_import))
!(import_prolog_functions_from_file (library lib_conformance.pl)
  (metta_check_space_provider))

;(check-space-provider &mine) answers the checks that ran.
(: check-space-provider (-> Atom Expression))
(= (check-space-provider $space) (metta_check_space_provider $space))
