% Purpose: load the private stream-owned database lock operation.
% Guarantees: import loads its provider or raises a named build refusal.
% [tested: lib_database; commit=060bea3199e9f504c6d425f60841f229fc96e861].

:- module(lib_database_native, [claim_stream/2]).
:- use_module(native_build, [native_object/1]).
:- use_module('../../_support/native_install', [native_install/2]).
:- native_install(native_object, install_lib_database).
