% Purpose: build and locate lib_regex's private PCRE2 binding.
% Guarantees: a successful build replaces the object atomically; failed builds
% leave no stage and preserve an existing object
% [tested: test_native_build_is_atomic_and_reused; commit=7b42d5ee5cecb82709617b7ed08dfa2c1441f268].
% Owns resources: the file lock closes on every exit. An interrupted caller
% waits for its compiler before removing the temporary object
% [tested: test_cancelled_build_waits_for_its_compiler_and_discards_the_stage; commit=7b42d5ee5cecb82709617b7ed08dfa2c1441f268].
% Guarded by: the object-path mutex serializes threads; build.lock serializes
% processes sharing the same library directory
% [tested: test_concurrent_processes_and_threads_publish_one_native_object; commit=7b42d5ee5cecb82709617b7ed08dfa2c1441f268].
% Decides: the native object is local to the library and host SWI ABI
% [source: lib/_support/native_build.pl:native_object/6; commit=7b42d5ee5cecb82709617b7ed08dfa2c1441f268].

:- module(lib_regex_native_build, [native_object/1]).
:- use_module(library(filesex), [directory_file_path/3]).
:- use_module('../../_support/native_build', []).

native_object(Object) :-
    source_file(native_object(_), Recipe),
    file_directory_name(Recipe, Support),
    directory_file_path(Support, '../vendor/pcre4pl.c', Source),
    catch(native_build:native_object(Source, [], Recipe, pcre, ['-lpcre2-8'], Object),
          Error,
          throw(error(regex_native_build(Error),
                      context(lib_regex_native_build:native_object/1,
                              'Install SWI-Prolog development tools, a C compiler and PCRE2 development headers (Debian/Ubuntu: build-essential swi-prolog-nox libpcre2-dev). Give the library .native directory write access, then run: swipl -q -s lib/lib_regex/support/native_build.pl -g "lib_regex_native_build:native_object(_)" -t halt. Prebuild with library(process) and the same SWI ABI before deploying a reduced platform.')))).
