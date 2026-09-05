; Purpose: make execution observations queryable with match and get-atoms.
!(import! &self (library lib_import))
!(import_prolog_functions_from_file (library lib_observe.pl) (trace-source))

(: trace-source (-> SpaceType String Atom Number SpaceType))
(@doc trace-source
      (@desc "Run source in a space and return a space of trace-event atoms. The filter is all or a tuple of exact function names. The limit counts only selected events. trace-stopped records false or the exhausted bound. Evaluation performs the source's writes.")
      (@params ((@param "the execution space")
                (@param "MeTTa source text")
                (@param "all or a tuple of function names")
                (@param "positive event limit")))
      (@return "a space of (trace-event depth kind term answer) and (trace-stopped reason) atoms"))
