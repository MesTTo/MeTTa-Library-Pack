; Purpose: weighted-superposition operations for normalization, ranking,
; sampling, aggregation, and expectation.
; Open Obligations:
;   To Do: None
;   Hacks: None
;   Future Enhancements: None
;
;Weighted superpositions: alternatives that carry a measure.
;
;A weighted superposition is a tuple of (weight value) pairs, the head shape
;of an annotated disjunction in probabilistic logic programming (Vennekens,
;Verbaeten, Bruynooghe, "Logic Programs with Annotated Disjunctions", ICLP
;2004; Sato's distribution semantics underneath). The operations here are
;the measure algebra those programs and modern attention share: normalize is
;a distribution, softmax with a temperature is attention's own weighting
;(Ramsauer et al., "Hopfield Networks is All You Need"), sampling executes
;the probabilistic choice, argmax is the zero-temperature limit, and top-k
;is beam search's keep rule. One representation, every reading.

;The mass of a weighted superposition. foldl-atom's list parameter is
;Expression, so it holds its operand as written; the mapped weights are NAMED
;and the name handed over.
(= (ws-total $ps)
   (let $weights (map-atom $ps (|-> ($p) (index-atom $p 0)))
     (foldl-atom $weights 0.0 +)))

;Scale every weight so the mass is one; a distribution:
(= (ws-normalize $ps)
   (if (== $ps ())
       ()
       (let $t (ws-total $ps)
            (if (<= (abs-math $t) 0.0)
                (Error $ps "ws-normalize requires nonzero total mass")
                (map-atom $ps
                  (|-> ($p) ((/ (index-atom $p 0) $t)
                              (index-atom $p 1))))))))

;Softmax with a temperature: scores become a distribution. Low temperature
;sharpens toward the best pair, high temperature flattens toward uniform.
;
;THE PEAK IS SUBTRACTED BEFORE EXPONENTIATING, which is what makes this
;usable on scores a network produced rather than only on a hand-written
;table. Softmax is invariant to a constant shift, so no answer in the safe
;range moves; outside it, exponentiating directly broke at BOTH ends, and
;the two failures look nothing alike:
;
;  (ws-softmax ((1000.0 a) (1001.0 b)) 1.0)     ((NaN a) (NaN b))
;  (ws-softmax ((-1000.0 a) (-1001.0 b)) 1.0)   (Error ... "nonzero total mass")
;
;Both are the same one-unit gap that answers (0.2689 0.7311) at small
;scores. After the shift the largest term is exp(0) exactly, so the mass is
;never zero and never overflows [measured 2026-09-04; the standard remedy,
;the one scipy.special.softmax and every array library apply].
;
;The shift is taken AFTER the division, on the scaled scores, so it holds
;for a negative temperature too: what has to be bounded is the exponent, and
;dividing by a negative temperature reverses which score produces the
;largest one.
(= (ws-peak $ps)
   (let ($h $t) (decons-atom $ps)
     (index-atom (foldl-atom $t $h ws-pickmax) 0)))
(= (ws-softmax $ps $temp)
   (if (<= (abs-math $temp) 0.0)
       (Error $ps "ws-softmax requires a nonzero temperature")
       (if (== $ps ())
           ()
           (let $scaled (map-atom $ps (|-> ($p) ((/ (index-atom $p 0) $temp)
                                                 (index-atom $p 1))))
             (let $peak (ws-peak $scaled)
               (ws-normalize
                 (map-atom $scaled
                   (|-> ($p) ((exp-math (- (index-atom $p 0) $peak))
                              (index-atom $p 1))))))))))

;The pair with more weight, then the best value; the temperature-zero limit:
(= (ws-pickmax $a $b) (if (>= (index-atom $a 0) (index-atom $b 0)) $a $b))
(= (ws-best $ps)
   (let $rest (cdr-atom $ps)
     (let $first (car-atom $ps)
       (let $best (foldl-atom $rest $first ws-pickmax)
         (index-atom $best 1)))))

;Pairs sorted best-first, and the first k of them, beam search's keep rule:
(= (ws-ranked $ps) (reverse (sort-atom $ps)))
(= (ws-take $ps $k)
   (if (or (== $ps ()) (<= $k 0))
       ()
       (let ($h $t) (decons-atom $ps)
            (let $rest (ws-take $t (- $k 1))
              (cons-atom $h $rest)))))
(= (ws-top $ps $k) (ws-take (ws-ranked $ps) $k))

;Draw one value with probability proportional to its weight: the annotated
;disjunction's choice, executed.
(= (ws-sample! $ps)
   (ws-sample-walk $ps (random-float 0.0 (ws-total $ps))))
(= (ws-sample-walk $ps $u)
   (let ($h $t) (decons-atom $ps)
        (if (or (== $t ()) (< $u (index-atom $h 0)))
            (index-atom $h 1)
            (ws-sample-walk $t (- $u (index-atom $h 0))))))

;Merge pairs carrying the same value, adding their weights: the summing of
;explanations for one conclusion.
(= (ws-merge-into $acc $p)
   (if (== $acc ())
       ($p)
       (let ($h $t) (decons-atom $acc)
            (if (== (index-atom $h 1) (index-atom $p 1))
                (let $summed (+ (index-atom $h 0) (index-atom $p 0))
                  (let $value (index-atom $h 1)
                    (cons-atom ($summed $value) $t)))
                (let $rest (ws-merge-into $t $p)
                  (cons-atom $h $rest))))))
(= (ws-collapse $ps) (foldl-atom $ps () ws-merge-into))

;The expected value of a numeric weighted superposition:
(= (ws-expect $ps)
   (let $terms (map-atom $ps (|-> ($p) (* (index-atom $p 0) (index-atom $p 1))))
     (foldl-atom $terms 0.0 +)))

;Nondeterministic reading: each pair is one alternative, measure as data:
(= (ws-choose $ps) (superpose $ps))

;Pairs above a weight, and (score value) from (value score), for sources
;such as knn retrieval that answer value-first:
(= (ws-filter $ps $least)
   (filter-atom $ps (|-> ($p) (>= (index-atom $p 0) $least))))
(= (ws-flip $ps)
   (map-atom $ps (|-> ($p) ((index-atom $p 1) (index-atom $p 0)))))
