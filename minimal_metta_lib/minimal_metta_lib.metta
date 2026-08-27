; Purpose: minimal MeTTa's instruction set. The half that is expressible in
; MeTTa is written here; the half that is not is `minimal_metta_lib.pl`, which
; this file imports.
;
;     !(import! &self (library minimal_metta_lib))
;
; The four operations below used to be Python, which cost the janus crossing
; on every evaluation step and meant a program run through run.sh or the
; packaged CLI could not do inference control at all, there being no Python in
; that loop. `minimal_metta_lib.py` is now a thin loader kept for callers that
; already import it.
;
; Assumes: the engine prelude registers `function`, `collapse-bind` and
;   `superpose-bind`; this file registers `unify-mod` from
;   minimal_metta_lib.pl. `return` deliberately is NOT registered, so that
;   (return x) survives evaluation as data.
; Guarantees: the specification's own example programs run unchanged, except
;   for the renames the Open Obligations below record.
; Decides: the `mm-` prefix, and it is a collision decision rather than a
;   reservation one. This library loads with `import!` into `&self`, the space
;   every program shares, so `read`, `move`, `switch` and `subst` would land on
;   top of a user's own names. That is why the prefix stays.
; Open Obligations:
;   To Do: None
;   Hacks: None
;   Future Enhancements:
;     - `reduce` alone is prefixed for a second reason: it is a MeTTa builtin.
;       The raw `assertz/2: No permission to modify static procedure` that used
;       to greet a redefinition is gone; it now names the builtin, its arity,
;       the space and the way round: define it in a NAMED space and it shadows
;       the builtin there while &self keeps the original
;       [tested: spaces_builtin_override]. So a minimal-MeTTa program that runs
;       in its own space can already write `reduce`. Dropping the prefix HERE
;       would break every `import! &self` caller, which is why it stays.

!(import! &self (library lib_import))
!(import_prolog_functions_from_file (library minimal_metta_lib.pl)
  (unify-mod))

; Atom on a parameter means it reaches the operation UNEVALUATED, which is what
; every instruction here needs: `function` walks its body, and unify-mod
; matches a pattern and chooses a branch without either being reduced first.
;
; superpose-bind is the exception and has an Expression parameter in the
; prelude. Its argument is the result of a collapse-bind call and must arrive
; evaluated; declaring it Atom hands over the literal expression
; (collapse-bind ...) and the loop yields its head symbols.
(: unify-mod (-> Atom Atom Atom Atom %Undefined%))

; ---------------------------------------------------------------------------
; Partial functions.  The specification: "Each instruction in a minimal
; instruction set is a total function. Nevertheless Empty allows defining
; partial functions in MeTTa."
; ---------------------------------------------------------------------------

(= (if-partial $condition $then)
   (unify-mod $condition True $then Empty))

; ---------------------------------------------------------------------------
; The specification's recursive `switch`, written in the minimal instruction
; set.  This is the specification's own code and is the reason the library
; exists: if `function`, `return`, `chain` and `unify` are right, this runs.
; ---------------------------------------------------------------------------

(= (mm-switch $atom $cases)
   (function
     (chain (decons-atom $cases) $list
       (chain (eval (mm-switch-internal $atom $list)) $res
         (unify-mod $res NotReducible (return Empty) (return $res))))))

; The exhausted case list is answered here rather than by a second mm-switch
; equation. The specification says every instruction in the minimal set is a
; total function, and without this one is not: (decons-atom ()) has NO answer,
; so a switch whose cases all failed to match failed outright, `function`
; turned that into (Error ... NoReturn), and the (return Empty) arm above could
; never be reached. Answering NotReducible is what that arm is waiting for.
;
; A second equation (= (mm-switch $atom ()) NotReducible) also reaches the arm,
; but the general equation still matches () and still answers its error, so the
; switch would carry a spurious second answer. Stopping before the recursion
; leaves exactly one.
(= (mm-switch-internal $atom (($pattern $template) $tail))
   (function
     (unify-mod $atom $pattern
       (return $template)
       (unify-mod $tail (:= ())
         (return NotReducible)
         (chain (eval (mm-switch $atom $tail)) $ret (return $ret))))))

