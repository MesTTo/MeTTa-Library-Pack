; %%%% Hyperon-Experimental compatibility library. %%%%
; Many of the included functions were considered ad hoc and
; straightforward to express directly in MeTTa itself:

;Equality and Reduction
(= (if-equal $A $B $Then $Else)
   (if (== $A $B) $Then $Else))

(= (if-equal2 $A $B $Then $Else)
   (if (== $A $B) $Then $Else))

(= (assertEqual $A $B)
   (assert (== $A $B)))

(= (assertAlphaEqual $A $B)
   (assert (=alpha $A $B)))

;The ToResult forms do not evaluate their second argument: it is the set of
;expected results, written as a tuple. Both parameters are Atom so neither is
;evaluated on the way in, and the first is collapsed here into the tuple of
;every result it produces. Hyperon's own corpus states the contract, in
;tests/corpus/a1_symbols.metta: "assertEqualToResult checks all the results of
;the first expression; it doesn't evaluate the second expression, which is
;treated as a set of expected results."
(: assertEqualToResult (-> Atom Atom %Undefined%))
(= (assertEqualToResult $A $B)
   (assert (== (collapse (eval $A)) $B)))

(: assertAlphaEqualToResult (-> Atom Atom %Undefined%))
(= (assertAlphaEqualToResult $A $B)
   (assert (=alpha (collapse (eval $A)) $B)))

;Every expected result must appear among the results produced. Subtracting the
;produced set from the expected one leaves nothing when all of them did.
(: assertIncludes (-> Atom Atom %Undefined%))
(= (assertIncludes $A $B)
   (assert (== (subtraction-atom $B (collapse (eval $A))) ())))

;The Msg variants carry a failure message. assert/2 already reports the failing
;expression, so each delegates and the message is accepted but unused.
(: assertEqualMsg (-> Atom Atom Atom %Undefined%))
(= (assertEqualMsg $A $B $M)
   (assert (== (collapse (eval $A)) (collapse (eval $B)))))

(: assertAlphaEqualMsg (-> Atom Atom Atom %Undefined%))
(= (assertAlphaEqualMsg $A $B $M)
   (assert (=alpha (collapse (eval $A)) (collapse (eval $B)))))

(: assertEqualToResultMsg (-> Atom Atom Atom %Undefined%))
(= (assertEqualToResultMsg $A $B $M)
   (assertEqualToResult $A $B))

(: assertAlphaEqualToResultMsg (-> Atom Atom Atom %Undefined%))
(= (assertAlphaEqualToResultMsg $A $B $M)
   (assertAlphaEqualToResult $A $B))

;unify is an engine special form now, for the same reason add-reduct
;below is: it is standard library, not a compatibility shim. The engine
;form also does what the shim here could not: bindings flow from the
;match into the selected branch, numbers compare promoted, a space
;operand queries through every context kind, and grounded values with
;their own matching logic are consulted, per the arbiter's matcher.

;add-reduct is an engine builtin now, along with add-atoms and add-reducts,
;because all three are standard library operations rather than compatibility
;shims and a program should not have to import anything to reach them. The
;shim that used to sit here also had the wrong contract: it destructured its
;argument as an equation and reduced only the body, where the standard library
;says "Reduces atom (second argument) and adds it into the [space]", so
;`(add-reduct &self (+ 1000 1))` has to add 1001 and this added the call.

;Error Handling
(= (if-error $X $A $B)
   (if (= $X (cons Error $_)) 
       $A $B))

(= (return-on-error $result $B)
   (if-error $result
             $result
             $B))

;Evaluation control
(= (for-each-in-atom $L $f)
   (map-atom $L $f))

;evalc is an engine builtin now, and it takes any space rather than only the
;literal &self this shim matched.

;Quoting
(: unquote (-> Atom %Undefined%))
(= (unquote (quote $A))
   (let $cut (cut) (eval $A)))
(= (unquote $A) (quote (unquote $A)))

(: noreduce-eq (-> Atom Atom Bool))
(= (noreduce-eq $A $B)
   (== $A $B))

;Types
(= (is-function (-> $A $B)) (let $temp (cut) True))
(= (is-function $X) False)

(= (get-type-space &self $x)
   (get-type $x))

(= (match-types $A $B $Then $Else)
   (if (== $A $B) $Then $Else))

(= (match-type-or $value $type1 $type2)
   (match-types $type1 $type2 True $value))

;HE's type-cast: the atom itself when it has the type, (Error $atom BadType)
;when it does not. Three ways it can have it. The requested type IS the atom's
;metatype, so (type-cast A Symbol &self) casts any symbol. A declared type is
;equal to the requested one. Or the atom has no declaration at all, which
;PeTTa answers as %Undefined%, and an undeclared atom is not the wrong type.
;
;Atom on the parameters because a cast is about the atom as written: casting
;(+ 1 1) asks about that expression, not about 2. The RESULT is %Undefined%
;rather than HE's Atom: in PeTTa an Atom output type means the body is not
;translated at all, which is how a macro returns its own text, and declaring
;it here answered the unevaluated (if (== type1 (get-metatype A)) ...).
(: type-cast (-> Atom Atom Atom %Undefined%))
(= (type-cast $atom $type $space)
   (if (== $type (get-metatype $atom))
       $atom
       (if (type-cast-holds $atom $type $space)
           $atom
           (Error $atom BadType))))

(= (type-cast-holds $atom $type $space)
   (foldl-atom (collapse (get-type-space $space $atom)) False $acc $declared
      (or $acc (type-cast-check $declared $type))))

(= (type-cast-check $declared $wanted)
   (if (== $declared %Undefined%) True (== $declared $wanted)))
