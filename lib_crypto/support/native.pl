% Purpose: load lib_crypto's private checked OpenSSL predicates.
% Guarantees: library import either loads the complete adapter or raises
% [tested: test_native_build_is_atomic_and_reused; commit=WORKTREE].

:- module(lib_crypto_native,
          [digest/4, random_bytes/2, random_below_hex/2,
           password_iterations/2, password_hash/4, password_verify/5]).
:- use_module(library(shlib), [load_foreign_library/2]).
:- use_module(native_build, [native_object/1]).
:- native_object(Object), load_foreign_library(Object, install_lib_crypto).
