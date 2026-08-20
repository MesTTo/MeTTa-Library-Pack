; Purpose: declare the type surface of PeTTa's shipped builtins for engine
; reflection and optional live typed dispatch.
; Guarantees:
;   - reader-token registration takes a regex string and readable constructor
;     symbol, while removal takes the same regex string [tested:
;     test_a_registered_token_class_parses_like_a_shipped_one;
;     commit=2c741dda928a30d0ce1c7e1fcf0b263b4d1bb97b].
; Open Obligations:
;   To Do: None
;   Hacks: None
;   Future Enhancements: None

; %%%% Type definitions of MeTTa built-in operators. %%%%

;; Type definitions of arithmetic operators
(: + (-> Number Number Number))
(: - (-> Number Number Number))
(: * (-> Number Number Number))
(: / (-> Number Number Number))
(: % (-> Number Number Number))

;; Type definitions of ordered comparison operators
(: < (-> Number Number Bool))
(: <= (-> Number Number Bool))
(: > (-> Number Number Bool))
(: >= (-> Number Number Bool))

;; Type definitions of equality and negated equality operators
(: == (-> $a $a Bool))
(: != (-> $a $a Bool))

;; Type definitions of common mathematical functions
(: pow-math (-> Number Number Number))
(: sqrt-math (-> Number Number))
(: abs-math (-> Number Number))
(: log-math (-> Number Number Number))
(: trunc-math (-> Number Number))
(: ceil-math (-> Number Number))
(: floor-math (-> Number Number))
(: round-math (-> Number Number))
(: sin-math (-> Number Number))
(: asin-math (-> Number Number))
(: cos-math (-> Number Number))
(: acos-math (-> Number Number))
(: tan-math (-> Number Number))
(: atan-math (-> Number Number))
(: min-atom (-> $a Number))
(: max-atom (-> $a Number))
(: min (-> Number Number Number))
(: max (-> Number Number Number))
(: exp (-> Number Number))

;; Type definitions of isnan and isinf predicates
(: isnan-math (-> Number Bool))
(: isinf-math (-> Number Bool))

;; Type definitions of boolean operators
(: and (-> Bool Bool Bool))
(: or (-> Bool Bool Bool))
(: not (-> Bool Bool))
(: xor (-> Bool Bool Bool))

;; Type definitions of time control.
;; timeout and elapsed take their expression as Atom so it is NOT evaluated
;; before they see it. Without that the work would already be finished by the
;; time the bound was applied, or by the time the clock started.
(: sleep (-> Number Bool))
(: timeout (-> Number Atom %Undefined%))
(: elapsed (-> Atom %Undefined%))

;; pragma! is UNDECLARED, and the absence is the answer: the official corelib
;; block for it reads `Type %Undefined%`, which is the gradual default rather
;; than a type, so `!(get-type pragma!)` answers `%Undefined%` on both engines
;; even when the program has written `(: pragma! Number)` into the space
;; [source: LeaTTa wiki/Hyperon-Divergences.md, the grounded-operation-type
;; row, measured 2026-08-16; tests/semantics/types-basic/
;; 20-undefined-stdlib-operation.metta, STATUS conforms]. It answers the UNIT
;; value, for the reason add-atom does.

;; HE's metta/3: interpret an atom in a named space. The Type argument is
;; accepted and ignored, as HE does for %Undefined%.
(: metta (-> Atom Type SpaceType Atom))

