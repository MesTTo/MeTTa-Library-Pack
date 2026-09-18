; Purpose: inspect the engine's surface and manipulate literal terms as data.
; Guarantees: origin-of projects get-property's occurrence origins, including
;   deferred definitions [tested: head_properties:origin_of_delegates_without_forcing_a_definition; commit=90ba93eb8f6e98ebfefc55416859bf13de6a8427].
; Guarantees: atom-variables retains first-appearance identity; atom-replace
; composes topmost traversal and exact pair lookup, preserving literal values,
; shared variables and every duplicate replacement answer.
; [tested: lib_reflect_terms; commit=505ce25b9384e782afa26f621527d4b1fd695924].
; Fails when: term traversal receives cyclic host data or replacement rows are
; malformed; the shared finite-expression and pair checks report the refusal.
; Decides: all written variables count, including variables inside binder syntax.
; Substitution is simultaneous and structural, without lexical capture avoidance.
;
;The engine's own surface, as data you can match.
;
;Two consumers want this and both currently guess. metta-lsp computes its
;diagnostics against MeTTaScript's builtin list rather than this engine's, and the
;documentation surface has no way to enumerate what it ought to document. A
;list maintained in two places drifts; a list the engine answers cannot.
;
;(builtins) answers every builtin name, one per solution, so collapse it for a
;tuple. (special-forms) answers the translator's forms, which are NOT builtins
;and appear in no registry: hyperpose, timeout, let, case and the rest are
;COMPILED rather than called, which is exactly why a tool that knows only the
;builtin list gets them wrong. (functions) is everything, (user-functions) is
;what this space defines itself.
;
;(arity-of $name) answers the registered arities, (knows? $name) answers True
;or False so it guards a query, and (surface-counts) is the cheap health check.
;
;(surface-json) is the whole thing as a JSON string, which is what an external
;tool consumes. It is built here out of the accessors plus lib_json, so the
;Prolog half never needs to know that JSON exists.

!(import! &self (library lib_import))
!(import! &self (library lib_json))
!(import! &self (library lib_pairs))
!(import! &self (library lib_strategy))
!(import_prolog_functions_from_file (library lib_reflect.pl)
  (engine-builtin engine-special-form engine-arity engine-function
   engine-user-function engine-knows engine-origin engine-extension-point
   engine-surface-counts))

(@doc builtins (@desc "Every builtin name, one per solution"))
(= (builtins) (engine-builtin))

(@doc special-forms
      (@desc "Every translator special form, one per solution. These are compiled rather than called, so they are in no registry"))
(= (special-forms) (engine-special-form))

(@doc functions (@desc "Every function the engine knows, builtin or not"))
(= (functions) (engine-function))

(@doc user-functions (@desc "Every function this space defines itself"))
(= (user-functions) (engine-user-function))

(@doc arity-of
      (@desc "The registered arities for a name, one per solution")
      (@params ((@param "the name")))
      (@return "an arity"))
(= (arity-of $name) (engine-arity $name))

(@doc knows?
      (@desc "Whether the engine knows a name at all, as True or False")
      (@params ((@param "the name")))
      (@return "True or False"))
(= (knows? $name) (engine-knows $name))

;An origin names the defining space and the available source position. The
;engine-origin compatibility door still reports implementation tiers.
(@doc origin-of
      (@desc "The (origin space file line) rows from get-property, one per defining occurrence; an unavailable line is -1"))
(: origin-of (-> Atom Expression))
(= (origin-of $name)
   (let (origin $space $file $line) (get-property $name)
     (origin $space $file $line)))

;Every extension point the engine declares, as (name arity kind). The kind
;says what a handler may do in it: an event or declaration seam has every
;clause read, so a cut in one silently disables every clause after it, while
;an ownership seam is claimed by the first handler that succeeds and a cut
;after a guard proving the request is yours belongs there.
(@doc extension-points
      (@desc "Every extension point the engine declares, as (name arity kind), one per solution")
      (@return "(name arity kind)"))
(= (extension-points) (engine-extension-point))

(@doc surface-counts
      (@desc "How many builtins, special forms, functions and user functions")
      (@return "((key count) ...)"))
(= (surface-counts) (engine-surface-counts))

;The export an external tool consumes. Built out of the accessors and
;lib_json, so nothing in the Prolog half knows about JSON.
(@doc surface-json
      (@desc "The engine's whole surface as a JSON string, for external tools")
      (@return "a JSON string"))
;A footgun worth knowing: dict-space evaluates its pairs, so a key that
;NAMES A FUNCTION gets called. Writing (builtins (collapse (builtins))) asks
;the engine to call builtins/1, which does not exist, and the error names an
;arity rather than the real problem. The keys below are deliberately not
;function names, and the values are bound first so the pairs are already data.
(= (surface-json)
   (let* (($builtin-names (collapse (builtins)))
          ($special-form-names (collapse (special-forms)))
          ($user-function-names (collapse (user-functions))))
     (json-encode
       (dict-space ((builtinNames $builtin-names)
                    (specialFormNames $special-form-names)
                    (userFunctionNames $user-function-names))))))

(: atom-variables (-> Atom Expression))
(= (atom-variables $term)
   (unique-atom
     (filter-atom (flatten-deep (quote ($term))) $leaf (is-var $leaf))))
(@doc atom-variables
  (@desc "Every written variable once, in first-appearance order, preserving its identity and sharing with the original term. Inspect literal contents, including expression heads and binder syntax. This is structural inspection, not lexical free-variable analysis.")
  (@params ((@param "Term")))
  (@return "Variables"))

(: atom-replace (-> Atom Atom %Undefined%))
(= (atom-replace $term $replacements)
   (let* (($finite (collections-size (quote ($term))))
          ($checked (unzip (quote $replacements))))
     (alltd (|-> ($node) (pairs-lookup (quote $replacements) (quote $node))) $term)))
(@doc atom-replace
  (@desc "Replace exact subterms through a literal (From To) relation. A matching root wins over its descendants; replacement terms are final for this pass. Preserve every matching row as an alternative, including duplicates, and form all combinations across different occurrences. Compare by identity without unifying unrelated variables. Empty relations return the original term; malformed rows and cyclic host terms raise. This does not implement lexical capture avoidance.")
  (@params ((@param "Term") (@param "Replacements")))
  (@return "Every simultaneously replaced term"))
