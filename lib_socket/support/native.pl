% Purpose: load socket ownership, metadata, shutdown and complete datagram input.
% Guarantees: import loads the complete adapter or raises a named build refusal.
% [tested: lib_socket; commit=781ee98e188c23ea7ef9298636d6e5e6c7fdc727].

:- module(lib_socket_native,
          [kind/2,endpoint/5,receive/5,shutdown/2,accept_owner/1,try_accept/4,
           finish_accept/2,abort_accept/1,abort/1,monotonic/1]).
:- use_module(library(shlib), [load_foreign_library/2]).
:- use_module(native_build, [native_object/1]).
:- native_object(Object), load_foreign_library(Object, install_lib_socket).
