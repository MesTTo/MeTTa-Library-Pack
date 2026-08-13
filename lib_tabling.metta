;Expert-only tabling control. Tabling memoizes a function at the engine
;level: same call, cached answers, with answer ORDER and DUPLICATES
;normalized away and answers reused until cleared. That is only sound for
;a function that is pure (no space writes, state, output, randomness,
;Python calls), whose equations and read spaces stay frozen while its
;tables live, whose callers never observe order or multiplicity, and
;whose call modes stay bounded. Declaring anything else tabled changes
;its meaning; the admission burden is yours. See ai-tabling-review.md in
;the workspace for the probe evidence behind every one of those words.
;
;Every operation is a constructed, module-qualified goal, never source
;text, so hyphenated and uppercase names work, a named space's functions
;instrument their own module, declarations are cumulative and idempotent,
;and each operation verifies its effect and errors loudly otherwise.
;Declare AFTER defining the function; tabling a name that does not exist
;yet is refused by name and arity.
;
;Live declarations reflect into &petta as (tabled space name arity)
;facts, input arity, so (match &petta (tabled $s $f $a) ...) lists what
;is tabled right now. Undeclaring removes the fact, and clearing or
;dropping a space removes its declarations, tables and all: tabling
;state never outlives the space life that declared it.

!(import! &self (library lib_import))
!(import_prolog_functions_from_file (library lib_tabling.pl)
  (metta_tabled_decl metta_untabled_decl metta_table_clear metta_table_clear_all))

;Keep arbitrary Prolog-source loading available for experts; tabling no
;longer rides through it.
(= (injectPrologCode $code)
   (progn (translatePredicate (open_string $code $S))
          (translatePredicate (load_files user ((Predicate (stream $S)))))
          True))

;(tabled (fib $n)) tables fib at its compiled arity in the module that
;defines it.
(: tabled (-> Atom Bool))
(= (tabled $call) (metta_tabled_decl (quote $call)))

;(untabled (fib $n)) removes the instrumentation again.
(: untabled (-> Atom Bool))
(= (untabled $call) (metta_untabled_decl (quote $call)))

;(table-clear (fib $n)) abolishes this function's cached answers and
;keeps the declaration; every other table stands.
(: table-clear (-> Atom Bool))
(= (table-clear $call) (metta_table_clear (quote $call)))

;(table-clear-all) abolishes every table in the process.
(: table-clear-all (-> Bool))
(= (table-clear-all) (metta_table_clear_all))
