;Upstream's own skeleton module, the one it ships to show what a built-in
;module is: three declarations, one MeTTa equation, and one grounded
;operation, so a single import exercises every tier at once.
;
;Transcribed from `builtin_mods/skel.metta` and `skel.rs` at
;hyperon-experimental@3f76dc4, by way of the arbiter's own transcription
;[source: LeaTTa MettaHyperonFull/Minimal/Interpreter.lean, skelBuiltin;
;tests/semantics/grounded/28-builtin-module-skel.metta, STATUS conforms].
;The native operation's type is the one skel.rs gives its
;GroundedFunctionAtom, `expr!("->" ("PairType" ta tb) ("PairType" tb ta))`,
;written here as an ordinary declaration because that is how a grounded
;operation's type reaches a space in this engine.

(: PairType (-> $ta $tb Type))
(: Pair (-> $ta $tb (PairType $ta $tb)))

(: skel-swap-pair (-> (PairType $ta $tb) (PairType $tb $ta)))
(= (skel-swap-pair (Pair $a $b)) (Pair $b $a))

(: skel-swap-pair-native (-> (PairType $ta $tb) (PairType $tb $ta)))
!(import! &self (library lib_import))
!(import_prolog_functions_from_file (library "builtin_mods/skel.pl")
  (skel-swap-pair-native))
