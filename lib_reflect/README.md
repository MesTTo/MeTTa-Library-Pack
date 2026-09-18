# Literal code and the engine surface

Import Reflect to inspect declarations or manipulate terms without executing
their contents. Replacement rules are an ordinary relation of `(From To)` pairs.

```metta
!(import! &self (library lib_reflect))
!(test (atom-replace (+ 1 2) ((1 one))) (noeval (+ one 2)))
!(test (atom-replace (f a) (((f a) root) (a child))) root)
!(test (atom-replace (a a) ((a b) (b c))) (b b))
!(test (collapse (atom-replace (a a) ((a b) (a c)))) ((b b) (b c) (c b) (c c)))
!(test (collapse (atom-replace a ((a b) (a b)))) (b b))
!(test (atom-replace a ((a (Error data code)))) (noeval (Error data code)))
!(test (== (atom-variables ($x ($y $x) $z)) (quote ($x $y $z))) True)
!(test (== (atom-replace ($x $y $x) (($x $z))) (quote ($z $y $z))) True)
```

A root match stops that subtree. A replacement is final for the current pass,
and every matching row contributes an answer, including identical rows. Other
occurrences choose their replacements independently. Expression heads are
children too. Empty relations preserve the original term. Malformed pair rows
and cyclic host terms raise through the shared collection checks.

Variable keys compare by identity. Replacing `$x` does not bind an unrelated
`$y`, and comparing `(f $x)` with `(f $y)` does not make them the same term.
`atom-variables` includes every written variable, even inside binder syntax.
Neither operation implements lexical free-variable analysis or capture-avoiding
substitution.

The implementation is available to `match`, like any other equation. A relation
read from a Space can supply the rules directly:

```metta
(rename old new)
(rename old alternative)
!(test
   (let $rules (collapse (match &self (rename $from $to) (quote ($from $to))))
     (collapse (atom-replace (call old) $rules)))
   (noeval ((call new) (call alternative))))
!(test
   (let $source
        (match &self (= (atom-variables $term) $body)
          (quote (|-> ($term) $body)))
     (let $inspect (eval $source)
       (== ($inspect (quote ($x $x))) (quote ($x))))) True)
```

Strategy supplies the traversal, independently of the rule. `alltd` tries the
root and descends only when the rule declines. `topdown` also visits newly
returned children; `bottomup` visits children before their parent. Rules can be
named functions, lambdas or partial applications. A rule declines by producing
no answer, for example with `(empty)`. The symbol `Empty` remains an ordinary
literal result. An unknown function application is irreducible data in MeTTa.

Core answer collection prunes a bare `Empty` result. Strategy protects its
internal result bags with one-element expressions. Use the same composition
when collecting literal replacements that may themselves be `Empty`:

```metta
!(test (collapse (let $result (atom-replace a ((a Empty) (a b)))
                   (noeval ($result))))
       (noeval ((Empty) (b))))
```

```metta
!(test (alltd (|-> ($node)
                (if (== $node a) (noeval (+ 1 2)) (empty)))
             (f a))
       (noeval (f (+ 1 2))))
!(test (seq (+ 1 2)) (noeval (+ 1 2)))
!(test (collapse (choice (+ 1 2))) ())
!(test (atom-replace a ((a Empty))) (noeval Empty))
```

`seq` and `choice` take any number of strategies before their final literal
operand. Their held plans are `(seq Rule ...)` and `(choice Rule ...)`.
`strategy-repeat` rewrites until failure; Functional's `repeat` requests a
numeric count. A held `(repeat Rule)` remains a rewrite plan.

Small collection operations compose the existing basis:

| Operation | Composition and distinction |
| --- | --- |
| Enumerate literal elements | `index-atom` over `range 0 (size-atom ...)` preserves order and duplicates. `superpose-bind` instead decodes binding rows produced by `collapse-bind`. |
| Exact membership | `lib_sets`'s `set-member` compares by identity. `is-member` instead unifies. |
| Membership under another equality | Enumerate with `index-atom`, apply the chosen comparator, and combine the verdicts with `forall`. Use `=alpha` for equal variable-sharing structure up to renaming. |
| Stable union | Bind the result of `union-atom`, then apply `unique-atom` to that literal value. |
| Subset | `forall` over the left collection with exact membership in the right. |
| Written variables | `atom-variables` composes `flatten-deep`, `filter-atom`, `is-var` and `unique-atom`. |
| Syntactic negation | A structural `case` unwraps `(Not Term)` or constructs it. Quote both subject and keys when their contents could execute as functional patterns. |
| Exact simultaneous replacement | `atom-replace` composes `alltd` and `pairs-lookup`. |

The historical `is-alpha-member` name does not mean `=alpha` membership: its
implementation tests unifiability with a special bare-variable case. Use the
comparison whose variable behavior the caller needs. `atom-subst` substitutes
one written variable in a template; it is distinct from an arbitrary-term
replacement relation.

Python exposes the same operations through `m.fn.atom_replace` and
`m.fn.atom_variables` after `m += lib.reflect`. The native Python `Atom.vars`,
`Atom.map` and `Atom.subs` APIs are also useful. `map` and `subs` traverse children
before parents, and a substitution dictionary supplies one replacement per key;
they have different traversal and answer multiplicity from `atom-replace`.
Returned unbound variables may acquire fresh printed names during decoding.
Check identity relationships within one MeTTa query, or compare a result together
with its input-variable context up to alpha equivalence. When passing returned
code into an eager parameter in another call, hold it with `S.quote`.

The executable catalog examples are
[Reflect](../../examples/ch08-data/08-03-the-shipped-libraries/14-reflect_lib.metta),
[Strategy](../../examples/ch20-extending-the-engine/20-02-metta-written-in-metta/11-strategy.metta)
and [its internal operations](../../examples/ch20-extending-the-engine/20-02-metta-written-in-metta/13-strategy_internals.metta).
`builtins`, `special-forms`, `functions`, `arity-of` and `origin-of` expose the
engine's current surface as queryable data; `surface-json` derives its JSON view.
