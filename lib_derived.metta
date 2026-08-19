; Purpose: the derived forms the engine keeps FUSED into its compiler, written
;   out as translator rules, so a program that wants the smaller instruction
;   set can have it and pay the difference knowingly.
;
;     !(import! &self (library lib_derived))
;
;   Every form here answers what the fused form answers. What differs is the
;   goals it compiles to, and each one is fused by default because that
;   difference was measured and went the compiler's way. KERNEL.md carries the
;   whole ledger, this file carries the forms it says are derived.
;
; Assumes: `add-translator-rule!` registers globally, for every space and for
;   the rest of the session, which is what makes this an import decision
;   rather than a per-call one. `remove-translator-rule!` undoes it.
; Guarantees: `once` under this rule answers what `once` answers, over the
;   whole examples corpus [measured 2026-08-19: 205 files, every answer group
;   identical].
; Fails when: the form is on a hot path. `once` here costs 2 inferences a call
;   more than the fused clause [measured 2026-08-19: 454,152 against 354,122
;   over a 50,000-call loop, +28%], because `(take 1 ...)` compiles to
;   metta_take/2 where the fused clause compiles to Prolog's own once/1.
; Decides: only the forms whose rule is COMPLETE ship here. `progn` and
;   `prog1` are variadic and a translator rule has a fixed arity, so a rule
;   for them would rewrite some calls and leave others to the compiler, which
;   is two compilations of one form rather than one. `test-no-answer` cannot
;   be written this way at all: its `(collapse ...)` spelling prunes `Empty`,
;   so `(test-no-answer (quote ()))` would pass where it must fail.
; Open Obligations:
;   To Do: None
;   Hacks: None
;   Future Enhancements: None

;`once` takes the first answer of a generator and stops, which is `(take 1 ...)`
;said with a number. The Atom parameter is what keeps the generator unrun
;until the expansion places it, and %Undefined% is what makes the quoted body
;translate rather than arrive as the quote itself.
(: once (-> Atom %Undefined%))
(= (once $expr) (quote (take 1 $expr)))
!(add-translator-rule! once)

(@doc once
  (@desc "The first answer of an expression, and no more. Derived here as (take 1 ...); the engine's own once is the same form fused into the compiler")
  (@params ((@param "The expression to take one answer of")))
  (@return "Its first answer"))
