;lib_import owns import_prolog_functions_from_file. This library used to carry
;its own copy of the definition, so a program importing both got TWO equations
;for one function: (collapse (import_prolog_functions_from_file ...)) answered
;(true true) and every named predicate was consulted and registered twice.
!(import! &self (library lib_import))

!(import_prolog_functions_from_file
    (library lib_memo.pl)
    (memoize config-memoize get-memoize-config clear-memoize invalidate-memoize is-memoized get-memoize-stats clear-memoize-stats))
