% Purpose: expose compiled PCRE2 matching, captures, ranges and substitution.
% Guarantees: zero-width matches retain valid nonempty alternatives; ranges use
% Unicode character offsets; matching operations accept the same compiled blob
% [tested: lib_regex; commit=WORKTREE].
% Owns resources: compiled blobs are immutable and reclaimed by atom collection;
% native matching frees its match data and optional boundary index on every exit
% [source: lib/lib_regex/vendor/pcre4pl.c:release_pcre; commit=WORKTREE].
% Guarded by: the provider's shared tables own pattern and replacement caches
% [source: lib/lib_regex/vendor/lib_regex_pcre.pl:re_compiled_; commit=WORKTREE].
% Decides: capture scans enumerate answers in match order; scans materialize their
% answers before enumeration. Flags are inline PCRE2 syntax such as (?i)
% [source: lib/lib_regex/lib_regex.pl:regex_dicts; commit=WORKTREE].

:- module(lib_regex,
          [regex_match/3, regex_find/3, regex_captures/3, regex_split/3,
           regex_replace/4, regex_replace_all/4,
           're-match'/3, 're-find'/3, 're-captures'/3, 're-split'/3,
           're-replace'/4, 're-replace-all'/4, 're-compile'/2,
           're-fullmatch'/3, 're-scan'/3, 're-ranges'/3, 're-count'/3,
           're-escape'/2]).
:- set_module(base(metta_engine)).
:- metta_requires(regex).
:- use_module('vendor/lib_regex_pcre',
              [re_compile/3, re_match/2, re_match/3, re_matchsub/4,
               re_foldl/6, re_fold_ranges/6, re_fold_nocapture/6,
               re_split/3, re_replace/4]).
:- use_module(library(apply), [maplist/3]).
:- use_module(library(lists), [reverse/2, member/2]).

%! regex_match(+Pattern:any, +Text:any, -Answer:boolean) is det.
%
% Return whether Pattern matches anywhere in Text. Pattern is text or a compiled
% re-compile value. Invalid patterns and native matching failures raise.
regex_match(Pattern, Text, Answer) :-
    ( re_match(Pattern, Text) -> Answer = true ; Answer = false ).

%! 're-match'(+Pattern:any, +Text:any, -Answer:boolean) is det.
%
% Return whether Pattern matches anywhere in Text, with the regex_match contract.
're-match'(Pattern, Text, Answer) :- regex_match(Pattern, Text, Answer).

%! regex_find(+Pattern:any, +Text:any, -Match:string) is nondet.
%
% Enumerate every whole match in left-to-right order, preserving repeated and
% empty answers. After an empty match, try a nonempty alternative at the same
% position before advancing one character. The final empty match is included.
regex_find(Pattern, Text, Match) :-
    regex_dicts(Pattern, Text, Dict),
    get_dict(0, Dict, Match).

%! 're-find'(+Pattern:any, +Text:any, -Match:string) is nondet.
%
% Enumerate every whole match, with the regex_find contract.
're-find'(Pattern, Text, Match) :- regex_find(Pattern, Text, Match).

%! regex_captures(+Pattern:any, +Text:any, -Groups:list) is semidet.
%
% Return the first match as ((Key Value) ...) pairs. Key 0 names the whole
% match; other keys are group numbers or names. Unmatched optional groups are
% omitted. Suffixes _S/_A/_R select String/Symbol/(- Start Length), and _I/_F/_N/_T
% parse a native Prolog term. Compounds become (Functor Argument ...) expressions;
% proper lists remain expressions and improper lists become (cons Head Tail).
% Invalid text and cyclic terms raise; no match has no answer.
regex_captures(Pattern, Text, Groups) :-
    re_matchsub(Pattern, Text, Dict, []),
    regex_pairs(Dict, Groups).

%! 're-captures'(+Pattern:any, +Text:any, -Groups:list) is semidet.
%
% Return the first match's capture pairs, with the regex_captures contract.
're-captures'(Pattern, Text, Groups) :- regex_captures(Pattern, Text, Groups).

%! regex_split(+Pattern:any, +Text:any, -Parts:list) is det.
%
% Return alternating skipped and matched Strings, beginning and ending with a
% skipped part. The list always has odd length, including for an empty pattern.
regex_split(Pattern, Text, Parts) :- re_split(Pattern, Text, Parts).

%! 're-split'(+Pattern:any, +Text:any, -Parts:list) is det.
%
% Split Text into skipped/matched parts, with the regex_split contract.
're-split'(Pattern, Text, Parts) :- regex_split(Pattern, Text, Parts).

%! regex_replace(+Pattern:any, +With:any, +Text:any, -Replaced:string) is det.
%
% Replace the first match. With references captures as $name, $1 or \1; braces
% can delimit the name. Double a dollar or backslash to quote it. Missing or
% unbound groups raise. Typed captures substitute their parsed value, so 007
% with _I becomes 7; compound values use native quoted term syntax.
regex_replace(Pattern, With, Text, Replaced) :-
    re_replace(Pattern, With, Text, Replaced).

