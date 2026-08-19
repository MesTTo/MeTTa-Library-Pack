% Purpose: the grounded tier of upstream's `skel` built-in module, the one
%   operation that makes the module exercise every tier at once.
% Guarantees:
%   - skel-swap-pair-native/2 answers `(Pair b a)` for `(Pair a b)` and
%     nothing for anything else, which is what upstream's
%     GroundedFunctionAtom does [tested: builtin_modules].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

%The grounded twin of the module's equation, and deliberately the same answer:
%what the corpus reads from the pair is that a built-in module carries both
%tiers, not that they differ [source: LeaTTa
%tests/semantics/grounded/28-builtin-module-skel.metta, whose two calls answer
%`(Pair b a)` alike].
'skel-swap-pair-native'(['Pair', A, B], ['Pair', B, A]).
