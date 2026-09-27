% Purpose: build lib_string's two native objects, the permissive half
%   (string_native.cpp) and the ISub half (isub_native.cpp), each tracking every
%   header it includes.
% Guarantees: header changes invalidate the shared atomic build cache.
% [tested 2026-09-27T22:15:47+10:00: test_native_header_change_rebuilds_the_object].
% Decides: missing native tools raise string_native_build, or
%   string_isub_native_build for the ISub half, with a prebuild remedy.
% [tested 2026-09-27T22:15:47+10:00: test_native_build_is_atomic_and_reused].

:- module(lib_string_native_build, [native_object/1, isub_object/1]).
:- use_module(library(filesex), [directory_file_path/3]).
:- use_module(library(readutil), [read_file_to_string/3]).
:- use_module(library(apply), [maplist/3, exclude/3]).
:- use_module(library(lists), [member/2]).
:- use_module('../../_support/native_build', []).

native_object(Object) :-
    string_object(native_object, permissive, Object).

isub_object(Object) :-
    string_object(isub_object, isub, Object).

%Each half's source and the stem its object is named by.
half(permissive, 'string_native.cpp', string).
half(isub, 'isub_native.cpp', string_isub).

%Which vendored headers each half includes: ISub's scorer, the one
%LGPL-2.0-or-later header, only the ISub half.
includes(permissive, Path) :- Path \== "isub.hpp".
includes(isub, "isub.hpp").

string_object(Goal, Half, Object) :-
    half(Half, File, Stem),
    source_file(native_object(_), Recipe),
    file_directory_name(Recipe, Support),
    directory_file_path(Support, File, Source),
    directory_file_path(Support, 'string_boundary.hpp', Boundary),
    directory_file_path(Support, '../vendor', Vendor),
    catch(( directory_file_path(Vendor, 'SHA256SUMS', Manifest),
            read_file_to_string(Manifest, Text, []),
            split_string(Text, "\n", "", Lines0), exclude(=(""), Lines0, Lines),
            maplist(manifest_path, Lines, Paths),
            findall(Header,
                    (member(Path, Paths), file_name_extension(_, hpp, Path),
                     includes(Half, Path), directory_file_path(Vendor, Path, Header)),
                    Headers),
            atom_concat('-I', Vendor, Include),
            native_build:native_object(Source, [Manifest, Boundary|Headers], Recipe, Stem,
                                       ['-cc-options,-std=c++11', Include], Object) ),
          Error,
          (   atom_concat(Stem, '_native_build', Name),
              Refusal =.. [Name, Error],
              format(atom(Remedy),
                     'Install SWI-Prolog development tools and a C++11 compiler (Debian/Ubuntu: build-essential swi-prolog-nox). Give the library .native directory write access, then run: swipl -q -s lib/lib_string/support/native_build.pl -g "lib_string_native_build:~w(_)" -t halt. Prebuild with library(process) and the same SWI ABI before deploying a reduced platform.',
                     [Goal]),
              throw(error(Refusal, context(lib_string_native_build:Goal/1, Remedy)))
          )).

manifest_path(Line, Path) :-
    ( sub_string(Line, 64, 2, _, "  "), sub_string(Line, 66, _, 0, Path), Path \== ""
    -> true
    ; throw(error(domain_error(native_source_manifest, Line), _))
    ).
