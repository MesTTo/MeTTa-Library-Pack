; Purpose: score written terms using symbol similarity and structural recursion.
; Guarantees: a function-naming symbol retains its similarity; grounded values
;   compare crisply [tested: sh engine/test.sh suites/libraries/lib_soft.plt;
;   commit=4f2d6c0f8eb293b73f8dde30a1c84e24834f7393].

;Soft structural unification: match quality as a measure over terms.
;
;This is weak unification in Sessa's sense ("Approximate reasoning by
;similarity-based SLD resolution", Theoretical Computer Science 275, 2002,
;implemented by Bousi~Prolog): two expressions weakly unify when their
;symbols are close to a degree and their arguments recurse, the degrees
;aggregated by minimum, the fuzzy t-norm. Variables bind exactly as in
;crisp unification; structure stays crisp; closeness lives on the symbols.
;The aggregation is a choice, declared per space with (soft-aggregate mean)
;where ranking wants a mean rather than logic's worst-position rule.
;
;Closeness comes from (similar $a $b $degree) facts in the running space,
;read in both directions; identical symbols are 1.0 and unrelated ones 0.0.
;A host can write those facts from anywhere, an embedding store included,
;which is the move neural theorem provers make (Rocktaschel and Riedel,
;"End-to-end Differentiable Proving", NeurIPS 2017): attention over symbols,
;here over whole terms.
;
;(soft-match $space $pattern $threshold) scores the pattern against every
;atom in the space, binds the pattern's variables against each candidate,
;and answers (score candidate) pairs, score first, so results feed directly
;into lib_measure: (ws-best (collapse (soft-match ...))) is the closest
;match, ws-softmax over them is attention over terms.

!(import! &self (library lib_import))
!(import_prolog_functions_from_file (library lib_soft.pl) (soft-symbol?))
(: soft-symbol? (-> Atom Bool))
(@doc soft-symbol?
      (@desc "Tests written symbol representation, regardless of function registration")
      (@params ((@param "the held atom; grounded values and expressions answer False")))
      (@return "True for a symbol, False otherwise"))

;The degree two symbols are close: exact is 1.0, then declared similarity
;in either direction, then 0.0.
;
;Both operands are Atom, for soft-score's reason below: a scorer receives
;the term it is asked about, and a symbol that happens to name a function
;would otherwise be called on the way in.
(: sym-sim (-> Atom Atom Number))
(= (sym-sim $a $b)
   (if (== $a $b)
       1.0
       ;The three family operations below read their operands AS WRITTEN, so
       ;each collapsed answer set is NAMED before the one above it consumes it.
       (let $forward (collapse (match (context-space) (similar $a $b $d) $d))
         (let $backward (collapse (match (context-space) (similar $b $a $d) $d))
           (let $both (union-atom $forward $backward)
             (let $with-floor (cons-atom 0.0 $both)
               (max-atom $with-floor)))))))

;HOW THE POSITION DEGREES COMBINE, and when the walk can stop.
;
;min is the fuzzy t-norm and the default, which is the right rule for LOGIC:
;a term is as close as its worst position. For RANKING it flattens, because
;one unrelated symbol takes an otherwise strong match to zero -- (likes cat
;fish) against (likes dog fish) scores 0.0 under min and 0.667 under mean --
;and a flat ordering carries no gradient for a learned similarity to move.
;The t-norm is right for one job and wrong for the other, so the library
;does not choose for you.
;
;The choice is a DECLARATION rather than a parameter, which is
;Bousi~Prolog's own shape for the same decision: `:- transitivity(min).`
;selects the t-norm for a whole program there. Write one (soft-aggregate
;mean) atom in the space and every scorer in it reads it; soft-score-by
;takes one explicitly for a caller who wants both in one program.
;
;AN AGGREGATION IS TWO CLAUSES, a fold and a walk, dispatched on its name.
;It was four accessors first -- a unit, a combine, a finish and a halting
;degree -- which reads better and costs three to five times as much,
;because those are called PER POSITION where a clause head is selected
;once: measured 2026-09-04 on 400 six-position candidates, the accessor
;spelling cost 322,179 inferences against 98,135 where the pattern
;mismatches at position 0, and 1,001,407 against 189,341 where it matches.
;The walk's own early stop is the other half of that number: min may stop
;at 0.0 because no later position can raise it, and the probe below derives
;what stopping buys rather than carrying a quotient. A mean walks every
;position, having nothing to stop on. Adding a third aggregation is these two
;clauses again.
;
;The name must NOT reach them as an Atom, because an Atom parameter takes
;its operand AS WRITTEN: declared that way,
;(soft-score-by (soft-aggregation) ...) passed the CALL rather than the name
;it answers, and the walk had no clause for it. A symbol evaluates to
;itself, so an evaluated parameter is the right one.
;
;IT SAID Symbol UNTIL 2026-09-05, and it cannot any more. `min` is the default
;aggregation and it is also one of the engine's own arithmetic operations, and
;since the metatype rule became upstream PeTTa's -- a name is Grounded when
;this engine holds a function for it [source: PeTTa@43705f5d
;src/metta.pl:202] -- `(get-metatype min)` is Grounded, so a Symbol parameter
;REFUSED the library's own default with
;(Error (soft-score-by min ...) (BadArgType 1 Symbol (-> Number Number
;Number))) [measured 2026-09-05]. Renaming the aggregation would only postpone
;it: any name a caller picks may be one the engine holds a function for, `max`
;included, so the domain of this parameter is not a metatype at all. There is
;no union of Symbol and Grounded to declare, and Atom is the one that breaks
;the public spelling above, which leaves the gradual declaration.
;
;The early-stop benchmark measures the shipped scorer rather than a
;declaration that no longer accepts min. The 2026-09-05 figures and the
;rejected Symbol declaration are recorded in
;docs/journal/2026-09-05-get-metatype-follows-fun.md.
;
;  mismatch at position 0     87,657
;  match at position 0       183,661    early stop buys 2.10x
;
;[measured: inference counts above; command=python extensions/python/benchmarks/soft_match_cost.py;
;fixture=400 candidates with six arguments, Python 3.14.4 with Janus; commit=4f2d6c0f8eb293b73f8dde30a1c84e24834f7393].
(: soft-fold (-> %Undefined% Atom Atom Number))
(: soft-walk (-> %Undefined% Atom Atom Number Number))
(= (soft-fold min $ps $as) (soft-walk min $ps $as 1.0))
(= (soft-walk min $ps $as $acc)
   (if (or (== $ps ()) (== $acc 0.0))
       $acc
       (let ($ph $pt) (decons-atom $ps)
            (let ($ah $at) (decons-atom $as)
                 (soft-walk min $pt $at
                            (min $acc (soft-score-by min $ph $ah)))))))
