; Purpose: import finite generators for properties expressed with core assertions.
; Guarantees: traversal, verdicts, counting and commitment use the existing
; forall, test, assertEqualToResult, foldall and once operations. This library
; defines no alternative assertion or generator protocol.
; [tested: lib_testing; commit=7fad61bab72098722b27091a94282ff69989920e].
!(import! &self (library lib_combinatorics))

(@doc lib_testing
  (@desc "Compose finite generators with core assertions. (forall (range 0 4) (|-> ($x) (test (>= $x 0) True))) checks four inputs. Use assertEqualToResult for an entire answer bag, retaining duplicates; forall itself asks whether the predicate has a True answer. foldall counts with (|-> ($value $count) (+ $count 1)). once commits to the first answer of a filtered generator. range excludes its upper bound; cartesian-power supplies lists of a chosen length. Quote runnable expressions when they are data, use index-atom to select them, and request fresh variables explicitly with copy_term. No specialized test-forall or witness operation is needed."))
