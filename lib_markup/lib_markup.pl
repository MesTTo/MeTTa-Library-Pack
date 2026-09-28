% Purpose: XML and HTML as expressions, with a selector language over them.
%
%   An element is (element Name Attributes Children): the name a Symbol, each
%   attribute an (attr Name Value) row, the children an expression of elements and
%   Strings. A text node is a String, so a program pattern-matches a document with
%   no library call at all, and the host's element/3 compound never reaches MeTTa,
%   where it would be a value no written form could hold
%   [source: /usr/lib/swi-prolog/library/ext/sgml/sgml.pl; commit=ed976b0e70c1176a7ef9feabb0359313105c786e].
%
%   The attribute row is TAGGED for a measured reason: an untagged (Name Value)
%   pair whose name is also a function's, which `id`, `class`, `type` and `value`
%   all are, is evaluated as a CALL where the document is written, so
%   (element d ((id "7")) ()) answers (element d ("7") ()) and the attribute is
%   gone. With the tag the row's head is `attr`, which names no function, and the
%   whole document is inert data [measured 2026-09-12: both forms through the
%   engine, the untagged one losing the name].
% Assumes:
%   - a document is TEXT. An XML parse is strict: the host's parser fixes up a
%     missing end tag, a stray close tag and stray character data with a warning
%     on stderr and answers a DOM anyway, so it passes max_errors(0) and the
%     first complaint becomes a refusal naming it
%     [tested: lib_markup:a_malformed_document_is_refused_rather_than_repaired;
%     commit=ed976b0e70c1176a7ef9feabb0359313105c786e]
%     An HTML parse takes the repairs the DTD decides as HTML's own rules and
%     refuses what it cannot read: under load_html/3's syntax_errors(quiet) the
%     host counts only an error, such as an undefined entity or an attribute
%     written without a value no keyword of the element's holds, against
%     max_errors(0), and drops each warning
%     [source 2026-09-28T11:35:19+10:00: swipl-devel packages/sgml/sgml2pl.c,
%     on_error_ and CHECKERROR]
%     [tested 2026-09-28T13:33:55+10:00: lib_markup:an_html_parse_takes_the_dtds_repairs_and_refuses_what_it_cannot_read]
%   - the build has library(sgml) and library(xpath), which are SWI's ext/sgml
%     pack. The declaration below refuses the library before it loads where they
%     are absent [source: engine/metta.pl:metta_platform_capability/3;
%     commit=ed976b0e70c1176a7ef9feabb0359313105c786e]
% Guarantees:
%   - an HTML parse reads DTD/HTML5.dtd beside this file, generated from the
%     WHATWG HTML Standard by extensions/python/tools/html5dtd.py, whatever
%     HTML5.dtd the host's own library holds and whatever the html_dialect flag
%     says: loading this library puts DTD/ first on file_search_path(dtd, ...),
%     the path dtd('HTML5') resolves over in clause order, and a thread's first
%     HTML parse loads the file that name resolves to, as dtd/2 does, rather
%     than one the flag names, which library(sgml) resets whenever it loads
%     [source 2026-09-28T11:39:07+10:00: swipl-patched.8
%     library/ext/sgml/sgml.pl, dtd/2 and load_html/3, and boot/init.pl,
%     '$chk_alias_file'/6]
%     [tested 2026-09-28T13:33:55+10:00: lib_markup:the_html_dtd_is_this_librarys_own]
%   - an HTML parse changes nothing a later parse reads. HTML has no markup
%     declaration but its DOCTYPE, so a document declaring an entity, an
%     element or an attribute list, in the DOCTYPE's internal subset or after
%     it, is refused; the host's parser has written the declaration into the
%     thread's DTD by then, so that DTD is freed and the next parse loads the
%     file again. An HTML document declaring a SYSTEM entity is refused the
%     same way, so neither kind of parse fetches one
%     [source 2026-09-28T13:06:59+10:00:
%     https://github.com/whatwg/html/blob/2f441941fc523877bd9d5cd7de3b91a81a00ca2e/source#L143365,
%     markup declaration open state]
%     [source 2026-09-28T13:02:19+10:00: swipl-devel packages/sgml/parser.c,
%     process_declaration]
%     [tested 2026-09-28T13:33:55+10:00: lib_markup:a_declaration_is_refused_and_no_later_parse_reads_it]
%   - an HTML parse whose DTD cannot be found raises the host's
%     existence_error(source_sink, dtd('HTML5')) in context of
%     markup-parse-html, because nothing is wrong with the text
%     [tested 2026-09-28T13:33:55+10:00: lib_markup:a_missing_dtd_is_not_a_fault_of_the_text]
%   - an external entity is never fetched: the host refuses a SYSTEM entity by
%     default and this library turns that refusal into an error rather than the
%     silently empty element the warning leaves behind
%     [tested: lib_markup:an_external_entity_is_refused_and_never_fetched;
%     commit=ed976b0e70c1176a7ef9feabb0359313105c786e]
%   - writing an element answers text that parses back to the same element, up to
%     text MERGING: two adjacent text nodes are one run of characters in the markup
%     and come back as one node, and an empty text node has no markup at all
%     [tested: lib_markup:writing_and_parsing_round_trip; commit=ed976b0e70c1176a7ef9feabb0359313105c786e]
%   - every selector answers once per match, in document order, and a selector
%     that matches nothing has no answer
%     [tested: lib_markup:every_selector_answers_once_per_match; commit=ed976b0e70c1176a7ef9feabb0359313105c786e]
% Fails when: a caller wants namespaces resolved into prefixes of their own, a
%   DTD validated, or an HTML5 tree builder. The host's parser reports a namespace
%   as part of the name, validates only what the document declares, and repairs
%   HTML the way SGML does rather than the way a browser does: a custom element's
%   name, a valueless attribute other than a Boolean one or hidden, and an end
%   tag of title, textarea, script, style or iframe with white space before its
%   '>' are outside what the DTD can say.
% Owns resources: one HTML5 DTD per thread, html_dtd_instance/1, loaded by the
%   thread's first HTML parse and freed by a thread_exit listener when the
%   thread or engine ends, the main thread's living as long as the process
%   [source 2026-09-28T13:09:05+10:00: swipl-devel src/pl-thread.c,
%   freePrologThread]; a DTD a declaration reached is freed as the parse that
%   met it returns. Every answer is a new expression, and a parse reads the text
%   it was given and opens no stream of its own.
% Guarded by: user:file_search_path/2's registration and the thread_exit
%   listener's each run once, at load, and are idempotent; a DTD is thread-local,
%   so no two threads parse against one.
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
:- use_module(library(sgml), [free_dtd/1, load_dtd/2, load_structure/3, load_xml/3, new_dtd/2]).
:- use_module(library(sgml_write), [xml_write/3]).
:- use_module(library(xpath), [xpath/3]).

