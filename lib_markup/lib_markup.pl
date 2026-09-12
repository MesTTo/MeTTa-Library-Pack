% Purpose: XML and HTML as expressions, with a selector language over them.
%
%   An element is (element Name Attributes Children): the name a Symbol, each
%   attribute an (attr Name Value) row, the children an expression of elements and
%   Strings. A text node is a String, so a program pattern-matches a document with
%   no library call at all, and the host's element/3 compound never reaches MeTTa,
%   where it would be a value no written form could hold
%   [source: /usr/lib/swi-prolog/library/ext/sgml/sgml.pl; commit=WORKTREE].
%
%   The attribute row is TAGGED for a measured reason: an untagged (Name Value)
%   pair whose name is also a function's, which `id`, `class`, `type` and `value`
%   all are, is evaluated as a CALL where the document is written, so
%   (element d ((id "7")) ()) answers (element d ("7") ()) and the attribute is
%   gone. With the tag the row's head is `attr`, which names no function, and the
%   whole document is inert data [measured 2026-09-12: both forms through the
%   engine, the untagged one losing the name].
% Assumes:
%   - a document is TEXT, and every parse is strict: the host's parser fixes up a
%     missing end tag, a stray close tag and stray character data with a warning
%     on stderr and answers a DOM anyway, so both parses pass max_errors(0) and
%     the first complaint becomes a refusal naming it
%     [tested: lib_markup:a_malformed_document_is_refused_rather_than_repaired;
%     commit=WORKTREE]
%   - the build has library(sgml) and library(xpath), which are SWI's ext/sgml
%     pack. The declaration below refuses the library before it loads where they
%     are absent [source: engine/metta.pl:metta_platform_capability/3;
%     commit=WORKTREE]
% Guarantees:
%   - an external entity is never fetched: the host refuses a SYSTEM entity by
%     default and this library turns that refusal into an error rather than the
%     silently empty element the warning leaves behind
%     [tested: lib_markup:an_external_entity_is_refused_and_never_fetched;
%     commit=WORKTREE]
%   - writing an element answers text that parses back to the same element, up to
%     text MERGING: two adjacent text nodes are one run of characters in the markup
%     and come back as one node, and an empty text node has no markup at all
%     [tested: lib_markup:writing_and_parsing_round_trip; commit=WORKTREE]
%   - every selector answers once per match, in document order, and a selector
%     that matches nothing has no answer
%     [tested: lib_markup:every_selector_answers_once_per_match; commit=WORKTREE]
% Fails when: a caller wants namespaces resolved into prefixes of their own, a
%   DTD validated, or an HTML5 tree builder. The host's parser reports a namespace
%   as part of the name, validates only what the document declares, and repairs
%   HTML the way SGML does rather than the way a browser does.
% Owns resources: none; every answer is a new expression. A parse reads the text
%   it was given and opens no stream of its own.
% Decides: the selector language is an EXPRESSION, converted to the host's xpath
%   term: (descendant Name), (child Name), (index N Selector), (attribute Name),
%   (text), and a path as a collection of steps. An unknown step is refused with
%   the five listed, because a misspelled step would otherwise select nothing.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None


:- module(lib_markup,
          [ 'markup-parse-xml'/2,
            'markup-parse-html'/2,
            'markup-write'/2,
            'markup-select'/3,
            'markup-attribute'/3,
            'markup-text'/2
          ]).

