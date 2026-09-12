% Purpose: sets as ordered expressions, with the merge operations over them.
%
%   A set IS an expression whose elements are in the standard order of terms with
%   no duplicates, which is SWI's own ordered-set representation, so every
%   operation here is a linear merge rather than a quadratic scan and no separate
%   value type is introduced [source: /usr/lib/swi-prolog/library/ordsets.pl;
%   commit=e3e8c891065765765ee8fe567c5eb6864e79b652].
% Assumes:
%   - a set argument really is one. Every head checks, because the host's merges
%     answer nonsense on unsorted input rather than failing: ord_union/3 over
%     ([2 1], [1]) answers (2 1 1), with nothing said
%     [tested: lib_sets:an_unordered_argument_is_refused_by_every_head;
%     commit=e3e8c891065765765ee8fe567c5eb6864e79b652]
%   - elements are compared as TERMS. A variable is not a member of a set of
%     numbers, where member/2 would unify it with the first one
%     [tested: lib_sets:membership_compares_terms_rather_than_unifying;
%     commit=e3e8c891065765765ee8fe567c5eb6864e79b652]
% Guarantees:
%   - every answer is itself a set, so the operations compose without a
%     normalisation step, and set-of is the only head that has to sort
%     [tested: lib_sets:every_answer_is_a_set; commit=e3e8c891065765765ee8fe567c5eb6864e79b652]
%   - the merges agree with the same operations computed over lists for
%     generated inputs, and the laws they obey (commutativity, associativity,
%     distribution, De Morgan over a universe) hold
%     [tested: lib_sets:the_merges_agree_with_their_list_definitions,
%     lib_sets:the_laws_of_the_algebra_hold; commit=e3e8c891065765765ee8fe567c5eb6864e79b652]
% Fails when: a caller wants duplicates or insertion order kept. That is an
%   expression, and lib_functional's group-by, sort-by and flatten-once are what
%   work over one; lib_roman's `/?\`, `\?` and `\?/` take the COMPARISON as an
%   argument and work over unordered lists, which is the other trade.
% Owns resources: none; every answer is a new expression.
% Decides: no separate emptiness, cardinality or equality head. The empty set is
%   `()`, the cardinality is `size-atom`, and two sets are equal exactly when
%   they are `==`, because the representation is canonical. A head for any of the
%   three would be a second spelling of something the language already has.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None


:- module(lib_sets,
          [ 'set-of'/2,
            'set-is'/2,
            'set-member'/3,
            'set-insert'/3,
            'set-remove'/3,
            'set-union'/3,
            'set-union-all'/2,
            'set-intersection'/3,
            'set-intersection-all'/2,
            'set-difference'/3,
            'set-symmetric-difference'/3,
            'set-subset'/3,
            'set-disjoint'/3
          ]).

