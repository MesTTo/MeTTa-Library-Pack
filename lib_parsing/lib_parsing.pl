% Purpose: grammars as VALUES, run over text by a definite clause grammar.
%
%   A grammar is an expression built from fourteen primitives and eleven
%   combinators, held rather than evaluated, and grammar-parse runs it over a
%   string the way phrase/2 runs a DCG: every way the grammar matches is an
%   answer, and a text it does not match is NO answer rather than an error. The
%   interpreter is one DCG over code lists that dispatches on the form's head, so
%   a grammar costs what the equivalent hand-written DCG costs plus one dispatch
%   per node [source: /usr/lib/swi-prolog/library/dcg/basics.pl, whose number//1
%   and eos//0 the primitives use; commit=WORKTREE].
% Assumes:
%   - the grammar argument is a well-formed grammar. It is walked before any text
%     is read, and a form the library does not know is refused naming it and
%     listing the forms, because a misspelled combinator would otherwise be a
%     grammar that matches nothing, silently
%     [tested: lib_parsing:a_malformed_grammar_is_refused_before_parsing;
%     commit=WORKTREE]
%   - the character classes are ASCII: digits are 0-9 and blanks are the six
%     ASCII whitespace codes, so nothing here consults the process locale, and a
%     Unicode class is written as (char-if F) over lib_unicode's unicode-is
%     [tested: lib_parsing:the_classes_are_ascii_and_locale_free; commit=WORKTREE]
% Guarantees:
%   - a parse that consumes the whole text answers the grammar's value, one
%     answer per way the grammar matches, and a prefix parse answers the value
%     with the unread rest; many and sep-by answer their longest match first
%     [tested: lib_parsing:whole_and_prefix_parses_agree_with_phrase;
%     commit=WORKTREE]
%   - the primitives answer what dcg/basics answers over the same text where the
%     host has the primitive, and the combinators obey their algebra: cat is
%     associative in its values, alt of one branch is that branch, many is
%     optional over many1 [tested: lib_parsing:the_primitives_agree_with_dcg_basics,
%     lib_parsing:the_combinators_obey_their_algebra; commit=WORKTREE]
%   - a grammar may refer to itself through ref, which evaluates a MeTTa function
%     of no arguments to a grammar when it is reached, so recursive languages are
%     expressible and left recursion is the caller's own contract
%     [tested: lib_parsing:a_grammar_may_recurse_through_ref; commit=WORKTREE]
% Fails when: a caller wants error positions or a longest-failing-prefix report.
%   A failed match is no answer, which is what makes alt and optional compose; a
%   diagnostic parser is written as a grammar whose alt's last branch is (rest).
% Owns resources: none; every answer is a new expression.
% Decides: the value of a primitive is the text it matched, except integer and
%   number, which answer the number, and eos, which answers (); skip drops a
%   value from a cat, map applies a function to one, and as tags one. A grammar
%   built by a program is therefore a parse tree by construction rather than a
%   string to be re-read.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None


:- module(lib_parsing,
          [ 'grammar-parse'/3,
            'grammar-parse-prefix'/3,
            'grammar-forms'/1,
            'grammar-is'/2
          ]).

% Guarantees: private helpers and autoload declarations belong to this module.
% [tested: engine_modules; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
% Assumes: engine operations resolve through metta_engine's published exports.
% [source: engine/metta.pl:metta_engine_reexport/2; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
:- set_module(base(metta_engine)).

:- use_module(library(lists), [member/2, memberchk/2, append/3]).
:- use_module(library(dcg/basics), [number/3, eos/2, remainder/3]).

%! 'grammar-parse'(+Grammar:'Atom', +Text:string, -Value:any) is nondet.
%
% The value of the grammar over the WHOLE text, one answer per way it matches and
% no answer when it does not. The grammar is held, so its forms are read as
% data; it is checked before any text is read, and a form the library does not
% know is refused naming it.
'grammar-parse'(Grammar, Text, Value) :-
    grammar_argument('grammar-parse', Grammar),
    text_codes('grammar-parse', Text, Codes),
    current_metta_module(Module),
    phrase(grammar(Module, Grammar, Raw), Codes),
    surfaced(Raw, Value).

%! 'grammar-parse-prefix'(+Grammar:'Atom', +Text:string, -Answer:list) is nondet.
%
% The value of the grammar over a PREFIX of the text, with the unread rest, as
% (Value Rest): one answer per way it matches, longest first where a repetition
% decides, and no answer when no prefix matches. This is phrase/3 with the
% remainder, and the way a text is read one construct at a time.
'grammar-parse-prefix'(Grammar, Text, [Value, Rest]) :-
    grammar_argument('grammar-parse-prefix', Grammar),
    text_codes('grammar-parse-prefix', Text, Codes),
    current_metta_module(Module),
    phrase(grammar(Module, Grammar, Raw), Codes, RestCodes),
    surfaced(Raw, Value),
    string_codes(Rest, RestCodes).

%! 'grammar-forms'(-Forms:list) is det.
%
% Every form a grammar may be built from, as (Name Arity) pairs, with the arity
% of the variadic ones written as *. This is the vocabulary the refusal lists,
% published so a program can ask for it.
'grammar-forms'(Forms) :-
    findall([Name, Arity], form(Name, Arity), Forms).

%! 'grammar-is'(+Value:any, -Answer:boolean) is det.
%
% Whether the value is a well-formed grammar: every node a known form with its
% arity and every text argument a string. A ref's target is not followed, because
% it is a function evaluated only when the parse reaches it.
'grammar-is'(Value, Answer) :-
    (   well_formed(Value)
    ->  Answer = true
    ;   Answer = false
    ).

% The vocabulary. A leaf answers the text it matched unless said otherwise.
form(lit, 1).              % (lit Text): exactly that text
form(any, 0).              % one character
form('char-in', 1).        % (char-in Text): one character among those
form('char-not-in', 1).    % (char-not-in Text): one character not among those
form('char-if', 1).        % (char-if Function): one character the function answers True for
form(digits, 0).           % one or more ASCII digits
form(integer, 0).          % an optional sign and digits, answering the Number
form(number, 0).           % Prolog number syntax, answering the Number
form(blanks, 0).           % zero or more ASCII whitespace characters
form(nonblanks, 0).        % one or more characters that are not ASCII whitespace
form(until, 1).            % (until Text): zero or more characters not among those
form(quoted, 0).           % a double-quoted string with backslash escapes, answering the content
form(eos, 0).              % the end of the text, answering ()
form(rest, 0).             % everything that remains
form(cat, *).              % (cat G ...): each in turn, answering their values as an expression
form(alt, *).              % (alt G ...): any of them, one answer per branch that matches
form(many, 1).             % (many G): zero or more, longest first, answering the values
form(many1, 1).            % (many1 G): one or more
form(optional, 1).         % (optional G): the value as (V), or () when it does not match
form('sep-by', 2).         % (sep-by G Sep): zero or more G separated by Sep, answering the G values
form(between, 3).          % (between Open G Close): G's value, the two ends dropped
form(skip, 1).             % (skip G): matches G and contributes nothing to a cat
form(map, 2).              % (map Function G): the function applied to G's value
form(as, 2).               % (as Tag G): G's value tagged, (Tag V)
form(token, 1).            % (token G): G with blanks skipped on both sides
form(ref, 1).              % (ref Function): the grammar the function answers, evaluated when reached

% ------------------------------------------------------------ the interpreter

% One clause per form, dispatching on the head. The module is the calling
% space's, so char-if, map and ref apply their functions where the grammar was
% written, the way lib_functional's heads apply theirs.
grammar(_, [lit, Text], Text) -->
    { string_codes(Text, Codes) },
    Codes.
grammar(_, [any], Value) -->
    [Code],
    { string_codes(Value, [Code]) }.
grammar(_, ['char-in', Set], Value) -->
    [Code],
    { string_codes(Set, Codes), memberchk(Code, Codes), string_codes(Value, [Code]) }.
grammar(_, ['char-not-in', Set], Value) -->
    [Code],
    { string_codes(Set, Codes), \+ memberchk(Code, Codes), string_codes(Value, [Code]) }.
% The verdict is READ rather than asked for: passing `true` in as the expected
% answer threads it into the compiled call, and a callee declared det then FAILS
% with its output already bound instead of answering false, which SWI reports as
% `Deterministic procedure ... failed` [measured 2026-09-12: (char-if letter?)
% over "1" raised that for lib_unicode's unicode-is/3].
grammar(Module, ['char-if', Function], Value) -->
    [Code],
    { string_codes(Value, [Code]),
      eval_metta_in_module(Module, [Function, Value], Verdict),
      Verdict == true }.
grammar(_, [digits], Value) -->
    digits1(Codes),
    { string_codes(Value, Codes) }.
grammar(_, [integer], Value) -->
    sign(Sign),
    digits1(Codes),
    { append(Sign, Codes, All), number_codes(Value, All) }.
grammar(_, [number], Value) -->
    number(Value).
grammar(_, [blanks], Value) -->
    blank_run(Codes),
    { string_codes(Value, Codes) }.
grammar(_, [nonblanks], Value) -->
    nonblank_run(Codes),
    { Codes \== [], string_codes(Value, Codes) }.
grammar(_, [until, Set], Value) -->
    { string_codes(Set, Stops) },
    until_run(Stops, Codes),
    { string_codes(Value, Codes) }.
grammar(_, [quoted], Value) -->
    "\"", quoted_body(Codes), "\"",
    { string_codes(Value, Codes) }.
grammar(_, [eos], []) -->
    eos.
grammar(_, [rest], Value) -->
    remainder(Codes),
    { string_codes(Value, Codes) }.
grammar(Module, [cat|Parts], Values) -->
    cat(Parts, Module, Values).
grammar(Module, [alt|Branches], Value) -->
    { member(Branch, Branches) },
    grammar(Module, Branch, Value).
grammar(Module, [many, Part], Values) -->
    many(Module, Part, Values).
grammar(Module, [many1, Part], [Value|Values]) -->
    grammar(Module, Part, Value),
    many(Module, Part, Values).
grammar(Module, [optional, Part], Values) -->
    (   grammar(Module, Part, Value), { Values = [Value] }
    ;   { Values = [] }
    ).
grammar(Module, ['sep-by', Part, Separator], Values) -->
    (   grammar(Module, Part, First),
        separated(Module, Part, Separator, More),
        { Values = [First|More] }
    ;   { Values = [] }
    ).
grammar(Module, [between, Open, Part, Close], Value) -->
    grammar(Module, Open, _),
    grammar(Module, Part, Value),
    grammar(Module, Close, _).
grammar(Module, [skip, Part], '$skip') -->
    grammar(Module, Part, _).
grammar(Module, [map, Function, Part], Value) -->
    grammar(Module, Part, Raw),
    { surfaced(Raw, Argument),
      eval_metta_in_module(Module, [Function, Argument], Value) }.
grammar(Module, [as, Tag, Part], [Tag, Value]) -->
    grammar(Module, Part, Raw),
    { surfaced(Raw, Value) }.
grammar(Module, [token, Part], Value) -->
    blank_run(_),
    grammar(Module, Part, Value),
    blank_run(_).
grammar(Module, [ref, Function], Value) -->
    { eval_metta_in_module(Module, [Function], Grammar),
      grammar_argument(ref, Grammar) },
    grammar(Module, Grammar, Value).

% A skipped part contributes nothing to a cat, and a skip on its own answers ().
cat([], _, []) --> [].
cat([Part|Parts], Module, Values) -->
    grammar(Module, Part, Value),
    { Value == '$skip' -> Values = More ; Values = [Value|More] },
    cat(Parts, Module, More).

surfaced('$skip', []) :- !.
surfaced(Value, Value).

% Longest match first: the repetition is tried before the empty alternative, so
% the first answer is the greedy one and the shorter ones follow on backtracking
% when a later part needs them.
many(Module, Part, [Value|Values]) -->
    grammar(Module, Part, Value),
    many(Module, Part, Values).
many(_, _, []) --> [].

separated(Module, Part, Separator, [Value|Values]) -->
    grammar(Module, Separator, _),
    grammar(Module, Part, Value),
    separated(Module, Part, Separator, Values).
separated(_, _, _, []) --> [].

% ASCII, and only ASCII, so the process locale plays no part: the digits are
% 0-9 and the blanks are tab, newline, vertical tab, form feed, carriage return
% and space. A Unicode class is (char-if F) over lib_unicode's unicode-is.
sign([0'-]) --> "-", !.
sign([]) --> [].

digits1([Code|Codes]) --> digit(Code), digit_run(Codes).
digit_run([Code|Codes]) --> digit(Code), !, digit_run(Codes).
digit_run([]) --> [].
digit(Code) --> [Code], { Code >= 0'0, Code =< 0'9 }.

blank_run([Code|Codes]) --> [Code], { blank_code(Code) }, !, blank_run(Codes).
blank_run([]) --> [].
blank_code(Code) :- memberchk(Code, [9, 10, 11, 12, 13, 32]).

nonblank_run([Code|Codes]) --> [Code], { \+ blank_code(Code) }, !, nonblank_run(Codes).
nonblank_run([]) --> [].

until_run(Stops, [Code|Codes]) --> [Code], { \+ memberchk(Code, Stops) }, !, until_run(Stops, Codes).
until_run(_, []) --> [].

% The four escapes a quoted string carries, and every other character as itself.
quoted_body([Code|Codes]) --> "\\", escape(Code), !, quoted_body(Codes).
quoted_body([Code|Codes]) --> [Code], { Code \== 0'", Code \== 0'\\ }, !, quoted_body(Codes).
quoted_body([]) --> [].
escape(0'") --> "\"".
escape(0'\\) --> "\\".
escape(0'\n) --> "n".
escape(0'\t) --> "t".

% ------------------------------------------------------------ the arguments

% Walked before any text is read, so a form the library does not know is a
% refusal naming it, with the vocabulary beside it. A ref's target is a
% function, checked when the parse reaches it.
grammar_argument(Head, Grammar) :-
    (   well_formed(Grammar)
    ->  true
    ;   bad_form(Grammar, Bad),
        findall(Name, form(Name, _), Names),
        throw(error(domain_error(grammar, Bad),
                    context(Head, Names)))
    ).

well_formed(Grammar) :-
    is_list(Grammar),
    Grammar = [Name|Arguments],
    atom(Name),
    form(Name, Arity),
    length(Arguments, Count),
    ( Arity == * -> true ; Count == Arity ),
    arguments_well_formed(Name, Arguments).

arguments_well_formed(lit, [Text]) :- string(Text).
arguments_well_formed('char-in', [Text]) :- string(Text).
arguments_well_formed('char-not-in', [Text]) :- string(Text).
arguments_well_formed(until, [Text]) :- string(Text).
arguments_well_formed('char-if', [_]).
arguments_well_formed(cat, Parts) :- forall(member(Part, Parts), well_formed(Part)).
arguments_well_formed(alt, Parts) :- Parts \== [], forall(member(Part, Parts), well_formed(Part)).
arguments_well_formed(many, [Part]) :- well_formed(Part).
arguments_well_formed(many1, [Part]) :- well_formed(Part).
arguments_well_formed(optional, [Part]) :- well_formed(Part).
arguments_well_formed('sep-by', [Part, Separator]) :- well_formed(Part), well_formed(Separator).
arguments_well_formed(between, [Open, Part, Close]) :-
    well_formed(Open), well_formed(Part), well_formed(Close).
arguments_well_formed(skip, [Part]) :- well_formed(Part).
arguments_well_formed(map, [_, Part]) :- well_formed(Part).
arguments_well_formed(as, [_, Part]) :- well_formed(Part).
arguments_well_formed(token, [Part]) :- well_formed(Part).
arguments_well_formed(ref, [_]).
arguments_well_formed(Name, []) :- form(Name, 0).

% The innermost node that is not well formed, which is the one to name.
bad_form(Grammar, Bad) :-
    (   is_list(Grammar), Grammar = [Name|Arguments], atom(Name), form(Name, _),
        member(Argument, Arguments), is_list(Argument), \+ well_formed(Argument),
        \+ ( Name == ref ; Name == map, Arguments = [Argument, _] ; Name == as, Arguments = [Argument, _] )
    ->  bad_form(Argument, Bad)
    ;   Bad = Grammar
    ).

text_codes(Head, Text, Codes) :-
    (   string(Text)
    ->  string_codes(Text, Codes)
    ;   throw(error(type_error(string, Text),
                    context(Head, 'the text to parse is a string')))
    ).

:- det('grammar-forms'/1).
:- det('grammar-is'/2).
