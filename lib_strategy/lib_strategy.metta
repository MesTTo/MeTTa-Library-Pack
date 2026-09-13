; Purpose: compose literal term rewrites through ordinary MeTTa functions.
; Guarantees: held plans and terms preserve variable sharing, literal runnable
; contents and every alternative. Strategy application lowers to an inspectable
; equation rather than a host callback [tested: lib_strategy, lib_reflect_terms;
; commit=WORKTREE].
; Assumes: terms are finite; a callable strategy declines by producing no answer.
; Guarantees: literal Empty is an ordinary result, distinct from (empty).
; [tested: lib_reflect_terms:empty_symbol_is_a_value_and_not_strategy_failure;
; commit=WORKTREE].
; Fails when: repeat or innermost keeps succeeding without reaching a normal
; form, including a rule that always returns its input.
; Decides: choice uses the first nonempty answer bag. Expression heads are
; children, and one answers every successful immediate-child position.
; The direct strategy-repeat name distinguishes rewriting until failure from
; Functional's numeric repeat. The held plan (repeat Rule) is unchanged.
;
; Traversal laws follow Stratego at commit35009963ebc99c4fa8c93cae064309186a877d0e:
; https://github.com/metaborg/stratego/blob/35009963ebc99c4fa8c93cae064309186a877d0e/strategolib/trans/strategy/traversal/simple.str2
; MeTTa retains complete answer bags and treats function values as ordinary data.

!(import! &self (library minimal_metta_lib))

(: strategy-eval (-> Atom Atom %Undefined%))
(: strategy-all (-> Atom Atom %Undefined%))
(: strategy-all-tail (-> Atom Atom %Undefined%))
(: strategy-one (-> Atom Atom %Undefined%))
(: strategy-apply (-> Atom Atom %Undefined%))

; A bound operand already is a value. Rebuilding a metta call would evaluate it
; again for an eager callback; ordinary application preserves the literal.
; Quote the subject and its case keys because unquoted keys are functional
; patterns and would execute seq or turn all into a partial application.
; One ordered case avoids overlapping constructor and fallback equations.
; Collect each result inside a one-element expression: answer aggregation
; prunes bare Empty, while the wrapper preserves it as literal data until
; superpose-bind restores the answer's bindings. Choice uses the same shape.
(= (strategy-eval $strategy $term)
   (if (is-var $strategy) (empty)
     (case (noeval (quote $strategy))
       (((quote id) (noeval $term))
        ((quote fail) (empty))
        ((quote (seq (:seg $steps)))
         (foldl-atom $steps $term $value $step (strategy-eval $step $value)))
        ((quote (choice (:seg $steps))) (strategy-choice-tail $steps $term))
        ((quote (try $inner)) (strategy-eval (choice $inner id) $term))
        ((quote (repeat $inner))
         (let $hits (collapse-bind
                      (let $value (strategy-eval $inner $term) (noeval ($value))))
           (if (== $hits ()) (noeval $term)
             (let ($next) (superpose-bind $hits)
               (strategy-eval (repeat $inner) $next)))))
        ((quote (all $inner)) (strategy-all $inner $term))
        ((quote (stratego-all $inner)) (strategy-all $inner $term))
        ((quote (one $inner)) (strategy-one $inner $term))
        ((quote (stratego-one $inner)) (strategy-one $inner $term))
        ((quote (topdown $inner))
         (strategy-eval (seq $inner (all (topdown $inner))) $term))
        ((quote (bottomup $inner))
         (strategy-eval (seq (all (bottomup $inner)) $inner) $term))
        ((quote (innermost $inner))
         (strategy-eval (bottomup (try (seq $inner (innermost $inner)))) $term))
        ((quote (alltd $inner))
         (strategy-eval (choice $inner (all (alltd $inner))) $term))
        ($_
         (let $callable
           (if (== (get-metatype $strategy) Expression)
             (eval $strategy) (noeval $strategy))
           ($callable $term)))))))
(@doc strategy-eval
  (@desc "Apply a held rewrite plan or callable value to a literal term. Named functions, lambdas and partial applications use ordinary application. An unbound strategy declines. Preserve every answer and its bindings, including literal Empty; (empty) produces no answer.")
  (@params ((@param "Strategy") (@param "Term")))
  (@return "Rewritten term"))

(: strategy-choice-tail (-> Atom Atom %Undefined%))
(= (strategy-choice-tail $steps $term)
   (if (== $steps ()) (empty)
     (let ($first (:seg $rest)) (noeval $steps)
       (let $hits (collapse-bind
                    (let $value (strategy-eval $first $term) (noeval ($value))))
         (if (== $hits ()) (strategy-choice-tail $rest $term)
           (let ($answer) (superpose-bind $hits) (noeval $answer)))))))
(@doc strategy-choice-tail
  (@desc "Apply held strategies in order until one has answers, then return that complete bag. An empty sequence declines. Shared bindings survive collapse-bind and superpose-bind.")
  (@params ((@param "Strategies") (@param "Term")))
  (@return "First nonempty answer bag"))