;; ===========================================================================
;; The rest of the engine's surface: 117 names that answered %Undefined%.
;;
;; The types come from the reference corelib dump wherever it has one, because
;; a type PeTTa does not already have is additive and the reference governs
;; there [source: LeaTTa stdlib.md, 146 typed entries; 39 of
;; these names are in it]. One vocabulary translation was needed: HE's unit
;; result `(->)` is PeTTa's `Bool`, because every one of these answers `true`.
;; `SpaceType` is written as itself, because a space handle answers `Grounded`
;; here as it does there and carries that type
;; [tested: spaces:space_handle_type]. It was written `Symbol` until
;; 2026-08-20, when `(get-metatype &self)` still answered `Symbol` here, and
;; the two disagreed the moment the handle gained its own type: every one of
;; these declarations then REFUSED a space handle as a first argument.
;; Divergences from the dump are marked where they occur.
;;
;; THIS FILE HAS TWO ROLES AND THEY DIFFER. The engine reads it at boot into
;; `builtin_type_declaration/2`, which `get_type_candidate/2` consults LAST, so
;; the declarations answer `get-type` and change no call site: the engine's own
;; type surface, reported without being enforced twice. A program that also
;; writes `!(import! &self (library lib_builtin_types))` puts the same
;; declarations into `&self`, where `type_declaration/2` DOES see them and they
;; become live typed dispatch. Both are wanted; only the second costs anything.
;;
;; Two of the three groups below could not go live even then, which is worth
;; knowing when reading them.
;;
;; A SPECIAL FORM is compiled by the translator and never reaches typed
;; dispatch at all. Proven rather than assumed: `(= (f $n) (if (> $n 1) yes no))`
;; compiles to a byte-identical clause with and without `(: if ...)` present
;; [measured 2026-08-16].
;;
;; A RUNTIME-GUARDED builtin enforces its own input contract inside its own
;; predicate, so dispatch is skipped for it too. `runtime_type_guarded/1` in
;; engine/metta.pl is the list.
;;
;; The rest WOULD become checks on import, so a parameter there carries a
;; concrete type only where the implementation was read and it is certain, and
;; `%Undefined%` everywhere else, which the translator skips entirely.
;; `%Undefined%` in a parameter is not a gap in the declaration; it is the
;; accurate statement that the predicate accepts anything there, and the arrow
;; still tells a reader and a tool the arity.
;; ===========================================================================

;; --- Special forms: control ---
;; Compiled by the translator. Nothing here reaches typed dispatch.
(: if (-> Bool Atom Atom $t))
(: case (-> Atom Expression %Undefined%))
(: let (-> Atom %Undefined% Atom %Undefined%))
(: chain (-> Atom Variable Atom %Undefined%))
(: quote (-> Atom Atom))
(: sealed (-> Expression Atom Atom))
(: catch (-> Atom %Undefined%))
(: once (-> Atom %Undefined%))
(: cut (-> Bool))
(: and-then (-> Atom Atom %Undefined%))
(: or-else (-> Atom Atom %Undefined%))
(: progn (-> Atom %Undefined%))
(: prog1 (-> Atom %Undefined%))
(: forall (-> Atom Atom Bool))
(: foldall (-> Atom Atom %Undefined% %Undefined%))

;; --- Special forms: evaluation and nondeterminism ---
(: eval (-> Atom Atom))
(: evalc (-> Atom SpaceType Atom))
;; The argument is a CALL and it arrives unevaluated, because which function is
;; being delegated to has to be known before the call runs: the module holding
;; it is resolved when the equation compiles.
(: super (-> Atom %Undefined%))
(: reduce (-> Atom %Undefined%))
(: collapse (-> Atom Atom))
(: superpose (-> Expression %Undefined%))
(: hyperpose (-> Expression %Undefined%))
(: |-> (-> Expression Atom %Undefined%))

;; --- Special forms: spaces ---
;These five answer the UNIT value, `(->)`, which is the type the standard
;library gives them and which the engine now returns. They were declared Bool
;here because the implementation answered `true`; that read the type off the
;implementation instead of correcting the implementation to the type.
;
;The second parameter is `Atom` in every one of them, so the argument arrives
;UNREDUCED. That is load-bearing for the reducing three: `add-reduct` reduces
;the atom itself, and a caller that reduced it first would hand it a value
;`reduce/3` has nothing left to do with.
(: add-atom (-> SpaceType Atom (->)))
(: remove-atom (-> SpaceType Atom (->)))
(: add-atoms (-> SpaceType Atom (->)))
(: add-reduct (-> SpaceType Atom (->)))
(: add-reducts (-> SpaceType Atom (->)))
(: match (-> SpaceType Atom Atom %Undefined%))

;; --- Special forms: collections ---
(: map-atom (-> Expression Variable Atom Expression))
(: filter-atom (-> Expression Variable Atom Expression))
(: foldl-atom (-> Expression Atom Variable Variable Atom %Undefined%))

;; --- Special forms: transactions and threads ---
(: transaction (-> Atom %Undefined%))
(: with_mutex (-> Symbol Atom %Undefined%))

;; --- Special forms: the Prolog seams ---
;; Both take the goal as written, which is what makes them seams at all.
(: translatePredicate (-> Atom %Undefined%))
(: call (-> Atom %Undefined%))

;; --- Special forms: assertions ---
(: test (-> Atom Atom Bool))
(: test-no-answer (-> Atom Bool))

