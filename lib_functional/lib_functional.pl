% Purpose: the collection operations a program writes over and over: zipping,
%   grouping, chunking, windowing, partitioning, scanning, unfolding and
%   piping, each one pass over an expression.
%
%   The engine already has map-atom, filter-atom and foldl-atom, so this library
%   is what those three cannot say in one call. Each head that takes a FUNCTION
%   applies it through the evaluator, so a lambda, a defined name and a partial
%   application all work, exactly as par-map takes one
%   [source: lib/lib_thread/lib_thread.pl:par_map/3; commit=WORKTREE].
% Assumes:
%   - a collection is an expression; a function argument is anything the
%     evaluator can apply, and it is applied once per element
%   - a function used as a KEY is deterministic: group-by and sort-by ask it
%     once per element and compare what it answered
% Guarantees:
%   - every operation is one pass over its input plus the cost of the function
%     it applies, so nothing here is quadratic
%     [tested: lib_functional:one_pass_costs_scale_linearly; commit=WORKTREE]
%   - group-by keeps the keys in first-appearance order and the members in the
%     collection's order, and sort-by is stable, so equal keys keep their
%     relative order [tested: lib_functional:grouping_and_sorting_are_stable;
%     commit=WORKTREE]
%   - zip truncates at the shorter collection and unzip inverts it, so a round
%     trip over equal lengths is the identity
%     [tested: lib_functional:zip_and_unzip_round_trip; commit=WORKTREE]
% Fails when: a count that has to be positive is not, or a function answers
%   nothing where one answer is required. Each refusal names the operation.
% Owns resources: none; every answer is a new expression.
% Decides: `take` is combinatorics' existing takeK, so this library has `drop`
%   and the chunking forms and adds no second spelling of the prefix.
% Decides: the one-level and the every-level flatten are `flatten-once` and
%   `flatten-deep`, and neither takes the bare name `flatten`. A registered head
%   is reached by NAME through the module chain the calling space resolves in,
%   and the engine module imports the whole of library(lists), whose own
%   flatten/2 is the every-level one; a head spelled flatten/2 here therefore
%   registered, reported success, and answered library(lists)' deep flatten with
%   nothing said. The shipped libraries' hyphenated, domain-qualified names are
%   what keep every other head clear of that chain
%   [tested: sh check.sh lib-autoload, whose shadowed-head check refuses a
%   published name a tier above the libraries already answers; commit=WORKTREE].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None


:- module(lib_functional,
          [ zip/3,
            unzip/2,
            drop/3,
            chunk/3,
            window/3,
            'flatten-once'/2,
            'flatten-deep'/2,
            partition/3,
            'group-by'/3,
            'sort-by'/3,
            scan/4,
            unfold/3,
            pipe/3,
            'apply-to'/3
          ]).

