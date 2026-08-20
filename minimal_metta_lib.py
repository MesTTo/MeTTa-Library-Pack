"""Purpose: load minimal MeTTa's instruction set. It lives in
`minimal_metta_lib.metta` and `minimal_metta_lib.pl`; this module is the
Python entry point for callers that already import it.

The four operations that cannot be written in MeTTa, `function`,
`collapse-bind`, `superpose-bind` and `unify-mod`, used to be defined here as
grounded Python operations. Two things were wrong with that. Every evaluation
step crossed the janus boundary, and `function` ran an evaluation loop calling
back into the engine once per step. And a program run through `run.sh` or the
packaged CLI has no Python in the loop at all, so the language's own inference
control was unavailable exactly where the engine runs on its own.

Measured 2026-08-15, one harness, min-of-5, on the trivial case
`(function (return 42))` which runs no evaluation loop whatsoever:

    Python operation      36.14 inferences   3.95us   5.01x a plain function
    Prolog predicate      11.14 inferences   0.21us   1.55x a plain function

3.2x fewer inferences and 18.8x faster in wall clock, and the wall-clock cost
against a plain MeTTa function falls from 24.65x to 1.30x.

Assumes: the engine can reach `lib/lib_import.metta`, which is how the MeTTa
  half registers the Prolog half [tested: tests/prolog/prolog_interface.plt].
Guarantees:
  - install(m) is idempotent and returns the names it registered
    [tested: test_minimal_lib_install_is_idempotent_after_cross_file_traffic;
    commit=WORKTREE]
  - the instruction set is available without this module, through
    `!(import! &self (library minimal_metta_lib))`
    [tested: examples/libraries/minimal_metta.metta]
Fails when: nothing. A missing file or an unregistrable name raises from the
  import itself, naming the path or the predicate.
Owns: nothing. The registrations belong to the process, as every Prolog
  library loaded from MeTTa does.
Open Obligations:
  To Do: None
  Hacks: None
  Future Enhancements: None
"""

from __future__ import annotations

import os

__all__ = ["install", "NAMES"]

NAMES = (
    "function",
    "collapse-bind",
    "superpose-bind",
    "unify-mod",
)


def install(m, *, load_metta: bool = True) -> tuple[str, ...]:
    """Load the instruction set on `m` and return the operation names.

        from petta import MeTTa
        import minimal_metta_lib
        m = MeTTa()
        minimal_metta_lib.install(m)
        m.run('!(function (return 42))')          # [[42]]

    Equivalent, and with no Python involved:

        !(import! &self (library minimal_metta_lib))

    Pass load_metta=False to register only the operations, which is what the
    MeTTa half's own tests do to keep the two halves separable.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    if load_metta:
        m.load(os.path.join(here, "minimal_metta_lib.metta"))
    else:
        m.register_prolog(
            path=os.path.join(here, "minimal_metta_lib.pl"), names=NAMES
        )
        # Atom on a parameter is what makes an argument arrive unevaluated,
        # which every instruction here needs. superpose-bind is deliberately
        # left undeclared: its argument is a collapse-bind result and must
        # arrive evaluated.
        m.run("(: function (-> Atom %Undefined%))")
        m.run("(: unify-mod (-> Atom Atom Atom Atom %Undefined%))")
        m.run("(: collapse-bind (-> Atom %Undefined%))")
    return NAMES