(= (strategy-all $strategy $term)
   (if (== (get-metatype $term) Expression)
     (strategy-all-tail $strategy $term) (noeval $term)))
(@doc strategy-all
  (@desc "Rewrite every immediate child, including an expression's head. A leaf and the empty expression are identities. A declining child ends that combination; branching children produce every combination.")
  (@params ((@param "Strategy") (@param "Term")))
  (@return "Rebuilt term"))

(= (strategy-all-tail $strategy $items)
   (if (== (get-metatype $items) Expression)
     (map-atom $items $child (strategy-eval $strategy $child)) (empty)))
(@doc strategy-all-tail
  (@desc "Map a strategy over a literal expression through map-atom. Unlike strategy-all, a non-expression declines.")
  (@params ((@param "Strategy") (@param "Items")))
  (@return "Rebuilt expression"))

(= (strategy-one $strategy $term)
   (if (== (get-metatype $term) Expression)
     (let ((:seg $before) $child (:seg $after)) (noeval $term)
       (let $changed (strategy-eval $strategy $child)
         (union-atom $before (cons-atom $changed $after)))) (empty)))
(@doc strategy-one
  (@desc "Rewrite exactly one immediate child, answering every successful position from left to right. Preserve other children literally. Leaves, empty expressions and all-declining children have no answer.")
  (@params ((@param "Strategy") (@param "Term")))
  (@return "One-position rewrite"))

; This translator rule expands into another MeTTa call; stored plans remain data.
(= (strategy-apply $strategy $term) (noeval (strategy-eval $strategy $term)))
!(add-translator-rule! strategy-apply)
(@doc strategy-apply
  (@desc "Lower a held strategy application to strategy-eval through the ordinary translator-rule door.")
  (@params ((@param "Strategy") (@param "Term")))
  (@return "Every rewrite"))

(: fail (-> Atom %Undefined%))
(= (fail $term) (empty))
(@doc fail (@desc "Decline every term.") (@params ((@param "Term"))) (@return "No answer"))

(: seq (-> Atom (:seg Atom) %Undefined%))
(= (seq (:seg $strategies) $term) (strategy-apply (seq (:seg $strategies)) $term))
(@doc seq
  (@desc "Apply zero or more held strategies from left to right to the final literal term. Zero strategies is identity. A runtime plan is (seq Rule ...).")
  (@params ((@param "Strategies") (@param "Term")))
  (@return "Every composed rewrite"))

(: choice (-> Atom (:seg Atom) %Undefined%))
(= (choice (:seg $strategies) $term) (strategy-apply (choice (:seg $strategies)) $term))
(@doc choice
  (@desc "Use the first strategy with any answers and preserve its whole bag. Accept zero or more held strategies before the final literal term; zero strategies declines.")
  (@params ((@param "Strategies") (@param "Term")))
  (@return "First nonempty answer bag"))

(: try (-> Atom Atom %Undefined%))
(= (try $strategy $term) (strategy-apply (try $strategy) $term))
(@doc try
  (@desc "Apply the strategy, or return the original term when it has no answers.")
  (@params ((@param "Strategy") (@param "Term"))) (@return "Rewrite or original"))

(: gtry (-> Atom Atom %Undefined%))
(= (gtry $strategy $term) (strategy-apply (try $strategy) $term))
(@doc gtry
  (@desc "The generic try spelling: apply a strategy or preserve the original term when it declines.")
  (@params ((@param "Strategy") (@param "Term"))) (@return "Rewrite or original"))

(: strategy-repeat (-> Atom Atom %Undefined%))
(= (strategy-repeat $strategy $term) (strategy-apply (repeat $strategy) $term))
(@doc strategy-repeat
  (@desc "Repeat a rewrite until it declines, retaining every resulting normal form. A rule that always succeeds, including identity, does not terminate. The reified plan is (repeat Rule); numeric repeat remains Functional's operation.")
  (@params ((@param "Strategy") (@param "Term"))) (@return "Normal form"))

(: all (-> Atom Atom %Undefined%))
(= (all $strategy $term) (strategy-apply (all $strategy) $term))
(@doc all
  (@desc "Apply a strategy to all immediate children. Leaves and empty expressions are identities.")
  (@params ((@param "Strategy") (@param "Term"))) (@return "Rebuilt term"))

(: one (-> Atom Atom %Undefined%))
(= (one $strategy $term) (strategy-apply (one $strategy) $term))
(@doc one
  (@desc "Apply a strategy at exactly one child position, preserving every successful position as an answer.")
  (@params ((@param "Strategy") (@param "Term"))) (@return "One-position rewrite"))

(: topdown (-> Atom Atom %Undefined%))
(= (topdown $strategy $term) (strategy-apply (topdown $strategy) $term))
(@doc topdown
  (@desc "Rewrite the root, then recursively visit the children of each result. All visited nodes must succeed; compose try for identity on a declining node. Newly introduced subterms are visited.")
  (@params ((@param "Strategy") (@param "Term"))) (@return "Preorder rewrite"))

