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

(: unify (-> Atom Atom Atom Atom %Undefined%))
(= (unify $space $pattern $then $else)
   (if (is-space $space)
       (let $temp (cut)
            (case (match $space $pattern $pattern)
                  (($pattern (eval $then))
                   (Empty (eval $else))))) (empty)))

(= (unify $a $b $then $else)
   (if (= $a $b)
       (eval $then)
       (eval $else)))

(: add-reduct (-> %Undefined% Atom Bool))
(= (add-reduct $space $f)
   (let* (($headbody (cdr-atom $f))
          ($head (car-atom $headbody))
          ($body (cdr-atom $headbody))
          ($bodyreduced (eval $body)))
         (add-atom $space (= $head $bodyreduced))))

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

(: evalc (-> Atom %Undefined% %Undefined%))
(= (evalc $expression &self)
   (eval $expression))

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
