; Purpose: expose the resident automatic and explicit memoization controls.
; Assumes: engine/metta.pl has already loaded lib_memo.pl into user.
; Guarantees: importing this facade registers the public controls without
;   reconsulting lib_memo.pl and erasing its live automatic-cache decisions
;   [tested:
;   test_a_doubly_branching_recursion_is_tabled_automatically_and_a_tail_recursion_is_not;
;   commit=9e7d5dc2cad810940e5386d52636ac6946df279d].
;
; lib_import owns import_prolog_functions_from_file. This library used to carry
; its own copy of the definition, so a program importing both got TWO equations
; for one function: (collapse (import_prolog_functions_from_file ...)) answered
; (true true) and every named predicate was consulted and registered twice.
!(import! &self (library lib_import))

!(import_prolog_function memoize)
!(import_prolog_function config-memoize)
!(import_prolog_function get-memoize-config)
!(import_prolog_function clear-memoize)
!(import_prolog_function invalidate-memoize)
!(import_prolog_function is-memoized)
!(import_prolog_function get-memoize-stats)
!(import_prolog_function clear-memoize-stats)
