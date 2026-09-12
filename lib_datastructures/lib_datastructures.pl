% Purpose: sorted maps and priority queues as immutable values, over the host's
%   own balanced-tree and pairing-heap implementations.
%
%   A map and a queue are ORDINARY MeTTa VALUES: an expression whose head is a
%   private marker, so `bind!` stores one, a program prints and compares one,
%   and every position that takes a value takes these. The algorithms are the
%   host's own, adapted to that shape in vendor/structures.pl, because a host
%   COMPOUND crosses into MeTTa and back unchanged but leaves a written form
%   unreduced when it is substituted into one
%   [tested: lib_datastructures:a_map_survives_bind; commit=2072899a9f6ba36f92faabb92f9e0b12e6e0f666].
% Assumes:
%   - keys and priorities are compared by the standard order of terms, which is
%     what the two upstream libraries use, so 1 and 1.0 are different keys and
%     a Number orders before a Symbol
%     [tested: lib_datastructures:keys_use_the_standard_order; commit=2072899a9f6ba36f92faabb92f9e0b12e6e0f666]
% Guarantees:
%   - every operation answers a NEW value and leaves its input alone, because
%     the host's structures are immutable [tested:
%     lib_datastructures:a_put_leaves_its_input_alone; commit=2072899a9f6ba36f92faabb92f9e0b12e6e0f666]
%   - a lookup, a minimum and a removal of something absent have NO answer
%     rather than a made-up one, so a caller can tell absence from a stored
%     value [tested: lib_datastructures:absence_has_no_answer; commit=2072899a9f6ba36f92faabb92f9e0b12e6e0f666]
%   - map-pairs, map-keys and map-values answer in key order and pq-pairs in
%     priority order [tested: lib_datastructures:order_is_the_standard_order;
%     commit=2072899a9f6ba36f92faabb92f9e0b12e6e0f666]
% Fails when: given something that is not a map or a heap. The host's own type
%   check raises, naming the argument, rather than answering nonsense.
% Owns resources: none; every value is an immutable term the caller holds.
% Decides: a map is library(assoc)'s AVL tree and a priority queue is
%   library(heaps)'s pairing heap, both adapted to MeTTa's expression shape, so
%   their bounds are the upstream ones: O(log n) put, get and remove; O(1)
%   queue insert and merge; O(log n) amortised pop; O(n) named removal, which
%   upstream notes too.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None


:- module(lib_datastructures,
          [ 'map-empty'/1,
            'map-put'/4,
            'map-get'/3,
            'map-get-or'/4,
            'map-remove'/3,
            'map-has'/3,
            'map-size'/2,
            'map-keys'/2,
            'map-values'/2,
            'map-pairs'/2,
            'map-from-pairs'/2,
            'map-min'/2,
            'map-max'/2,
            'pq-empty'/1,
            'pq-insert'/4,
            'pq-min'/2,
            'pq-pop'/2,
            'pq-remove'/4,
            'pq-size'/2,
            'pq-merge'/3,
            'pq-pairs'/2,
            'pq-from-pairs'/2
          ]).

