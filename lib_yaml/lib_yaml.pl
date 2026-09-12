% Purpose: YAML documents as MeTTa values, in the shape lib_json already uses.
%
%   A mapping becomes a SPACE of (Key Value) atoms, a sequence an expression, a
%   string a String, a number a Number, the two booleans True and False, and null
%   Null. That is lib_json's own decision, and it is taken here rather than
%   invented so that one traversal walks both formats: lib_json's json-at follows
%   a path through a YAML value, and dict-space builds the mappings
%   [source: lib/lib_json/lib_json.pl:'dict-space'/2; commit=672e5be181839a8301ba70bc6ead69678f3735bd].
% Assumes:
%   - one document per call. The host's yaml_read/2 loads exactly one and FAILS on
%     a stream holding more, whatever markers it carries, so a multi-document
%     stream is refused by name rather than answered wrongly
%     [tested: lib_yaml:a_multi_document_stream_is_refused_by_name; commit=672e5be181839a8301ba70bc6ead69678f3735bd]
%   - the build has library(yaml), which is SWI's ext/yaml pack over libyaml. The
%     declaration below refuses the library before it loads where it does not
%     [source: engine/metta.pl:metta_platform_capability/3; commit=672e5be181839a8301ba70bc6ead69678f3735bd]
% Guarantees:
%   - decoding and encoding round-trip every value this library can decode, so
%     the text a value encodes to decodes back to that value
%     [tested: lib_yaml:decoding_and_encoding_round_trip; commit=672e5be181839a8301ba70bc6ead69678f3735bd]
%   - an unsupported tag is refused NAMING the tag, where the host answers an
%     opaque tag(Tag, Text) term that no MeTTa form can read
%     [tested: lib_yaml:an_unknown_tag_is_refused_by_name; commit=672e5be181839a8301ba70bc6ead69678f3735bd]
%   - a duplicate key, malformed text and an unreadable number are each refused
%     with the host's own line number where it has one
%     [tested: lib_yaml:malformed_text_is_refused_with_its_line; commit=672e5be181839a8301ba70bc6ead69678f3735bd]
% Fails when: a caller wants anchors preserved as sharing, comments kept, or key
%   order preserved. libyaml resolves an alias into a copy before this library
%   sees it, comments are not part of the data model, and a mapping is a space,
%   whose atoms answer in storage order rather than the document's.
% Fails when: a document means null by writing a key with NO value. The host's
%   reader answers the empty string for `note:` and cannot be told apart from
%   `note: ""`, where YAML 1.2 reads an omitted value as null, so a document that
%   means null writes `~` or `null`
%   [measured 2026-09-12: yaml_read/2 over "k:\n" answers yaml{k:""} and over
%   "k: ~\n" answers yaml{k:null}; tested:
%   lib_yaml:an_omitted_value_is_the_empty_string_and_not_null; commit=672e5be181839a8301ba70bc6ead69678f3735bd].
% Owns resources: every mapping is a space this library created and the caller
%   owns, exactly as lib_json's decoder hands one over; a failed decode releases
%   every space it made before raising.
% Decides: the file doors are DERIVED in the face rather than implemented here:
%   yaml-read! is yaml-decode over lib_file's read-file! and yaml-write! is
%   lib_file's replace-file! over yaml-encode, so this library holds no second
%   copy of the publication protocol.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None


:- module(lib_yaml,
          [ 'yaml-decode'/2,
            'yaml-encode'/2
          ]).

