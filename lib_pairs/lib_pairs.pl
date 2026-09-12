% Purpose: a collection of (Key Value) pairs read as a RELATION: the two
%   projections, the converse, the grouping into a multimap and back, the two
%   stable orderings, and the lookup that answers every value a key has.
%
%   A pair is a two-element expression and a relation is a collection of them,
%   so nothing here is a new value type; what the library owns is the operations
%   that only make sense once a collection is read as pairs. lib_functional's
%   `zip` and `unzip` BUILD and SPLIT one, and its `group-by` and `sort-by` take
%   a key function over arbitrary elements; these take the pair shape itself.
% Assumes:
%   - every element of the collection is a two-element expression. Each head
%     checks and names the element that is not one, because the projections are
%     the operations most often handed a half-built collection
%     [tested: lib_pairs:a_collection_that_is_not_pairs_is_refused_by_name;
%     commit=WORKTREE]
%   - a key is compared as a TERM, so a lookup asks identity rather than
%     unification and a variable key matches nothing
%     [tested: lib_pairs:a_lookup_compares_keys_as_terms; commit=WORKTREE]
% Guarantees:
%   - duplicates are kept everywhere: a relation may hold one key many times, and
%     the grouping gathers every value it has, in the collection's own order
%     [tested: lib_pairs:duplicates_survive_every_operation; commit=WORKTREE]
%   - both orderings are STABLE, so pairs with equal keys keep their relative
%     order, and sorting by key then grouping is the same as grouping
%     [tested: lib_pairs:the_orderings_are_stable; commit=WORKTREE]
%   - grouping and ungrouping are inverses over any relation: ungrouping a
%     grouping answers the relation sorted by key
%     [tested: lib_pairs:grouping_and_ungrouping_are_inverses; commit=WORKTREE]
% Fails when: a caller wants a mutable mapping. That is lib_dict, a dictionary
%   that IS a space, or lib_datastructures' sorted map, an immutable value with
%   logarithmic lookup; a relation is a collection walked in full.
% Owns resources: none; every answer is a new expression.
% Decides: pairs-group SORTS by key itself rather than requiring sorted input.
%   The host's group_pairs_by_key/2 groups only ADJACENT pairs, so an unsorted
%   relation answers the same key twice and nothing says so; the sort is stable,
%   so the values still arrive in the collection's own order
%   [source: /usr/lib/swi-prolog/library/pairs.pl:group_pairs_by_key/2;
%   commit=WORKTREE].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None


:- module(lib_pairs,
          [ 'pairs-is'/2,
            'pairs-keys'/2,
            'pairs-values'/2,
            'pairs-swap'/2,
            'pairs-sort-by-key'/2,
            'pairs-sort-by-value'/2,
            'pairs-group'/2,
            'pairs-ungroup'/2,
            'pairs-lookup'/3
          ]).

