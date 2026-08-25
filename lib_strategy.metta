; Purpose: provide a Stratego-style strategy basis whose plans are ordinary
;   MeTTa terms and whose application is lowered by the translator.
;
;   !(import! &self (library lib_strategy))
;
; Assumes: `minimal_metta_lib` supplies function, collapse-bind, and
;   superpose-bind, while the engine supplies id and the atom decomposition
;   operations. A named strategy declines by answering no result, conventionally
;   through an equation whose body is Empty.
; Guarantees: id, fail, seq, choice, try, repeat, all, one, topdown, bottomup,
;   innermost, stratego-all, and stratego-one are reified atom families. Applying
;   one through strategy-apply lowers to strategy-eval; it never installs a host
;   callback [tested: sh test.sh examples/libraries/strategy.metta; commit=WORKTREE]
; Fails when: a strategy used under repeat keeps succeeding forever, including an
;   identity success. Stratego's repeat has the same progress obligation.
; Decides: choice is left-biased over result bags. stratego-one follows LeaTTa by
;   returning every successful immediate-child position rather than committing
;   to the first. Written expression heads count as children, as they do in
;   LeaTTa's flat MeTTa term model.
;
; The controlling laws come from the Stratego library at immutable commit
; 35009963ebc99c4fa8c93cae064309186a877d0e:
; https://github.com/metaborg/stratego/blob/35009963ebc99c4fa8c93cae064309186a877d0e/strategolib/trans/strategy/conditional.str2
; https://github.com/metaborg/stratego/blob/35009963ebc99c4fa8c93cae064309186a877d0e/strategolib/trans/strategy/iteration.str2
; https://github.com/metaborg/stratego/blob/35009963ebc99c4fa8c93cae064309186a877d0e/strategolib/trans/strategy/traversal/simple.str2
; https://github.com/metaborg/stratego/blob/35009963ebc99c4fa8c93cae064309186a877d0e/strategolib/trans/strategy/traversal/fixpoint.str2

!(import! &self (library minimal_metta_lib))

(: strategy-eval (-> Atom Atom %Undefined%))
(: strategy-all (-> Atom Atom Atom))
(: strategy-all-tail (-> Atom Expression Expression))
(: strategy-one (-> Atom Atom Atom))
(: strategy-apply (-> Atom Atom %Undefined%))

; all(s) applies s to every immediate child. It is identity on leaves and the
; empty expression, and the complete traversal fails when any child declines.
(= (strategy-all $strategy $x)
   (function
     (chain (eval (get-metatype $x)) $kind
       (unify $kind Expression
         (eval (if-equal $x ()
           (return ())
           (chain (decons-atom $x) $head-tail
             (unify ($head $tail) $head-tail
               (chain (eval (strategy-eval $strategy $head)) $head-result
                 (chain (eval (strategy-all-tail $strategy $tail)) $tail-result
                   (chain (cons-atom $head-result $tail-result) $result
                     (return $result))))
               (return $x)))))
         (return $x)))))

(= (strategy-all-tail $strategy $tail)
   (function
     (eval (if-equal $tail ()
       (return ())
       (chain (decons-atom $tail) $head-tail
         (unify ($head $rest) $head-tail
           (chain (eval (strategy-eval $strategy $head)) $head-result
             (chain (eval (strategy-all-tail $strategy $rest)) $tail-result
               (chain (cons-atom $head-result $tail-result) $result
                 (return $result))))
           (return $tail)))))))

; one(s) applies s at exactly one immediate child. The two segment gaps enumerate
; every position, so MeTTa exposes every success in left-to-right order. A leaf,
; empty expression, or all-declining child strategy answers no result.
(= (strategy-one $strategy ((:seg $before) $child (:seg $after)))
   (function
     (chain (eval (strategy-eval $strategy $child)) $child-result
       (return ((:seg $before) $child-result (:seg $after))))))
(= (strategy-one $strategy $leaf) Empty)

