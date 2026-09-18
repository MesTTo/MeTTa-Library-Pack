% Purpose: build the stream-owned database lock with the shared atomic builder.
% Guarantees: build failures name the dependency repair and prebuild command.
% [tested: lib_database; commit=060bea3199e9f504c6d425f60841f229fc96e861].
% Owns resources: native_build:native_object/6 owns compiler, stage and locks.

:- module(lib_database_native_build, [native_object/1]).
:- use_module(library(filesex), [directory_file_path/3]).
:- use_module('../../_support/native_build', []).

native_object(Object) :-
    source_file(native_object(_),Recipe),file_directory_name(Recipe,Support),
    directory_file_path(Support,'lock.c',Source),
    catch(native_build:native_object(Source,[],Recipe,database,[],Object),
          Error,
          throw(error(database_native_build(Error),
                      context(lib_database_native_build:native_object/1,
                              'Install SWI-Prolog development tools and a C compiler. Give lib_database/.native write access, then run: swipl -q -s lib/lib_database/support/native_build.pl -g "lib_database_native_build:native_object(_)" -t halt. Prebuild with library(process) and the same SWI ABI before deploying a reduced platform.')))).
