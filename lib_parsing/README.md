# Grammars and callable parsers

```metta
!(import! &self (library lib_parsing))
!(grammar-parse (cat (integer) (skip (lit ",")) (integer)) "12,34")
; (12 34)
!(collapse (grammar-parse-prefix (many (any)) "ab"))
; ((("a" "b") "") (("a") "b") (() "ab"))
```

A grammar is a held expression. `cat` sequences its parts; `alt` keeps every
matching alternative, including duplicates. Both accept zero or any number of
parts. A mismatch has no answers. `grammar-is` checks a grammar without running
its parsing callbacks or recursive `ref` targets. `grammar-forms` reads the same
metadata used to prepare grammars.

`grammar-parser` returns a written lambda over a finite expression of tokens.
Its answers are `(Contribution Remainder)`: `()` contributes nothing, while
`(Value)` contributes one literal value. That slot keeps `Error`, `Empty`,
executable expressions and shared variables separate from skipping. The text
doors surface a skipped result as `()` and join the unread character tokens.

```metta
!(let $parser (grammar-parser (any))
   (apply-to $parser (quote (((+ 1 2) Empty)))))
; (((+ 1 2)) (Empty))
```

The parser is code you can store, match, rewrite and apply. Its preparation and
composition are MeTTa equations over String, Pairs and Functional. A custom form
adds one metadata row and an ordinary parsing function:

```metta
(parsing-form pure-value (Atom) keep-value)
(: keep-value (-> Atom Atom Expression))
(= (keep-value $value $input) (quote (($value) $input)))
!(grammar-parse (pure-value (+ 1 2)) "")
; (+ 1 2)
```

Metadata argument kinds are `Atom` for a held value, `Text` for a literal String
prepared as character tokens, and `Parser` for a nested grammar. The sole
`(Parsers)` signature prepares any number of nested grammars as one collection.
The function receives those prepared arguments followed by the input. Each name
must have one metadata row. Functions may be names, lambdas or partial
applications; callback and tag arguments are opaque during grammar validation.

Parser results must have the contribution/remainder shape, with finite input
and remainder expressions. Repeated steps must shorten their input. A nullable
`many` or a nullable separator-and-part pair raises an assertion with a
consumption remedy. Left-recursive grammars remain the caller's responsibility.
Character classes are ASCII; use `(char-if Function)` for another class.
Number and integer lexing retain the decimal rules of the original library.

```python
from metta import MeTTa, S, lib

with MeTTa() as context:
    m = context.self
    m += lib.parsing
    parser = m.fn.grammar_parser(S.any()).one()
    literal = S["+"](1, 2)
    assert m.fn.apply_to(parser, S.quote(((literal, S.Empty),))) == [
        ((literal,), (S.Empty,)),
    ]
```

Python receives the same written lambda. Quote a runnable token collection
when supplying it to the eager `apply-to` argument. The
[executable example](../../examples/ch08-data/08-03-the-shipped-libraries/27-parsing_lib.metta)
also reconstructs `grammar-parser` from its retained equation.
