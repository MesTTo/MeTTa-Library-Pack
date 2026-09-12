% Purpose: the balanced-tree and pairing-heap cores, written over MeTTa's own
%   expression shape so a map and a priority queue are ORDINARY MeTTa VALUES.
%
%   The algorithms are SWI-Prolog's, adapted: library(assoc)'s AVL insert,
%   delete and rotations and library(heaps)'s pairing heap, with each node
%   written as a list rather than a compound. VENDOR.md pins the sources and
%   records that one change.
%
%   The change is not cosmetic. A MeTTa expression IS a list in this engine, so
%   a list-shaped node is a value every position accepts: `bind!` stores it, a
%   program prints and compares it, and a pattern can walk it. A compound
%   crosses into MeTTa and back unchanged as an opaque Grounded value, but
%   substituting one into a written form leaves the form unreduced, because the
%   translator reads the compound as a nested call
%   [tested: lib_datastructures:a_map_survives_bind; commit=WORKTREE].
% Assumes: keys and priorities are compared with compare/3 and (@<)/2, the
%   standard order of terms, exactly as the two upstream libraries do.
% Guarantees:
%   - every operation answers what library(assoc) and library(heaps) answer for
%     the same inputs, which is what the differential asserts over generated
%     key sequences [tested: test_maps_agree_with_library_assoc,
%     test_queues_agree_with_library_heaps; commit=WORKTREE]
%   - the structures are immutable: an insert or a delete answers a new value
%     and shares the untouched parts with the old one
% Owns resources: none.
% Decides: the empty map is the Symbol MapEmpty and a node is
%   (MapNode Key Value Balance Left Right); the empty queue is
%   (PqHeap PqNil 0) and a queue is (PqHeap Tree Size) over
%   (PqNode Value Priority Children). Those markers are the library's own
%   private shape; a program builds and reads them through the operations.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- module(lib_datastructures_structures,
          [ map_empty/1,
            map_is/1,
            map_insert/4,
            map_lookup/3,
            map_delete/4,
            map_list/2,
            map_keys/2,
            map_values/2,
            map_from_list/2,
            map_min/3,
            map_max/3,
            pq_empty/1,
            pq_is/1,
            pq_add/4,
            pq_get/4,
            pq_min/3,
            pq_delete/4,
            pq_size/2,
            pq_merge/3,
            pq_list/2,
            pq_from_list/2
          ]).

:- use_module(library(lists), [member/2, append/3]).

% ---------------------------------------------------------------- the map
%
% library(assoc)'s AVL tree: every node carries the balance of its subtrees as
% <, - or >, an insert or a delete adjusts that balance on the way out, and a
% node that would go two deep on one side is rotated. The clauses below are
% that code with t(K,V,B,L,R) written as (MapNode K V B L R) and the empty tree
% t written as MapEmpty.
% [source: /usr/lib/swi-prolog/library/assoc.pl, SWI-Prolog 10.1.13, insert/5
% through table2/3; VENDOR.md pins the upstream revision; commit=WORKTREE]

map_empty('MapEmpty').

map_is('MapEmpty') :- !.
map_is(['MapNode', _, _, _, _, _]).

map_insert(Map, Key, Value, New) :-
    map_insert_(Map, Key, Value, New, _).

map_insert_('MapEmpty', Key, Value, ['MapNode', Key, Value, -, 'MapEmpty', 'MapEmpty'], yes).
map_insert_(['MapNode', Key, Value, Balance, Left, Right], K, V, New, Changed) :-
    compare(Order, K, Key),
    map_insert_at(Order, ['MapNode', Key, Value, Balance, Left, Right], K, V, New, Changed).

map_insert_at(=, ['MapNode', Key, _, Balance, Left, Right], _, V,
              ['MapNode', Key, V, Balance, Left, Right], no).
map_insert_at(<, ['MapNode', Key, Value, Balance, Left, Right], K, V, New, Changed) :-
    map_insert_(Left, K, V, NewLeft, LeftChanged),
    map_adjust(LeftChanged, ['MapNode', Key, Value, Balance, NewLeft, Right], left, New, Changed).
map_insert_at(>, ['MapNode', Key, Value, Balance, Left, Right], K, V, New, Changed) :-
    map_insert_(Right, K, V, NewRight, RightChanged),
    map_adjust(RightChanged, ['MapNode', Key, Value, Balance, Left, NewRight], right, New, Changed).

