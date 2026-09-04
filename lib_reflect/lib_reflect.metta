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

;Where a name came from: (builtin), (special-form), (prolog "file.pl"),
;(python det), (specialization <name>), or (equation <module>). A flat list of
;function names cannot tell an equation from a registered Prolog predicate,
;which is the question a collision raises and the one a library asks to verify
;its own installation.
;
;(specialization <name>) is the one the ENGINE wrote. Evaluating a
;higher-order call stores a generated equation under a name like
;twice_Spec_[inc], and those atoms save and digest like any other, so a tool
;showing a program what it holds had no way to tell them from source and
;presented engine bookkeeping as the program. The detail is the name being
;specialized, which is what a reader wants next.
(: origin-of (-> %Undefined% Expression))
(= (origin-of $name) (engine-origin $name))

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
