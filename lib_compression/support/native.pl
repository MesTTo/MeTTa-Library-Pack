% Purpose: own private archive readers and load their UTF8 call adapter.
% Guarantees: import loads the adapter or raises a named build refusal.
% [tested: lib_compression; commit=7b42d5ee5cecb82709617b7ed08dfa2c1441f268].
% Owns resources: with_archive/4 closes its preallocated archive even if opening
% fails, then closes an owned parent file; stream(Input) borrows its parent.
% [tested: archive_scope_releases_failed_acquisitions; commit=7b42d5ee5cecb82709617b7ed08dfa2c1441f268].

:- module(lib_compression_native,
          [with_utf8/1,with_archive/4,archive_property/2,archive_next_header/2,
           archive_header_property/2,archive_open_entry/2]).
:- use_module(library(shlib), [load_foreign_library/2]).
:- use_module(library(lists), [member/2]).
:- use_module(native_build, [native_object/1]).
:- meta_predicate with_archive(+,+,-,0), with_archive_stream(+,+,-,0).
:- native_object(Object), load_foreign_library(Object, install_lib_compression).

with_archive(Source,Options,Archive,Goal) :-
    ( Source=stream(Input)
    -> with_archive_stream(Input,Options,Archive,Goal)
    ; setup_call_cleanup(open(Source,read,Input,[type(binary)]),
                         with_archive_stream(Input,Options,Archive,Goal),close(Input)) ).
with_archive_stream(Input,Options,Archive,Goal) :-
    setup_call_cleanup('$archive_new'(Archive),
        ('$archive_open_stream'(Input,read,Archive,[close_parent(false)|Options]),call(Goal)),
        archive_close(Archive)).

archive_property(Archive,filter(Filters)) :- archive_property(Archive,filter,Filters).
archive_header_property(Archive,Property) :-
    % policy-inventory-exempt: mechanism-internal; reason=enumerate the property functors accepted by the pinned archive binding; evidence=lib/lib_compression/vendor/archive4pl.c:1127
    member(Property,[filetype(_),mtime(_),size(_),link_target(_),format(_),permissions(_)]),
    archive_header_prop_(Archive,Property).