% Guarantees: private helpers and autoload declarations belong to this module.
% [tested: engine_modules; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
% Assumes: engine operations resolve through metta_engine's published exports.
% [source: engine/metta.pl:metta_engine_reexport/2; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
:- set_module(base(metta_engine)).
:- metta_requires(yaml).

:- use_module('../lib_json/lib_json', ['dict-space'/2]).
:- use_module(library(error), [must_be/2]).
:- use_module(library(lists), [member/2, memberchk/2]).
:- use_module(library(yaml), [yaml_read/2, yaml_write/3]).

%! 'yaml-decode'(+Text:string, -Value:any) is det.
%
% One YAML document as a MeTTa value: a mapping becomes a space of (Key Value)
% atoms, a sequence an expression, a string a String, a number a Number, the
% booleans True and False, and null Null. An empty document is Null, because that
% is what YAML says an empty document holds.
%
% A stream holding more than one document is refused naming the marker: the host's
% reader loads exactly one and fails on the rest, so answering the first would be
% answering less than the text says. An unsupported tag, a duplicate key and
% malformed text are each refused, the last with the line the host reports.
'yaml-decode'(Text, Value) :-
    text_argument('yaml-decode', Text),
    read_document(Text, Document),
    document_value(Document, Value).

read_document(Text, Document) :-
    (   catch(setup_call_cleanup(open_string(Text, Stream),
                                yaml_read(Stream, Read),
                                close(Stream)),
              error(yaml_error(Line, Message), _),
              throw(error(syntax_error(yaml(Line, Message)),
                          context('yaml-decode', 'the host reader names the line it stopped on'))))
    ->  Document = Read
    ;   documents_marked(Text)
    ->  throw(error(domain_error(one_yaml_document, Text),
                    context('yaml-decode',
                            'the host reader takes one document and this stream holds a --- marker; split the stream and decode each piece')))
    ;   throw(error(syntax_error(yaml(unknown, 'no document')),
                    context('yaml-decode',
                            'the host reader answered no document for this text')))
    ).

% Only ever asked once a read has already failed, and only to say WHY: a `---`
% line at the start of a line is the document marker, and its presence is the
% difference between "more than one document" and "not YAML at all".
documents_marked(Text) :-
    (   sub_string(Text, Before, 3, _, "---"),
        (   Before == 0
        ->  true
        ;   Preceding is Before - 1,
            sub_string(Text, Preceding, 1, _, "\n")
        )
    ->  true
    ;   sub_string(Text, _, 3, _, "...")
    ).

% One clause per shape the host's reader can answer. A dict is a mapping, a list
% a sequence, `null` the null scalar, an unbound variable the empty document, and
% tag/2 a tag the library has no value for.
document_value(Document, Value) :-
    (   var(Document)
    ->  Value = 'Null'
    ;   is_dict(Document)
    ->  mapping_space(Document, Value)
    ;   is_list(Document)
    ->  sequence_values(Document, Value)
    ;   scalar_value(Document, Value)
    ).

% The rows are built BEFORE the space is, so a nested mapping that raises leaves
% no space of this one behind: dict-space allocates last and owns what it made,
% which is lib_json's own protocol for the same job
% [source: lib/lib_json/lib_json.pl:'dict-space'/2, whose with_outcome_cleanup
% releases every space it created on a failed construction; commit=672e5be181839a8301ba70bc6ead69678f3735bd].
mapping_space(Dict, Space) :-
    dict_pairs(Dict, _, Pairs),
    findall([Key, Value],
            ( member(Name-Raw, Pairs),
              key_name(Name, Key),
              document_value(Raw, Value) ),
            Rows),
    'dict-space'(Rows, Space).

% A YAML key is a scalar, and the host answers it as an atom, so it arrives as a
% Symbol: that is what a space query writes, and a String key would need quoting
% at every call site.
key_name(Name, Key) :-
    (   atom(Name)
    ->  Key = Name
    ;   number(Name)
    ->  Key = Name
    ;   atom_string(Name, Key)
    ).

sequence_values(Items, Values) :-
    findall(Value, ( member(Item, Items), document_value(Item, Value) ), Values).

scalar_value(Scalar, Value) :-
    (   Scalar == null
    ->  Value = 'Null'
    ;   Scalar == true
    ->  Value = true
    ;   Scalar == false
    ->  Value = false
    ;   number(Scalar)
    ->  Value = Scalar
    ;   string(Scalar)
    ->  Value = Scalar
    ;   Scalar = tag(Tag, Content)
    ->  throw(error(domain_error(yaml_tag, Tag),
                    context('yaml-decode',
                            'the host has no value for this tag; the standard ones are !!str, !!int, !!float, !!bool, !!null, !!binary, !!seq and !!map')))
    ;   atom(Scalar)
    ->  atom_string(Scalar, Value)
    ;   throw(error(type_error(yaml_scalar, Scalar),
                    context('yaml-decode', 'the host answered a term this library has no value for')))
    ).

%! 'yaml-encode'(+Value:any, -Text:string) is det.
%
% One YAML document as text: a space becomes a mapping of its (Key Value) atoms,
% an expression a sequence, a String a string, a Number a number, True and False
% the booleans and Null the null scalar. The text ends in a newline, as a YAML
% document does, and keys come out in the host writer's order rather than the
% space's.
'yaml-encode'(Value, Text) :-
    value_document(Value, Document),
    with_output_to(string(Text),
                   yaml_write(current_output, Document, [])).

value_document(Value, Document) :-
    (   Value == 'Null'
    ->  Document = null
    ;   Value == true
    ->  Document = true
    ;   Value == false
    ->  Document = false
    ;   number(Value)
    ->  Document = Value
    ;   string(Value)
    ->  Document = Value
    ;   is_list(Value)
    ->  findall(Item, ( member(Part, Value), value_document(Part, Item) ), Document)
    ;   space_value(Value, Rows)
    ->  findall(Name-Item,
                ( member([Key, Part], Rows),
                  document_key(Key, Name),
                  value_document(Part, Item) ),
                Pairs),
        dict_pairs(Document, yaml, Pairs)
    ;   atom(Value)
    ->  atom_string(Value, Document)
    ;   throw(error(type_error(yaml_value, Value),
                    context('yaml-encode',
                            'a YAML value is a space, an expression, a String, a Number, True, False or Null')))
    ).

% A mapping to encode is a space, read through the engine's own enumeration, and
% every atom in it has to be a (Key Value) pair: a space holding anything else is
% not a mapping and says so rather than losing the atom.
space_value(Space, Rows) :-
    metta_space_operand(Space),
    findall([Key, Value], 'get-atoms'(Space, [Key, Value]), Rows),
    findall(Atom, ( 'get-atoms'(Space, Atom),
                    \+ ( is_list(Atom), Atom = [_, _] ) ), Others),
    (   Others == []
    ->  true
    ;   Others = [First|_],
        throw(error(type_error(key_value_pair, First),
                    context('yaml-encode', 'a mapping is a space of (Key Value) atoms')))
    ).

document_key(Key, Name) :-
    (   atom(Key)
    ->  Name = Key
    ;   string(Key)
    ->  atom_string(Name, Key)
    ;   number(Key)
    ->  Name = Key
    ;   throw(error(type_error(yaml_key, Key),
                    context('yaml-encode', 'a key is a Symbol, a String or a Number')))
    ).

text_argument(Head, Text) :-
    (   ( string(Text) ; atom(Text) )
    ->  true
    ;   throw(error(type_error(string, Text),
                    context(Head, 'the document to decode is a string')))
    ).

:- det('yaml-decode'/2).
:- det('yaml-encode'/2).