% Guarantees: private helpers and autoload declarations belong to this module.
% [tested: engine_modules; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
% Assumes: engine operations resolve through metta_engine's published exports.
% [source: engine/metta.pl:metta_engine_reexport/2; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
:- set_module(base(metta_engine)).

:- use_module('vendor/structures',
              [map_empty/1, map_is/1, map_insert/4, map_lookup/3, map_delete/4,
               map_list/2, map_keys/2, map_values/2, map_from_list/2,
               map_min/3, map_max/3,
               pq_empty/1, pq_is/1, pq_add/4, pq_get/4, pq_min/3, pq_delete/4,
               pq_size/2, pq_merge/3, pq_list/2, pq_from_list/2]).
:- use_module(library(error), [must_be/2]).
:- use_module(library(apply), [maplist/2]).

%! 'map-empty'(-Map:any) is det.
%
% The empty sorted map. Every other map grows from it with map-put, and two
% empty maps are the same value.
'map-empty'(Map) :- map_empty(Map).

%! 'map-put'(+Map:any, +Key:any, +Value:any, -Result:any) is det.
%
% The map with Key holding Value, replacing whatever Key held. The input map is
% unchanged, because a map is a value.
'map-put'(Map, Key, Value, Result) :-
    map_value('map-put', Map),
    map_insert(Map, Key, Value, Result).

%! 'map-get'(+Map:any, +Key:any, -Value:any) is semidet.
%
% The value Key holds. An absent key has no answer, so absence and a stored
% value are different things; map-get-or takes a default instead.
'map-get'(Map, Key, Value) :-
    map_value('map-get', Map),
    map_lookup(Map, Key, Value).

%! 'map-get-or'(+Map:any, +Key:any, +Default:any, -Value:any) is det.
%
% The value Key holds, or Default when the key is absent.
'map-get-or'(Map, Key, Default, Value) :-
    map_value('map-get-or', Map),
    ( map_lookup(Map, Key, Found) -> Value = Found ; Value = Default ).

%! 'map-remove'(+Map:any, +Key:any, -Result:any) is det.
%
% The map without Key. Removing a key that is absent answers the same map, so a
% caller need not look first.
'map-remove'(Map, Key, Result) :-
    map_value('map-remove', Map),
    ( map_delete(Map, Key, _, Smaller) -> Result = Smaller ; Result = Map ).

%! 'map-has'(+Map:any, +Key:any, -Answer:boolean) is det.
%
% True when the map holds Key, False otherwise.
'map-has'(Map, Key, Answer) :-
    map_value('map-has', Map),
    ( map_lookup(Map, Key, _) -> Answer = true ; Answer = false ).

%! 'map-size'(+Map:any, -Size:integer) is det.
%
% How many keys the map holds.
'map-size'(Map, Size) :-
    map_value('map-size', Map),
    map_keys(Map, Keys),
    length(Keys, Size).

%! 'map-keys'(+Map:any, -Keys:list) is det.
%
% Every key, in the standard order of terms.
'map-keys'(Map, Keys) :-
    map_value('map-keys', Map),
    map_keys(Map, Keys).

%! 'map-values'(+Map:any, -Values:list) is det.
%
% Every value, in its key's order.
'map-values'(Map, Values) :-
    map_value('map-values', Map),
    map_values(Map, Values).

%! 'map-pairs'(+Map:any, -Pairs:list) is det.
%
% Every (Key Value) pair, in key order. This is the shape map-from-pairs reads,
% so a map round-trips through it.
'map-pairs'(Map, Pairs) :-
    map_value('map-pairs', Map),
    map_list(Map, Pairs).

%! 'map-from-pairs'(+Pairs:list, -Map:any) is det.
%
% A map holding every (Key Value) pair. A repeated key raises, because two
% values for one key is not a map; put the second one with map-put to say which
% wins.
'map-from-pairs'(Pairs, Map) :-
    pair_list('map-from-pairs', Pairs),
    map_keys_distinct('map-from-pairs', Pairs),
    map_from_list(Pairs, Map).

%! 'map-min'(+Map:any, -Pair:list) is semidet.
%
% The (Key Value) pair with the smallest key. An empty map has no answer.
'map-min'(Map, Pair) :-
    map_value('map-min', Map),
    map_min(Map, Key, Value),
    Pair = [Key, Value].

%! 'map-max'(+Map:any, -Pair:list) is semidet.
%
% The (Key Value) pair with the largest key. An empty map has no answer.
'map-max'(Map, Pair) :-
    map_value('map-max', Map),
    map_max(Map, Key, Value),
    Pair = [Key, Value].

%! 'pq-empty'(-Queue:any) is det.
%
% The empty priority queue. Every other queue grows from it with pq-insert.
'pq-empty'(Queue) :- pq_empty(Queue).

%! 'pq-insert'(+Queue:any, +Priority:any, +Value:any, -Result:any) is det.
%
% The queue with Value added at Priority. A repeated priority is kept, so a
% queue holds as many entries as were inserted; the input queue is unchanged.
'pq-insert'(Queue, Priority, Value, Result) :-
    queue_value('pq-insert', Queue),
    pq_add(Queue, Priority, Value, Result).

%! 'pq-min'(+Queue:any, -Pair:list) is semidet.
%
% The (Priority Value) pair at the smallest priority, without removing it. An
% empty queue has no answer.
'pq-min'(Queue, Pair) :-
    queue_value('pq-min', Queue),
    pq_min(Queue, Priority, Value),
    Pair = [Priority, Value].

%! 'pq-pop'(+Queue:any, -Answer:list) is semidet.
%
% The (Priority Value Rest) triple: the smallest entry and the queue without
% it, in one operation, because reading and removing separately would walk the
% queue twice. An empty queue has no answer.
'pq-pop'(Queue, Answer) :-
    queue_value('pq-pop', Queue),
    pq_get(Queue, Priority, Value, Rest),
    Answer = [Priority, Value, Rest].

%! 'pq-remove'(+Queue:any, +Priority:any, +Value:any, -Result:any) is semidet.
%
% The queue without one entry holding exactly this priority and value, which is
% how a scheduled item is cancelled. An entry that is not there has no answer.
'pq-remove'(Queue, Priority, Value, Result) :-
    queue_value('pq-remove', Queue),
    pq_delete(Queue, Priority, Value, Result).

%! 'pq-size'(+Queue:any, -Size:integer) is det.
%
% How many entries the queue holds, counting repeated priorities separately.
'pq-size'(Queue, Size) :-
    queue_value('pq-size', Queue),
    pq_size(Queue, Size).

%! 'pq-merge'(+Left:any, +Right:any, -Result:any) is det.
%
% One queue holding every entry of both, which a pairing heap does in constant
% time. Both inputs are unchanged.
'pq-merge'(Left, Right, Result) :-
    queue_value('pq-merge', Left),
    queue_value('pq-merge', Right),
    pq_merge(Left, Right, Result).

%! 'pq-pairs'(+Queue:any, -Pairs:list) is det.
%
% Every (Priority Value) pair in priority order, which is the sorted sequence
% the queue exists to produce. This is the shape pq-from-pairs reads.
'pq-pairs'(Queue, Pairs) :-
    queue_value('pq-pairs', Queue),
    pq_list(Queue, Pairs).

%! 'pq-from-pairs'(+Pairs:list, -Queue:any) is det.
%
% A queue holding every (Priority Value) pair, repeated priorities included.
'pq-from-pairs'(Pairs, Queue) :-
    pair_list('pq-from-pairs', Pairs),
    pq_from_list(Pairs, Queue).

% An entry is a two-element expression, which is the shape both structures read
% and write; the check is at the boundary and never inside an operation.
pair_list(Operation, Pairs) :-
    (   is_list(Pairs), forall(member(Pair, Pairs), Pair = [_, _])
    ->  true
    ;   throw(error(type_error(key_value_pairs, Pairs),
                    context(Operation, 'Each entry is a two-element expression, (Key Value)')))
    ).

% A repeated key is refused rather than silently keeping the last value: two
% values for one key is not a map, and map-put is how a caller says which wins.
map_keys_distinct(Operation, Pairs) :-
    findall(Key, member([Key, _], Pairs), Keys),
    sort(Keys, Distinct),
    (   same_length(Keys, Distinct)
    ->  true
    ;   throw(error(duplicate_map_key(Pairs),
                    context(Operation,
                            'A key holds one value; use map-put to say which value wins')))
    ).

% The shapes, checked here so a wrong argument names the operation rather than
% failing inside a tree walk.
map_value(_, Map) :- map_is(Map), !.
map_value(Operation, Map) :-
    throw(error(type_error(sorted_map, Map),
                context(Operation, 'Build a map with map-empty, map-put or map-from-pairs'))).

queue_value(_, Queue) :- pq_is(Queue), !.
queue_value(Operation, Queue) :-
    throw(error(type_error(priority_queue, Queue),
                context(Operation, 'Build a queue with pq-empty, pq-insert or pq-from-pairs'))).

:- multifile prolog:error_message//1.
prolog:error_message(duplicate_map_key(Pairs)) -->
    [ 'duplicate-map-key: ~q holds one key twice; a key holds one value, so use \c
       map-put to say which value wins'-[Pairs] ].

% Every public operation answers at most once: a lookup, a minimum and a
% removal of something absent FAIL rather than answering, which is the semidet
% contract the doc rows state, and the rest are deterministic.
:- det('map-empty'/1).
:- det('map-put'/4).
:- det('map-get-or'/4).
:- det('map-remove'/3).
:- det('map-has'/3).
:- det('map-size'/2).
:- det('map-keys'/2).
:- det('map-values'/2).
:- det('map-pairs'/2).
:- det('map-from-pairs'/2).
:- det('pq-empty'/1).
:- det('pq-insert'/4).
:- det('pq-size'/2).
:- det('pq-merge'/3).
:- det('pq-pairs'/2).
:- det('pq-from-pairs'/2).
