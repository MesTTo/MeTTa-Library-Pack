% Purpose: expose text operations, line layout, templates and exact metrics.
% Assumes: text accepts String, Symbol or Number; indexes count codepoints.
% [tested: lib_string, lib_string_surface; commit=3aaad3435292e4c7d5cc3a01bfda39430aacc6e8].
% Guarantees: text results are Strings and NUL survives every text boundary.
% [tested: lib_string_surface, test_string_unicode_oracles; commit=3aaad3435292e4c7d5cc3a01bfda39430aacc6e8].
% Literal search, exact splitting and replacement share KMP traversal.
% [source: lib/lib_string/support/string_native.cpp:occurrences; commit=3aaad3435292e4c7d5cc3a01bfda39430aacc6e8].
% Decides: slices clamp, absent indexes are -1, empty replacement patterns
% preserve their input, and parse-number fails on ordinary nonnumbers.
% [tested: lib_string, lib_string_surface; commit=3aaad3435292e4c7d5cc3a01bfda39430aacc6e8].

:- module(lib_string,
          ['number-to-string'/2, 'parse-number'/2,
           'string-chars'/2, 'string-from-chars'/2,
           'string-codes'/2, 'string-from-codes'/2,
           'string-length'/2, 'string-slice'/4,
           'string-split'/3, 'string-split-exact'/3, 'string-join'/3,
           'string-trim'/2, 'string-upper'/2, 'string-lower'/2,
           'string-starts-with'/3, 'string-ends-with'/3, 'string-contains'/3,
           'string-index-of'/3, 'string-last-index-of'/3,
           'string-count'/3, 'string-count'/4, 'string-replace'/4,
           'string-repeat'/3, 'string-pad-left'/4, 'string-pad-right'/4,
           'string-center'/4, 'string-lines'/2, 'string-unlines'/2,
           'string-dedent'/2, 'string-indent'/3,
           'string-wrap'/3, 'string-wrap'/4, 'string-template'/3,
           'string-edit-distance'/3, 'string-similarity'/3,
           'string-isub'/3, 'string-isub'/4, metta_text/2]).