map_adjust(no, Old, _, Old, no).
map_adjust(yes, ['MapNode', Key, Value, Balance, Left, Right], Side, New, Changed) :-
    map_insert_table(Balance, Side, NewBalance, Changed, Rebalance),
    map_rebalance(Rebalance, ['MapNode', Key, Value, Balance, Left, Right], NewBalance, New, _, _).

%     balance  where     balance  whole tree  to be
%     before   inserted  after    increased   rebalanced
map_insert_table(-, left,  <, yes, no) :- !.
map_insert_table(-, right, >, yes, no) :- !.
map_insert_table(<, left,  -, no,  yes) :- !.
map_insert_table(<, right, -, no,  no) :- !.
map_insert_table(>, left,  -, no,  no) :- !.
map_insert_table(>, right, -, no,  yes) :- !.

map_lookup(['MapNode', Key, Value, _, Left, Right], K, V) :-
    compare(Order, K, Key),
    map_lookup_at(Order, Key, Value, Left, Right, K, V).

map_lookup_at(=, _, Value, _, _, _, Value).
map_lookup_at(<, _, _, Left, _, K, V) :- map_lookup(Left, K, V).
map_lookup_at(>, _, _, _, Right, K, V) :- map_lookup(Right, K, V).

map_delete(Map, Key, Value, New) :-
    map_delete_(Map, Key, Value, New, _).

map_delete_(['MapNode', Key, Value, Balance, Left, Right], K, V, New, Changed) :-
    compare(Order, K, Key),
    map_delete_at(Order, ['MapNode', Key, Value, Balance, Left, Right], K, V, New, Changed).

map_delete_at(=, ['MapNode', Key, Value, _, 'MapEmpty', Right], Key, Value, Right, yes) :- !.
map_delete_at(=, ['MapNode', Key, Value, _, Left, 'MapEmpty'], Key, Value, Left, yes) :- !.
map_delete_at(=, ['MapNode', Key, Value, >, Left, Right], Key, Value, New, Changed) :-
    % The right subtree is deeper, so the smallest key on the right takes over.
    map_delete_min(Right, K, V, NewRight, RightChanged),
    map_deladjust(RightChanged, ['MapNode', K, V, >, Left, NewRight], right, New, Changed),
    !.
map_delete_at(=, ['MapNode', Key, Value, Balance, Left, Right], Key, Value, New, Changed) :-
    % Otherwise the largest key on the left takes over.
    map_delete_max(Left, K, V, NewLeft, LeftChanged),
    map_deladjust(LeftChanged, ['MapNode', K, V, Balance, NewLeft, Right], left, New, Changed),
    !.
map_delete_at(<, ['MapNode', Key, Value, Balance, Left, Right], K, V, New, Changed) :-
    map_delete_(Left, K, V, NewLeft, LeftChanged),
    map_deladjust(LeftChanged, ['MapNode', Key, Value, Balance, NewLeft, Right], left, New, Changed).
map_delete_at(>, ['MapNode', Key, Value, Balance, Left, Right], K, V, New, Changed) :-
    map_delete_(Right, K, V, NewRight, RightChanged),
    map_deladjust(RightChanged, ['MapNode', Key, Value, Balance, Left, NewRight], right, New, Changed).

map_delete_min(['MapNode', Key, Value, _, 'MapEmpty', Right], Key, Value, Right, yes) :- !.
map_delete_min(['MapNode', Key, Value, Balance, Left, Right], K, V, New, Changed) :-
    map_delete_min(Left, K, V, NewLeft, LeftChanged),
    map_deladjust(LeftChanged, ['MapNode', Key, Value, Balance, NewLeft, Right], left, New, Changed).

map_delete_max(['MapNode', Key, Value, _, Left, 'MapEmpty'], Key, Value, Left, yes) :- !.
map_delete_max(['MapNode', Key, Value, Balance, Left, Right], K, V, New, Changed) :-
    map_delete_max(Right, K, V, NewRight, RightChanged),
    map_deladjust(RightChanged, ['MapNode', Key, Value, Balance, Left, NewRight], right, New, Changed).