% Guarantees: private helpers and autoload declarations belong to this module.
% [tested: engine_modules; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
% Assumes: engine operations resolve through metta_engine's published exports.
% [source: engine/metta.pl:metta_engine_reexport/2; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
:- set_module(base(metta_engine)).

:- use_module(library(error), [must_be/2]).
:- use_module(library(lists), [member/2]).
:- use_module(library(ordsets), [is_ordset/1, list_to_ord_set/2, ord_add_element/3,
                                 ord_del_element/3, ord_disjoint/2,
                                 ord_intersection/2, ord_intersection/3,
                                 ord_memberchk/2, ord_subset/2, ord_subtract/3,
                                 ord_symdiff/3, ord_union/2, ord_union/3]).

%! 'set-of'(+Items:list, -Set:list) is det.
%
% The set of an expression's elements: the same elements in the standard order of
% terms, each once. This is the only head that sorts, because every other one
% answers a set already.
'set-of'(Items, Set) :-
    must_be(list, Items),
    list_to_ord_set(Items, Set).

%! 'set-is'(+Value:any, -Answer:boolean) is det.
%
% Whether the value is a set: an expression in the standard order of terms with
% no duplicates. This is the question every other head asks before it merges,
% asked out loud.
'set-is'(Value, Answer) :-
    (   is_list(Value), is_ordset(Value)
    ->  Answer = true
    ;   Answer = false
    ).

%! 'set-member'(+Set:list, +Element:any, -Answer:boolean) is det.
%
% Whether the element is in the set, compared as a TERM rather than unified: a
% variable is not a member of a set of numbers, where member/2 would bind it to
% the first one. The comparison is the standard order, so the search stops at the
% first element that is larger.
'set-member'(Set, Element, Answer) :-
    set_argument('set-member', Set),
    (   ord_memberchk(Element, Set)
    ->  Answer = true
    ;   Answer = false
    ).

%! 'set-insert'(+Set:list, +Element:any, -Bigger:list) is det.
%
% The set with the element added, which is the set itself when it was already
% there. The input is left alone, as every operation here leaves its inputs.
'set-insert'(Set, Element, Bigger) :-
    set_argument('set-insert', Set),
    ord_add_element(Set, Element, Bigger).

%! 'set-remove'(+Set:list, +Element:any, -Smaller:list) is det.
%
% The set without the element, which is the set itself when it was not there, so
% removing something absent is not an error.
'set-remove'(Set, Element, Smaller) :-
    set_argument('set-remove', Set),
    ord_del_element(Set, Element, Smaller).

%! 'set-union'(+Left:list, +Right:list, -Union:list) is det.
%
% Every element of either, once: one merge down both sets rather than a scan of
% one for each element of the other.
'set-union'(Left, Right, Union) :-
    set_argument('set-union', Left),
    set_argument('set-union', Right),
    ord_union(Left, Right, Union).

%! 'set-union-all'(+Sets:list, -Union:list) is det.
%
% The union of a collection of sets, in one pass over all of them: the fold a
% caller would otherwise write, and the empty collection's union is the empty set.
'set-union-all'(Sets, Union) :-
    sets_argument('set-union-all', Sets),
    ord_union(Sets, Union).

%! 'set-intersection'(+Left:list, +Right:list, -Common:list) is det.
%
% The elements in both, once.
'set-intersection'(Left, Right, Common) :-
    set_argument('set-intersection', Left),
    set_argument('set-intersection', Right),
    ord_intersection(Left, Right, Common).

%! 'set-intersection-all'(+Sets:list, -Common:list) is det.
%
% The elements every set in the collection holds. A collection of no sets has no
% intersection to speak of, so that raises rather than answering a universe it
% cannot name.
'set-intersection-all'(Sets, Common) :-
    sets_argument('set-intersection-all', Sets),
    (   Sets == []
    ->  throw(error(domain_error(non_empty_list, Sets),
                    context('set-intersection-all',
                            'the intersection of no sets is every term there is, which is not a set; ask for at least one')))
    ;   ord_intersection(Sets, Common)
    ).

%! 'set-difference'(+Left:list, +Right:list, -Rest:list) is det.
%
% The elements of the first that the second does not hold. The order matters:
% this is not symmetric, and set-symmetric-difference is the one that is.
'set-difference'(Left, Right, Rest) :-
    set_argument('set-difference', Left),
    set_argument('set-difference', Right),
    ord_subtract(Left, Right, Rest).

%! 'set-symmetric-difference'(+Left:list, +Right:list, -Either:list) is det.
%
% The elements exactly one of them holds, which is the union of the two
% differences and the same set whichever way round the arguments go.
'set-symmetric-difference'(Left, Right, Either) :-
    set_argument('set-symmetric-difference', Left),
    set_argument('set-symmetric-difference', Right),
    ord_symdiff(Left, Right, Either).

%! 'set-subset'(+Left:list, +Right:list, -Answer:boolean) is det.
%
% Whether every element of the first is in the second. A set is a subset of
% itself, and the empty set is a subset of everything.
'set-subset'(Left, Right, Answer) :-
    set_argument('set-subset', Left),
    set_argument('set-subset', Right),
    (   ord_subset(Left, Right)
    ->  Answer = true
    ;   Answer = false
    ).

%! 'set-disjoint'(+Left:list, +Right:list, -Answer:boolean) is det.
%
% Whether they share no element. The empty set is disjoint from everything,
% including itself.
'set-disjoint'(Left, Right, Answer) :-
    set_argument('set-disjoint', Left),
    set_argument('set-disjoint', Right),
    (   ord_disjoint(Left, Right)
    ->  Answer = true
    ;   Answer = false
    ).

% The one check every head makes, and the reason it exists: the host's merges
% read their arguments as already ordered and answer nonsense when they are not,
% which is a wrong answer with no symptom. The refusal names the head and the
% remedy.
set_argument(Head, Value) :-
    (   is_list(Value), is_ordset(Value)
    ->  true
    ;   throw(error(type_error(set, Value),
                    context(Head,
                            'a set is an expression in the standard order of terms with no duplicates; set-of makes one out of any expression')))
    ).

sets_argument(Head, Sets) :-
    (   is_list(Sets)
    ->  forall(member(Set, Sets), set_argument(Head, Set))
    ;   throw(error(type_error(list, Sets),
                    context(Head, 'the argument is a collection of sets')))
    ).

% Every head answers exactly once: a refusal raises and the Bool heads answer a
% Bool rather than failing, so nothing here is semidet.
:- det('set-of'/2).
:- det('set-is'/2).
:- det('set-member'/3).
:- det('set-insert'/3).
:- det('set-remove'/3).
:- det('set-union'/3).
:- det('set-union-all'/2).
:- det('set-intersection'/3).
:- det('set-intersection-all'/2).
:- det('set-difference'/3).
:- det('set-symmetric-difference'/3).
:- det('set-subset'/3).
:- det('set-disjoint'/3).