:- set_module(base(metta_engine)).
:- use_module('support/native', []).
:- use_module('vendor/string_lines', []).
:- use_module(library(error), [must_be/2, domain_error/2]).
:- use_module(library(apply), [maplist/2, maplist/3, exclude/3]).
:- use_module(library(strings), [interpolate_string/4]).
:- use_module(library(dcg/basics), [prolog_var_name//1]).
:- use_module(library(lynx/format), [format_paragraph/2]).

%! metta_text(+Value:any, -Text:string) is det.
%
% Coerce the library's String, Symbol and Number text inputs.
% @private
metta_text(Value, Text) :-
    (   string(Value) -> Text = Value
    ;   atom(Value) -> atom_string(Value, Text)
    ;   number(Value) -> number_string(Value, Text)
    ;   throw_metta_type_error('string-op', 'String', Value)
    ).

%! 'string-length'(+Value:any, -Length:integer) is det.
%
% Count Unicode codepoints, including embedded NUL. Text coercions apply.
'string-length'(Value, Length) :- metta_text(Value, Text), string_length(Text, Length).

%! 'string-slice'(+Value:any, +From:integer, +To:integer, -Out:string) is det.
%
% Return the half-open codepoint interval [From,To). Clamp each endpoint to
% the input; negative starts and reversed or beyond-end intervals are safe.
'string-slice'(Value, From, To, Out) :-
    metta_text(Value, Text), must_be(integer, From), must_be(integer, To),
    string_length(Text, Length), Start is max(0, min(From, Length)),
    End is max(Start, min(To, Length)), Span is End - Start,
    sub_string(Text, Start, Span, _, Out).

%! 'string-split'(+Separators:any, +Value:any, -Parts:list) is det.
%
% Split on each character in Separators, retaining empty fields. An empty
% separator set returns the whole input; NUL splits only when explicitly listed.
'string-split'(Separators, Value, Parts) :-
    metta_text(Separators, Set), metta_text(Value, Text),
    lib_string_native:split_text(Text, Set, "", Parts).

%! 'string-split-exact'(+Separator:any, +Value:any, -Parts:list) is det.
%
% Split at nonoverlapping occurrences of the complete, nonempty Separator.
% Preserve empty fields and text verbatim. An empty separator raises.
'string-split-exact'(Separator, Value, Parts) :-
    metta_text(Separator, Sep), metta_text(Value, Text),
    lib_string_native:split_exact(Text, Sep, Parts).

%! 'string-join'(+Separator:any, +Parts:list, -Out:string) is det.
%
% Join coerced text parts once with Separator; an empty list produces "".
'string-join'(Separator, Parts, Out) :-
    must_be(list, Parts), metta_text(Separator, Sep), maplist(metta_text, Parts, Texts),
    atomics_to_string(Texts, Sep, Out).

%! 'string-trim'(+Value:any, -Out:string) is det.
%
% Remove ASCII space, tab, LF and CR from both ends. Interior text and NUL stay.
'string-trim'(Value, Out) :-
    metta_text(Value, Text), lib_string_native:split_text(Text, "", " \t\n\r", [Out]).

%! 'string-upper'(+Value:any, -Out:string) is det.
%
% Apply the host Unicode uppercase mapping and return a String.
'string-upper'(Value, Out) :- metta_text(Value, Text), string_upper(Text, Out).

%! 'string-lower'(+Value:any, -Out:string) is det.
%
% Apply the host Unicode lowercase mapping and return a String.
'string-lower'(Value, Out) :- metta_text(Value, Text), string_lower(Text, Out).

%! 'string-starts-with'(+Value:any, +Prefix:any, -Answer:boolean) is det.
%
% Return True exactly when Prefix begins the text. An empty prefix matches.
'string-starts-with'(Value, Prefix, Answer) :-
    metta_text(Value, Text), metta_text(Prefix, Part),
    ( sub_string(Text, 0, _, _, Part) -> Answer = true ; Answer = false ).

%! 'string-ends-with'(+Value:any, +Suffix:any, -Answer:boolean) is det.
%
% Return True exactly when Suffix ends the text. An empty suffix matches.
'string-ends-with'(Value, Suffix, Answer) :-
    metta_text(Value, Text), metta_text(Suffix, Part),
    ( sub_string(Text, _, _, 0, Part) -> Answer = true ; Answer = false ).

%! 'string-contains'(+Value:any, +Part:any, -Answer:boolean) is det.
%
% Return True when Part occurs literally, including an empty Part.
'string-contains'(Value, Part, Answer) :-
    'string-index-of'(Value, Part, Index), ( Index >= 0 -> Answer = true ; Answer = false ).

%! 'string-index-of'(+Value:any, +Part:any, -Index:integer) is det.
%
% Return the first zero-based codepoint index, or -1. An empty Part returns 0.
'string-index-of'(Value, Part, Index) :-
    metta_text(Value, Text), metta_text(Part, Needle),
    lib_string_native:find_index(Text, Needle, false, Index).

%! 'string-last-index-of'(+Value:any, +Part:any, -Index:integer) is det.
%
% Return the last zero-based codepoint index, including overlapping matches,
% or -1. An empty Part returns the input length.
'string-last-index-of'(Value, Part, Index) :-
    metta_text(Value, Text), metta_text(Part, Needle),
    lib_string_native:find_index(Text, Needle, true, Index).

%! 'string-count'(+Value:any, +Part:any, -Count:integer) is det.
%! 'string-count'(+Value:any, +Part:any, +Overlap:boolean, -Count:integer) is det.
%
% Count literal occurrences, nonoverlapping by default. True enables overlap.
% An empty Part counts every boundary, including both ends, giving length+1.
'string-count'(Value, Part, Count) :- 'string-count'(Value, Part, false, Count).
'string-count'(Value, Part, Overlap, Count) :-
    metta_text(Value, Text), metta_text(Part, Needle), must_be(boolean, Overlap),
    lib_string_native:count_matches(Text, Needle, Overlap, Count).

%! 'string-replace'(+Value:any, +From:any, +To:any, -Out:string) is det.
%
% Replace every nonoverlapping literal occurrence. An empty From preserves
% the original input. Matching and output assembly do not copy shrinking suffixes.
'string-replace'(Value, From, To, Out) :-
    metta_text(Value, Text), metta_text(From, Pattern), metta_text(To, Replacement),
    lib_string_native:replace_all(Text, Pattern, Replacement, Out).

%! 'string-chars'(+Value:any, -Chars:list) is det.
%
% Return one-character Strings, preserving Unicode and embedded NUL.
'string-chars'(Value, Chars) :-
    metta_text(Value, Text), string_chars(Text, Atoms), maplist(atom_string, Atoms, Chars).

%! 'string-from-chars'(+Chars:list, -Out:string) is det.
%
% Join text items into one String. Retain the existing acceptance of items
% containing zero or several characters, Symbols and Numbers.
'string-from-chars'(Chars, Out) :- 'string-join'("", Chars, Out).

%! 'string-codes'(+Value:any, -Codes:list) is det.
%
% Return Unicode scalar integers. NUL is 0; supplementary characters count once.
'string-codes'(Value, Codes) :-
    metta_text(Value, Text), string_codes(Text, Codes), maplist(scalar_code, Codes).

%! 'string-from-codes'(+Codes:list, -Out:string) is det.
%
% Build a String from Unicode scalar integers. Reject improper lists,
% nonintegers, surrogates and values outside 0 through 0x10FFFF.
'string-from-codes'(Codes, Out) :-
    must_be(list, Codes), maplist(scalar_code, Codes), string_codes(Out, Codes).

scalar_code(Code) :-
    must_be(integer, Code),
    ( Code >= 0, Code =< 0x10ffff, (Code < 0xd800 ; Code > 0xdfff) -> true
    ; domain_error(unicode_scalar_value, Code) ).

%! 'string-repeat'(+Value:any, +Times:integer, -Out:string) is det.
%
% Repeat the text Times times. Zero and negative counts produce an empty String.
'string-repeat'(Value, Times, Out) :-
    metta_text(Value, Text), must_be(integer, Times), Count is max(0, Times),
    length(Copies, Count), maplist(=(Text), Copies), atomics_to_string(Copies, Out).

%! 'string-pad-left'(+Value:any, +Width:integer, +Pad:any, -Out:string) is det.
%
% Pad on the left to Width codepoints. Repeat and truncate a multicharacter
% filler. An empty filler or a width no greater than the input leaves it unchanged.
'string-pad-left'(Value, Width, Pad, Out) :- pad_with(Value, Width, Pad, left, Out).

%! 'string-pad-right'(+Value:any, +Width:integer, +Pad:any, -Out:string) is det.
%
% Pad on the right using string-pad-left's width and filler rules.
'string-pad-right'(Value, Width, Pad, Out) :- pad_with(Value, Width, Pad, right, Out).

pad_with(Value, Width, Pad, Side, Out) :-
    metta_text(Value, Text), metta_text(Pad, Filler), must_be(integer, Width),
    string_length(Text, Length), Missing is Width - Length,
    padding(Filler, Missing, Fill),
    ( Side == left -> string_concat(Fill, Text, Out) ; string_concat(Text, Fill, Out) ).

padding(Pad, Missing, Fill) :-
    ( (Missing =< 0 ; Pad == "") -> Fill = ""
    ; string_length(Pad, Size), Times is (Missing + Size - 1) // Size,
      'string-repeat'(Pad, Times, Repeated), sub_string(Repeated, 0, Missing, _, Fill) ).

%! 'string-center'(+Value:any, +Width:integer, +Pad:any, -Out:string) is det.
%
% Pad both sides to Width codepoints, with an odd extra character on the right.
% Each side starts at the beginning of Pad; empty filler leaves the input unchanged.
'string-center'(Value, Width, Pad, Out) :-
    metta_text(Value, Text), metta_text(Pad, Filler), must_be(integer, Width),
    string_length(Text, Length), Missing is max(0, Width - Length),
    Left is Missing // 2, Right is Missing - Left,
    padding(Filler, Left, Before), padding(Filler, Right, After),
    atomics_to_string([Before, Text, After], Out).

%! 'string-lines'(+Value:any, -Lines:list) is det.
%
% Split at LF and omit one terminal empty component. Empty input gives ().
% CR and NUL remain data. Duplicate and internal empty lines survive.
'string-lines'(Value, Lines) :- metta_text(Value, Text), lib_string_lines:string_lines(Text, Lines).

%! 'string-unlines'(+Lines:list, -Out:string) is det.
%
% Append LF to every coerced line and concatenate. An empty list produces "".
'string-unlines'(Lines, Out) :-
    must_be(list, Lines), maplist(metta_text, Lines, Texts), lib_string_lines:string_lines(Out, Texts).

%! 'string-dedent'(+Value:any, -Out:string) is det.
%
% Remove the common literal space/tab prefix of nonblank LF-separated lines.
% Blank lines become empty and the final LF is preserved. Tabs are not expanded.
'string-dedent'(Value, Out) :- metta_text(Value, Text), lib_string_lines:dedent_lines(Text, Out, []).

%! 'string-indent'(+Prefix:any, +Value:any, -Out:string) is det.
%
% Prefix each LF-separated line except lines containing only spaces and tabs.
% Preserve blank-line contents and a final LF.
'string-indent'(Prefix, Value, Out) :-
    metta_text(Prefix, Before), metta_text(Value, Text), lib_string_lines:indent_lines(Before, Text, Out).

%! 'string-wrap'(+Value:any, +Width:integer, -Out:string) is det.
%! 'string-wrap'(+Value:any, +Width:integer, +Alignment:any, -Out:string) is det.
%
% Greedily wrap words to a positive codepoint width. Collapse ASCII space,
% tab, LF and CR. Keep long words whole. Alignment is left (default), right,
% center or justify. The final justified line aligns left; no final LF is added.
'string-wrap'(Value, Width, Out) :- 'string-wrap'(Value, Width, left, Out).
'string-wrap'(Value, Width, Alignment, Out) :-
    metta_text(Value, Text), must_be(positive_integer, Width),
    metta_text(Alignment, Name), atom_string(Align, Name),
    must_be(oneof([left,right,center,justify]), Align),
    lib_string_native:split_text(Text, " \t\n\r", " \t\n\r", Parts),
    exclude(=(""), Parts, Words), phrase(word_tokens(Words), Tokens),
    with_output_to(string(Out), format_paragraph(Tokens, [width(Width),text_align(Align)])).

word_tokens([]) --> [].
word_tokens([Word|Rest]) -->
    { string_length(Word, Length) }, [w(Word,Length,[])],
    ( {Rest == []} -> [] ; [b(1,_)], word_tokens(Rest) ).

%! 'string-template'(+Template:any, +Bindings:list, -Out:string) is det.
%
% Replace {Name} or {Name,Default} using unique (Name Value) pairs. Names are
% Prolog variable identifiers. Render values through the engine's console
% renderer. Missing names raise; unrecognized braces remain literal. Goals never run.
'string-template'(Template, Bindings, Out) :-
    metta_text(Template, Text), must_be(list, Bindings),
    maplist(template_binding, Bindings, Pairs), dict_create(_, template, Pairs),
    maplist(template_assignment, Pairs, Assignments),
    once(interpolate_string(Text, Out, Assignments, [goals(false)])).

template_binding(Binding, Name-Text) :-
    ( nonvar(Binding), Binding = [Key,Value] -> true ; domain_error(template_binding, Binding) ),
    metta_text(Key, KeyText), string_codes(KeyText, Codes),
    ( phrase(prolog_var_name(Name), Codes) -> true ; domain_error(template_name, Key) ),
    metta_engine:metta_console_text(Value, Text).

template_assignment(Name-Value, Name=Value).

%! 'string-edit-distance'(+First:any, +Second:any, -Distance:integer) is det.
%
% Return exact unit-cost Levenshtein distance over Unicode codepoints.
% NUL is data. No normalization or score cutoff changes the comparison.
'string-edit-distance'(First, Second, Distance) :-
    metta_text(First, Left), metta_text(Second, Right), lib_string_native:edit_distance(Left, Right, Distance).

%! 'string-similarity'(+First:any, +Second:any, -Score:float) is det.
%
% Return 1 - edit-distance/max(lengths), in [0,1]. Two empty Strings score 1.
'string-similarity'(First, Second, Score) :-
    metta_text(First, Left), metta_text(Second, Right),
    string_length(Left, L), string_length(Right, R), Maximum is max(L,R),
    ( Maximum =:= 0 -> Score = 1.0
    ; lib_string_native:edit_distance(Left, Right, Distance), Score is 1.0 - Distance/Maximum ).

%! 'string-isub'(+First:any, +Second:any, -Score:float) is det.
%! 'string-isub'(+First:any, +Second:any, +Options:list, -Score:float) is det.
%
% Return SWI's substring-based ontology-label ISub score, preserving complete
% text. Unique options are (normalize Bool), (zero-to-one Bool) and
% (substring-threshold Number), defaulting to False, False and 2. Threshold
% is nonnegative; matched substrings must be longer than it. Normalization
% lowercases and removes dot, underscore and ASCII space. The usual range is
% [-1,1], or [0,1] with zero-to-one. Both empty score 1; one empty scores 0.
'string-isub'(First, Second, Score) :- 'string-isub'(First, Second, [], Score).
'string-isub'(First, Second, Options, Score) :-
    must_be(list, Options), maplist(isub_option, Options, Pairs), dict_create(Explicit, isub, Pairs),
    Config = isub{normalize:false,zero_to_one:false,threshold:2}.put(Explicit),
    metta_text(First, Text1), metta_text(Second, Text2),
    isub_text(Config.normalize, Text1, Left), isub_text(Config.normalize, Text2, Right),
    string_length(Left, L), string_length(Right, R), Threshold is min(Config.threshold,max(L,R)),
    lib_string_native:substring_similarity(Left, Right, Threshold, Config.zero_to_one, Score).

isub_option(Option, Key-Value) :-
    ( nonvar(Option), Option = [Name,Value] -> true ; domain_error(isub_option, Option) ),
    ( Name == normalize -> Key = normalize, must_be(boolean, Value)
    ; Name == 'zero-to-one' -> Key = zero_to_one, must_be(boolean, Value)
    ; Name == 'substring-threshold' -> Key = threshold, must_be(nonneg, Value)
    ; domain_error(isub_option, Option) ).

isub_text(false, Text, Text).
isub_text(true, Text, Out) :-
    string_lower(Text, Lower), lib_string_native:split_text(Lower, "._ ", "", Parts),
    atomics_to_string(Parts, Out).

%! 'parse-number'(+Value:any, -Number:number) is semidet.
%
% Parse the host numeric syntax. Ordinary nonnumbers produce no answer;
% type, resource and interruption exceptions remain visible.
'parse-number'(Value, Number) :- metta_text(Value, Text), number_string(Number, Text).

%! 'number-to-string'(+Number:number, -Out:string) is det.
%
% Return the host String representation of a Number, including rationals.
'number-to-string'(Number, Out) :- must_be(number, Number), number_string(Number, Out).

:- det(metta_text/2).
:- det('string-length'/2).
:- det('string-slice'/4).
:- det('string-split'/3).
:- det('string-split-exact'/3).
:- det('string-join'/3).
:- det('string-trim'/2).
:- det('string-upper'/2).
:- det('string-lower'/2).
:- det('string-starts-with'/3).
:- det('string-ends-with'/3).
:- det('string-contains'/3).
:- det('string-index-of'/3).
:- det('string-last-index-of'/3).
:- det('string-count'/3).
:- det('string-count'/4).
:- det('string-replace'/4).
:- det('string-chars'/2).
:- det('string-from-chars'/2).
:- det('string-codes'/2).
:- det('string-from-codes'/2).
:- det('string-repeat'/3).
:- det('string-pad-left'/4).
:- det('string-pad-right'/4).
:- det('string-center'/4).
:- det('string-lines'/2).
:- det('string-unlines'/2).
:- det('string-dedent'/2).
:- det('string-indent'/3).
:- det('string-wrap'/3).
:- det('string-wrap'/4).
:- det('string-template'/3).
:- det('string-edit-distance'/3).
:- det('string-similarity'/3).
:- det('string-isub'/3).
:- det('string-isub'/4).
:- det('number-to-string'/2).
