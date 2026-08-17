% Purpose: the text surface of the language. Before this the whole of it was
%   atom_concat, atom_chars, repr, repra, parse and sread, so there was no way
%   to take a substring, split on a separator, join a list, trim, change case
%   or test a prefix. Every real program needs those.
%
%   Loaded from metta.pl's ensure_loaded rather than imported, the same way
%   lib_gitimport is, because strings are core rather than optional.
% Assumes:
%   - a MeTTa string is an SWI string and a MeTTa symbol is an atom
%     [verified 2026-08-15: sread("(f \"hello\" world 42)", T) gives
%     [f,"hello",world,42] with string/1, atom/1 and number/1 respectively]
% Guarantees:
%   - every operation answers a String, never an atom, so results compose with
%     each other without a coercion step in between [tested 2026-08-16: lib_string:every_operation_that_answers_text_answers_a_String]
%   - text input is accepted as a String, a Symbol or a Number, because a
%     symbol arriving where a string was meant is ordinary in MeTTa; anything
%     else is a loud type error naming the operation [tested: lib_string:length_accepts_a_symbol, length_accepts_a_number]
% Fails when:
%   - an index is out of range. string-slice clamps rather than failing, which
%     is what every language with slicing does; string-index-of answers -1.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- use_module(library(lists)).
:- use_module(library(apply)).

%Accept a String, Symbol or Number wherever text is wanted. A symbol reaching
%a string operation is ordinary in MeTTa, so coercing is right; a compound is
%a mistake and says so.
%
%The chain is the cheapest of the four spellings and the order inside it is
%free, because SWI inlines string/1, atom/1 and number/1: a number tested
%third costs 3.00 inferences, exactly what testing it first costs. Per call,
%same inputs [measured 2026-08-16]: this 4.17, a clause per type with guard
%and cut 6.17, SSU =>/2 rules 8.17, compute-a-tag-then-dispatch 11.17. A type
%test cannot be a clause index, and computing a tag to make one does not help:
%the four-clause dispatch predicate is still `indexed: none` after 50,000
%calls. SSU is the right move where the clauses would otherwise leave a CHOICE
%POINT, which is why lib_json.pl uses it and this does not.
metta_text(Value, Text) :-
    (   string(Value)
    ->  Text = Value
    ;   atom(Value)
    ->  atom_string(Value, Text)
    ;   number(Value)
    ->  number_string(Value, Text)
    ;   throw_metta_type_error('string-op', 'String', Value)
    ).

'string-length'(Value, Length) :-
    metta_text(Value, Text),
    string_length(Text, Length).

%Half-open, like every language with slicing: From is included, To is not.
%Out-of-range ends clamp instead of failing, and From beyond the end answers
%the empty string rather than an error.
'string-slice'(Value, From, To, Out) :-
    metta_text(Value, Text),
    must_be(integer, From),
    must_be(integer, To),
    string_length(Text, Length),
    Start is max(0, min(From, Length)),
    End is max(Start, min(To, Length)),
    Span is End - Start,
    sub_string(Text, Start, Span, _, Out).

%Every separator character splits, which is split_string/4's contract, so
%(string-split "," "a,b") and (string-split ", " "a, b") both give ("a" "b")
%only when the separator is one character. Use string-replace first for a
%multi-character separator.
'string-split'(Separator, Value, Parts) :-
    metta_text(Separator, SepText),
    metta_text(Value, Text),
    split_string(Text, SepText, "", Parts).

%One pass. Interleaving the separator and concatenating the whole list once
%costs O(total length); folding string_concat/3 over the parts recopies
%everything already joined at every step, which is O(total length squared)
%[measured 2026-08-15, 4000 parts: 0.0476s folding, 0.0001s here]. The
%inference counter barely moves between the two, 16002 against 4005, because
%it does not see bytes being copied, so this one has to be timed.
'string-join'(Separator, Parts, Out) :-
    must_be(list, Parts),
    metta_text(Separator, SepText),
    maplist(metta_text, Parts, Texts),
    (   Texts == []
    ->  Out = ""
    ;   Texts = [First|Rest],
        separated_by(Rest, SepText, Tail),
        atomics_to_string([First|Tail], Out)
    ).

separated_by([], _, []).
separated_by([Text|Rest], Separator, [Separator, Text|Tail]) :-
    separated_by(Rest, Separator, Tail).

'string-trim'(Value, Out) :-
    metta_text(Value, Text),
    split_string(Text, "", " \t\n\r", [Out]).

'string-upper'(Value, Out) :-
    metta_text(Value, Text),
    string_upper(Text, Out).

'string-lower'(Value, Out) :-
    metta_text(Value, Text),
    string_lower(Text, Out).

