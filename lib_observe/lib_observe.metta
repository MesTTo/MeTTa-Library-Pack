; Purpose: make execution observations queryable with match and get-atoms.
!(import! &self (library lib_import))
!(import_prolog_functions_from_file (library lib_observe.pl) (trace-source observe-source))

(: trace-source (-> SpaceType String Atom Number SpaceType))
(@doc trace-source
      (@desc "Run source in a space and return a space of trace-event atoms. The filter is all or a tuple of exact function names. The limit counts only selected events. trace-stopped records false or the exhausted bound. Evaluation performs the source's writes.")
      (@params ((@param "the execution space")
                (@param "MeTTa source text")
                (@param "all or a tuple of function names")
                (@param "positive event limit")))
      (@return "a space of (trace-event seq time depth kind term answer) and (trace-stopped reason) atoms"))


(: observe-source (-> SpaceType String String SpaceType))
(@doc observe-source
      (@desc "Run source with coverage and error diagnostics. Source coordinates are one-based Unicode codepoint locations, with exclusive ends. Reports include binary source-coverage flags (0 unexecuted, 1 executed), unchanged source-error values, and source-frame atoms. A generated-by attribution identifies the construct which generated a closure; source-coverage-unavailable explains sites without an independent counter. source-function-unavailable and source-frame-unavailable identify code that has no captured source map. Completed root-form answers survive a later exception. Ordinary execution outside this operation retains no diagnostic state. The source performs its writes in the execution space.")
      (@params ((@param "the execution space")
                (@param "a source label")
                (@param "MeTTa source text")))
      (@return "a queryable space of observation-status, observation-answer, observation-exception, source-coverage, source-coverage-unavailable, source-function-unavailable, source-error, source-frame, and source-frame-unavailable atoms"))
