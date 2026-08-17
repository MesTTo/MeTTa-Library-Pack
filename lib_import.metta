!(import_prolog_function consult_global)

;No (exists_file) guard. It made a missing file fail SILENTLY, with no answer
;and no error, where consult itself throws
;existence_error(source_sink, 'nofile.pl') and names the path. Guarding first
;swallowed that and reported nothing at all.
;
;The names are checked BEFORE the source loads and registered all-or-nothing
;after, which is two rules the engine owns rather than a loop here. Checking
;inside the loop was two separate defects: consulting a file that defines a
;builtin's name had already replaced the engine's predicate by the time the
;refusal fired, and a typo in the third name left the first two registered
;with no way for the caller to learn which.
(= (import_prolog_functions_from_file $prologfile $importfunctions)
   (let* (($checked (check_prolog_function_names $importfunctions $prologfile))
          ($prologfile (consult_global))
          ($registered (import_prolog_functions $importfunctions)))
     $registered))

!(import_prolog_function use_module_global)

(= (import_prolog_functions_from_module $prologfile $importfunctions)
   (let* (($checked (check_prolog_function_names $importfunctions $prologfile))
          ($prologfile (use_module_global))
          ($registered (import_prolog_functions $importfunctions)))
     $registered))

!(import_prolog_functions_from_file (library lib_import.pl) (static-import! use-module!))

;Documentation, as atoms. A @doc form is inert data, so a library can document
;itself without importing lib_doc; only READING the docs needs it.
(@doc import_prolog_functions_from_file
      (@desc "Consults a Prolog file and registers the named predicates as MeTTa functions")
      (@params ((@param "the Prolog file, as (library name.pl) or a path")
                (@param "the predicate names to register")))
      (@return "unit"))
(@doc import_prolog_functions_from_module
      (@desc "Loads a Prolog module and registers the named predicates as MeTTa functions")
      (@params ((@param "the Prolog module, as (library name.pl) or a path")
                (@param "the predicate names to register")))
      (@return "unit"))
