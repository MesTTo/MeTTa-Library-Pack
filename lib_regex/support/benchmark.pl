% Purpose: compare native range projection against the installed SWI provider.
% Assumes: the host provides library(pcre) and a compiler for the local binding.
% Decides: compare identical two-capture Unicode scans at three input sizes;
% each CPU time is the minimum of three runs with a precompiled pattern
% [source: lib/lib_regex/support/benchmark.pl:benchmark_size; commit=7dcfe83fcf74742a1e944db240aa918596c8d4b0].

:- module(lib_regex_benchmark, [regex_benchmark/0]).
:- use_module(library(pcre), []).
:- use_module('../vendor/lib_regex_pcre', []).
:- use_module(library(apply), [maplist/2]).
:- use_module(library(lists), [member/2, min_list/2]).

regex_benchmark :-
    format('provider,characters,cpu_seconds,checksum~n'),
    % policy-inventory-exempt: mechanism-internal; reason=geometric benchmark inputs distinguish growth of the two range projections; evidence=lib/lib_regex/support/benchmark.pl:benchmark_size/1
    forall(member(Size, [1024,4096,16384]), benchmark_size(Size)).

benchmark_size(Size) :-
    length(Codes, Size),
    maplist(=(0'é), Codes),
    string_codes(Text, Codes),
    Pairs is Size // 2,
    Expected is 3*Pairs*Pairs + 2*Pairs,
    % policy-inventory-exempt: mechanism-internal; reason=compare the installed oracle and the private Unicode-corrected provider on the same data; evidence=lib/lib_regex/support/benchmark.pl:benchmark_size/1
    forall(member(Provider, [pcre,lib_regex_pcre]),
           (Provider:re_compile("(?<a_R>.)(?<b_R>.)", Pattern, [capture_type(range)]),
            findall(Elapsed,
                    (between(1,3,_),
                     statistics(cputime, Start),
                     Provider:re_foldl(lib_regex_benchmark:checksum, Pattern, Text, 0, Sum, []),
                     statistics(cputime, End),
                     (Sum =:= Expected -> true ; throw(error(regex_checksum(Sum,Expected),_))),
                     Elapsed is End-Start),
                    Times),
            min_list(Times, Best),
            format('~w,~d,~6f,~d~n', [Provider,Size,Best,Expected]))).

checksum(Dict, Before, After) :-
    get_dict(0, Dict, Whole-WholeLength),
    get_dict(a, Dict, A-ALength),
    get_dict(b, Dict, B-BLength),
    After is Before + Whole + WholeLength + A + ALength + B + BLength.