'string-starts-with'(Value, Prefix, Answer) :-
    metta_text(Value, Text),
    metta_text(Prefix, PrefixText),
    ( sub_string(Text, 0, _, _, PrefixText) -> Answer = true ; Answer = false ).

'string-ends-with'(Value, Suffix, Answer) :-
    metta_text(Value, Text),
    metta_text(Suffix, SuffixText),
    ( sub_string(Text, _, _, 0, SuffixText) -> Answer = true ; Answer = false ).

'string-contains'(Value, Sub, Answer) :-
    metta_text(Value, Text),
    metta_text(Sub, SubText),
    ( sub_string(Text, _, _, _, SubText) -> Answer = true ; Answer = false ).

%The index of the first occurrence, or -1 when there is none, rather than
%failing: a caller asking "where is it" wants an answer either way, and -1 is
%the answer every language gives.
'string-index-of'(Value, Sub, Index) :-
    metta_text(Value, Text),
    metta_text(Sub, SubText),
    (   sub_string(Text, Before, _, _, SubText)
    ->  Index = Before
    ;   Index = -1
    ).

%Every occurrence, which is what replace means to most people; there is no
%first-only form because string-index-of plus string-slice expresses it.
'string-replace'(Value, From, To, Out) :-
    metta_text(Value, Text),
    metta_text(From, FromText),
    metta_text(To, ToText),
    (   FromText == ""
    ->  Out = Text
    ;   replacement_pieces(Text, FromText, ToText, Pieces),
        atomics_to_string(Pieces, Out)
    ).

%Collect the pieces and join once. Concatenating the processed tail onto the
%head at every level recopies the whole remainder each time [measured
%2026-08-15, 4000 occurrences: 0.0089s that way, 0.0014s this way].
replacement_pieces(Text, From, To, Pieces) :-
    (   sub_string(Text, Before, Length, After, From)
    ->  sub_string(Text, 0, Before, _, Head),
        Rest is Before + Length,
        sub_string(Text, Rest, After, _, Tail),
        Pieces = [Head, To|More],
        replacement_pieces(Tail, From, To, More)
    ;   Pieces = [Text]
    ).

%One-character STRINGS rather than Prolog char atoms, so the pieces are the
%same kind of thing as the whole and feed straight back into these operations.
'string-chars'(Value, Chars) :-
    metta_text(Value, Text),
    string_chars(Text, CharAtoms),
    maplist(char_to_string, CharAtoms, Chars).

%A named predicate rather than a yall lambda. yall copy_terms the lambda once
%per element, which costs about four times the inferences and seven times the
%cpu of an ordinary call [measured 2026-08-15, maplist over 100,000 elements:
%1301283 inferences with the lambda, 300004 with a named predicate].
char_to_string(Char, String) :- atom_string(Char, String).

'string-from-chars'(Chars, Out) :-
    must_be(list, Chars),
    maplist(metta_text, Chars, Texts),
    atomics_to_string(Texts, Out).

'string-repeat'(Value, Times, Out) :-
    metta_text(Value, Text),
    must_be(integer, Times),
    Count is max(0, Times),
    length(Copies, Count),
    maplist(=(Text), Copies),
    atomics_to_string(Copies, Out).

'string-pad-left'(Value, Width, Pad, Out) :-
    pad_with(Value, Width, Pad, left, Out).

'string-pad-right'(Value, Width, Pad, Out) :-
    pad_with(Value, Width, Pad, right, Out).

pad_with(Value, Width, Pad, Side, Out) :-
    metta_text(Value, Text),
    metta_text(Pad, PadText),
    must_be(integer, Width),
    string_length(Text, Length),
    Missing is Width - Length,
    %The parentheses are load-bearing: ; binds looser than ->, so
    %( A ; B -> C ; D ) reads as ( A ; (B -> C ; D) ), which left Out unbound
    %on the short-width case and then fell through to sub_string/5 with a
    %negative length [caught by padding_shorter_than_the_string_leaves_it_alone].
    (   ( Missing =< 0 ; PadText == "" )
    ->  Out = Text
    ;   string_length(PadText, PadLength),
        Repeats is (Missing + PadLength - 1) // max(1, PadLength),
        'string-repeat'(PadText, Repeats, Filler),
        sub_string(Filler, 0, Missing, _, Fill),
        ( Side == left -> string_concat(Fill, Text, Out)
        ; string_concat(Text, Fill, Out) )
    ).

%MeTTa HE's spelling: (format-args "Probability of {} is {}%" (head 50)).
%Extra {} beyond the arguments are left standing rather than erroring, so a
%template is never destroyed by a short argument list; extra arguments are
%ignored for the same reason.
'format-args'(Template, Args, Out) :-
    metta_text(Template, TemplateText),
    must_be(list, Args),
    maplist(format_arg_text, Args, Texts),
    filled_pieces(TemplateText, Texts, Pieces),
    atomics_to_string(Pieces, Out).