(= (soft-fold mean $ps $as) (/ (soft-walk mean $ps $as 0.0) (size-atom $ps)))
(= (soft-walk mean $ps $as $acc)
   (if (== $ps ())
       $acc
       (let ($ph $pt) (decons-atom $ps)
            (let ($ah $at) (decons-atom $as)
                 (soft-walk mean $pt $at
                            (+ $acc (soft-score-by mean $ph $ah)))))))

;The aggregation this space declares, min where it declares none.
;
;NOT declared (-> Atom): an Atom RESULT is held back from evaluation, so the
;declaration returned this equation's own body unreduced and every scorer
;then folded with an unbound aggregation. The answer is a symbol naming an
;aggregation, which evaluates to itself.
(= (soft-aggregation)
   (let $declared (collapse (match (context-space) (soft-aggregate $name) $name))
     (if (== $declared ()) min (car-atom $declared))))

;The degree a pattern weakly unifies with a term, binding the pattern's
;variables as it goes. Value structure drives the cases: a variable binds anything
;at degree one, expressions recurse position by position under minimum,
;symbols consult sym-sim, and grounded values stay crisp.
;
;BOTH OPERANDS ARE Atom, so a scorer does not run the program it is
;choosing between. Undeclared, they were evaluated on the way in, and the
;atoms in a space that most deserve scoring are its EQUATIONS:
;
;  (soft-score (= (tepid $x) $b) (= (warm $y) (* $y 2)))
;
;refused with "* ran backwards with more than one unknown", which is correct
;arithmetic met in the wrong place. The same call now answers a degree
;[measured 2026-09-04]. Scoring a bare head worked either way, which is why
;the header's own examples never met this.
(: soft-score (-> Atom Atom Number))
(= (soft-score $p $a) (soft-score-by (soft-aggregation) $p $a))

;The same, under a named aggregation rather than the space's declared one.
(: soft-score-by (-> %Undefined% Atom Atom Number))
(= (soft-score-by $agg $p $a)
   (if (== (get-metatype $p) Variable)
       (let $p $a 1.0)
       (if (and (== (get-metatype $p) Expression) (== (get-metatype $a) Expression))
           (if (== (size-atom $p) (size-atom $a))
               (soft-fold $agg $p $a)
               0.0)
           ;A function name is Grounded under get-metatype, just like a
           ;number. Test its representation to retain symbol similarity.
           (if (and (soft-symbol? $p) (soft-symbol? $a))
               (sym-sim $p $a)
               (if (== $p $a) 1.0 0.0)))))

;Every atom of a space the pattern weakly unifies with above a threshold,
;nondeterministically, as (score candidate) with the pattern's variables
;bound per answer. The aggregation is read ONCE, before the candidates are
;enumerated, rather than per candidate.
(= (soft-match $sp $pattern $least)
   (let $agg (soft-aggregation)
     (let $candidate (get-atoms $sp)
          (let $score (soft-score-by $agg $pattern $candidate)
               (if (>= $score $least)
                   ($score $candidate)
                   (empty))))))

;The closest match and its degree, through the measure algebra:
(= (soft-best $sp $pattern)
   (ws-best (collapse (soft-match $sp $pattern 0.0))))