; ---------------------------------------------------------------------------
; The specification's evaluation loop: evaluate an atom until it stops
; reducing, then substitute.  `subst` is total; `mm-reduce` drives the loop.
; ---------------------------------------------------------------------------

(= (mm-subst $atom $var $templ)
   (unify-mod $atom $var $templ
     (Error (mm-subst $atom $var $templ)
            "subst expects a variable as a second argument")))

; The specification stops the loop when eval answers NotReducible, which
; assumes eval takes ONE step. MeTTa's eval evaluates to completion, so it
; never answers NotReducible: (eval (step-down 3)) is `done`, not a step
; towards it. Written the specification's way the loop reduced `done` to
; `done` forever. The old Python implementation hit a Python recursion error
; there; this one exhausted the Prolog stack, which is worse.
;
; So the test is "did anything change", written with the := equality modifier
; this library already provides rather than with a new instruction: (:= $atom)
; matches $res only when it is identical to what went in, which on a
; full-evaluation engine is exactly what "stopped reducing" means. The
; NotReducible arm stays ahead of it, because an engine that does answer
; NotReducible should still be believed.
(= (mm-reduce $atom $var $templ)
   (chain (eval $atom) $res
     (unify-mod $res Empty
       Empty
       (unify-mod $res (Error $a $m)
         (Error $a $m)
         (unify-mod $res NotReducible
           (eval (mm-subst $atom $var $templ))
           (unify-mod $res (:= $atom)
             (eval (mm-subst $atom $var $templ))
             (eval (mm-reduce $res $var $templ))))))))

; ---------------------------------------------------------------------------
; The specification's Turing machine, its own Turing-completeness witness.
; Names are prefixed because `read` and `move` are ordinary enough to collide
; with a user's program, not because MeTTa reserves them.
; ---------------------------------------------------------------------------

(= (mm-tm $rule $state $tape)
   (function (eval (mm-tm-body $rule $state $tape))))

(= (mm-tm-body $rule $state $tape)
   (unify-mod $state HALT
     (return $tape)
     (chain (eval (mm-read $tape)) $char
       (chain (eval ($rule $state $char)) $res
         (unify-mod $res ($next-state $next-char $dir)
           (chain (eval (mm-move $tape $next-char $dir)) $next-tape
             (eval (mm-tm-body $rule $next-state $next-tape)))
           (return (Error (mm-tm-body $rule $state $tape)
                          "Incorrect state")))))))

(= (mm-read ($head $hole $tail)) $hole)

(= (mm-move ($head $hole $tail) $char N) ($head $char $tail))

; The tape is ($head $hole $tail): the cells to the left in reverse, the cell
; under the machine, and the cells to the right. Moving right writes $char, so
; it joins $head, and the new hole comes off $tail. Moving left is the mirror.
;
; These two clauses had their BODIES SWAPPED. The clause marked L pushed onto
; $head and read from $tail, which is a move right, and R did the reverse. A
; machine driven by them walked the wrong way on every step.
;
; Running off the end of the tape reads a blank, and the else arm of each
; unify-mod below is what supplies it. Those arms were unreachable:
; (decons-atom ()) has NO answer, so the chain FAILED before any branch could
; be chosen and the machine never took its first step at all. Testing the side
; for empty before deconsing it is the same repair mm-switch-internal needed,
; and for the same reason.
(= (mm-move ($head $hole $tail) $char R)
   (function
     (chain (cons-atom $char $head) $next-head
       (unify-mod $tail (:= ())
         (return ($next-head 0 ()))
         (chain (decons-atom $tail) $list
           (unify-mod $list ($next-hole $next-tail)
             (return ($next-head $next-hole $next-tail))
             (return ($next-head 0 ()))))))))

(= (mm-move ($head $hole $tail) $char L)
   (function
     (chain (cons-atom $char $tail) $next-tail
       (unify-mod $head (:= ())
         (return (() 0 $next-tail))
         (chain (decons-atom $head) $list
           (unify-mod $list ($next-hole $next-head)
             (return ($next-head $next-hole $next-tail))
             (return (() 0 $next-tail))))))))