%An argument keeps its written form, so a symbol arrives as its name and a
%string without its quotes, which is what a template is for.
format_arg_text(Value, Text) :-
    (   string(Value)
    ->  Text = Value
    ;   atom(Value)
    ->  atom_string(Value, Text)
    ;   number(Value)
    ->  number_string(Value, Text)
    ;   swrite(Value, Text)
    ).

%Pieces rather than nested concatenation, for the same reason as
%replacement_pieces/4: concatenating the filled tail onto the head at every
%level recopies the remainder of the template once per argument. Worth 5.12x
%at 4,000 placeholders [measured 2026-08-16: 183,959,570 against 942,434,771
%instructions:u, min-of-2, setup subtracted]. Inferences see only 1.50x of
%that, 16,004 against 24,002, because string_concat/3 is one inference
%whatever it copies, which is why this needs instructions or wall clock.
%
%STILL QUADRATIC, and deliberately. sub_string/5 copies the remaining template
%at every placeholder, so this is O(n^2) in the template's LENGTH even though
%the output is assembled once. A single pass over string_codes/2, sharing the
%tail instead of copying it, is genuinely linear and byte-identical on every
%case tested, and it is NOT taken because it is 2x SLOWER where format
%templates actually live [measured 2026-08-16, instructions:u per call]:
%
%  placeholders |        5 |       20 |     1,000 |      4,000 |      8,000
%  this         |   33,452 |  124,396 | 16,459,512| 183,959,771| 684,290,019
%  one pass     |   67,966 |  246,339 | 11,726,072|  46,852,464|  93,715,771
%
%The crossover is near 1,000 placeholders. string_codes/2 over the whole
%template plus rebuilding each piece from codes costs more than a couple of
%sub_string/5 calls, and a template has a handful of holes. Recorded here so
%the linear rewrite is not made a third time.
filled_pieces(Text, [], [Text]).
filled_pieces(Text, [Arg|Rest], Pieces) :-
    (   sub_string(Text, Before, 2, After, "{}")
    ->  sub_string(Text, 0, Before, _, Head),
        Resume is Before + 2,
        sub_string(Text, Resume, After, _, Tail),
        Pieces = [Head, Arg|More],
        filled_pieces(Tail, Rest, More)
    ;   Pieces = [Text]
    ).

%MeTTa HE's spelling. Alphabetical, and duplicates are kept, because this
%sorts a list rather than making a set: sort-atom and unique-atom are the
%operations that remove duplicates.
'sort-strings'(List, Sorted) :-
    must_be(list, List),
    maplist(metta_text, List, Texts),
    msort(Texts, Sorted).

%Text to Number, with no answer when the text is not a number, so a caller
%can test with a match rather than catching.
'parse-number'(Value, Number) :-
    metta_text(Value, Text),
    catch(number_string(Number, Text), _, fail).

'number-to-string'(Number, Out) :-
    must_be(number, Number),
    number_string(Number, Out).

%Every operation here succeeds exactly once. det/1 is SWI's own directive, not
%a library, and it makes that a checked claim rather than a comment: a
%predicate declared det raises determinism_error if it fails or if it returns
%holding a choice point.
%
%It costs nothing. Measured 2026-08-15 over 200,000 calls: 0.0186s undeclared
%against 0.0191s declared, within noise, and the inference counts are identical
%at 3.00 per call. So this is a permanent guard rather than a trade.
%
%parse-number is deliberately absent. It FAILS when the text is not a number,
%which is its contract, so it is semidet and declaring it det would raise on
%the ordinary case.
:- det('string-length'/2).
:- det('string-slice'/4).
:- det('string-split'/3).
:- det('string-join'/3).
:- det('string-trim'/2).
:- det('string-upper'/2).
:- det('string-lower'/2).
:- det('string-starts-with'/3).
:- det('string-ends-with'/3).
:- det('string-contains'/3).
:- det('string-index-of'/3).
:- det('string-replace'/4).
:- det('string-chars'/2).
:- det('string-from-chars'/2).
:- det('string-repeat'/3).
:- det('string-pad-left'/4).
:- det('string-pad-right'/4).
:- det('format-args'/3).
:- det('sort-strings'/2).
:- det('number-to-string'/2).
:- det(metta_text/2).
:- det(char_to_string/2).
:- det(separated_by/3).
:- det(replacement_pieces/4).
:- det(filled_pieces/3).
:- det(format_arg_text/2).
:- det(pad_with/5).
