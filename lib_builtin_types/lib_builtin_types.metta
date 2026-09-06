; Purpose: declare the type surface of MeTTa's shipped builtins, its type-kind
; markers included, for engine reflection and optional live typed dispatch.
; Guarantees:
;   - reader-token registration takes a regex string and readable constructor
;     symbol, while removal takes the same regex string [tested:
;     test_a_registered_token_class_parses_like_a_shipped_one;
;     commit=2c741dda928a30d0ce1c7e1fcf0b263b4d1bb97b].
;   - DontEvalType marks user-declared parameter types whose arguments stay
;     unevaluated at the typed dispatch boundary.
;   [tested: test_a_user_declared_lazy_type_receives_its_argument_unevaluated; commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3]
;   - unit-returning surface declarations report `(->)` as their result.
;   [tested: test_the_empty_expressions_type_follows_the_arbiters_ruling; commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3]
;   - typing-rule declarations receive their patterns and outcomes unevaluated.
;   [tested: test_a_user_typing_rule_participates_like_a_shipped_one; commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3]
; Open Obligations:
;   To Do: None
;   Hacks: None
;   Future Enhancements: None

; %%%% Type definitions of MeTTa built-in operators. %%%%

;; A type declared with DontEvalType is a user-defined evaluation mask. It
;; carries no naming convention: the declaration, rather than the type's name,
;; is the only fact the compiler consults.
(: DontEvalType Type)

;; Type definitions of arithmetic operators
;;
;; The (cost ...) rows below are claims the cost-rows lane measures and fails.
;; Addition's hole sits at a Number parameter, so the lane sizes it by the
;; VALUE of $n and holds the call constant over the ladder: arithmetic that
;; started scanning its operand would fail here. Every other row on this page
;; holds an Expression parameter, whose size is its LENGTH, and the floor for
;; those is linear, because the call evaluates the expression it is handed.
(: + (-> Number Number Number))
(cost (+ $n 1) constant)
(: - (-> Number Number Number))
(: * (-> Number Number Number))
(: / (-> Number Number Number))
(: % (-> Number Number Number))

;; Type definitions of ordered comparison operators
(: < (-> Number Number Bool))
(: <= (-> Number Number Bool))
(: > (-> Number Number Bool))
(: >= (-> Number Number Bool))

;; Type definitions of equality and negated equality operators.
;; TWO INDEPENDENT variables, not one shared one: comparing values of two
;; different types is a legitimate question whose answer is False, not a type
;; error. Written `(-> $a $a Bool)` here until 2026-08-30, which refused
;; upstream's own examples/types_nondet.metta at `(== $a T1in)` with
;; `(Error (== T2in T1in) (BadArgType 2 Type2 Type1))` where upstream answers
;; False and carries on [source: PeTTa@ae66fa8 lib/lib_builtin_types.metta:17-18].
(: == (-> $a $b Bool))
(: != (-> $a $b Bool))

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
;; than a type, so `!(get-type pragma!)` answers `%Undefined%`. Upstream
;; declares nothing for the name either, and answers the same
;; [source: PeTTa@43705f5d src/metta.pl, which registers no pragma! and
;; carries no (: pragma! ...) row; measured 2026-09-05 against
;; PeTTa@43705f5d: `!(get-type pragma!)` is `%Undefined%` on both engines].
;; A program that writes `(: pragma! Number)` into the space DOES change the
;; answer to Number, on both engines, because the declaration is read from the
;; space; the row here is what is absent, not the lookup
;; [measured 2026-09-05 against PeTTa@43705f5d]. It answers the UNIT
;; value, for the reason add-atom does.

;; HE's metta/3: interpret an atom in a named space. The Type argument is
;; accepted and ignored, as HE does for %Undefined%.
(: metta (-> Atom Type SpaceType Atom))

