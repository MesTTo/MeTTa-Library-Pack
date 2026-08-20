% Purpose: JSON, and the dict-as-space it decodes into. MeTTa HE's surface
%   exactly: json-decode, json-encode, dict-space, get-keys and get-value
%   [source 2026-08-15: MeTTa HE stdlib, JSON].
%
%   HE's decision is the interesting one and it is right: a JSON object becomes
%   a SPACE of (key value) atoms, not an opaque dict value. So looking a key up
%   is a match, a decoded document is queryable with the same operations as any
%   other space, and there is no new type to learn.
% Assumes:
%   - a MeTTa string is an SWI string and a space is an atom beginning with &
%     [source: engine/metta.pl, 'is-space'/2]
% Guarantees:
%   - decode and encode round-trip an object, an array, a string, a number and
%     the three literals [tested: lib_json]
%   - the conversions are deterministic, so a recursive decode keeps last call
%     optimisation and does not retain a frame per element [measured
%     2026-08-15: a walk whose step leaves a choice point holds 81,600,096
%     bytes of local stack over 300,000 elements where a deterministic step
%     holds 0; verified here by plunit reporting no choicepoint on any
%     lib_json test]
%   - an unhandled shape raises existence_error(matching_rule, _) rather than
%     failing silently, because the conversions are =>/2 rules [tested: lib_json:malformed_json_raises_rather_than_answering_empty]
% Fails when:
%   - the text is not JSON. That is an error naming the position, from SWI's
%     own reader, rather than a silent failure that reads as an empty document.
% Owns:
%   - one storage module per decoded object, named &json-N. These live as long
%     as the process; a decoded document is data, and dropping it silently
%     while a caller still held the handle would be worse than keeping it.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- use_module(library(http/json)).
:- use_module(library(lists)).

:- dynamic petta_json_counter/1.

petta_json_counter(0).

next_json_space(Space) :-
    with_mutex('$petta_json',
               ( retract(petta_json_counter(N)),
                 Next is N + 1,
                 assertz(petta_json_counter(Next)) )),
    atom_concat('&json-', Next, Space).

% ------------------------------------------------------------------ decode

'json-decode'(Text, Out) :-
    metta_text(Text, Json),
    atom_json_term(Json, Term, [value_string_as(string)]),
    json_to_metta(Term, Out).

%One rule per JSON shape, as single sided unification rules. The earlier
%version claimed first-argument indexing made these deterministic without a
%cut. That was wrong, and plunit had been reporting it as eight tests
%"succeeded with choicepoint": a clause whose first argument is a variable
%cannot be excluded by any index, and the manual is blunter still, that a
%predicate with more than 10% such clauses is not considered for indexing on
%that argument at all [source: SWI-Prolog 10.1 Reference Manual, section 2.17].
%With one variable-headed clause in four, this predicate was a linear scan.
%
%What that cost is memory, not time. A leftover choice point defeats last call
%optimisation, so a recursive walk retains every frame [measured 2026-08-15,
%300,000 elements: 81,600,096 bytes of local stack against 0]. Time was within
%noise at min-of-7.
%
%=>/2 rather than a cut because these are single moded (+,-) conversions where
%an unhandled shape should be an error, not a silent failure, and because the
%head of an =>/2 rule cannot bind the caller's term. That is the steadfastness
%trap: adding a cut to a clause that binds its output in the head is what makes
%max(5,2,2) succeed [source: same manual, section 5.6, citing The Craft of
%Prolog]. Output is unified in the body here for that reason.
json_to_metta(json(Pairs), Space) =>
    next_json_space(Space),
    forall(member(Key = Value, Pairs),
           ( json_to_metta(Value, MettaValue),
             'add-atom'(Space, [Key, MettaValue], _) )).
json_to_metta(@(Literal), Out) =>
    json_literal(Literal, Out).
json_to_metta([Head|Tail], Out) =>
    Out = [MettaHead|MettaTail],
    json_to_metta(Head, MettaHead),
    json_to_metta_list(Tail, MettaTail).
json_to_metta(Value, Out), atomic(Value) =>
    Out = Value.

