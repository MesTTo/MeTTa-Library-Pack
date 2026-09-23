% Purpose: load lib_crypto's private checked OpenSSL predicates.
% Guarantees: library import either loads the complete adapter or raises
% [tested: test_native_build_is_atomic_and_reused; commit=28c6146d805b5adba3047ffc72b2508c11816636].

:- module(lib_crypto_native,
          [digest/4, random_bytes/2, random_below_hex/2,
           password_iterations/2, password_hash/4, password_verify/5]).
:- use_module(native_build, [native_object/1]).
:- use_module('../../_support/native_install', [native_install/2]).
:- native_install(native_object, install_lib_crypto).
