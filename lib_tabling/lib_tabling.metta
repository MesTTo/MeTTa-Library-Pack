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
;Live declarations reflect into &metta as (tabled space name arity)
;facts, input arity, so (match &metta (tabled $s $f $a) ...) lists what
;is tabled right now. Undeclaring removes the fact, and clearing or
;dropping a space removes its declarations, tables and all: tabling
;state never outlives the space life that declared it. On a threaded SWI the
;tables are shared between engines, so the live Python Answers cursor, a
;source run and the statistics door reuse the same answer trie. On the
;threads-disabled swipl-wasm used by the Node seat, each run's SWI engine owns
;its trie: forms in one run reuse answers, while a later run recomputes them.
;
;HOW a function is tabled is a catalog row, (cache Name Policy), whose words
;are the cache-policy vocabulary: plain, incremental, monotonic, lazy, shared,
;private, subsumptive, (lattice Join), (max-answers N), (subgoal-abstract N),
;(answer-abstract N), one word or a list of them, as in
;(cache f (monotonic lazy)). The row is the declaration: it installs the table
;for every arity the name is defined at, now or when the equations arrive, and
;removing it takes the table away again; (tabled ...) installs under the
;standing row's policy or, with no row, the default, which is incremental over
;a body whose reads the engine can watch and plain otherwise. A row the engine
;cannot honour is refused naming the remedy and never lands: a watch over a
;body the effect walk cannot classify, a foreign read under a watch, a second
;watch on a space predicate another table already watches, lazy without
;monotonic, two words of one class, a shared or watched lattice, a watched
;subsumptive. force and refuse are lib_memo's words in the same vocabulary and
;stand alone in their row. examples/ch18-performance/18-02-memoisation-and-tabling/13
;to 16 walk each policy.

!(import! &self (library lib_import))
!(import_prolog_functions_from_file (library lib_tabling.pl)
  (metta_tabled_decl metta_untabled_decl metta_table_clear metta_table_clear_all
   metta_table_statistics))

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

;(table-stats (reach $x $y)) answers what this function's tables have
;actually done, as ((tables 1) (answers 2) (complete-call 2)
;(invalidated 1) (reevaluated 1) (policy (incremental shared))), the last
;pair being the cache policy in force while the table is declared: the watch,
;the thread word, and every further word the (cache ...) row compiled to.
;
;The pair worth reading is invalidated against reevaluated. A write to a
;space a tabled function reads invalidates its table, and the next call
;re-evaluates it; reevaluated LOWER than invalidated is SWI having decided
;a dependency changed without changing this table's answers, which is the
;incremental win rather than a rebuild. Before this the guarantee was only
;testable by its effect, a fresh answer, which a table rebuilt from
;scratch produces too.
(: table-stats (-> Atom Expression))
(= (table-stats $call) (metta_table_statistics (quote $call)))