:- multifile user:file_search_path/2.
:- dynamic user:file_search_path/2.

% This library's HTML5 DTD is DTD/HTML5.dtd beside this file, so its directory
% goes FIRST on the dtd path: dtd/2 resolves dtd('HTML5') through
% file_search_path(dtd, Dir) in clause order, and library(sgml) has already
% added library('DTD'), where a host may keep an HTML5.dtd of its own. The
% guard makes a reload leave one clause, as SWI's own library(unicode) does for
% its data directory [source 2026-09-28T12:07:49+10:00: swipl-devel
% library/unicode/unicode_data.pl].
:- prolog_load_context(directory, Here),
   directory_file_path(Here, 'DTD', Directory),
   (   user:file_search_path(dtd, Directory)
   ->  true
   ;   asserta(user:file_search_path(dtd, Directory))
   ).

%! 'markup-parse-xml'(+Text:any, -Element:list) is det.
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

%! 'markup-parse-html'(+Text:any, -Element:list) is det.
%
% One HTML document in the same shape. It is read against this library's own
% HTML5 DTD, derived from the WHATWG HTML Standard, and HTML's rules are the
% DTD's: an omitted end or start tag that HTML allows is not an error, so
% `<p>one<p>two` parses, and so does a tag outside its parent's content model,
% where it stays. An undefined entity, an attribute written without a value that
% is neither Boolean nor hidden, and text that is not markup are refusals, and so
% is a declaration of an entity, an element or an attribute list: HTML declares
% nothing but its DOCTYPE, and the host would keep the declaration for every
% later parse in the thread.
'markup-parse-html'(Text, Element) :-
    text_argument('markup-parse-html', Text),
    html_dtd('markup-parse-html', DTD),
    parsed('markup-parse-html', html_structure(DTD), Text, Element).

% Workaround: swi-sgml-dtd-cache-rolls-back - the thread's DTD is this library's own, in a '$notransact' row freed at thread exit, not dtd/2's cached one.
% The DTD this thread's HTML parses read, loaded by the first of them from the
% file dtd('HTML5') resolves to, as dtd/2 loads the one it caches
% [source 2026-09-28T13:03:34+10:00: swipl-devel packages/sgml/sgml.pl, dtd/2].
% It is this library's own rather than dtd/2's because a document can write a
% declaration into it (html_declaration/2), and only its owner can retire it.
% The DTD comes BEFORE the text is read, outside the catch that makes every
% complaint of the reader a fault of the text: a DTD that cannot be found is the
% host's, and it raises as the host named it, in context of the head.
%
% The row names C memory no rollback gives back, so it is '$notransact', as the
% engine's rows naming things outside the database are: a parse inside a
% transaction or snapshot that loads the DTD keeps it, and one whose refusal
% retires the DTD cannot have the rollback bring back a row naming a DTD
% html_structure/4 has freed [tested 2026-09-28T13:33:55+10:00:
% lib_markup:a_rollback_neither_loses_a_loaded_dtd_nor_revives_a_retired_one].
:- thread_local html_dtd_instance/1.
:- '$notransact'(html_dtd_instance/1).

