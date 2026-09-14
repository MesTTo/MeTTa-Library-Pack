% Purpose: the Unicode character database and the standard text transformations
%   over it: normalization, case folding, per-character properties, grapheme
%   clusters and code-point validity.
%
%   Every answer comes from the host's own database, which is utf8proc's, so the
%   version that produced it is a head of its own: a normalization is only
%   reproducible beside the version that did it
%   [source: /usr/lib/swi-prolog/library/ext/utf8proc/unicode.pl; commit=a30e0a59e8e16d15705dc0258d7e0a004ae63e4b].
% Assumes:
%   - text is a String and a CHARACTER is either a one-character String or the
%     Number of a code point, because a program reaching for a property has one
%     or the other in hand [tested: lib_unicode:a_character_is_a_string_or_a_code;
%     commit=a30e0a59e8e16d15705dc0258d7e0a004ae63e4b]
%   - the build has library(unicode). The declaration below refuses the library
%     before it loads where it does not, naming what is lost
%     [source: engine/metta.pl:metta_platform_capability/3; commit=a30e0a59e8e16d15705dc0258d7e0a004ae63e4b]
% Guarantees:
%   - the five normalization forms are the five UAX#15 and UAX#31 compositions of
%     unicode-map's flags, and each is that one line rather than a second
%     implementation [tested: lib_unicode:each_form_is_a_composition_of_flags;
%     commit=a30e0a59e8e16d15705dc0258d7e0a004ae63e4b]
%   - a property with no value for a character has NO answer, where an unknown
%     property NAME is refused: the first is data about the character and the
%     second is a mistake in the program
%     [tested: lib_unicode:an_absent_property_has_no_answer_and_a_wrong_name_is_refused;
%     commit=a30e0a59e8e16d15705dc0258d7e0a004ae63e4b]
%   - graphemes are the user-perceived characters of UAX#29, so a base character
%     and its combining marks are ONE answer where string-chars answers each code
%     point [tested: lib_unicode:graphemes_group_what_code_points_split;
%     commit=a30e0a59e8e16d15705dc0258d7e0a004ae63e4b]
% Fails when: a caller wants case CONVERSION or any other operation over whole
%   strings. lib_string's string-upper and string-lower are that; case FOLDING
%   here is the different operation UAX#31 defines for caseless comparison, which
%   maps German sharp s to two letters and is not a lowercasing.
% Owns resources: none; every answer is a new string, number or symbol.
% Decides: one head per QUESTION with the variant as an argument, rather than one
%   head per variant: five normalization forms, thirteen properties and fourteen
%   character classes are three heads, and each refusal lists the names it knows.
%   The classes are the database's general categories and never the process
%   locale, which code_type/2 consults and which the twins lane sets to C.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None


:- module(lib_unicode,
          [ 'unicode-version'/1,
            'unicode-normalize'/3,
            'unicode-casefold'/2,
            'unicode-map'/3,
            'unicode-property'/3,
            'unicode-is'/3,
            'unicode-graphemes'/2,
            'unicode-codepoint-valid'/2
          ]).

