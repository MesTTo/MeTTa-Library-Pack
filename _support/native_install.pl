% Purpose: install a library's native half on either kind of SWI-Prolog host:
% one that loads shared objects, and one that links foreign code statically.
% Assumes: the caller's own build goal answers the path of a complete shared
% object for the running ABI (each library's support/native_build.pl), and a
% static host was built with the half by the library's support/static.cmake.
% Guarantees: on a host that loads shared objects, native_install/2 builds and
% loads the object with the named install function, as the libraries did
% through load_foreign_library/2 before; on a static host it activates the
% extension named by what follows install_, needs no build tool and no
% library(shlib), and a host built without that extension raises
% native_extension_missing(Name) naming the rebuild rather than leaving the
% library's foreign predicates undefined
% [tested: examples/ch08-data/08-03-the-shipped-libraries/18-string_lib.metta
% under tsmetta on the host tools/wasm-host/build.sh builds; commit=WORKTREE].
% Decides: a separate module from native_build.pl because that file is an
% input of every native object's build, so an edit to how a half is loaded
% would otherwise rebuild all of them [source: lib/_support/native_build.pl:native_object/6].

:- module(native_install, [native_install/2]).

%A host whose use_foreign_library/1 activates linked extensions, which is the
%test SWI's own boot/syspred.pl makes to choose that definition.
static_host :-
    current_predicate(system:'$activate_static_extension'/1).

%A directive rather than :- if, because this file is compiled to a .qlf and a
%conditional compilation block is decided where the file compiles, not where
%it loads [source: engine/metta.pl, the census's own note on :- if].
:- (   static_host
   ->  true
   ;   use_module(library(shlib), [load_foreign_library/2])
   ).
:- meta_predicate native_install(1, +).

%! native_install(:Object, +Install) is det.
%
% Install a library's native half into the module calling this. Object is the
% library's own build goal, called as call(Object, Path) for the shared object
% to load, and Install is the object's install function. A host that links
% foreign code statically (SWI's STATIC_EXTENSIONS, the WebAssembly build) has
% no shared objects to load: its binary carries the half as the extension
% swipl_plugin named after what follows install_, and activating that
% extension in the calling module is the whole install.
native_install(Module:Object, Install) :-
    (   static_host
    ->  atom_concat(install_, Name, Install),
        catch(@('$activate_static_extension'(Name), Module),
              error(existence_error(foreign_extension, _), _),
              throw(error(native_extension_missing(Name),
                          context(native_install:native_install/2,
                                  'This host links foreign code statically and was built without this library\'s native half. Rebuild it with tools/wasm-host/build.sh, which links every library that carries support/static.cmake.'))))
    ;   call(Module:Object, Path),
        load_foreign_library(Module:Path, Install)
    ).
