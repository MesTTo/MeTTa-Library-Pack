;Soft structural unification: match quality as a measure over terms.
;
;This is weak unification in Sessa's sense ("Approximate reasoning by
;similarity-based SLD resolution", Theoretical Computer Science 275, 2002,
;implemented by Bousi~Prolog): two expressions weakly unify when their
;symbols are close to a degree and their arguments recurse, the degrees
;aggregated by minimum, the fuzzy t-norm. Variables bind exactly as in
;crisp unification; structure stays crisp; closeness lives on the symbols.
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

;The degree two symbols are close: exact is 1.0, then declared similarity
;in either direction, then 0.0.
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

;The degree a pattern weakly unifies with a term, binding the pattern's
;variables as it goes. Metatypes drive the cases: a variable binds anything
;at degree one, expressions recurse position by position under minimum,
;symbols consult sym-sim, and grounded values stay crisp.
(= (soft-score $p $a)
   (if (== (get-metatype $p) Variable)
       (let $p $a 1.0)
       (if (and (== (get-metatype $p) Expression) (== (get-metatype $a) Expression))
           (if (== (size-atom $p) (size-atom $a))
               (soft-score-args $p $a 1.0)
               0.0)
           (if (and (== (get-metatype $p) Symbol) (== (get-metatype $a) Symbol))
               (sym-sim $p $a)
               (if (== $p $a) 1.0 0.0)))))

(= (soft-score-args $ps $as $acc)
   (if (or (== $ps ()) (== $acc 0.0))
       $acc
       (let ($ph $pt) (decons-atom $ps)
            (let ($ah $at) (decons-atom $as)
                 (soft-score-args $pt $at (min $acc (soft-score $ph $ah)))))))

;Every atom of a space the pattern weakly unifies with above a threshold,
;nondeterministically, as (score candidate) with the pattern's variables
;bound per answer:
(= (soft-match $sp $pattern $least)
   (let $candidate (get-atoms $sp)
        (let $score (soft-score $pattern $candidate)
             (if (>= $score $least)
                 ($score $candidate)
                 (empty)))))

;The closest match and its degree, through the measure algebra:
(= (soft-best $sp $pattern)
   (ws-best (collapse (soft-match $sp $pattern 0.0))))
