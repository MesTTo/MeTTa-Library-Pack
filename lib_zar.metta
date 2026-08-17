;Prolog interop: predicate-style consult/use_module wrappers.
;
;consult_global and use_module_global rather than consult and use_module,
;because a Prolog library belongs to the process rather than to a space: SWI
;loads a file into the module the load runs in, and under per-space equations a
;runnable runs in its space's module, where register_fun/1 cannot see the
;arities. See the note on consult_global/1 in src/metta.pl.
;
;The path is %Undefined% rather than Atom so it can be computed. Atom means the
;argument arrives unevaluated, which is right for a literal but stops
;(consult_file (string-join "/" ($dir "f.pl"))) from ever working.
(: consult_file (-> %Undefined% %Undefined%))
(= (consult_file $prologfile)
   (callPredicate (Predicate (quote (consult_global $prologfile)))))

(: use_module_file (-> %Undefined% %Undefined%))
(= (use_module_file $prologfile)
   (callPredicate (Predicate (quote (use_module_global $prologfile)))))

;Import Prolog functions from a file (predicate-style, no main.pl wrappers needed)
;
;The name list is checked BEFORE the source loads and registered
;all-or-nothing after, which is the same two engine predicates lib_import's
;spelling calls. Registering inside the superpose loop was two defects at
;once: a file defining a builtin's name had already replaced the engine's
;predicate by the time the refusal could fire, and a typo anywhere in the list
;left every earlier name registered with no way to learn which.
(: import_prolog_functions_from_file_pred (-> %Undefined% Expression %Undefined%))
(= (import_prolog_functions_from_file_pred $prologfile $importfunctions)
   (let* (($checked (check_prolog_function_names $importfunctions $prologfile))
          ($ok (consult_file $prologfile)))
         (import_prolog_functions $importfunctions)))

;Expression, not Atom. The second parameter is a list of names in both of
;these, and declaring one Atom and the other Expression made two functions that
;do the same thing disagree about the same argument. Upstream declares both
;Expression.
;
;The declaration describes the argument rather than deciding how it is
;compiled: prolog_function_importer/1 in src/translator.pl names all four
;importer spellings, and the translator keeps their name list literal before
;typed dispatch is reached. It has to. Without it a list holding a name that
;had already become a function compiled to a CALL, so a second import
;mentioning an already-registered name answered nothing at all.
(: import_prolog_functions_from_module_pred (-> %Undefined% Expression %Undefined%))
(= (import_prolog_functions_from_module_pred $prologfile $importfunctions)
   (let* (($checked (check_prolog_function_names $importfunctions $prologfile))
          ($ok (use_module_file $prologfile)))
         (import_prolog_functions $importfunctions)))