map_deladjust(no, Old, _, Old, no).
map_deladjust(yes, ['MapNode', Key, Value, Balance, Left, Right], Side, New, RealChange) :-
    map_delete_table(Balance, Side, NewBalance, Changed, Rebalance),
    map_rebalance(Rebalance, ['MapNode', Key, Value, Balance, Left, Right], NewBalance, New,
                  Changed, RealChange).

%     balance  where     balance  whole tree  to be
%     before   deleted   after    changed     rebalanced
map_delete_table(-, right, <, no,  no) :- !.
map_delete_table(-, left,  >, no,  no) :- !.
map_delete_table(<, right, -, yes, yes) :- !.
map_delete_table(<, left,  -, yes, no) :- !.
map_delete_table(>, right, -, yes, no) :- !.
map_delete_table(>, left,  -, yes, yes) :- !.

% The single and double rotations, shared by insert and delete. The four
% patterns whose left side is (>)-(>), (>)-(<), (<)-(<) or (<)-(>) always
% change the height, which is why insert can decide from the table alone; after
% a delete any pattern can occur, so the height change is answered.
map_rebalance(no, ['MapNode', K, V, _, Left, Right], Balance,
              ['MapNode', K, V, Balance, Left, Right], Changed, Changed).
map_rebalance(yes, Old, _, New, _, RealChange) :-
    map_geq(Old, New, RealChange).

map_geq(['MapNode', A, VA, >, Alpha, ['MapNode', B, VB, >, Beta, Gamma]],
        ['MapNode', B, VB, -, ['MapNode', A, VA, -, Alpha, Beta], Gamma], yes) :- !.
map_geq(['MapNode', A, VA, >, Alpha, ['MapNode', B, VB, -, Beta, Gamma]],
        ['MapNode', B, VB, <, ['MapNode', A, VA, >, Alpha, Beta], Gamma], no) :- !.
map_geq(['MapNode', B, VB, <, ['MapNode', A, VA, <, Alpha, Beta], Gamma],
        ['MapNode', A, VA, -, Alpha, ['MapNode', B, VB, -, Beta, Gamma]], yes) :- !.
map_geq(['MapNode', B, VB, <, ['MapNode', A, VA, -, Alpha, Beta], Gamma],
        ['MapNode', A, VA, >, Alpha, ['MapNode', B, VB, <, Beta, Gamma]], no) :- !.
map_geq(['MapNode', A, VA, >, Alpha, ['MapNode', B, VB, <, ['MapNode', X, VX, B1, Beta, Gamma], Delta]],
        ['MapNode', X, VX, -, ['MapNode', A, VA, B2, Alpha, Beta],
                              ['MapNode', B, VB, B3, Gamma, Delta]], yes) :- !,
    map_balance_pair(B1, B2, B3).
map_geq(['MapNode', B, VB, <, ['MapNode', A, VA, >, Alpha, ['MapNode', X, VX, B1, Beta, Gamma]], Delta],
        ['MapNode', X, VX, -, ['MapNode', A, VA, B2, Alpha, Beta],
                              ['MapNode', B, VB, B3, Gamma, Delta]], yes) :- !,
    map_balance_pair(B1, B2, B3).

map_balance_pair(<, -, >).
map_balance_pair(>, <, -).
map_balance_pair(-, -, -).

map_list('MapEmpty', []) :- !.
map_list(['MapNode', Key, Value, _, Left, Right], List) :-
    map_list(Left, LeftList),
    map_list(Right, RightList),
    append(LeftList, [[Key, Value]|RightList], List).

map_keys('MapEmpty', []) :- !.
map_keys(['MapNode', Key, _, _, Left, Right], Keys) :-
    map_keys(Left, LeftKeys),
    map_keys(Right, RightKeys),
    append(LeftKeys, [Key|RightKeys], Keys).

map_values('MapEmpty', []) :- !.
map_values(['MapNode', _, Value, _, Left, Right], Values) :-
    map_values(Left, LeftValues),
    map_values(Right, RightValues),
    append(LeftValues, [Value|RightValues], Values).

% A fold over the pairs, so a duplicate key is the last one written rather than
% a refusal here; the public head decides what a duplicate means.
map_from_list(Pairs, Map) :-
    map_empty(Empty),
    foldl_pairs(Pairs, Empty, Map).