html_dtd(_, DTD) :-
    html_dtd_instance(DTD),
    !.
html_dtd(Head, DTD) :-
    catch(absolute_file_name(dtd('HTML5'), File, [extensions([dtd]), access(read)]),
          error(existence_error(source_sink, Spec), _),
          throw(error(existence_error(source_sink, Spec),
                      context(Head,
                              'no HTML5 DTD is on the dtd search path; this library puts its own DTD directory there when it loads')))),
    new_dtd(html5, DTD),
    catch(load_dtd(DTD, File), Error, (free_dtd(DTD), throw(Error))),
    asserta(html_dtd_instance(DTD)).

% A thread's DTD goes when the thread does. The listener runs with the exiting
% thread's own data, so html_dtd_instance/1 is that thread's, as library(sgml)
% relies on for its own cache [source 2026-09-28T13:09:05+10:00: swipl-devel
% src/pl-thread.c, freePrologThread]. A host without threads has only the main
% thread.
:- (   current_prolog_flag(threads, true)
   ->  metta_listen(thread_exit, release_html_dtd)
   ;   true
   ).

release_html_dtd(_Thread) :-
    forall(retract(html_dtd_instance(DTD)), free_dtd(DTD)).

% load_html/3 with its dialect named: the DTD, the dialect and quiet warnings
% it adds, where load_html/3 would read the dialect from the html_dialect flag
% [source 2026-09-28T11:32:57+10:00: swipl-devel packages/sgml/sgml.pl,
% load_html/3]. Every declaration in the document reaches html_declaration/2
% first, and a DTD one retired is freed once the parser holding it is done.
html_structure(DTD, Source, Document, Options) :-
    call_cleanup(load_structure(Source, Document,
                                [dtd(DTD), dialect(html5), syntax_errors(quiet),
                                 call(decl, html_declaration)|Options]),
                 free_retired(DTD)).

free_retired(DTD) :-
    (   html_dtd_instance(DTD)
    ->  true
    ;   free_dtd(DTD)
    ).

% Workaround: swi-sgml-html-declaration-written-into-dtd - a declaration other than DOCTYPE retires the thread's DTD and refuses the document.
% HTML has no markup declaration but its DOCTYPE: after `<!` a comment is
% `--`, which reaches this as '', and anything else is an
% incorrectly-opened-comment parse error [source 2026-09-28T13:06:59+10:00:
% https://github.com/whatwg/html/blob/2f441941fc523877bd9d5cd7de3b91a81a00ca2e/source#L143365].
% The host's parser calls this before it dispatches a declaration and writes
% the declaration into the DTD whatever this answers [source
% 2026-09-28T13:02:19+10:00: swipl-devel packages/sgml/parser.c,
% process_declaration], so a document declaring anything else has changed the
% DTD every later parse in the thread would read: it is refused, and the DTD
% leaves the thread's cache here, to be freed by html_structure/4. The host
% calls this by name with the declaration and the parser, so the DTD it retires
% is the thread's one.
html_declaration('', _) :- !.
html_declaration(Declaration, _) :-
    sub_atom_icasechk(Declaration, 0, doctype),
    !.
html_declaration(Declaration, _) :-
    retractall(html_dtd_instance(_)),
    throw(error(syntax_error(declaration(Declaration)), _)).

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
refuse_parse(Head, error(syntax_error(declaration(Declaration)), _)) :-
    !,
    throw(error(syntax_error(markup(declaration(Declaration))),
                context(Head,
                        'HTML declares nothing but its DOCTYPE; a declaration would reach every later parse'))).
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

%! 'markup-write'(+Element:any, -Text:string) is det.
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

%! 'markup-select'(+Element:any, +Selector:'Atom', -Selected:any) is nondet.
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
% [source: /usr/lib/swi-prolog/library/ext/sgml/xpath.pl:xpath/3; commit=ed976b0e70c1176a7ef9feabb0359313105c786e].
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

%! 'markup-attribute'(+Element:any, +Name:'Atom', -Value:string) is semidet.
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

%! 'markup-text'(+Element:any, -Text:string) is det.
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
