% Purpose: load the private stream-owned database lock operation.
% Guarantees: import loads its provider or raises a named build refusal.
% [tested: lib_database; commit=WORKTREE].

:- module(lib_database_native, [claim_stream/2]).
:- use_module(library(shlib), [load_foreign_library/2]).
:- use_module(native_build, [native_object/1]).
:- native_object(Object), load_foreign_library(Object,install_lib_database).
