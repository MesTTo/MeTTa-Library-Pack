% Purpose: build the private socket adapter with the shared atomic builder.
% Guarantees: a failed build raises with a repair and prebuild command.
% [tested: lib_socket; commit=7b42d5ee5cecb82709617b7ed08dfa2c1441f268].
% Owns resources: native_build:native_object/6 owns compiler, stage and locks.

:- module(lib_socket_native_build, [native_object/1]).
:- use_module(library(filesex), [directory_file_path/3]).
:- use_module('../../_support/native_build', []).

native_object(Object) :-
    source_file(native_object(_), Recipe),
    file_directory_name(Recipe, Support),
    directory_file_path(Support, 'socket_native.c', Source),
    ( current_prolog_flag(windows,true) -> Links=['-lws2_32'] ; Links=[] ),
    catch(native_build:native_object(Source,[],Recipe,socket,Links,Object),
          Error,
          throw(error(socket_native_build(Error),
                      context(lib_socket_native_build:native_object/1,
                              'Install SWI-Prolog development tools and a C compiler. Give lib_socket/.native write access, then run: swipl -q -s lib/lib_socket/support/native_build.pl -g "lib_socket_native_build:native_object(_)" -t halt. Prebuild with library(process) and the same SWI ABI before deploying a reduced platform.')))).