%! 're-replace'(+Pattern:any, +With:any, +Text:any, -Replaced:string) is det.
%
% Replace the first match, with the regex_replace contract.
're-replace'(Pattern, With, Text, Replaced) :- regex_replace(Pattern, With, Text, Replaced).

%! regex_replace_all(+Pattern:any, +With:any, +Text:any, -Replaced:string) is det.
%
% Replace every match, including empty matches and a nonempty alternative at
% the same position. With follows the regex_replace capture-reference syntax.
regex_replace_all(Pattern, With, Text, Replaced) :-
    re_replace(Pattern/g, With, Text, Replaced).

%! 're-replace-all'(+Pattern:any, +With:any, +Text:any, -Replaced:string) is det.
%
% Replace every match, with the regex_replace_all contract.
're-replace-all'(Pattern, With, Text, Replaced) :-
    regex_replace_all(Pattern, With, Text, Replaced).

%! 're-compile'(+Pattern:any, -Compiled:any) is det.
%
% Compile pattern text to an immutable native regex value accepted by every
% regex operation. It can be stored, passed between functions and reused across
% threads. Inline flags belong to Pattern. Invalid pattern syntax raises.
're-compile'(Pattern, Compiled) :- re_compile(Pattern, Compiled, []).

%! 're-fullmatch'(+Pattern:any, +Text:any, -Answer:boolean) is det.
%
% Return whether one match covers all Text. Native anchoring applies to the
% entire pattern, including every alternative, without adding capture groups.
're-fullmatch'(Pattern, Text, Answer) :-
    ( re_match(Pattern, Text, [anchored(true), endanchored(true)])
    -> Answer = true
    ;  Answer = false ).

%! 're-scan'(+Pattern:any, +Text:any, -Groups:list) is nondet.
%
% Enumerate capture-pair records for every match in order. The capture shape
% and typed suffixes follow re-captures; match progression follows re-find.
're-scan'(Pattern, Text, Groups) :-
    regex_dicts(Pattern, Text, Dict),
    regex_pairs(Dict, Groups).

%! 're-ranges'(+Pattern:any, +Text:any, -Range:list) is nondet.
%
% Enumerate (Start Length) records for whole matches in Unicode characters,
% starting at zero. Empty matches have length zero. A byte-oriented \C match
% that splits a Unicode character raises regex_character_boundary.
're-ranges'(Pattern, Text, [Start, Length]) :-
    re_fold_ranges(regex_collect, Pattern, Text, [], Reverse, []),
    reverse(Reverse, Dicts),
    member(Dict, Dicts),
    get_dict(0, Dict, range(Start, Length)).

%! 're-count'(+Pattern:any, +Text:any, -Count:integer) is det.
%
% Count matches using re-find's empty-match progression. This does not collect
% answers or parse typed capture values; counting needs constant auxiliary space.
're-count'(Pattern, Text, Count) :-
    re_fold_nocapture(regex_increment, Pattern, Text, 0, Count, []).

%! 're-escape'(+Text:any, -Pattern:string) is det.
%
% Quote literal text for a PCRE2 pattern, including whitespace in extended mode
% and embedded \E quoting terminators. The result matches exactly that text
% when used with re-fullmatch.
're-escape'(Text, Pattern) :-
    % Pattern.quote handles embedded terminators by ending, escaping and reopening.
    % https://github.com/openjdk/jdk/blob/jdk-25%2B36/src/java.base/share/classes/java/util/regex/Pattern.java
    atom_string(Atom, Text),
    atomic_list_concat(Parts, '\\E', Atom),
    atomic_list_concat(Parts, '\\E\\\\E\\Q', Inner),
    atomics_to_string(['\\Q', Inner, '\\E'], Pattern).

regex_dicts(Pattern, Text, Dict) :-
    re_foldl(regex_collect, Pattern, Text, [], Reverse, []),
    reverse(Reverse, Dicts),
    member(Dict, Dicts).

regex_collect(Dict, Acc, [Dict|Acc]).
regex_increment(_, Before, After) :- After is Before + 1.

regex_pairs(Dict, Groups) :-
    dict_pairs(Dict, _, Pairs),
    maplist(regex_pair, Pairs, Groups).

regex_pair(Key-Value, [Key, Converted]) :-
    (   compound(Value)
    ->  ( acyclic_term(Value)
        -> regex_term(Value, Converted)
        ;  throw(error(domain_error(acyclic_regex_capture, Value), _)) )
    ;   Converted = Value
    ).

% Make the wire's structural reading explicit before a host can claim a functor.
regex_term(Value, Converted) :-
    (   is_list(Value)
    ->  maplist(regex_term, Value, Converted)
    ;   nonvar(Value), Value = [_|_]
    ->  regex_improper(Value, Converted)
    ;   compound(Value)
    ->  compound_name_arguments(Value, Functor, Arguments),
        maplist(regex_term, Arguments, Elements),
        Converted = [Functor|Elements]
    ;   Converted = Value
    ).

regex_improper([Head|Tail], [cons, Converted, Rest]) :-
    regex_term(Head, Converted),
    ( nonvar(Tail), Tail = [_|_]
    -> regex_improper(Tail, Rest)
    ;  regex_term(Tail, Rest) ).
