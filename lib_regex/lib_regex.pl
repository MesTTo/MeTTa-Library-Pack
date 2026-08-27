% Purpose: PCRE2 regular expressions for MeTTa, over SWI's own
%   library(pcre): compiled patterns live in the engine's cache and are
%   thread-safe, matches enumerate nondeterministically, named capture
%   groups cross typed (a _I suffix in the group name answers an
%   integer), and split and replace are plain functions. Every predicate
%   follows the compiled convention, inputs then one output.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

%Nothing below this line works without library(pcre), so the file says so
%where the engine's pre-load scan can read it: an import on a build without
%the regex capability then refuses naming this file, the capability and what
%its absence costs, and the file never loads. Without it the import came back
%wrapped in a transcript of SWI's own source_sink error and named neither
%[measured 2026-08-28, pcre withheld from tests/prolog/reduced_platform.pl's
%farm]. This is what lib/lib_thread/lib_thread.pl does for concurrency; the
%use_module below stays unguarded because it is only reached on a build that
%HAS the capability.
:- metta_requires(regex).
:- use_module(library(pcre)).
:- use_module(library(apply)).

%Whether the pattern matches anywhere in the text, as a boolean answer.
%Flags ride the pattern inline, PCRE2's own (?i) style, because the
%Prolog Pattern/Flags spelling is not reachable from MeTTa source.
regex_match(Pattern, Text, Answer) :-
    ( re_match(Pattern, Text) -> Answer = true ; Answer = false ).

%Every match's whole text, one answer per match, leftmost first.
regex_find(Pattern, Text, Match) :-
    re_foldl(regex_collect_, Pattern, Text, [], Collected, []),
    reverse(Collected, Matches),
    member(Match, Matches).

regex_collect_(Dict, Sofar, [Match|Sofar]) :-
    get_dict(0, Dict, Match).

%The first match's capture groups as ((key value) ...) pairs: the whole
%match under 0, numbered groups under their indices, named groups under
%their names, values typed by the group's own suffix. No match fails,
%which MeTTa reads as no answer.
regex_captures(Pattern, Text, Groups) :-
    re_matchsub(Pattern, Text, Dict, []),
    dict_pairs(Dict, _, Pairs),
    maplist(regex_pair_, Pairs, Groups).

regex_pair_(Key-Value, [Key, Value]).

%Alternating skipped and matched parts, always an odd-length list,
%library(pcre)'s own contract.
regex_split(Pattern, Text, Parts) :-
    re_split(Pattern, Text, Parts).

%Replace the first match, or every match with the _all spelling.
regex_replace(Pattern, With, Text, Replaced) :-
    re_replace(Pattern, With, Text, Replaced).

regex_replace_all(Pattern, With, Text, Replaced) :-
    re_replace(Pattern/g, With, Text, Replaced).