% Guarantees: private helpers and autoload declarations belong to this module.
% [tested: engine_modules; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
% Assumes: engine operations resolve through metta_engine's published exports.
% [source: engine/metta.pl:metta_engine_reexport/2; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
:- set_module(base(metta_engine)).

:- use_module(library(lists), [member/2]).
:- use_module(library(apply), [maplist/3]).

%! 'pairs-is'(+Value:any, -Answer:boolean) is det.
%
% Whether the value is a relation: a collection whose every element is a
% two-element expression. This is the question every other head asks before it
% walks one, asked out loud.
'pairs-is'(Value, Answer) :-
    (   is_list(Value), forall(member(Pair, Value), pair_shape(Pair))
    ->  Answer = true
    ;   Answer = false
    ).

pair_shape(Pair) :- is_list(Pair), Pair = [_, _].

%! 'pairs-keys'(+Pairs:list, -Keys:list) is det.
%
% The key of every pair, in order and with duplicates kept, so the length is the
% relation's own. unzip answers both sides at once; this is the one projection.
'pairs-keys'(Pairs, Keys) :-
    pairs_argument('pairs-keys', Pairs),
    maplist(pair_key, Pairs, Keys).

%! 'pairs-values'(+Pairs:list, -Values:list) is det.
%
% The value of every pair, in order and with duplicates kept.
'pairs-values'(Pairs, Values) :-
    pairs_argument('pairs-values', Pairs),
    maplist(pair_value, Pairs, Values).

pair_key([Key, _], Key).
pair_value([_, Value], Value).

%! 'pairs-swap'(+Pairs:list, -Swapped:list) is det.
%
% The converse relation with the order kept: every (Key Value) becomes
% (Value Key) where it stands. pairs-sort-by-key over the answer is the sorted
% converse, which is what transposing a relation usually means.
'pairs-swap'(Pairs, Swapped) :-
    pairs_argument('pairs-swap', Pairs),
    maplist(swap_pair, Pairs, Swapped).

swap_pair([Key, Value], [Value, Key]).

%! 'pairs-sort-by-key'(+Pairs:list, -Sorted:list) is det.
%
% The relation ordered by key in the standard order of terms, STABLY: pairs with
% equal keys keep their relative order, and none is dropped.
'pairs-sort-by-key'(Pairs, Sorted) :-
    pairs_argument('pairs-sort-by-key', Pairs),
    sorted_by_key(Pairs, Sorted).

%! 'pairs-sort-by-value'(+Pairs:list, -Sorted:list) is det.
%
% The relation ordered by value in the standard order of terms, STABLY. This is
% the other half of the same question, and it is a sort of the converse rather
% than a second algorithm.
'pairs-sort-by-value'(Pairs, Sorted) :-
    pairs_argument('pairs-sort-by-value', Pairs),
    maplist(swap_pair, Pairs, Swapped),
    sorted_by_key(Swapped, SortedSwapped),
    maplist(swap_pair, SortedSwapped, Sorted).

% keysort/2 is the stable sort on the first element of a Key-Value term, and
% documented to be one, so the pairs are carried through it rather than compared
% by hand [source: SWI-Prolog Reference Manual, keysort/2].
sorted_by_key(Pairs, Sorted) :-
    maplist(pair_keyed, Pairs, Keyed),
    keysort(Keyed, Ordered),
    maplist(pair_keyed, Sorted, Ordered).

pair_keyed([Key, Value], Key-[Key, Value]).

%! 'pairs-group'(+Pairs:list, -Groups:list) is det.
%
% The relation as a multimap: every key once, in the standard order of terms,
% with every value it has as (Key Values). The sort is this head's own and is
% stable, so the values arrive in the relation's own order; the host's
% group_pairs_by_key/2 groups only ADJACENT pairs and answers a key twice for an
% unsorted relation, which is why this one sorts first.
'pairs-group'(Pairs, Groups) :-
    pairs_argument('pairs-group', Pairs),
    sorted_by_key(Pairs, Sorted),
    group_sorted(Sorted, Groups).

group_sorted([], []).
group_sorted([[Key, Value]|Rest], [[Key, [Value|Values]]|Groups]) :-
    same_key(Rest, Key, Values, Others),
    group_sorted(Others, Groups).

same_key([], _, [], []).
same_key([[Key, Value]|Rest], Wanted, [Value|Values], Others) :-
    Key == Wanted, !,
    same_key(Rest, Wanted, Values, Others).
same_key([Pair|Rest], Wanted, Values, [Pair|Others]) :-
    same_key(Rest, Wanted, Values, Others).

%! 'pairs-ungroup'(+Groups:list, -Pairs:list) is det.
%
% The relation a multimap holds: one (Key Value) per value, keys in the
% multimap's order and values in each group's order. This inverts pairs-group,
% and a group whose values are not a collection raises.
'pairs-ungroup'(Groups, Pairs) :-
    groups_argument('pairs-ungroup', Groups),
    findall([Key, Value],
            ( member([Key, Values], Groups), member(Value, Values) ),
            Pairs).

%! 'pairs-lookup'(+Pairs:list, +Key:any, -Value:any) is nondet.
%
% Every value the key has, one answer each, in the relation's own order. A key
% the relation does not hold has no answer, which is what makes a lookup
% composable with collapse and with an if over one; the key is compared as a TERM, so
% a variable matches nothing.
'pairs-lookup'(Pairs, Key, Value) :-
    pairs_argument('pairs-lookup', Pairs),
    member([Candidate, Value], Pairs),
    Candidate == Key.

% The check every head makes. It names the ELEMENT that is not a pair rather
% than the whole collection, because a relation built by hand usually has one
% bad row and finding it is the whole of the repair.
pairs_argument(Head, Pairs) :-
    (   is_list(Pairs)
    ->  forall(member(Pair, Pairs),
               (   pair_shape(Pair)
               ->  true
               ;   throw(error(type_error(pair, Pair),
                               context(Head,
                                       'every element is a two-element expression, (Key Value)')))
               ))
    ;   throw(error(type_error(list, Pairs),
                    context(Head, 'a relation is a collection of (Key Value) pairs')))
    ).

groups_argument(Head, Groups) :-
    (   is_list(Groups)
    ->  forall(member(Group, Groups),
               (   Group = [_, Values], is_list(Values)
               ->  true
               ;   throw(error(type_error(group, Group),
                               context(Head,
                                       'every element is a (Key Values) expression whose values are a collection')))
               ))
    ;   throw(error(type_error(list, Groups),
                    context(Head, 'a multimap is a collection of (Key Values) groups')))
    ).

% Every head answers exactly once, except the lookup, which answers once per
% value the key has and is the library's one nondeterministic door.
:- det('pairs-is'/2).
:- det('pairs-keys'/2).
:- det('pairs-values'/2).
:- det('pairs-swap'/2).
:- det('pairs-sort-by-key'/2).
:- det('pairs-sort-by-value'/2).
:- det('pairs-group'/2).
:- det('pairs-ungroup'/2).
