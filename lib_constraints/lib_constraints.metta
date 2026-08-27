;CLP(Q) over the rationals and CLP(B) over the booleans, the two constraint
;domains the engine does not carry itself. `#` is CLP(FD) and IS engine
;surface, because the engine's own duals read it; nothing in the engine reads
;these, so they live here and a program opts in.
;
;  !(import! &self (library lib_constraints))
;  !(let True (clpq (= (* 2 $x) 1)) (repr $x))    ; "1r2"
;  !(clpb-taut (+ $t (~ $t)))                     ; True
;
; Purpose: expose SWI's clpq and clpb as MeTTa operations.
; Decides: one entry point per solver rather than a prefixed operator family,
;   which is five names instead of about thirty. See lib_constraints.pl.
; Open Obligations:
;   To Do: None
;   Hacks: None
;   Future Enhancements: None

!(import! &self (library lib_import))
!(import_prolog_functions_from_file (library lib_constraints.pl)
  (clpq clpq-entailed clpb clpb-labeling clpb-taut))

;Atom on every constraint parameter, so it arrives UNEVALUATED. Without it
;`(clpq (= (* 2 $x) 1))` runs `(* 2 $x)` as ordinary arithmetic, which refuses
;two unknowns by name before the solver sees it, and a constraint over an
;unbound variable is the whole point of a constraint.
(: clpq (-> Atom Bool))
(: clpq-entailed (-> Atom Bool))
(: clpb (-> Atom Bool))
(: clpb-labeling (-> Atom Expression))
(: clpb-taut (-> Atom Bool))
