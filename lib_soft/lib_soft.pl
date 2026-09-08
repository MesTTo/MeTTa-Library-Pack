% Purpose: distinguish a written symbol from grounded values for soft scoring.
% Assumes: engine/parser.pl represents booleans as true/false and symbols as
%   textual atoms; seam:host_object/1 identifies extension values
%   [source: engine/metta/types.pl:metatype_of/2; commit=4f2d6c0f8eb293b73f8dde30a1c84e24834f7393].
% Guarantees: function registration does not change soft-symbol?; variables,
%   expressions and grounded values are refused [tested: sh engine/test.sh
%   suites/libraries/lib_soft.plt; commit=4f2d6c0f8eb293b73f8dde30a1c84e24834f7393].


:- module(lib_soft,
          [ 'soft-symbol?'/2
          ]).

% Guarantees: private helpers and autoload declarations belong to this module.
% [tested: engine_modules; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
% Assumes: engine operations resolve through metta_engine's published exports.
% [source: engine/metta.pl:metta_engine_reexport/2; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
:- set_module(base(metta_engine)).

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