;; ===========================================================================
;; The rest of the engine's surface: 117 names that answered %Undefined%.
;;
;; The types were SOURCED from the reference corelib dump wherever it had one,
;; because a type MeTTa does not already have is additive [assumed: taken from
;; a reference corelib dump of 146 typed entries, 39 of these names among them;
;; not re-measured against upstream PeTTa]. What GOVERNS is
;; upstream PeTTa, which became this branch's arbiter with the alignment: where
;; both declare a name, upstream's arrow wins. Nothing is in dispute today --
;; upstream declares 36 names, every one of them is declared here, and all 36
;; arrows are identical, this file declaring 189 in all [measured 2026-08-31 by
;; comparing the two files' (: name arrow) forms]. The distinction matters
;; because the two sentences differ the day they disagree, and the file said
;; the reference governed.
;; One vocabulary translation was needed: HE's unit
;; result `(->)` is MeTTa's `Bool`, because every one of these answers `true`.
;; `SpaceType` is written as itself, because a space handle carries that type
;; and every path that needs the species reads it
;; [tested: spaces:space_handle_type]. It was written `Symbol` until
;; 2026-08-20 and that was a metatype claim, which broke when the handle
;; gained a type of its own: every one of these declarations then REFUSED a
;; space handle as a first argument. Writing the TYPE rather than a metatype
;; is what has kept them working through both metatype rules since, the
;; 2026-09-05 move to upstream PeTTa's included, where `(get-metatype &self)`
;; became `Symbol` again while `(get-type &self)` did not move.
;; Divergences from the dump are marked where they occur.
;;
;; THIS FILE HAS TWO ROLES AND THEY DIFFER. The engine reads it at boot into
;; `seam:builtin_type_declaration/2`, which `get_type_candidate/2` consults LAST, so
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
;; switch evaluates its key where case holds it, which is upstream's own
;; split: (: switch (-> %Undefined% Expression %Undefined%)) against
;; (: case (-> Atom Expression %Undefined%)).
(: switch (-> %Undefined% Expression %Undefined%))
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
(: nop (-> (%Rest% %Undefined%) (->)))

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
;These five answer `true`, the effect answer every operation of this family
;gives; engine/metta/runtime.pl's note above 'println!'/2 carries the list and
;names the check that holds it together
;[source: PeTTa@ae66fa8 src/spaces.pl:10,24].
;
;They were declared `(->)` here for a while, following Hyperon's unit type, and
;the clauses were changed to match. Upstream PeTTa is the arbiter on this
;branch and answers `true`, so both halves came back.
;
;The second parameter is `Atom` in every one of them, so the argument arrives
;UNREDUCED. That is load-bearing for the reducing three: `add-reduct` reduces
;the atom itself, and a caller that reduced it first would hand it a value
;`reduce/3` has nothing left to do with.
(: add-atom (-> SpaceType Atom Bool))
(: remove-atom (-> SpaceType Atom Bool))
(: add-atoms (-> SpaceType Atom Bool))
(: add-reduct (-> SpaceType Atom Bool))
(: add-reducts (-> SpaceType Atom Bool))
(: match (-> SpaceType Atom Atom %Undefined%))

;; --- Special forms: collections ---
;; Each has TWO arrows, the binder spelling and the closure spelling, and both
;; are the reference's own rows byte for byte
;; [assumed 2026-08-24: the (: map-atom ...), (: filter-atom ...) and
;; (: foldl-atom ...) rows and `!(get-type map-atom)` answering both were
;; measured against an earlier reference corpus at that date, not re-measured
;; against upstream PeTTa].
;; The list is Expression and so arrives AS WRITTEN in either spelling:
;; !(map-atom (cdr-atom (a b)) $y (q $y)) is ((q cdr-atom) (q (a b))) there,
;; mapping over the two parts of the unrun call. foldl-atom's seed is Atom and
;; is held too: !(foldl-atom (1) (+ 1 2) $a $b (size-atom $a)) is 3, the size
;; of the held (+ 1 2), where an evaluated seed would refuse a Number.
(: map-atom (-> Expression Variable Atom Expression))
(: map-atom (-> Expression Expression Expression))
(: filter-atom (-> Expression Variable Atom Expression))
(: filter-atom (-> Expression Expression Expression))
(: foldl-atom (-> Expression Atom Variable Variable Atom %Undefined%))
(: foldl-atom (-> Expression Atom Expression %Undefined%))

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
;; The rest of the same two families, which the engine backs and this file did
;; not declare: `(get-type #<)` answered its arrow while `(get-type #=)`,
;; `(get-type #>=)` and `(get-type #//)` answered %Undefined%, so five working
;; operators were invisible to the type surface and to everything generated
;; from it [measured 2026-08-31 through `!(get-type ...)` on each].
(: #// (-> Number Number Number))
(: #= (-> Number Number Bool))
(: #\= (-> Number Number Bool))
(: #=< (-> Number Number Bool))
(: #>= (-> Number Number Bool))

;; --- Runtime-guarded: the rest ---
(: exp-math (-> Number Number))
(: implies (-> Bool Bool Bool))
;; with-seed holds its body: the scope is the body's dynamic extent, and the
;; body is compiled in place rather than evaluated as a term.
(: with-seed (-> Number Atom %Undefined%))
(: random-int (-> Number Number Number))
(: random-float (-> Number Number Number))

;; --- Checked on import: expression structure ---
;; car-atom's result is %Undefined% in the dump and stays so: the head of an
;; expression is whatever that expression holds.
(: car-atom (-> Expression %Undefined%))
(cost (car-atom $n) linear)
(: cdr-atom (-> Expression Expression))
(cost (cdr-atom $n) linear)
;; Both operands EVALUATE. Upstream ships cons-atom, cons, decons-atom,
;; decons, index-atom and the three set operations as bare Prolog predicates
;; with no declaration at all, so their arguments are ordinary evaluated
;; ones; a held operand answered `((+ 1 2) b)` where upstream answers
;; `(3 b)` [source: PeTTa@ae66fa8 src/metta.pl:111,153; measured 2026-08-30,
;; ai-tmp/family.metta, 7 of 15 forms in this family differed and every one
;; of them differed only here]. The RESULT types are untouched: `Atom` on
;; cons is what keeps a rebuild linear, per the note below.
(: cons-atom (-> %Undefined% %Undefined% Atom))
(: decons-atom (-> %Undefined% Atom))
;; Inspect the written expression and binders; evaluate only the selected branch.
;; Plain Expression eagerly evaluated (+ 1 2), selecting fallback instead of
;; exposing its tail (1 2) [tested: if_decons_expr:the_operand_is_inspected_without_evaluation; commit=9958c72363d2fbc640d2ae39ee6f0670ecfbff67].
(: if-decons-expr (-> (:Atom Expression) (:Atom Variable) (:Atom Variable) Atom Atom %Undefined%))
(: size-atom (-> Expression Number))
(cost (size-atom $n) linear)
(: index-atom (-> %Undefined% Number Atom))
;; atom-subst replaces one variable inside a template, all three operands
;; as written and the result as produced.
;;The BINDER is held, and it must be a variable. `Atom` is the only parameter
;;type that holds now, so the second position says both things at once through
;;this engine's type-position modifier: hold it, and check it is a Variable.
;;Written plain `Variable` the binder EVALUATED, so
;;`(atom-subst 1 (car-atom ($x)) ($x $x))` reduced its second operand to the
;;variable inside it and substituted happily, where holding the written
;;`(car-atom ($x))` refuses it as the non-binder it is [measured 2026-08-30].
(: atom-subst (-> Atom (:Atom Variable) Atom Atom))
;; MeTTa's own, no dump entry. cons/decons are the un-suffixed spellings and
;; first/second-from-pair read a two-element expression.
;;
;; Their RESULT is `Atom`, matching the suffixed rows two lines up, and the
;; result type is not decoration: `Atom` says the answer is final while every
;; other result re-enters evaluation [assumed: the `returnsAtom` rule was
;; adopted from an earlier reference semantics, not re-measured against
;; upstream PeTTa]. Written `Expression` here, each cons re-walked the list it
;; had just built and a million-element `range` went from linear to quadratic
;; [measured 2026-08-24: 20,000 elements, 0.30s to 7.01s, and the shipped
;; million-element holbenchmark kernel stopped finishing at all].
(: cons (-> %Undefined% %Undefined% Atom))
(: decons (-> %Undefined% Atom))
(: first (-> %Undefined% Atom))
;; first-from-pair is UNDECLARED, with empty, nop, pragma!, type-cast,
;; match-types and match-type-or: each official corelib block reads
;; `Type %Undefined%`, which is the gradual default rather than a type, so
;; get-type answers %Undefined% and a wrong-arity call stays unreduced instead
;; of being refused by an arity the declaration invented
;; [assumed 2026-08-15: the undeclared-helpers reading was measured against an
;; earlier reference corpus at that date, not re-measured against upstream
;; PeTTa].
(: second-from-pair (-> %Undefined% Atom))

;; --- Checked on import: set and list operations ---
(: union-atom (-> %Undefined% %Undefined% Atom))
(cost (union-atom $n $n) linear)
;; The contrast worth knowing: union-atom is append/3, while intersection-atom
;; builds an association tree of its right operand and looks every element of
;; its left one up in it, so the second costs a log factor more than the first.
;; Both rows were measured on the engine's inferences AND on retired
;; instructions, and the two counters agree on both.
(: intersection-atom (-> %Undefined% %Undefined% Atom))
(cost (intersection-atom $n $n) linearithmic)
(: subtraction-atom (-> %Undefined% %Undefined% Atom))
;; Neither of these two carries a (cost ...) row, and the reason is the
;; counter. unique-atom is SWI's list_to_set/2, which sorts in C: the engine
;; retires one inference for the whole call, so its inference curve is the
;; ARGUMENT arriving and reads linear, while retired instructions read 1.057
;; and say linearithmic. A row would state the cheaper of the two readings.
;; alpha-unique-atom has no such gap, its association tree being Prolog's, and
;; it is the row alpha-unique carries in engine/prelude.metta
;; [measured 2026-09-07: `python -m benchmarks.costs --paired`, unique-atom
;; 0.978 against 1.057 and alpha-unique-atom 1.076 against 1.079].
(: unique-atom (-> Expression Atom))
(: alpha-unique-atom (-> Expression Atom))
(: sort-atom (-> %Undefined% Expression))
;; The corelib's own two, whose blocks read `(-> String Expression String)` and
;; `(-> Expression Expression)`. Both are load-bearing: they are what turns
;; `(format-args n ())` into `(BadArgType 1 String Number)` and
;; `(sort-strings s)` into `(BadArgType 1 Expression String)`, where an
;; argument the type does not decide earns the operation's own words instead
;; [assumed: the two arrows were adopted from an earlier reference semantics,
;; not re-measured against upstream PeTTa].
(: format-args (-> String Expression String))
(: sort-strings (-> Expression Expression))
(: exclude-item (-> %Undefined% %Undefined% Expression))
(: is-member (-> %Undefined% %Undefined% Bool))
(: is-alpha-member (-> %Undefined% %Undefined% Bool))

;; --- Checked on import: the metatype predicates ---
;; Each takes anything and answers a Bool, which is the whole point of them.
(: is-var (-> Atom Bool))
(: is-ground (-> Atom Bool))
(: is-expr (-> Atom Bool))
(: is-space (-> %Undefined% Bool))
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
(: id (-> $t $t))

;; --- Checked on import: spaces and state ---
(: get-atoms (-> SpaceType Atom))
(: bind! (-> Symbol %Undefined% Bool))
(: register-token! (-> String Symbol Bool))
(: unregister-token! (-> String Bool))
(: context-space (-> SpaceType))
(: import! (-> Atom Atom Bool))
;; include pastes a module's source into the space that included it and
;; answers its LAST directive's answers, so its result type is open where
;; import!'s is unit [assumed: adopted from an earlier reference semantics, not
;; re-measured against upstream PeTTa, which has no include].
(: include (-> Atom %Undefined%))
;; The cell is a VALUE and its type is parametric in what it holds, which is
;; the upstream signature [assumed: measured against an earlier reference
;; corpus, not re-measured against upstream PeTTa]. A cell is a handle atom
;; here, so a plain symbol still names one and the older named spelling keeps
;; working; what changed is that (new-state V) answers a cell rather than only
;; being readable inside bind!. change-state! answers `true` like the rest of
;; the effect family [source: PeTTa@ae66fa8 src/metta.pl:265].
(: new-state (-> $t (StateMonad $t)))
(: change-state! (-> (StateMonad $t) $t Bool))
(: get-state (-> (StateMonad $t) $t))

;; --- Checked on import: text and printing ---
(: repr (-> %Undefined% String))
(: repra (-> %Undefined% Symbol))
(: parse (-> String Atom))
(: sread (-> String Atom))
(: println! (-> %Undefined% Bool))
(: readln! (-> String))
(: read-form! (-> Atom))
(: parse-command (-> String Atom))

;; --- Checked on import: time, files, process ---
(: current-time (-> Number))
(: format-time (-> String String))
;; assert's operand EVALUATES, so what reaches assert/2 is the VERDICT and not
;; the comparison, which is what upstream's `assert(Goal, true) :- call(Goal)`
;; receives: `call(true)` succeeds and `call(false)` fails. Declared `Atom`
;; here until 2026-08-30, and holding it made assert evaluate the written form
;; a SECOND time, so an operand whose variables were already bound to values
;; was re-applied: `(assertAlphaEqual (quote (+ $x $y)) (quote (+ $a $b)))`
;; aborted with `+ ran backwards` where upstream answers True
;; [source: PeTTa@ae66fa8 src/metta.pl:224-227 and examples/he_assert.metta:5].
;;
;; DECLARED rather than left out: retract_unrelated_system_arities/0 drops a
;; system predicate's arity only for a name the surface declares, so with no
;; declaration at all SWI's own assert/1 stayed callable and `!(assert)`
;; reached it instead of answering a partial application
;; [tested: test_an_underapplied_operation_answers_instead_of_aborting].
(: assert (-> %Undefined% (->)))
;; assert with the two answer bags carried, so a failed comparison over
;; answers can report which answers differed. The verdict is the caller's and
;; is evaluated; the call to report and the two bags are held, because a
;; reported form must be what the program wrote and a collapsed tuple
;; evaluated again is an APPLICATION of its first answer to the rest.
;; DECLARED HERE rather than in engine/prelude.metta, beside the assert family
;; that calls it: the mask index for a BUILTIN call site is derived from this
;; file, in load_builtin_type_surface/0, and the prelude compiles after that,
;; so a prelude-only declaration would arrive too late to hold anything
;; [source: engine/metta.pl:1435-1451 and :1718; commit=71de27a76dd16684941e3e090de0d17299d96493].
(: assert-answers (-> %Undefined% Atom Atom Atom (->)))
(: exists_file (-> %Undefined% Bool))
(: argv (-> Number %Undefined%))

;; --- Checked on import: SWI predicates registered as MeTTa builtins ---
;; Their modes are Prolog's, so most parameters are genuinely unconstrained:
;; append/3 runs in every direction and maplist/3 takes a closure. The arrow
;; is here for the arity and the result, which is what a reader needs.
;;
;; NONE OF THEM MASKS, and the parameter type is what says so. A declaration
;; here describes the value the PREDICATE receives, and every one of these
;; predicates receives a value: length/2 counts a list rather than the
;; expression that computes one, maplist/3 calls a goal the call site built,
;; and copy_term/2 copies what its argument evaluated to. Writing `Expression`
;; or `Atom` in those positions describes the caller's text instead, and once
;; the evaluation mask reached written calls those declarations stopped the
;; evaluation the predicate needs. Upstream registers the same predicates and
;; declares none of them, so nothing masks there either and the two engines
;; answer alike: `!(length (cdr-atom (a b c)))` is 2,
;; `!(reverse (cdr-atom (a b c)))` is `(c b)` and
;; `!(append (cdr-atom (a b)) (c))` is `(b c)` on both
;; [source: PeTTa@43705f5d src/metta.pl:330-344, the register_fun roster,
;; against lib/lib_builtin_types.metta which declares 36 names and none of
;; these; measured 2026-09-05 against PeTTa@43705f5d]. The same correction was
;; recorded for `first-from-pair`: the earlier (-> Expression Atom) invented an
;; Expression first parameter, which is exactly the instruction not to evaluate
;; the pair [assumed: read from an earlier reference semantics, not re-measured
;; against upstream PeTTa].
(: append (-> %Undefined% %Undefined% %Undefined%))
(: length (-> %Undefined% Number))
(: reverse (-> %Undefined% Expression))
(: msort (-> %Undefined% Expression))
(: sort (-> %Undefined% Expression))
(: last (-> %Undefined% Atom))
(: member (-> %Undefined% %Undefined% Bool))
(: list_to_set (-> %Undefined% Expression))
(: maplist (-> %Undefined% %Undefined% %Undefined%))
(: foldl (-> %Undefined% %Undefined% %Undefined% %Undefined%))
(: copy_term (-> %Undefined% %Undefined%))
(: atom_chars (-> %Undefined% %Undefined%))
(: atom_concat (-> %Undefined% %Undefined% %Undefined%))
(: term_hash (-> %Undefined% Number))

;; --- Checked on import: the Prolog interface ---
;; Predicate builds a goal from its parts; the four *Predicate operations take
;; one and run or assert it. Each answers true.
(: Predicate (-> Expression %Undefined%))
(: callPredicate (-> %Undefined% Bool))
(: assertaPredicate (-> %Undefined% Bool))
(: assertzPredicate (-> %Undefined% Bool))
(: retractPredicate (-> %Undefined% Bool))
(: import_prolog_function (-> Symbol Bool))

;; --- Checked on import: the compiler's own surface ---
(: add-translator-rule! (-> Symbol Bool))
;The declarations arrive as syntax, so the Atom parameter, and the list is
;written rather than computed: ((direction bidirectional)).
(: add-translator-rule! (-> Symbol Atom Bool))
(: remove-translator-rule! (-> Symbol Bool))
(: add-typing-rule! (-> Atom Atom Atom Atom Atom Bool))
(: remove-typing-rule! (-> Atom Bool))

;; --- Checked on import: Python and the outside world ---
(: py-call (-> %Undefined% %Undefined%))
;; py-atom RESOLVES where py-call applies, so what comes back is a value: a
;; Python callable MeTTa can hold, pass and apply. Atom parameters throughout,
;; because a name is a name rather than something to evaluate first.
(: new-space (-> SpaceType))
;;A ground expression held as Atom becomes a parametric space identifier.
(: new-space (-> Atom SpaceType))
;;The Atom descriptor is held as data: `(inherits &parent)` and
;;`(restricted (grants file ...))` select creation-time execution bases.
(: new-space (-> SpaceType Atom SpaceType))
(: py-atom (-> Atom %Undefined%))
(: py-atom (-> Atom Atom %Undefined%))
(: py-dot (-> %Undefined% Atom %Undefined%))
(: py-list (-> %Undefined% %Undefined%))
(: py-tuple (-> %Undefined% %Undefined%))
(: py-dict (-> %Undefined% %Undefined%))
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
(: git-import! (-> String Bool))
;; A library that rests on a seat says so, and the engine answers by name when
;; the seat is not there. Symbol rather than Atom because the argument is a
;; NAME the way bind!'s first argument is, and unit because what a require
;; leaves behind is the right to assume the seat, not a value.
(: require-extension! (-> Symbol (->)))
