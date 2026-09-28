; Purpose: load Prolog support and expose source imports as queryable data.
; Guarantees: imports and unimport! share the engine's source ownership journal
; [tested: lib_import_lifecycle; commit=4f2d6c0f8eb293b73f8dde30a1c84e24834f7393].
;
; (match (imports &space) (import $path) $path) lists canonical source paths.
; The read-only view follows committed imports without adding payload atoms.
; (unimport! &space $path) removes that source's surviving atom occurrences
; and compiled definitions, preserving equal atoms added by other owners.
; Repeating undo returns true. Deleted source files can still be withdrawn.
; A package goes with its own files, the package-relative files its manifest
; requires, each unless the program or another package still asks for it
; [tested 2026-09-29T05:34:02+10:00:
; packages:withdrawing_a_package_withdraws_its_own_files,
; packages:a_package_file_the_program_also_imported_survives_the_package,
; packages:a_file_two_packages_require_stays_until_the_last_goes].
; Every other nested import, the packages a manifest requires among them,
; has independent ownership and remains until withdrawn.
; Undo covers recorded native atoms, including those added by runnable forms;
; it does not reverse external I/O or unload Prolog/Python modules.

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

!(import_prolog_functions_from_file (library lib_import/lib_import.pl) (static-import! use-module! imports unimport!))

;Documentation, as atoms. A @doc form is inert data, and get-doc/help!
;are engine builtins now, so writing AND reading docs needs no import.
(@doc import_prolog_functions_from_file
      (@desc "Consults a Prolog file and registers the named predicates as MeTTa functions")
      (@params ((@param "the Prolog file, as (library dir/name.pl) or a path")
                (@param "the predicate names to register")))
      (@return "unit"))
(@doc import_prolog_functions_from_module
      (@desc "Loads a Prolog module and registers the named predicates as MeTTa functions")
      (@params ((@param "the Prolog module, as (library dir/name.pl) or a path")
                (@param "the predicate names to register")))
      (@return "unit"))

(@doc imports
      (@desc "A live read-only space of (import CanonicalPath) atoms for the destination's committed MeTTa source imports; query with (match (imports &space) (import $path) $path)")
      (@params ((@param "the destination space")))
      (@return "Space"))
(@doc unimport!
      (@desc "Withdraw one MeTTa source's surviving native atoms and compiled definitions, and a package's own files with it, the package-relative files its manifest requires that nothing else still asks for; equal atoms from other owners survive. Repeats return true and deleted source paths work. Other nested imports, the packages a manifest requires among them, remain independently imported. Does not reverse external I/O or unload host modules")
      (@params ((@param "the destination space")
                (@param "the imported module path, including a path returned by imports")))
      (@return "true"))
