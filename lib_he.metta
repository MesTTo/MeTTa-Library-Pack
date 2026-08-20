; %%%% Hyperon-Experimental compatibility library. %%%%
;
; Everything this library once defined is part of the core engine now,
; loaded from engine/prelude.metta at startup, so a program reaches every
; form below with no import at all. Importing this file remains a no-op
; so existing programs keep working unchanged.
;
; The promotions, in the order they happened:
;
; unify is an engine special form, for the reason recorded when it moved:
; bindings flow from the match into the selected branch, numbers compare
; promoted, a space operand queries through every context kind, and
; grounded values with their own matching logic are consulted, per the
; arbiter's matcher. The shim here could do none of that.
;
; add-reduct is an engine builtin, along with add-atoms and add-reducts,
; because all three are standard library operations rather than
; compatibility shims and a program should not have to import anything to
; reach them. The shim that used to sit here also had the wrong contract:
; it destructured its argument as an equation and reduced only the body,
; where the standard library says "Reduces atom (second argument) and
; adds it into the [space]", so `(add-reduct &self (+ 1000 1))` has to
; add 1001 and this added the call.
;
; evalc is an engine builtin, and it takes any space rather than only the
; literal &self this shim matched.
;
; Everything else moved to engine/prelude.metta on 2026-08-18, by the same
; rule the earlier promotions state: standard vocabulary, not shims.
; Each name registers as a builtin: reachable from every space,
; shadowable per named space by an equation there, stored as an atom in
; no space at all. The promoted forms: if-equal, if-equal2, assertEqual,
; assertAlphaEqual, assertEqualToResult, assertAlphaEqualToResult,
; assertIncludes, assertEqualMsg, assertAlphaEqualMsg,
; assertEqualToResultMsg, assertAlphaEqualToResultMsg, if-error,
; return-on-error, for-each-in-atom, unquote, noreduce-eq, is-function,
; match-types, match-type-or, type-cast, type-cast-holds.
;
; Several promotions FIX this file's contracts against the mechanised
; arbiter (LeaTTa MettaHyperonFull/Minimal/Stdlib.lean, measured against
; pinned Hyperon 0.2.10), the way add-reduct's promotion fixed its:
; if-equal compares by alpha-equivalence, not ==; assertEqual and
; assertAlphaEqual take Atom parameters and compare result sets, as
; their Msg twins always did; match-types is unification with
; %Undefined%/Atom wildcards, not equality; match-type-or takes
; (folded next type) in upstream's order;
; type-cast is undeclared on purpose so an ill-typed subject reports its
; own error, and its helper type-cast-check is subsumed by
; match-type-or. get-type-space is a native engine builtin now and takes
; ANY space, where the stub here matched the literal &self only.