;; --- Runtime-guarded: the CLP(FD) family ---
;; `#` operators post constraints rather than computing, so an argument may be
;; an unbound domain variable. Number is still right: clpfd constrains
;; integers, and each predicate refuses anything else itself.
(: #+ (-> Number Number Number))
(: #- (-> Number Number Number))
(: #* (-> Number Number Number))
(: #div (-> Number Number Number))
(: #mod (-> Number Number Number))
(: #min (-> Number Number Number))
(: #max (-> Number Number Number))
(: #< (-> Number Number Bool))
(: #> (-> Number Number Bool))

;; --- Runtime-guarded: the rest ---
(: exp-math (-> Number Number))
(: implies (-> Bool Bool Bool))
(: random-int (-> Number Number Number))
(: random-float (-> Number Number Number))

;; --- Checked on import: expression structure ---
;; car-atom's result is %Undefined% in the dump and stays so: the head of an
;; expression is whatever that expression holds.
(: car-atom (-> Expression %Undefined%))
(: cdr-atom (-> Expression Expression))
(: cons-atom (-> Atom Expression Atom))
(: decons-atom (-> Expression Atom))
(: size-atom (-> Expression Number))
(: index-atom (-> Expression Number Atom))
;; PeTTa's own, no dump entry. cons/decons are the un-suffixed spellings and
;; first/second-from-pair read a two-element expression.
(: cons (-> Atom Expression Expression))
(: decons (-> Expression Expression))
(: first (-> Expression Atom))
;; first-from-pair is UNDECLARED, with empty, nop, pragma!, type-cast,
;; match-types and match-type-or: each official corelib block reads
;; `Type %Undefined%`, which is the gradual default rather than a type, so
;; get-type answers %Undefined% and a wrong-arity call stays unreduced instead
;; of being refused by an arity the declaration invented
;; [source: LeaTTa wiki/Hyperon-Divergences.md, the undeclared-helpers row,
;; measured 2026-08-15; tests/semantics/types-basic/
;; 61-undeclared-type-helpers-surface.metta and eval-core/
;; empty-argument-arity.metta].
(: second-from-pair (-> Expression Atom))

;; --- Checked on import: set and list operations ---
(: union-atom (-> Expression Expression Atom))
(: intersection-atom (-> Expression Expression Atom))
(: subtraction-atom (-> Expression Expression Atom))
(: unique-atom (-> Expression Atom))
(: alpha-unique-atom (-> Expression Atom))
(: sort-atom (-> Expression Expression))
;; The corelib's own two, whose blocks read `(-> String Expression String)` and
;; `(-> Expression Expression)`. Both are load-bearing: they are what turns
;; `(format-args n ())` into `(BadArgType 1 String Number)` and
;; `(sort-strings s)` into `(BadArgType 1 Expression String)`, where an
;; argument the type does not decide earns the operation's own words instead
;; [source: LeaTTa MettaHyperonFull/Minimal/Stdlib.lean, the corelib blocks;
;; tests/semantics/grounded/07-partial-core.metta].
(: format-args (-> String Expression String))
(: sort-strings (-> Expression Expression))
(: exclude-item (-> Atom Expression Expression))
(: is-member (-> Atom Expression Bool))
(: is-alpha-member (-> Atom Expression Bool))

;; --- Checked on import: the metatype predicates ---
;; Each takes anything and answers a Bool, which is the whole point of them.
(: is-var (-> Atom Bool))
(: is-ground (-> Atom Bool))
(: is-expr (-> Atom Bool))
(: is-space (-> Atom Bool))
(: get-metatype (-> Atom Atom))
;; An error term carries the expression that caused it, so both arguments are
;; masked: (Error (+ 1 2) (+ 1 +)) has to hold the malformed term rather than
;; evaluate it, which is the one thing an error channel exists for
;; [source: metta-lang-docs, types_basics/metatypes].
(: Error (-> Atom Atom ErrorType))
;; noeval is the Atom mask twice over: the argument is not reduced going in and
;; the Atom return type stops the result being reduced coming out. That is how
;; the reference implements it, and it is the whole definition.
(: noeval (-> Atom Atom))
(: get-type (-> Atom %Undefined%))
(: =alpha (-> Atom Atom Bool))
(: id (-> $t $t))

;; --- Checked on import: spaces and state ---
(: get-atoms (-> SpaceType Atom))
(: bind! (-> Symbol %Undefined% Bool))
(: register-token! (-> String Symbol Bool))
(: unregister-token! (-> String Bool))
(: context-space (-> SpaceType))
(: import! (-> Atom Atom (->)))
;; include pastes a module's source into the space that included it and
;; answers its LAST directive's answers, so its result type is open where
;; import!'s is unit [source: LeaTTa MettaHyperonFull/Minimal/Interpreter.lean,
;; the include corelib block].
(: include (-> Atom %Undefined%))
;; DIVERGENCE from the dump, which types these over `(StateMonad $t)`.
;; PeTTa's state is a named global: change-state! is nb_setval/2 and get-state
;; is nb_getval/2, so the first argument is the NAME and there is no monadic
;; cell to type over [source: engine/metta.pl, 'change-state!'/3, 'get-state'/2].
(: change-state! (-> Symbol %Undefined% Bool))
(: get-state (-> Symbol %Undefined%))

;; --- Checked on import: text and printing ---
(: repr (-> Atom String))
(: repra (-> Atom Symbol))
(: parse (-> String Atom))
(: sread (-> String Atom))
(: println! (-> %Undefined% Bool))
(: readln! (-> String))
(: read-form! (-> Atom))
(: sread-command (-> String Atom))

;; --- Checked on import: time, files, process ---
(: current-time (-> Number))
(: format-time (-> String String))
(: exists_file (-> %Undefined% Bool))
(: argv (-> Number %Undefined%))

;; --- Checked on import: SWI predicates registered as MeTTa builtins ---
;; Their modes are Prolog's, so most parameters are genuinely unconstrained:
;; append/3 runs in every direction and maplist/3 takes a closure. The arrow
;; is here for the arity and the result, which is what a reader needs.
(: append (-> %Undefined% %Undefined% %Undefined%))
(: length (-> Expression Number))
(: reverse (-> Expression Expression))
(: msort (-> Expression Expression))
(: sort (-> Expression Expression))
(: last (-> Expression Atom))
(: member (-> Atom Expression Bool))
(: list_to_set (-> Expression Expression))
(: maplist (-> Atom %Undefined% %Undefined%))
(: foldl (-> Atom %Undefined% %Undefined% %Undefined%))
(: copy_term (-> Atom Atom))
(: atom_chars (-> %Undefined% %Undefined%))
(: atom_concat (-> %Undefined% %Undefined% %Undefined%))
(: term_hash (-> Atom Number))

;; --- Checked on import: the Prolog interface ---
;; Predicate builds a goal from its parts; the four *Predicate operations take
;; one and run or assert it. Each answers true.
(: Predicate (-> Expression %Undefined%))
(: callPredicate (-> %Undefined% Bool))
(: assertaPredicate (-> %Undefined% Bool))
(: assertzPredicate (-> %Undefined% Bool))
(: retractPredicate (-> %Undefined% Bool))
(: assert (-> Atom Bool))
(: import_prolog_function (-> Symbol Bool))

;; --- Checked on import: the compiler's own surface ---
(: add-translator-rule! (-> Symbol Bool))
(: remove-translator-rule! (-> Symbol Bool))

;; --- Checked on import: Python and the outside world ---
(: py-call (-> Expression %Undefined%))
;; py-atom RESOLVES where py-call applies, so what comes back is a value: a
;; Python callable MeTTa can hold, pass and apply. Atom parameters throughout,
;; because a name is a name rather than something to evaluate first.
(: new-space (-> SpaceType))
(: py-atom (-> Atom %Undefined%))
(: py-atom (-> Atom Atom %Undefined%))
(: py-dot (-> %Undefined% Atom %Undefined%))
(: py-list (-> Atom %Undefined%))
(: py-tuple (-> Atom %Undefined%))
(: py-dict (-> Atom %Undefined%))
(: py-iter (-> %Undefined% %Undefined%))
;; Kwargs takes its pairs UNEVALUATED, because the name half of a pair is a
;; name: without the mask `(Kwargs (reverse true))` was read as a call to the
;; `reverse` builtin and the whole form vanished. The VALUE half is evaluated
;; at the call, so `(Kwargs (n (+ 1 2)))` passes 3.
;;
;; One declaration per arity because MeTTa has no variadic type and the mask is
;; per position. Six pairs is well past what any call site uses; a seventh
;; simply gets the old behaviour rather than an error.
(: Kwargs (-> Atom %Undefined%))
(: Kwargs (-> Atom Atom %Undefined%))
(: Kwargs (-> Atom Atom Atom %Undefined%))
(: Kwargs (-> Atom Atom Atom Atom %Undefined%))
(: Kwargs (-> Atom Atom Atom Atom Atom %Undefined%))
(: Kwargs (-> Atom Atom Atom Atom Atom Atom %Undefined%))
(: library (-> %Undefined% %Undefined%))
(: git-import! (-> String (->)))