; Plans are dispatched in one ordered equation. Separate equations plus a
; catch-all would overlap under MeTTa's relational equation semantics and add a
; spurious answer to every recognized constructor.
(= (strategy-eval $strategy $term)
   (function
     ; id(t) = t.
     (unify $strategy id
       (return $term)
       ; fail(t) has no result.
       (unify $strategy fail
         (empty)
         ; seq(s1,s2)(t) = s1(t) followed by s2.
         (unify (seq $first $second) $strategy
           (chain (eval (strategy-eval $first $term)) $middle
             (chain (eval (strategy-eval $second $middle)) $result
               (return $result)))
           ; choice(s1,s2) = s1 <+ s2: use s2 only when all s1 branches fail.
           (unify (choice $left $right) $strategy
             (chain (collapse-bind (strategy-eval $left $term)) $left-results
               (unify $left-results ()
                 (chain (eval (strategy-eval $right $term)) $result
                   (return $result))
                 (chain (superpose-bind $left-results) $result
                   (return $result))))
             ; try(s) = choice(s,id).
             (unify (try $inner) $strategy
               (chain (eval (strategy-eval (choice $inner id) $term)) $result
                 (return $result))
               ; repeat(s) = choice(seq(s,repeat(s)),id).
               (unify (repeat $inner) $strategy
                 (chain (collapse-bind (strategy-eval $inner $term)) $results
                   (unify $results ()
                     (return $term)
                     (chain (superpose-bind $results) $next
                       (chain (eval (strategy-eval (repeat $inner) $next)) $result
                         (return $result)))))
                 ; all(s) is the universal immediate-child traversal.
                 (unify (all $inner) $strategy
                   (chain (eval (strategy-all $inner $term)) $result
                     (return $result))
                   ; stratego-all is the public LeaTTa spelling of all.
                   (unify (stratego-all $inner) $strategy
                     (chain (eval (strategy-all $inner $term)) $result
                       (return $result))
                     ; one(s) is the one-immediate-child traversal.
                     (unify (one $inner) $strategy
                       (chain (eval (strategy-one $inner $term)) $result
                         (return $result))
                       ; stratego-one is the public LeaTTa spelling of one.
                       (unify (stratego-one $inner) $strategy
                         (chain (eval (strategy-one $inner $term)) $result
                           (return $result))
                         ; topdown(s) = seq(s,all(topdown(s))).
                         (unify (topdown $inner) $strategy
                           (chain (eval (strategy-eval
                                          (seq $inner (all (topdown $inner)))
                                          $term))
                             $result
                             (return $result))
                           ; bottomup(s) = seq(all(bottomup(s)),s).
                           (unify (bottomup $inner) $strategy
                             (chain (eval (strategy-eval
                                            (seq (all (bottomup $inner)) $inner)
                                            $term))
                               $result
                               (return $result))
                             ; innermost(s) = bottomup(try(seq(s,innermost(s)))).
                             (unify (innermost $inner) $strategy
                               (chain (eval (strategy-eval
                                              (bottomup
                                                (try (seq $inner
                                                          (innermost $inner))))
                                              $term))
                                 $result
                                 (return $result))
                               ; A Symbol denotes a user strategy equation. Compound
                               ; plans not recognized above fail instead of becoming a
                               ; variable-headed call.
                               (chain (eval (get-metatype $strategy)) $kind
                                 (unify $kind Symbol
                                   (chain (context-space) $space
                                     (chain (metta ($strategy $term)
                                                   %Undefined% $space)
                                       $result
                                       (return $result)))
                                   (empty))))))))))))))))))

; strategy-apply is the only lowering door. Its expansion is another atom, so
; the runtime plan remains language data and no Python or Prolog callback is
; minted per strategy.
(= (strategy-apply $strategy $term)
   (noeval (strategy-eval $strategy $term)))
!(add-translator-rule! strategy-apply)

; Direct call spellings adapt the same reified plans to ordinary MeTTa calls.
; `id` itself is already the engine's identity operation, so the library does
; not shadow it with a second equation.

(: fail (-> Atom %Undefined%))
(= (fail $term) (strategy-apply fail $term))