% Guarantees: private helpers and autoload declarations belong to this module.
% [tested: engine_modules; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
% Assumes: engine operations resolve through metta_engine's published exports.
% [source: engine/metta.pl:metta_engine_reexport/2; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
:- set_module(base(metta_engine)).

:- use_module(library(error), [must_be/2, domain_error/2]).
:- use_module(library(lists), [append/3, reverse/2, nth1/3]).
:- use_module(library(apply), [maplist/3, foldl/4]).
:- use_module(library(pairs), [pairs_keys_values/3]).

%! zip(+Left:list, +Right:list, -Pairs:list) is det.
%
% The pairs of corresponding elements, truncating at the shorter collection, so
% zipping a long one with a short one answers the short one's length. unzip
% inverts it.
zip(Left, Right, Pairs) :-
    must_be(list, Left),
    must_be(list, Right),
    zip_(Left, Right, Pairs).

zip_([], _, []) :- !.
zip_(_, [], []) :- !.
zip_([Left|Lefts], [Right|Rights], [[Left, Right]|Pairs]) :-
    zip_(Lefts, Rights, Pairs).

%! unzip(+Pairs:list, -Sides:list) is det.
%
% The two collections a zip was made from, as (Lefts Rights). Every element
% must be a two-element expression; anything else raises.
unzip(Pairs, [Lefts, Rights]) :-
    must_be(list, Pairs),
    unzip_(Pairs, Lefts, Rights).

unzip_([], [], []).
unzip_([Pair|Pairs], [Left|Lefts], [Right|Rights]) :-
    (   Pair = [Left, Right]
    ->  true
    ;   throw(error(type_error(pair, Pair),
                    context(unzip, 'Each element is a two-element expression, (Left Right)')))
    ),
    unzip_(Pairs, Lefts, Rights).

%! drop(+Items:list, +Count:integer, -Rest:list) is det.
%
% The collection without its first Count elements, and empty when there are
% fewer than that. Dropping a negative count raises; the PREFIX is takeK, which
% lib_combinatorics already publishes.
drop(Items, Count, Rest) :-
    must_be(list, Items),
    must_be(nonneg, Count),
    drop_(Count, Items, Rest).

drop_(0, Items, Items) :- !.
drop_(_, [], []) :- !.
drop_(Count, [_|Items], Rest) :-
    Fewer is Count - 1,
    drop_(Fewer, Items, Rest).

%! chunk(+Items:list, +Size:integer, -Chunks:list) is det.
%
% The collection cut into pieces of that size, in order, with a shorter last
% piece when the size does not divide the length. A size of zero or less raises,
% because it would never finish; an empty collection has no chunks.
chunk(Items, Size, Chunks) :-
    must_be(list, Items),
    must_be(integer, Size),
    (   Size < 1
    ->  domain_error(positive_integer, Size)
    ;   true
    ),
    chunk_(Items, Size, Chunks).

chunk_([], _, []) :- !.
chunk_(Items, Size, [Chunk|Chunks]) :-
    take_(Size, Items, Chunk, Rest),
    chunk_(Rest, Size, Chunks).

take_(0, Items, [], Items) :- !.
take_(_, [], [], []) :- !.
take_(Count, [Item|Items], [Item|Taken], Rest) :-
    Fewer is Count - 1,
    take_(Fewer, Items, Taken, Rest).

%! window(+Items:list, +Size:integer, -Windows:list) is det.
%
% Every run of that many consecutive elements, overlapping by all but one: the
% sliding window a moving average or a bigram is written over. A collection
% shorter than the window has none. A size of zero or less raises.
window(Items, Size, Windows) :-
    must_be(list, Items),
    must_be(integer, Size),
    (   Size < 1
    ->  domain_error(positive_integer, Size)
    ;   true
    ),
    window_(Items, Size, Windows).

window_(Items, Size, Windows) :-
    length(Items, Length),
    (   Length < Size
    ->  Windows = []
    ;   take_(Size, Items, Window, _),
        Items = [_|Rest],
        window_(Rest, Size, More),
        Windows = [Window|More]
    ).

%! 'flatten-once'(+Items:list, -Flat:list) is det.
%
% One level of nesting removed: the elements of every element that is itself a
% collection, in order, with anything else kept as it is. flatten-deep removes
% every level, and the bare name flatten is the host's own every-level one,
% which is why neither of these is spelled that way.
'flatten-once'(Items, Flat) :-
    must_be(list, Items),
    flatten_(Items, Flat).

flatten_([], []).
flatten_([Item|Items], Flat) :-
    flatten_(Items, Rest),
    (   is_list(Item)
    ->  append(Item, Rest, Flat)
    ;   Flat = [Item|Rest]
    ).

%! 'flatten-deep'(+Items:list, -Flat:list) is det.
%
% Every level of nesting removed, so the answer holds only the leaves, in
% order. An empty collection nested anywhere contributes nothing; flatten-once
% removes exactly one.
'flatten-deep'(Items, Flat) :-
    must_be(list, Items),
    flatten_deep_(Items, Flat).

flatten_deep_([], []).
flatten_deep_([Item|Items], Flat) :-
    flatten_deep_(Items, Rest),
    (   is_list(Item)
    ->  flatten_deep_(Item, Inner),
        append(Inner, Rest, Flat)
    ;   Flat = [Item|Rest]
    ).

%! partition(+Test:any, +Items:list, -Sides:list) is det.
%
% The elements the test answers True for and the rest, as (Yes No), each in the
% collection's order. A test that answers anything but True puts its element in
% the second side, so a partition never loses an element.
partition(Test, Items, [Yes, No]) :-
    must_be(list, Items),
    current_metta_module(Module),
    partition_(Items, Module, Test, Yes, No).

partition_([], _, _, [], []).
partition_([Item|Items], Module, Test, Yes, No) :-
    (   applied(Module, Test, Item, true)
    ->  Yes = [Item|MoreYes], No = MoreNo
    ;   Yes = MoreYes, No = [Item|MoreNo]
    ),
    partition_(Items, Module, Test, MoreYes, MoreNo).

%! 'group-by'(+Key:any, +Items:list, -Groups:list) is det.
%
% The elements gathered by what the key function answers for each, as
% ((Key Members) ...). The keys come in first-appearance order and the members
% in the collection's own order, so grouping is stable and needs no sort.
'group-by'(Key, Items, Groups) :-
    must_be(list, Items),
    current_metta_module(Module),
    keyed(Items, Module, Key, Keyed),
    group_(Keyed, Groups).

group_([], []).
group_([Key-Item|Rest], [[Key, [Item|Members]]|Groups]) :-
    same_key(Rest, Key, Members, Others),
    group_(Others, Groups).

same_key([], _, [], []).
same_key([Key-Item|Rest], Wanted, [Item|Members], Others) :-
    Key == Wanted, !,
    same_key(Rest, Wanted, Members, Others).
same_key([Pair|Rest], Wanted, Members, [Pair|Others]) :-
    same_key(Rest, Wanted, Members, Others).

%! 'sort-by'(+Key:any, +Items:list, -Sorted:list) is det.
%
% The elements in the order of what the key function answers for each, compared
% in the standard order of terms. The sort is STABLE and keeps duplicates, so
% elements with equal keys stay in their original order.
'sort-by'(Key, Items, Sorted) :-
    must_be(list, Items),
    current_metta_module(Module),
    keyed(Items, Module, Key, Keyed),
    keysort(Keyed, Ordered),
    pairs_keys_values(Ordered, _, Sorted).

% One application of the key function per element, which is what makes a
% grouping or a sort one pass over the collection plus one call each.
keyed([], _, _, []).
keyed([Item|Items], Module, Key, [Answer-Item|Keyed]) :-
    applied(Module, Key, Item, Answer),
    keyed(Items, Module, Key, Keyed).

%! scan(+Function:any, +Start:any, +Items:list, -Running:list) is det.
%
% The running results of folding the function over the collection, starting with
% Start and ending with the whole fold: a prefix sum is scan with +. The answer
% is one longer than the collection, because the start is its first element.
scan(Function, Start, Items, [Start|Running]) :-
    must_be(list, Items),
    current_metta_module(Module),
    scan_(Items, Module, Function, Start, Running).

scan_([], _, _, _, []).
scan_([Item|Items], Module, Function, Accumulator, [Next|Running]) :-
    applied2(Module, Function, Accumulator, Item, Next),
    scan_(Items, Module, Function, Next, Running).

%! unfold(+Step:any, +Seed:any, -Items:list) is det.
%
% The collection a seed grows into: the step function is applied to the seed and
% answers (Value NextSeed) to continue or nothing to stop, so unfold is the
% opposite of a fold. A step that never stops never answers, which is the
% caller's own contract.
unfold(Step, Seed, Items) :-
    current_metta_module(Module),
    unfold_(Module, Step, Seed, Items).

unfold_(Module, Step, Seed, Items) :-
    (   applied(Module, Step, Seed, [Value, Next])
    ->  Items = [Value|More],
        unfold_(Module, Step, Next, More)
    ;   Items = []
    ).

%! pipe(+Functions:'Atom', +Value:any, -Result:any) is det.
%
% The value passed through each function in turn, left to right: (pipe (f g) x)
% is g applied to f applied to x. compose in lib_patrick composes the other way,
% right to left, which is the mathematical order; this is the reading order. The
% collection of functions is HELD, because an expression of function names would
% otherwise be evaluated as a call to the first of them.
pipe(Functions, Value, Result) :-
    must_be(list, Functions),
    current_metta_module(Module),
    pipe_(Functions, Module, Value, Result).

pipe_([], _, Value, Value).
pipe_([Function|Functions], Module, Value, Result) :-
    applied(Module, Function, Value, Next),
    pipe_(Functions, Module, Next, Result).

%! 'apply-to'(+Function:any, +Arguments:list, -Result:any) is det.
%
% The function applied to the arguments an expression holds, so a collection of
% arguments becomes a call: (apply-to + (1 2)) is 3. A function of one argument
% takes a one-element collection.
'apply-to'(Function, Arguments, Result) :-
    must_be(list, Arguments),
    current_metta_module(Module),
    eval_metta_in_module(Module, [Function|Arguments], Result).

% One application of a MeTTa function, the way par_map applies one: the
% evaluator decides what a lambda, a name or a partial application means, so
% this library never inspects the function it was handed.
applied(Module, Function, Argument, Answer) :-
    eval_metta_in_module(Module, [Function, Argument], Answer).

applied2(Module, Function, First, Second, Answer) :-
    eval_metta_in_module(Module, [Function, First, Second], Answer).

% Every operation answers exactly once: a refusal raises and a function that
% answers nothing is the caller's contract, so there is no semidet case among
% them. The one exception is unfold's own probe, which is why applied/4 is not
% declared.
:- det(zip/3).
:- det(unzip/2).
:- det(drop/3).
:- det(chunk/3).
:- det(window/3).
:- det('flatten-once'/2).
:- det('flatten-deep'/2).
:- det('group-by'/3).
:- det('sort-by'/3).
:- det(scan/4).
:- det(unfold/3).
:- det(pipe/3).