json_to_metta_list([], []).
json_to_metta_list([Head|Tail], [MettaHead|MettaTail]) :-
    json_to_metta(Head, MettaHead),
    json_to_metta_list(Tail, MettaTail).

%PeTTa's booleans are lowercase: the reader normalises True to true and False
%to false, and every engine predicate answers true/false, so JSON's literals
%map onto those rather than onto HE's capitalised spelling. Null has no PeTTa
%equivalent and the reader leaves it alone, so it stays as written
%[verified 2026-08-15: sread("(True False Null true)", T) gives
%[true,false,'Null',true]].
json_literal(true, true).
json_literal(false, false).
json_literal(null, 'Null').

% ------------------------------------------------------------------ encode

'json-encode'(Value, Text) :-
    metta_to_json(Value, Term),
    atom_json_term(Atom, Term, [as(atom)]),
    atom_string(Atom, Text).

%Rules rather than clauses, for the reasons on json_to_metta/2 above. The
%three literals are named atoms and are matched before the general atom rule.
metta_to_json(true, Out) => Out = @(true).
metta_to_json(false, Out) => Out = @(false).
metta_to_json('Null', Out) => Out = @(null).
metta_to_json([], Out) => Out = [].
metta_to_json([Head|Tail], Out) =>
    Out = [JsonHead|JsonTail],
    metta_to_json(Head, JsonHead),
    metta_to_json_list(Tail, JsonTail).
metta_to_json(Value, Out), atom(Value) =>
    (   'is-space'(Value, true)
    ->  space_to_json(Value, Out)
    ;   Out = Value
    ).
metta_to_json(Value, Out), ( string(Value) ; number(Value) ) =>
    Out = Value.

metta_to_json_list([], []).
metta_to_json_list([Head|Tail], [JsonHead|JsonTail]) :-
    metta_to_json(Head, JsonHead),
    metta_to_json_list(Tail, JsonTail).

%A space encodes as an object, which is the inverse of decoding one into a
%space. Only (key value) pairs are members; anything else in the space is not
%representable as a JSON field and is left out rather than guessed at.
space_to_json(Space, json(Pairs)) :-
    findall(Key = JsonValue,
            ( 'get-atoms'(Space, [Key, Value]),
              metta_to_json(Value, JsonValue) ),
            Pairs).

% -------------------------------------------------------------- dict as space

%HE's dict-space: (dict-space ((k1 v1) (k2 v2))) builds a space of those pairs.
'dict-space'(Pairs, Space) :-
    must_be(list, Pairs),
    next_json_space(Space),
    forall(member(Pair, Pairs),
           ( Pair = [Key, Value]
           ->  'add-atom'(Space, [Key, Value], _)
           ;   throw(error(type_error(key_value_pair, Pair),
                           context('dict-space'/1,
                                   'each entry is a (key value) pair')))
           )).

%Nondeterministic, one key per solution, because that is how get-atoms answers
%in PeTTa and an answer set is the MeTTa reading of "all of them". Wrap it in
%collapse for a tuple.
'get-keys'(Space, Key) :-
    'get-atoms'(Space, [Key, _]).

%No answer when the key is absent, which is HE's "empty if no such key".
'get-value'(Space, Key, Value) :-
    'get-atoms'(Space, [Key, Value]).

%Every operation here succeeds exactly once, and det/1 makes that a checked
%claim rather than a comment: a predicate declared det raises
%determinism_error if it fails or returns holding a choice point. It costs
%nothing, measured 2026-08-15 over 200,000 calls at 0.0186s undeclared against
%0.0191s declared with identical inference counts.
%
%get-keys and get-value are deliberately absent. get-keys is nondeterministic
%BY DESIGN, one key per solution, which is how get-atoms answers in PeTTa; and
%get-value has no answer when the key is absent, which is HE's "empty if no
%such key". Declaring either would raise on the behaviour they are for.
:- det('json-decode'/2).
:- det('json-encode'/2).
:- det('dict-space'/2).
:- det(json_to_metta/2).
:- det(json_to_metta_list/2).
:- det(metta_to_json/2).
:- det(metta_to_json_list/2).
:- det(next_json_space/1).
