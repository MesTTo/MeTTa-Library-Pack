; Purpose: prepare grammar data as ordinary nondeterministic MeTTa functions.
; Assumes: grammar forms use the argument kinds in parsing-form; input tokens
; and returned remainders are finite expressions.
; Guarantees: duplicate parses, longest-first repetitions, literal values and
; shared variables survive ordinary function composition.
; [tested: lib_parsing; commit=3c1d074a2069bc150a95cedc1946e0627a17a132].
; Guarantees: grammar-is does not run parsers or recursive reference targets.
; [tested: lib_parsing:checking_a_grammar_does_not_run_its_callbacks; commit=3c1d074a2069bc150a95cedc1946e0627a17a132].
; Fails when: a grammar is malformed, a parser returns the wrong shape, or a
; repeated step consumes no input. Left recursion remains a caller contract.
; Owns resources: only expressions and function values; no ambient parser state.
; Decides: character classes are ASCII; ambiguity is preserved as answers.

!(import! &self (library lib_pairs))
!(import! &self (library lib_string))
!(import! &self (library "_support/parsing.metta"))

(: grammar-parser (-> Atom %Undefined%))
(= (grammar-parser $grammar)
   (let $analysis (parsing-analyze $grammar)
     (case (noeval (quote $analysis))
       (((quote (Ready $parser)) (quote $parser))
        ((quote (Invalid $bad))
         (assertEqualMsg False True
           (quote (grammar-parser "use a well-formed grammar from grammar-forms" $bad))))))))
(@doc grammar-parser
  (@desc "Prepare a held grammar as an ordinary unary function over a finite expression of input tokens. Each answer is (Contribution Remainder), with () for a skipped contribution or (Value) for a retained literal value. Apply it with apply-to, compose it with let, or inspect and rewrite its ordinary equations. The function checks result shape and finite remainders. Grammar preparation never runs a parsing callback or ref target; parsing-form metadata supplies names, argument kinds and parsing functions.")
  (@params ((@param "Grammar")))
  (@return "Parser function"))

(: grammar-parse (-> Atom String %Undefined%))
(= (grammar-parse $grammar $text)
   (let* (($parser (grammar-parser $grammar))
          ($input (string-chars $text))
          (($given $rest) (apply-to $parser (quote ($input)))))
     (if (== $rest ()) (parsing-surface $given) (empty))))
(@doc grammar-parse
  (@desc "Parse the whole String with a held grammar. Return one literal value per successful parse and no answer for a mismatch. Validate the grammar before consuming text. Alternatives retain duplicates; many and sep-by try longer parses first. A skipped result surfaces as (). Numeric and text primitives compose String operations; ASCII classes do not depend on the locale.")
  (@params ((@param "Grammar") (@param "Text")))
  (@return "Value"))

(: grammar-parse-prefix (-> Atom String Expression))
(= (grammar-parse-prefix $grammar $text)
   (let* (($parser (grammar-parser $grammar))
          ($input (string-chars $text))
          (($given $rest) (apply-to $parser (quote ($input))))
          ($value (parsing-surface $given))
          ($suffix (string-from-chars (quote $rest))))
     (quote ($value $suffix))))
(@doc grammar-parse-prefix
  (@desc "Parse a prefix and return (Value UnreadString), one answer per match. Repetition keeps longest-first order and all shorter alternatives. Literal Error, Empty, executable expressions and shared variables remain values. A repeated parser that fails to shorten its input raises an assertion with an input-consumption remedy.")
  (@params ((@param "Grammar") (@param "Text")))
  (@return "Value and remainder"))

(: grammar-is (-> Atom Bool))
(= (grammar-is $grammar)
   (let $analysis (parsing-analyze $grammar)
     (case (noeval (quote $analysis))
       (((quote (Ready $_parser)) True)
        ((quote (Invalid $_bad)) False)))))
(@doc grammar-is
  (@desc "Whether the held value is a well-formed grammar under parsing-form metadata. Validate argument count, literal String fields and recursive grammar positions; callback and tag values remain opaque. Ref targets and parsing functions do not run. Empty cat and alt are valid. Host-injected cycles or improper expression tails refuse before traversal.")
  (@params ((@param "Grammar")))
  (@return "Boolean"))

(: grammar-forms (-> Expression))
(= (grammar-forms)
   (collapse
     (match &self (parsing-form $name $kinds $_function)
       (let $arity (if (== $kinds (quote (Parsers))) * (collections-size $kinds))
         (quote ($name $arity))))))
(@doc grammar-forms
  (@desc "Return the (Name Arity) rows from the same parsing-form metadata that prepares grammars. Cat and alt accept zero or any number of grammars and report *. The stock vocabulary has fourteen primitives and twelve combinators; a new distinct metadata name can supply an ordinary parsing function with the same contribution/remainder contract.")
  (@params ())
  (@return "Grammar forms"))
