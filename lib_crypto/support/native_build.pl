% Purpose: locate and build the checked OpenSSL adapter for lib_crypto.
% Guarantees: builds use the shared atomic publication and cancellation protocol
% [tested: test_native_build_is_atomic_and_reused,
% test_cancelled_build_waits_for_its_compiler_and_discards_the_stage; commit=WORKTREE].
% Decides: OpenSSL 3 supplies the algorithms; missing build dependencies raise
% crypto_native_build with the installation and prebuild commands
% [tested: test_native_build_is_atomic_and_reused; commit=WORKTREE].

:- module(lib_crypto_native_build, [native_object/1]).
:- use_module(library(filesex), [directory_file_path/3]).
:- use_module('../../_support/native_build', []).

native_object(Object) :-
    source_file(native_object(_), Recipe),
    file_directory_name(Recipe, Support),
    directory_file_path(Support, 'crypto_native.c', Source),
    catch(native_build:native_object(Source, [], Recipe, crypto, ['-lcrypto'], Object),
          Error,
          throw(error(crypto_native_build(Error),
                      context(lib_crypto_native_build:native_object/1,
                              'Install SWI-Prolog development tools, a C compiler and OpenSSL 3 development headers (Debian/Ubuntu: build-essential swi-prolog-nox libssl-dev). Give the library .native directory write access, then run: swipl -q -s lib/lib_crypto/support/native_build.pl -g "lib_crypto_native_build:native_object(_)" -t halt. Prebuild with library(process) and the same SWI ABI before deploying a reduced platform.')))).