(: seq (-> Atom Atom Atom %Undefined%))
(= (seq $first $second $term)
   (strategy-apply (seq $first $second) $term))

(: choice (-> Atom Atom Atom %Undefined%))
(= (choice $left $right $term)
   (strategy-apply (choice $left $right) $term))

(: try (-> Atom Atom %Undefined%))
(= (try $strategy $term) (strategy-apply (try $strategy) $term))

; gtry is LeaTTa's generic binary try spelling. Its law is try(s)(t).
(: gtry (-> Atom Atom Atom))
(= (gtry $strategy $term)
   (function
     (chain (eval (strategy-eval (try $strategy) $term)) $result
       (return $result))))

(: repeat (-> Atom Atom %Undefined%))
(= (repeat $strategy $term) (strategy-apply (repeat $strategy) $term))

(: all (-> Atom Atom %Undefined%))
(= (all $strategy $term) (strategy-apply (all $strategy) $term))

(: one (-> Atom Atom %Undefined%))
(= (one $strategy $term) (strategy-apply (one $strategy) $term))

(: topdown (-> Atom Atom %Undefined%))
(= (topdown $strategy $term) (strategy-apply (topdown $strategy) $term))

(: bottomup (-> Atom Atom %Undefined%))
(= (bottomup $strategy $term) (strategy-apply (bottomup $strategy) $term))

(: innermost (-> Atom Atom %Undefined%))
(= (innermost $strategy $term) (strategy-apply (innermost $strategy) $term))

(: stratego-all (-> Atom Atom Atom))
(= (stratego-all $strategy $term)
   (function
     (chain (eval (strategy-eval (stratego-all $strategy) $term)) $result
       (return $result))))

(: stratego-one (-> Atom Atom Atom))
(= (stratego-one $strategy $term)
   (function
     (chain (eval (strategy-eval (stratego-one $strategy) $term)) $result
       (return $result))))

; Lämmel's TP scheme is type-preserving: its accepted arrow has one sort on
; both sides. TU(r) is type-unifying: every accepted arrow returns r. The
; operational collapse-bind declaration already shipped by minimal MeTTa stays
; authoritative; redeclaring it as TU would change eager argument evaluation.
(: TP Type)
(: TU (-> Type Type))

; s ◁ TP @ t applies s only when t has the input sort of a type-preserving s.
; s ◁ TU(r) @ t applies s only when t fits an s whose output sort is r.
(: ◁ (-> Atom Type Atom Atom))
(= (◁ $strategy $target $term)
   (function
     (unify $target TP
       (chain (eval (strategy-typed-tp $strategy $term)) $result
         (return $result))
       (unify (TU $unified) $target
         (chain (eval (strategy-typed-tu $strategy $unified $term)) $result
           (return $result))
         (return Empty)))))

(: strategy-typed-tp (-> Atom Atom Atom))
(= (strategy-typed-tp $strategy $term)
   (function
     (chain (context-space) $space
       (chain (match $space (: $strategy (-> $sort $sort)) $sort) $expected
         (chain (eval (strategy-typed-apply $strategy $expected $term)) $result
           (return $result))))))

(: strategy-typed-tu (-> Atom Type Atom Atom))
(= (strategy-typed-tu $strategy $unified $term)
   (function
     (chain (context-space) $space
       (chain (match $space (: $strategy (-> $sort $unified)) $sort) $expected
         (chain (eval (strategy-typed-apply $strategy $expected $term)) $result
           (return $result))))))

; The two schemes differ only in how they select an input sort. Once selected,
; both apply the same gradual type check before running the reified strategy.
(: strategy-typed-apply (-> Atom Type Atom Atom))
(= (strategy-typed-apply $strategy $expected $term)
   (function
     (chain (context-space) $space
       (chain (eval (get-type-space $space $term)) $actual
         (unify $actual (Error $_actual-atom $_actual-message)
           (return $actual)
           (chain (eval (match-types $expected $actual True False)) $fits
             (unify $fits True
               (chain (eval (strategy-eval $strategy $term)) $result
                 (return $result))
               (return Empty))))))))
