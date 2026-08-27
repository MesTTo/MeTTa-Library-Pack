; Purpose: preserve the old lib_doc import path after its vocabulary moved
; into the engine.
; Guarantees:
;   - importing this file adds no duplicate definitions
;     [tested: prelude_docs:the_old_library_import_is_a_noop].
; Open Obligations:
;   To Do: None
;   Hacks: None
;   Future Enhancements: None
;
;Documentation, MeTTa HE's vocabulary. Everything this library defined
;is part of the core engine now, so a program reaches all of it with no
;import at all; importing this file remains a no-op so existing programs
;keep working unchanged.
;
;The design was already the right one and the promotion keeps it:
;documentation is ATOMS IN A SPACE, (@doc name (@desc ...) ...) is data
;a program writes and can reason about, and retrieval is a match. The
;constructors are unchanged and still inert: @doc, @desc, @param,
;@params, @return, @type, @item, @kind.
;
;What moved, and what each gained on the way:
;
;  get-doc     with one input resolves the raw document against the CURRENT
;              context rather than the literal &self this library matched,
;              and falls back to the engine's own doc register, where the
;              prelude documents its vocabulary; get-doc-space selects any
;              space. With a space and an atom, get-doc and its atom,
;              function, single-atom, and parameter helpers build upstream's
;              formal documentation shape from that space alone.
;  help!       prints every doc the resolver answers, engine vocabulary
;              included, and says so when there is none.
;  documented  program-scoped on purpose, with documented-space for a
;              selected space: "what have I documented" is a question
;              about the program, and an engine padding the answer with
;              its own names would bury yours.
;  defined-name  every function the current space defines, builtins
;              excluded, via the engine's own registry rather than a
;              match over equations.
;  undocumented  defined names with no documentation anywhere, the gap
;              worth closing; undocumented-space selects a space. This
;              library excluded its own names only by an accident of
;              load order; the engine excludes its vocabulary by the
;              registry.
