% Purpose: build the private String provider and track every included header.
% Guarantees: header changes invalidate the shared atomic build cache.
% [tested: test_native_header_change_rebuilds_the_object; commit=7b42d5ee5cecb82709617b7ed08dfa2c1441f268].
% Decides: missing native tools raise string_native_build with a prebuild remedy.
% [tested: test_native_build_is_atomic_and_reused; commit=7b42d5ee5cecb82709617b7ed08dfa2c1441f268].

:- module(lib_string_native_build, [native_object/1]).
:- use_module(library(filesex), [directory_file_path/3]).
:- use_module(library(readutil), [read_file_to_string/3]).
:- use_module(library(apply), [maplist/3, exclude/3]).
:- use_module(library(lists), [member/2]).
:- use_module('../../_support/native_build', []).

native_object(Object) :-
    source_file(native_object(_), Recipe),
    file_directory_name(Recipe, Support),
    directory_file_path(Support, 'string_native.cpp', Source),
    directory_file_path(Support, '../vendor', Vendor),
    catch(( directory_file_path(Vendor, 'SHA256SUMS', Manifest),
            read_file_to_string(Manifest, Text, []),
            split_string(Text, "\n", "", Lines0), exclude(=(""), Lines0, Lines),
            maplist(manifest_path, Lines, Paths),
            findall(Header,
                    (member(Path, Paths), file_name_extension(_, hpp, Path),
                     directory_file_path(Vendor, Path, Header)), Headers),
            atom_concat('-I', Vendor, Include),
            native_build:native_object(Source, [Manifest|Headers], Recipe, string,
                                       ['-cc-options,-std=c++11', Include], Object) ),
          Error,
          throw(error(string_native_build(Error),
                      context(lib_string_native_build:native_object/1,
                              'Install SWI-Prolog development tools and a C++11 compiler (Debian/Ubuntu: build-essential swi-prolog-nox). Give the library .native directory write access, then run: swipl -q -s lib/lib_string/support/native_build.pl -g "lib_string_native_build:native_object(_)" -t halt. Prebuild with library(process) and the same SWI ABI before deploying a reduced platform.')))).

manifest_path(Line, Path) :-
    ( sub_string(Line, 64, 2, _, "  "), sub_string(Line, 66, _, 0, Path), Path \== ""
    -> true
    ; throw(error(domain_error(native_source_manifest, Line), _))
    ).
