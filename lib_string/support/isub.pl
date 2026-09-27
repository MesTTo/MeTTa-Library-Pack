% Purpose: load lib_string's ISub half, the native object isub_native.cpp
%   builds, whose scorer is LGPL-2.0-or-later code, as its own shared object.
% Assumes: loaded only where the engine's census reads the isub capability
%   present, which lib_string.pl checks before loading this file; a host that
%   links foreign code statically links no ISub half, and native_install/2
%   would refuse this file there [source 2026-09-27T22:20:42+10:00: lib/lib_string/lib_string.pl,
%   lib/_support/native_install.pl:native_install/2].
% Guarantees: imports load the object or raise string_isub_native_build naming
%   the tools that build it [tested 2026-09-27T22:15:47+10:00: test_native_build_is_atomic_and_reused].

:- module(lib_string_isub_native, [substring_similarity/5]).
:- use_module(native_build, [isub_object/1]).
:- use_module('../../_support/native_install', [native_install/2]).
:- native_install(isub_object, install_lib_string_isub).
