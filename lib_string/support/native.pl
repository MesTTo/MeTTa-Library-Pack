% Purpose: load the complete private String native surface.
% Guarantees: imports load the provider or raise a named build refusal.
% [tested: test_native_build_is_atomic_and_reused; commit=3aaad3435292e4c7d5cc3a01bfda39430aacc6e8].

:- module(lib_string_native,
          [find_index/4, count_matches/4, split_exact/3, replace_all/4,
           split_text/4, edit_distance/3, substring_similarity/5]).
:- use_module(library(shlib), [load_foreign_library/2]).
:- use_module(native_build, [native_object/1]).
:- native_object(Object), load_foreign_library(Object, install_lib_string).