foldl_pairs([], Map, Map).
foldl_pairs([[Key, Value]|More], Map0, Map) :-
    map_insert(Map0, Key, Value, Map1),
    foldl_pairs(More, Map1, Map).

map_min(['MapNode', Key, Value, _, 'MapEmpty', _], Key, Value) :- !.
map_min(['MapNode', _, _, _, Left, _], Key, Value) :- map_min(Left, Key, Value).

map_max(['MapNode', Key, Value, _, _, 'MapEmpty'], Key, Value) :- !.
map_max(['MapNode', _, _, _, _, Right], Key, Value) :- map_max(Right, Key, Value).

% ------------------------------------------------------------ the queue
%
% library(heaps)'s pairing heap: a tree whose root is the minimum, melded in
% constant time, and a pop that pairs up the root's children in two passes,
% which is where the amortised logarithm comes from.
% [source: /usr/lib/swi-prolog/library/heaps.pl, SWI-Prolog 10.1.13,
% add_to_heap/4 through pairing/2; VENDOR.md pins the upstream revision;
% commit=WORKTREE]

pq_empty(['PqHeap', 'PqNil', 0]).

pq_is(['PqHeap', Tree, Size]) :- integer(Size), pq_tree(Tree).

pq_tree('PqNil') :- !.
pq_tree(['PqNode', _, _, Children]) :- is_list(Children).

pq_add(['PqHeap', Tree0, Size0], Priority, Value, ['PqHeap', Tree, Size]) :-
    pq_meld(Tree0, ['PqNode', Value, Priority, []], Tree),
    Size is Size0 + 1.

pq_get(['PqHeap', ['PqNode', Value, Priority, Children], Size0], Priority, Value,
       ['PqHeap', Tree, Size]) :-
    pq_pairing(Children, Tree),
    Size is Size0 - 1.

pq_min(['PqHeap', ['PqNode', Value, Priority, _], _], Priority, Value).

pq_size(['PqHeap', _, Size], Size).

pq_merge(['PqHeap', Left, LeftSize], ['PqHeap', Right, RightSize], ['PqHeap', Tree, Size]) :-
    pq_meld(Left, Right, Tree),
    Size is LeftSize + RightSize.

% Upstream's own note: deleting a named entry is linear, and it is here for the
% same reason, so that a scheduled item can be cancelled.
pq_delete(Queue0, Priority, Value, Queue) :-
    pq_get(Queue0, Priority, Value, Queue),
    !.
pq_delete(Queue0, Priority, Value, Queue) :-
    pq_get(Queue0, OtherPriority, OtherValue, Rest),
    pq_delete(Rest, Priority, Value, Without),
    pq_add(Without, OtherPriority, OtherValue, Queue).

pq_meld('PqNil', Queue, Queue) :- !.
pq_meld(Queue, 'PqNil', Queue) :- !.
pq_meld(Left, Right, Queue) :-
    Left = ['PqNode', X, PriorityX, ChildrenX],
    Right = ['PqNode', Y, PriorityY, ChildrenY],
    (   PriorityX @< PriorityY
    ->  Queue = ['PqNode', X, PriorityX, [Right|ChildrenX]]
    ;   Queue = ['PqNode', Y, PriorityY, [Left|ChildrenY]]
    ).

% Pair up, which is to say recursively meld, a list of pairing heaps.
pq_pairing([], 'PqNil').
pq_pairing([Queue], Queue) :- !.
pq_pairing([First, Second|More], Queue) :-
    pq_meld(First, Second, Paired),
    pq_pairing(More, Rest),
    pq_meld(Paired, Rest, Queue).

pq_list(Queue, List) :- pq_to_list(Queue, List).

pq_to_list(['PqHeap', 'PqNil', 0], []) :- !.
pq_to_list(Queue0, [[Priority, Value]|More]) :-
    pq_get(Queue0, Priority, Value, Queue),
    pq_to_list(Queue, More).

pq_from_list(Pairs, Queue) :-
    pq_empty(Empty),
    pq_from_list_(Pairs, Empty, Queue).

pq_from_list_([], Queue, Queue).
pq_from_list_([[Priority, Value]|More], Queue0, Queue) :-
    pq_add(Queue0, Priority, Value, Queue1),
    pq_from_list_(More, Queue1, Queue).