(: bottomup (-> Atom Atom %Undefined%))
(= (bottomup $strategy $term) (strategy-apply (bottomup $strategy) $term))
(@doc bottomup
  (@desc "Recursively rewrite children, then their rebuilt parent. All visited nodes must succeed; compose try for identity on a declining node.")
  (@params ((@param "Strategy") (@param "Term"))) (@return "Postorder rewrite"))

(: innermost (-> Atom Atom %Undefined%))
(= (innermost $strategy $term) (strategy-apply (innermost $strategy) $term))
(@doc innermost
  (@desc "Rewrite children before parents and revisit every reduct until no rule applies.")
  (@params ((@param "Strategy") (@param "Term"))) (@return "Normal form"))

(: alltd (-> Atom Atom %Undefined%))
(= (alltd $strategy $term) (strategy-apply (alltd $strategy) $term))
(@doc alltd
  (@desc "Return every root rewrite when the strategy has answers; otherwise descend into every child. A successful replacement is final for this pass, so root matches take precedence over descendant matches. Leaves with no match stay unchanged.")
  (@params ((@param "Strategy") (@param "Term"))) (@return "Topmost rewrites"))

(: stratego-all (-> Atom Atom %Undefined%))
(= (stratego-all $strategy $term) (strategy-apply (all $strategy) $term))
(@doc stratego-all
  (@desc "The Stratego spelling of all: rewrite all immediate children, preserving leaves.")
  (@params ((@param "Strategy") (@param "Term"))) (@return "Rebuilt term"))

(: stratego-one (-> Atom Atom %Undefined%))
(= (stratego-one $strategy $term) (strategy-apply (one $strategy) $term))
(@doc stratego-one
  (@desc "The Stratego spelling of one: answer every successful single-child rewrite.")
  (@params ((@param "Strategy") (@param "Term"))) (@return "One-position rewrite"))

; Lämmel's TP scheme is type-preserving: its accepted arrow has one sort on
; both sides. TU(r) is type-unifying: every accepted arrow returns r. The
; operational collapse-bind declaration already shipped by minimal MeTTa stays
; authoritative; redeclaring it as TU would change eager argument evaluation.
(: TP Type)
(: TU (-> Type Type))
(@doc TP (@desc "The type-preserving strategy scheme: accept a declared arrow with the same input and output sort."))
(@doc TU
  (@desc "The type-unifying strategy scheme: accept a declared arrow whose output has the supplied sort.")
  (@params ((@param "Result sort"))) (@return "Strategy scheme"))

; s ◁ TP @ t applies s only when t has the input sort of a type-preserving s.
; s ◁ TU(r) @ t applies s only when t fits an s whose output sort is r.
(: ◁ (-> Atom Type Atom %Undefined%))
(= (◁ $strategy $target $term)
   (case (noeval (quote $target))
     (((quote TP) (strategy-typed-tp $strategy $term))
      ((quote (TU $unified)) (strategy-typed-tu $strategy $unified $term))
      ($_ (empty)))))
(@doc ◁
  (@desc "Apply a declared strategy through TP or TU(ResultSort), filtering its input by the term's type in the current space. Unknown schemes and incompatible types decline.")
  (@params ((@param "Strategy") (@param "Scheme") (@param "Term")))
  (@return "Typed rewrite"))

(: strategy-typed-tp (-> Atom Atom %Undefined%))
(= (strategy-typed-tp $strategy $term)
   (let $space (context-space)
     (let $expected (match $space (: $strategy (-> $sort $sort)) $sort)
       (strategy-typed-apply $strategy $expected $term))))
(@doc strategy-typed-tp
  (@desc "Match a strategy's equal input and output sorts, then apply it when the term fits that sort.")
  (@params ((@param "Strategy") (@param "Term"))) (@return "Typed rewrite"))

(: strategy-typed-tu (-> Atom Type Atom %Undefined%))
(= (strategy-typed-tu $strategy $unified $term)
   (let $space (context-space)
     (let $expected (match $space (: $strategy (-> $sort $unified)) $sort)
       (strategy-typed-apply $strategy $expected $term))))
(@doc strategy-typed-tu
  (@desc "Match a strategy's declared output against the requested result sort, then check its input sort and apply it.")
  (@params ((@param "Strategy") (@param "Result sort") (@param "Term")))
  (@return "Typed rewrite"))

; The two schemes differ only in how they select an input sort. Once selected,
; both apply the same gradual type check before running the reified strategy.
(: strategy-typed-apply (-> Atom Type Atom %Undefined%))
(= (strategy-typed-apply $strategy $expected $term)
   (let $space (context-space)
     (let $actual (get-type-space $space $term)
       (if-error $actual (noeval $actual)
         (if (match-types $expected $actual True False)
           (strategy-eval $strategy $term) (empty))))))
(@doc strategy-typed-apply
  (@desc "Apply a strategy when match-types accepts the term's current-space type against the expected sort. Preserve type errors as values; an incompatible type declines.")
  (@params ((@param "Strategy") (@param "Expected sort") (@param "Term")))
  (@return "Typed rewrite"))