% Guarantees: private helpers and autoload declarations belong to this module.
% [tested: engine_modules; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
% Assumes: engine operations resolve through metta_engine's published exports.
% [source: engine/metta.pl:metta_engine_reexport/2; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
:- set_module(base(metta_engine)).
:- metta_requires(markup).

:- use_module(library(apply), [maplist/3]).
:- use_module(library(lists), [append/3, member/2, memberchk/2]).
:- use_module(library(sgml), [load_html/3, load_xml/3]).
:- use_module(library(sgml_write), [xml_write/3]).
:- use_module(library(xpath), [xpath/3]).

%! 'markup-parse-xml'(+Text:string, -Element:list) is det.
%
% One XML document as (element Name Attributes Children): the name a Symbol, each
% attribute an (attr Name Value) row and the children an expression of elements
% and Strings. The attribute row is tagged so that a document holding an `id` or a
% `class` is inert data rather than a call.
%
% The parse is STRICT. The host's parser repairs a missing end tag, a stray close
% tag and character data outside any element, warns on stderr and answers a DOM
% anyway; every one of those becomes a refusal here, because a document that
% needed repair is a document the sender got wrong. An external SYSTEM entity is
% refused for the same reason, which is also what keeps a parse from fetching a
% file or a URL the document names.
'markup-parse-xml'(Text, Element) :-
    text_argument('markup-parse-xml', Text),
    parsed('markup-parse-xml', load_xml, Text, Element).

%! 'markup-parse-html'(+Text:string, -Element:list) is det.
%
% One HTML document in the same shape. HTML's own rules are the host's: an omitted
% end tag that HTML allows is not an error, so `<p>one<p>two` parses, while a
% stray close tag or unparseable text is still a refusal.
'markup-parse-html'(Text, Element) :-
    text_argument('markup-parse-html', Text),
    parsed('markup-parse-html', load_html, Text, Element).

parsed(Head, Loader, Text, Element) :-
    (   catch(call(Loader, string(Text), Document, [max_errors(0), space(preserve)]),
              Error,
              refuse_parse(Head, Error))
    ->  true
    ;   throw(error(syntax_error(markup('no element')),
                    context(Head, 'the text holds no element')))
    ),
    (   Document = [Only]
    ->  element_form(Only, Element)
    ;   Document == []
    ->  throw(error(syntax_error(markup('no element')),
                    context(Head, 'the text holds no element')))
    ;   throw(error(domain_error(one_root_element, Document),
                    context(Head,
                            'a document has one root element; this text holds several')))
    ).

% Every complaint from the host's parser becomes one refusal, whatever shape it
% arrived in: max_errors(0) raises syntax_error(Message) for a repair it would
% otherwise make, and the empty document raises representation_error(code_point)
% from the reader instead [measured 2026-09-12: load_xml over "" raises that]. A
% control signal is rethrown untouched, because a caught limit or interrupt is a
% stopped program pretending it parsed.
refuse_parse(_, Error) :-
    control_exception(Error), !,
    throw(Error).
refuse_parse(Head, error(syntax_error(Message), _)) :-
    !,
    throw(error(syntax_error(markup(Message)),
                context(Head,
                        'the host parser would have repaired this document; a parse here refuses instead'))).
refuse_parse(Head, error(Formal, _)) :-
    !,
    throw(error(syntax_error(markup(Formal)),
                context(Head, 'the host reader could not read this text as markup'))).
refuse_parse(Head, Error) :-
    throw(error(syntax_error(markup(Error)),
                context(Head, 'the host reader could not read this text as markup'))).

% The host's element/3 compound becomes an expression, its attribute list a
% relation, and every text node a String: a compound crossing into MeTTa is a
% value no written form can hold, which the datastructures row measured.
element_form(element(Name, Attributes, Children), [element, Name, Pairs, Parts]) :-
    !,
    maplist(attribute_pair, Attributes, Pairs),
    maplist(child_form, Children, Parts).
element_form(Text, String) :-
    atom_string(Text, String).

attribute_pair(Name=Value, [attr, Name, String]) :-
    atom_string(Value, String).

child_form(Child, Form) :- element_form(Child, Form).

%! 'markup-write'(+Element:list, -Text:string) is det.
%
% The element as XML text, without the declaration the host writes by default and
% without layout, so the text is exactly the element's own markup and parses back
% to it.
'markup-write'(Element, Text) :-
    element_term('markup-write', Element, Term),
    with_output_to(string(Text),
                   xml_write(current_output, Term,
                             [header(false), layout(false)])).

% The way back: an expression becomes the host's compound so the writer can take
% it, and a String becomes the atom a text node is.
element_term(Head, [element, Name, Pairs, Parts], element(Name, Attributes, Children)) :-
    !,
    (   atom(Name)
    ->  true
    ;   throw(error(type_error(symbol, Name),
                    context(Head, 'an element name is a Symbol')))
    ),
    maplist(term_attribute(Head), Pairs, Attributes),
    maplist(term_child(Head), Parts, Children).
element_term(_, Text, Atom) :-
    string(Text), !,
    atom_string(Atom, Text).
element_term(Head, Other, _) :-
    throw(error(type_error(markup_element, Other),
                context(Head,
                        'an element is (element Name Attributes Children) and a text node is a String'))).

term_attribute(Head, Pair, Name=Value) :-
    (   Pair = [attr, Name, Text], atom(Name)
    ->  (   string(Text)
        ->  atom_string(Value, Text)
        ;   atom(Text)
        ->  Value = Text
        ;   number(Text)
        ->  Value = Text
        ;   throw(error(type_error(markup_attribute_value, Text),
                        context(Head, 'an attribute value is a String, a Symbol or a Number')))
        )
    ;   throw(error(type_error(markup_attribute, Pair),
                    context(Head,
                            'an attribute is an (attr Name Value) row whose name is a Symbol; the tag is what keeps a document holding an id or a class from being read as a call')))
    ).

term_child(Head, Part, Child) :- element_term(Head, Part, Child).

%! 'markup-select'(+Element:list, +Selector:'Atom', -Selected:any) is nondet.
%
% Every match of the selector, one answer each and in document order. A selector
% that matches nothing has no answer, which is what makes a selection compose with
% collapse and with an if over it.
%
% The selector is an expression, and a collection of steps is a path:
% (descendant Name) is every element of that name at any depth, (child Name) every
% immediate child of that name, and (self Name) the element itself when it carries
% that name. The other three MODIFY the step they follow:
% (index N) takes the Nth match counting from one, (attribute Name) answers that
% attribute's value as a String and (text) answers the element's text content. An
% unknown form is refused with the five listed.
'markup-select'(Element, Selector, Selected) :-
    element_term('markup-select', Element, Term),
    selector_spec('markup-select', Selector, Spec),
    xpath(Term, Spec, Found),
    selected_form(Found, Selected).

selected_form(Found, Form) :-
    (   Found = element(_, _, _)
    ->  element_form(Found, Form)
    ;   atom(Found)
    ->  atom_string(Found, Form)
    ;   Form = Found
    ).

% The selector language, converted to the host's own xpath term. A selector is one
% STEP or a path of them, and the three MODIFIERS attach to the step they follow:
% xpath spells a modifier as an extra argument on the step's own term, `//(item(text))`
% rather than `//(item)/text`, which is why they are not steps of their own
% [source: /usr/lib/swi-prolog/library/ext/sgml/xpath.pl:xpath/3; commit=WORKTREE].
selector_spec(Head, Selector, Spec) :-
    selector_forms(Head, Selector, Forms),
    folded_steps(Head, Forms, Steps),
    path_spec(Steps, Spec).

selector_forms(Head, Selector, Forms) :-
    (   element_step(Selector, _, _)
    ->  Forms = [Selector]
    ;   modifier(Selector, _)
    ->  Forms = [Selector]
    ;   is_list(Selector), Selector \== [], forall(member(Form, Selector), is_list(Form))
    ->  Forms = Selector
    ;   refuse_selector(Head, Selector)
    ).

% Each element step starts a term, and every modifier that follows it becomes one
% of that term's arguments. A modifier with no step before it is a refusal, because
% there is nothing for it to modify.
folded_steps(Head, Forms, Steps) :-
    folded_steps(Head, Forms, [], Steps).

folded_steps(_, [], Pending, Steps) :-
    (   Pending == []
    ->  Steps = []
    ;   Pending = [Step|Modifiers],
        finished_step(Step, Modifiers, Finished),
        Steps = [Finished]
    ).
folded_steps(Head, [Form|Forms], Pending, Steps) :-
    (   element_step(Form, _, _)
    ->  (   Pending == []
        ->  folded_steps(Head, Forms, [Form], Steps)
        ;   Pending = [Step|Modifiers],
            finished_step(Step, Modifiers, Finished),
            folded_steps(Head, Forms, [Form], Rest),
            Steps = [Finished|Rest]
        )
    ;   modifier(Form, _)
    ->  (   Pending == []
        ->  throw(error(domain_error(markup_selector, Form),
                        context(Head,
                                'a modifier applies to the step before it; name an element step first')))
        ;   append(Pending, [Form], Grown),
            folded_steps(Head, Forms, Grown, Steps)
        )
    ;   refuse_selector(Head, Form)
    ).

% The step's own term, with every modifier as an argument: xpath reads
% `//(item(2, @n))` as "the second item, its n attribute". The direction is the
% term the step becomes: a child is the BARE name, a descendant is //(Name), and
% the element itself is /(Name), which is what the host's own reader means by each
% [measured 2026-09-12: over <d><a><i>1</i></a></d>, xpath/3 answers the inner i
% for the bare name `a` under a path and nothing for /(a), because /(Name) asks
% whether the context element itself is named that].
finished_step(Step, Modifiers, Finished) :-
    element_step(Step, Direction, Name),
    findall(Argument, ( member(Modifier, Modifiers), modifier(Modifier, Argument) ), Arguments),
    (   Arguments == []
    ->  Term = Name
    ;   Term =.. [Name|Arguments]
    ),
    (   Direction == bare
    ->  Finished = Term
    ;   Finished =.. [Direction, Term]
    ).

element_step([descendant, Name], //, Name) :- atom(Name).
element_step([child, Name], bare, Name) :- atom(Name).
element_step([self, Name], /, Name) :- atom(Name).

modifier([text], text).
modifier([attribute, Name], @(Name)) :- atom(Name).
modifier([index, Number], Number) :- integer(Number), Number >= 1.

refuse_selector(Head, Selector) :-
    findall(Name, step_name(Name), Names),
    throw(error(domain_error(markup_selector, Selector),
                context(Head, Names))).

step_name(descendant).
step_name(child).
step_name(self).
step_name(index).
step_name(attribute).
step_name(text).

% A path folds to the LEFT, which is how the host's own operators read it:
% `//a/i` is /(//(a), i) and not //(a)/(i).
path_spec([First|Steps], Spec) :- path_spec(Steps, First, Spec).

path_spec([], Spec, Spec).
path_spec([Step|Steps], Acc, Spec) :- path_spec(Steps, Acc/Step, Spec).

%! 'markup-attribute'(+Element:list, +Name:'Atom', -Value:string) is semidet.
%
% One attribute's value as a String, with no answer when the element does not
% carry it, which is the shape a lookup has here and in lib_pairs.
%
% The name is HELD, which an attribute name has to be: one is often called id,
% class or type, and each of those is also a name the engine knows. Declared Symbol
% the call was refused with a BadArgType naming the identity function's arrow, and
% declared %Undefined% the name was evaluated and matched nothing
% [measured 2026-09-12: both, over (markup-attribute $doc id)].
'markup-attribute'(Element, Name, Value) :-
    (   Element = [element, _, Pairs, _]
    ->  member([attr, Found, Value], Pairs),
        Found == Name
    ;   throw(error(type_error(markup_element, Element),
                    context('markup-attribute',
                            'an element is (element Name Attributes Children)')))
    ).

%! 'markup-text'(+Element:list, -Text:string) is det.
%
% Every text node under the element, in document order, joined: the content a
% reader sees with the markup taken out. An element with no text answers the empty
% String.
'markup-text'(Element, Text) :-
    (   Element = [element, _, _, Children]
    ->  findall(Part, ( member(Child, Children), text_part(Child, Part) ), Parts),
        atomic_list_concat(Parts, Joined),
        atom_string(Joined, Text)
    ;   string(Element)
    ->  Text = Element
    ;   throw(error(type_error(markup_element, Element),
                    context('markup-text',
                            'an element is (element Name Attributes Children) and a text node is a String')))
    ).

text_part(Child, Part) :-
    (   string(Child)
    ->  Part = Child
    ;   Child = [element, _, _, _]
    ->  'markup-text'(Child, Part)
    ;   fail
    ).

text_argument(Head, Text) :-
    (   ( string(Text) ; atom(Text) )
    ->  true
    ;   throw(error(type_error(string, Text),
                    context(Head, 'the document to parse is a string')))
    ).

:- det('markup-parse-xml'/2).
:- det('markup-parse-html'/2).
:- det('markup-write'/2).
:- det('markup-text'/2).