% Guarantees: private helpers and autoload declarations belong to this module.
% [tested: engine_modules; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
% Assumes: engine operations resolve through metta_engine's published exports.
% [source: engine/metta.pl:metta_engine_reexport/2; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
:- set_module(base(metta_engine)).
:- metta_requires(unicode).

:- use_module(library(error), [must_be/2]).
:- use_module(library(lists), [member/2, memberchk/2]).
:- use_module(library(unicode), [string_graphemes/2, unicode_casefold/2,
                                unicode_codepoint_valid/1, unicode_map/3,
                                unicode_property/2, unicode_version/1]).

%! 'unicode-version'(-Version:string) is det.
%
% The version of the Unicode database every other answer here comes from. A
% normalization is reproducible only beside the version that produced it, which
% is why this is a head rather than a comment.
'unicode-version'(Version) :-
    unicode_version(Atom),
    atom_string(Atom, Version).

%! 'unicode-normalize'(+Form:'Symbol', +Text:string, -Normalized:string) is det.
%
% The text in one of the five standard forms: nfc and nfd are the canonical
% composition and decomposition of UAX#15, nfkc and nfkd their compatibility
% counterparts, and nfkc-casefold the caseless identifier form of UAX#31. Each is
% one composition of unicode-map's flags, named; an unknown form is refused with
% the five listed.
'unicode-normalize'(Form, Text, Normalized) :-
    text_argument('unicode-normalize', Text),
    (   normalization(Form, Flags)
    ->  unicode_map(Text, Mapped, Flags),
        atom_string(Mapped, Normalized)
    ;   findall(Known, normalization(Known, _), Forms),
        throw(error(domain_error(normalization_form, Form),
                    context('unicode-normalize', Forms)))
    ).

% The five forms as the flag sets the host's own convenience predicates use, so
% the library states each derivation rather than calling a second predicate for
% it [source: /usr/lib/swi-prolog/library/ext/utf8proc/unicode.pl:unicode_nfc/2
% and its four siblings; commit=a30e0a59e8e16d15705dc0258d7e0a004ae63e4b].
normalization(nfc, [stable, compose]).
normalization(nfd, [stable, decompose]).
normalization(nfkc, [stable, compose, compat]).
normalization(nfkd, [stable, decompose, compat]).
normalization('nfkc-casefold', [stable, compose, compat, casefold]).

%! 'unicode-casefold'(+Text:string, -Folded:string) is det.
%
% The text case-folded for caseless comparison, which is NOT a lowercasing: it
% maps to whatever compares equal regardless of case, so German sharp s becomes
% two letters and the answer may be longer than the input. lib_string's
% string-lower is the lowercasing.
'unicode-casefold'(Text, Folded) :-
    text_argument('unicode-casefold', Text),
    unicode_casefold(Text, Atom),
    atom_string(Atom, Folded).

%! 'unicode-map'(+Text:string, +Flags:list, -Mapped:string) is det.
%
% The text transformed by a collection of flags in ONE pass, which is the general
% operation the normalizations and the fold are compositions of: stable, compat,
% compose, decompose, ignore, rejectna, nlf2ls, nlf2ps, nlf2lf, stripcc,
% casefold, charbound, lump and stripmark. Stripping accents is
% (compose stripmark); normalising typographic quotes and dashes to ASCII is
% (lump). An unknown flag is refused with the fourteen listed, and so are the two
% combinations the host refuses with nothing but a domain error: compose together
% with decompose, which asks for both directions at once, and stripmark without
% either, which has no form to strip marks from.
'unicode-map'(Text, Flags, Mapped) :-
    text_argument('unicode-map', Text),
    (   is_list(Flags)
    ->  true
    ;   throw(error(type_error(list, Flags),
                    context('unicode-map', 'the flags are a collection of symbols')))
    ),
    forall(member(Flag, Flags),
           (   map_flag(Flag)
           ->  true
           ;   findall(Known, map_flag(Known), Known),
               throw(error(domain_error(unicode_flag, Flag),
                           context('unicode-map', Known)))
           )),
    flags_agree(Flags),
    unicode_map(Text, Atom, Flags),
    atom_string(Atom, Mapped).

% The two conditions the host's own mapper enforces by refusing with
% domain_error(unicode_map_options, Flags) and no reason: composing and
% decomposing at once, and stripping marks with neither
% [measured 2026-09-12: unicode_map("café", O, [decompose, compose]) and
% unicode_map("café", O, [stripmark]) both raise that error, where
% [compose, stripmark] answers "cafe"].
flags_agree(Flags) :-
    (   memberchk(compose, Flags), memberchk(decompose, Flags)
    ->  throw(error(domain_error(unicode_flag_combination, Flags),
                    context('unicode-map',
                            'compose and decompose ask for both directions at once; name one')))
    ;   memberchk(stripmark, Flags),
        \+ ( memberchk(compose, Flags) ; memberchk(decompose, Flags) )
    ->  throw(error(domain_error(unicode_flag_combination, Flags),
                    context('unicode-map',
                            'stripmark needs compose or decompose beside it, because a mark is stripped from a normalized form')))
    ;   true
    ).

% utf8proc's own flag set, which the host passes through unchanged
% [source: /usr/lib/swi-prolog/library/ext/utf8proc/unicode.pl:unicode_map/3;
% commit=a30e0a59e8e16d15705dc0258d7e0a004ae63e4b].
map_flag(stable).
map_flag(compat).
map_flag(compose).
map_flag(decompose).
map_flag(ignore).
map_flag(rejectna).
map_flag(nlf2ls).
map_flag(nlf2ps).
map_flag(nlf2lf).
map_flag(stripcc).
map_flag(casefold).
map_flag(charbound).
map_flag(lump).
map_flag(stripmark).

%! 'unicode-property'(+Character:any, +Property:'Symbol', -Value:any) is semidet.
%
% What the database says about one character: its general category, combining
% class, bidi class and mirroring, compatibility decomposition type, default
% ignorability, grapheme boundary class, display width, East-Asian ambiguity, its
% three single-character case mappings and its Indic conjunct break. A property
% the character has no value for has NO answer, which is data about the
% character; an unknown property name is refused, which is a mistake in the
% program. A case mapping answers the code point, because the mapping is defined
% on code points and not every one has a single-character mapping.
'unicode-property'(Character, Property, Value) :-
    character_code('unicode-property', Character, Code),
    (   property_name(Property, Native)
    ->  Query =.. [Native, Value],
        unicode_property(Code, Query)
    ;   findall(Known, property_name(Known, _), Names),
        throw(error(domain_error(unicode_property, Property),
                    context('unicode-property', Names)))
    ).

% The database's properties under MeTTa's own spelling, which is hyphenated where
% the host's is underscored [source:
% /usr/lib/swi-prolog/library/ext/utf8proc/unicode.pl:unicode_property/2;
% commit=a30e0a59e8e16d15705dc0258d7e0a004ae63e4b].
property_name(category, category).
property_name('combining-class', combining_class).
property_name('bidi-class', bidi_class).
property_name('bidi-mirrored', bidi_mirrored).
property_name('decomp-type', decomp_type).
property_name(ignorable, ignorable).
property_name(boundclass, boundclass).
property_name(width, width).
property_name('ambiguous-width', ambiguous_width).
property_name(uppercase, uppercase).
property_name(lowercase, lowercase).
property_name(titlecase, titlecase).
property_name('indic-conjunct-break', indic_conjunct_break).

%! 'unicode-is'(+Character:any, +Class:'Symbol', -Answer:boolean) is det.
%
% Whether the character belongs to a class the Unicode database defines: letter,
% upper, lower, title, digit, number, mark, punctuation, symbol, separator,
% white-space, control, ascii or assigned. Each is a general category or a group
% of them, white-space is the standard's own White_Space list, and ascii is the
% range; none of them consults the process locale, which is what code_type/2
% does and why it is not the mechanism here. This is the question a lexer asks
% per character, a Bool rather than a failure so it composes with if, and an
% unknown class is refused with the names listed.
'unicode-is'(Character, Class, Answer) :-
    character_code('unicode-is', Character, Code),
    (   character_class(Class, Rule)
    ->  (   in_class(Rule, Code)
        ->  Answer = true
        ;   Answer = false
        )
    ;   findall(Known, character_class(Known, _), Classes),
        throw(error(domain_error(character_class, Class),
                    context('unicode-is', Classes)))
    ).

% The classes as rules over the general category, which is the database's own
% and does not move with the locale: code_type(233, alpha) is false under LC_ALL=C
% and true under a UTF-8 locale, where category(Ll) is Ll under both
% [measured 2026-09-12: the twins lane runs its children under LC_ALL=C and the
% code_type/2 version of this head answered False for "é" there; source:
% https://www.unicode.org/reports/tr44/#General_Category_Values and
% https://www.unicode.org/Public/16.0.0/ucd/PropList.txt (White_Space)].
character_class(letter, prefix('L')).
character_class(upper, category('Lu')).
character_class(lower, category('Ll')).
character_class(title, category('Lt')).
character_class(digit, category('Nd')).
character_class(number, prefix('N')).
character_class(mark, prefix('M')).
character_class(punctuation, prefix('P')).
character_class(symbol, prefix('S')).
character_class(separator, prefix('Z')).
character_class('white-space', white_space).
character_class(control, category('Cc')).
character_class(ascii, ascii).
character_class(assigned, assigned).

in_class(category(Wanted), Code) :-
    unicode_property(Code, category(Wanted)).
in_class(prefix(Letter), Code) :-
    unicode_property(Code, category(Category)),
    sub_atom(Category, 0, 1, _, Letter).
% The standard's White_Space property: every separator, the five ASCII controls
% tab through carriage return, and NEXT LINE.
in_class(white_space, Code) :-
    (   in_class(prefix('Z'), Code)
    ->  true
    % policy-inventory-exempt: mechanism-internal; reason=Unicode White_Space includes TAB through CR and NEXT LINE beside separator categories; evidence=lib/lib_unicode/lib_unicode.pl:in_class/2
    ;   memberchk(Code, [9, 10, 11, 12, 13, 133])
    ).
in_class(ascii, Code) :-
    Code < 128.
in_class(assigned, Code) :-
    unicode_property(Code, category(_)).

%! 'unicode-graphemes'(+Text:string, -Graphemes:list) is det.
%
% The user-perceived characters of UAX#29, one string each: a base character with
% its combining marks is ONE answer, where string-chars answers a code point
% each. This is the length a person counts and the boundary a cursor moves over.
'unicode-graphemes'(Text, Graphemes) :-
    text_argument('unicode-graphemes', Text),
    string_graphemes(Text, Atoms),
    findall(String, ( member(Atom, Atoms), atom_string(Atom, String) ), Graphemes).

%! 'unicode-codepoint-valid'(+Code:integer, -Answer:boolean) is det.
%
% Whether the database ASSIGNS this number a character: in range, not a surrogate
% half, and not unassigned or a noncharacter. It is stricter than "a scalar
% value": U+D7FF and U+10FFFF are in range and are not surrogates, and both are
% unassigned, so both answer False, while a private-use code point is assigned and
% answers True. The same question through the database is whether
% unicode-property answers a category at all
% [measured 2026-09-12: unicode_codepoint_valid/1 answers false for 55295, 65534
% and 1114111, each of which has no category, and true for 57344, whose category
% is Co].
'unicode-codepoint-valid'(Code, Answer) :-
    must_be(integer, Code),
    (   unicode_codepoint_valid(Code)
    ->  Answer = true
    ;   Answer = false
    ).

% A character is a one-character string or the number of a code point, because a
% program reaching for a property has one or the other in hand: the string comes
% from text it is walking, the number from string-codes or from arithmetic.
% The numeric check is the RANGE, not unicode-codepoint-valid: that head answers
% whether the database assigns the number a character, and an unassigned number
% in range is a fair question to ask a property about, which the database answers
% by having nothing to say [measured 2026-09-12: validating with it made
% (unicode-property 1114111 category) raise where it should have no answer].
character_code(Head, Character, Code) :-
    (   integer(Character)
    ->  (   Character >= 0, Character =< 0x10ffff
        ->  Code = Character
        ;   throw(error(domain_error(unicode_codepoint, Character),
                        context(Head, 'a code point is 0..0x10FFFF')))
        )
    ;   string(Character), string_codes(Character, [Code])
    ->  true
    ;   atom(Character), atom_codes(Character, [Code])
    ->  true
    ;   throw(error(type_error(character, Character),
                    context(Head,
                            'a character is a one-character string or the number of a code point; unicode-graphemes or string-codes splits text into either')))
    ).

% The disjunction is PARENTHESISED: `;` binds looser than `->`, so
% `( string(T) ; atom(T) -> true ; throw(...) )` reads as a disjunction whose
% first branch is bare, which left a choicepoint on every string and made the
% det/1 declaration fire [measured 2026-09-12: `Deterministic procedure
% lib_unicode:'unicode-normalize'/3 succeeded with a choicepoint` on the first
% claim of the example].
text_argument(Head, Text) :-
    (   ( string(Text) ; atom(Text) )
    ->  true
    ;   throw(error(type_error(string, Text),
                    context(Head, 'the text is a string')))
    ).

% Every head answers exactly once, except the property, which has no answer for
% a character that has no such value.
:- det('unicode-version'/1).
:- det('unicode-normalize'/3).
:- det('unicode-casefold'/2).
:- det('unicode-map'/3).
:- det('unicode-is'/3).
:- det('unicode-graphemes'/2).
:- det('unicode-codepoint-valid'/2).
