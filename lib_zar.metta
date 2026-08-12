;Prolog interop: predicate-style consult/use_module wrappers
(= (consult_file $prologfile)
   (callPredicate (Predicate (quote (consult_global $prologfile)))))

(= (use_module_file $prologfile)
   (callPredicate (Predicate (quote (use_module_global $prologfile)))))

;Import Prolog functions from a file (predicate-style, no main.pl wrappers needed)
(: import_prolog_functions_from_file_pred (-> %Undefined% Expression %Undefined%))
(= (import_prolog_functions_from_file_pred $prologfile $importfunctions)
   (let* (($ok (consult_file $prologfile))
          ($function (superpose $importfunctions)))
         (import_prolog_function $function)))

(: import_prolog_functions_from_module_pred (-> %Undefined% Atom %Undefined%))
(= (import_prolog_functions_from_module_pred $prologfile $importfunctions)
   (let* (($ok (use_module_file $prologfile))
          ($function (superpose $importfunctions)))
         (import_prolog_function $function)))
