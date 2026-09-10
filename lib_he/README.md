# lib_he

Importing lib_he installs the vendored upstream equations and shadows the prelude in the receiving space. Its assertion equations compare individual answers; the engine prelude compares answer bags. Its add-reduct rewrites an equation and returns the add-atom Boolean; the engine prelude stores a reduced atom and returns that atom.

The MeTTa file is byte-identical to `tests/conformance/petta/lib/lib_he.metta`.
The prelude agrees with the vendored `if-equal`, `if-equal2`, `match-types`,
`match-type-or` and `return-on-error` equations. Programs that require the
engine's bag assertions or reduced-atom result use the prelude directly.
