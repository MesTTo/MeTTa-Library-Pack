% Purpose: distinguish a written symbol from grounded values for soft scoring.
% Assumes: engine/parser.pl represents booleans as true/false and symbols as
%   textual atoms; seam:host_object/1 identifies extension values
%   [source: engine/metta/types.pl:metatype_of/2; commit=WORKTREE].
% Guarantees: function registration does not change soft-symbol?; variables,
%   expressions and grounded values are refused [tested: sh engine/test.sh
%   suites/libraries/lib_soft.plt; commit=WORKTREE].

% atom/1 is a representation test, independent of the function registry.
% SWI-Prolog V10.0.0 documents this test independently of predicate existence:
% https://github.com/SWI-Prolog/swipl-devel/blob/V10.0.0/man/builtin.doc#L1831-L1832
'soft-symbol?'(Value, Result) :-
    (   atom(Value),
        Value \== true,
        Value \== false,
        \+ seam:host_object(Value)
    ->  Result = true
    ;   Result = false
    ).
