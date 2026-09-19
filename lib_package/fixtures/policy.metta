; Purpose: executable equations for the default package policy's pure choices.
; Assumes: normalized backing rows and the attached claim tokens are data.
; Guarantees: selection keeps source order; receipts retain every answer;
; retirement reverses acquisition order [tested: lib_package; commit=WORKTREE].

(: package-fixture-member (-> Atom Atom Bool))
(= (package-fixture-member $x ()) False)
(= (package-fixture-member $x ($y (:seg $ys)))
   (if (== $x $y) True (package-fixture-member $x $ys)))

(: package-fixture-choice (-> Atom Atom Atom %Undefined%))
(= (package-fixture-choice $head () $claims) absent)
(= (package-fixture-choice $head (($token $artifact $heads) (:seg $rows)) $claims)
   (if (and (package-fixture-member $token $claims)
            (package-fixture-member $head $heads))
       (quote ($token $artifact $heads))
       (package-fixture-choice $head $rows $claims)))

(: package-fixture-reverse (-> Atom Atom %Undefined%))
(= (package-fixture-reverse () $done) $done)
(= (package-fixture-reverse ($first (:seg $rest)) $done)
   (let $next (cons-atom $first $done)
     (package-fixture-reverse $rest $next)))

(: package-fixture-record (-> Atom Atom %Undefined%))
(= (package-fixture-record $row ()) ())
(= (package-fixture-record $row ($answer (:seg $answers)))
   (cons-atom (quote (performed $row $answer))
              (package-fixture-record $row $answers)))
