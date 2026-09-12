% Purpose: directed graphs as expressions, with the walks and orderings over them.
%
%   A graph IS a collection of (Vertex Neighbours) pairs, vertices in the standard
%   order of terms and each neighbour collection a set, which is lib_pairs'
%   multimap shape and SWI's own graph representation with its pairs written as
%   expressions [source: /usr/lib/swi-prolog/library/ugraphs.pl; commit=a5738e9390f2941d8f1c3207b5a28310a22e1f14].
%   Every vertex a neighbour names is itself a vertex of the graph, which is what
%   makes a walk total: graph-of adds the vertices its edges mention.
% Assumes:
%   - a graph argument really is one, in that shape. Each head checks, because
%     the host's walks read the representation as an invariant and answer nothing
%     or the wrong thing when it does not hold
%     [tested: lib_graph:a_value_that_is_not_a_graph_is_refused_by_every_head;
%     commit=a5738e9390f2941d8f1c3207b5a28310a22e1f14]
%   - a vertex is compared as a TERM, so graph-neighbours of a vertex the graph
%     does not hold is a refusal naming it rather than an empty answer, which
%     would read as a sink [tested: lib_graph:an_unknown_vertex_is_named;
%     commit=a5738e9390f2941d8f1c3207b5a28310a22e1f14]
% Guarantees:
%   - every answer that is a graph is itself in the representation, so the
%     operations compose with no repair between them
%     [tested: lib_graph:every_answer_is_a_graph; commit=a5738e9390f2941d8f1c3207b5a28310a22e1f14]
%   - the operations answer what library(ugraphs) answers over the same graph, and
%     the reachability, closure and ordering agree with each other: a vertex is
%     reachable exactly when the closure holds the edge, and a topological order
%     puts every edge's tail before its head
%     [tested: lib_graph:the_operations_agree_with_library_ugraphs,
%     lib_graph:the_walks_agree_with_each_other; commit=a5738e9390f2941d8f1c3207b5a28310a22e1f14]
%   - graph-topological-order refuses a graph with a cycle and NAMES a vertex on
%     one, where the host's top_sort/2 fails silently
%     [tested: lib_graph:a_cycle_refuses_the_ordering_and_names_a_vertex_on_it;
%     commit=a5738e9390f2941d8f1c3207b5a28310a22e1f14]
% Fails when: a caller wants edge weights, a path with a cost, or an undirected
%   graph. An undirected graph is this one with both directions added, which
%   graph-union over the transpose gives; weights belong to a relation of their
%   own, which lib_pairs walks.
% Owns resources: none; every answer is a new expression.
% Decides: an unknown vertex is a refusal rather than no answer, and a cycle is a
%   refusal rather than a failure. Both are the difference between a library that
%   reports a mistake and one that answers as though the graph were different.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None


:- module(lib_graph,
          [ 'graph-of'/3,
            'graph-is'/2,
            'graph-vertices'/2,
            'graph-edges'/2,
            'graph-neighbours'/3,
            'graph-add-vertices'/3,
            'graph-remove-vertices'/3,
            'graph-add-edges'/3,
            'graph-remove-edges'/3,
            'graph-transpose'/2,
            'graph-union'/3,
            'graph-closure'/2,
            'graph-reachable'/3,
            'graph-topological-order'/2,
            'graph-is-acyclic'/2
          ]).

% Guarantees: private helpers and autoload declarations belong to this module.
% [tested: engine_modules; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
% Assumes: engine operations resolve through metta_engine's published exports.
% [source: engine/metta.pl:metta_engine_reexport/2; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
:- set_module(base(metta_engine)).

:- use_module(library(lists), [member/2, memberchk/2]).
:- use_module(library(apply), [maplist/3]).
:- use_module(library(ordsets), [is_ordset/1]).
:- use_module(library(ugraphs), [add_edges/3, add_vertices/3, del_edges/3,
                                del_vertices/3, edges/2, neighbours/3,
                                reachable/3, top_sort/2, transitive_closure/2,
                                transpose_ugraph/2, ugraph_union/3,
                                vertices/2, vertices_edges_to_ugraph/3]).
% Workaround: swi-ugraphs-append2 - ugraphs.pl declares
% `:- autoload(library(lists),[append/3])` and its top_sort/2 also calls the OTHER
% append/2, which concatenates a list of lists and is declared nowhere, so it
% resolves by GLOBAL autoload. With the autoloader off, graph-topological-order
% raises existence_error(procedure, ugraphs:append/2) [measured 2026-09-12:
% `NO_AUTOLOAD=1 sh test.sh` over
% examples/ch08-data/08-03-the-shipped-libraries/25-graph_lib.metta, on the
% topological-order claim]. The import is injected into the host module's own
% namespace, which is idempotent and is what lib_constraints and lib_memo already
% do for their own reach into library(ugraphs) [source:
% lib/lib_constraints/lib_constraints.pl:`:- ugraphs:use_module`; commit=a5738e9390f2941d8f1c3207b5a28310a22e1f14].
:- ugraphs:use_module(library(lists), [append/2]).

%! 'graph-of'(+Vertices:list, +Edges:list, -Graph:list) is det.
%
% The graph of those edges, each written (From To), with those vertices added:
% every vertex an edge mentions is a vertex whether it is listed or not, so the
% first argument is for the ISOLATED ones. Vertices come out in the standard
% order of terms and each neighbour collection is a set.
'graph-of'(Vertices, Edges, Graph) :-
    vertex_list('graph-of', Vertices),
    edge_list('graph-of', Edges),
    maplist(edge_term, Edges, Terms),
    vertices_edges_to_ugraph(Vertices, Terms, Ugraph),
    graph_form(Ugraph, Graph).

edge_term([From, To], From-To).

%! 'graph-is'(+Value:any, -Answer:boolean) is det.
%
% Whether the value is a graph: a collection of (Vertex Neighbours) pairs whose
% vertices are a set, whose neighbour collections are sets, and whose every
% neighbour is itself a vertex of the graph. That last condition is what the
% walks rely on, and the one a hand-written graph most often misses.
'graph-is'(Value, Answer) :-
    (   graph_shape(Value)
    ->  Answer = true
    ;   Answer = false
    ).

graph_shape(Value) :-
    is_list(Value),
    forall(member(Row, Value), ( is_list(Row), Row = [_, Neighbours], is_list(Neighbours) )),
    findall(Vertex, member([Vertex, _], Value), Vertices),
    is_ordset(Vertices),
    forall(member([_, Neighbours], Value),
           ( is_ordset(Neighbours),
             forall(member(Neighbour, Neighbours), memberchk(Neighbour, Vertices)) )).

%! 'graph-vertices'(+Graph:list, -Vertices:list) is det.
%
% Every vertex, in the standard order of terms, which is a set and therefore what
% lib_sets' operations take: membership of a vertex is set-member over this.
'graph-vertices'(Graph, Vertices) :-
    ugraph_argument('graph-vertices', Graph, Ugraph),
    vertices(Ugraph, Vertices).

%! 'graph-edges'(+Graph:list, -Edges:list) is det.
%
% Every edge as a (From To) pair, ordered by tail and then by head. This is
% lib_pairs' relation shape, so the edges of a graph are a relation and its
% operations apply to them.
'graph-edges'(Graph, Edges) :-
    ugraph_argument('graph-edges', Graph, Ugraph),
    edges(Ugraph, Terms),
    maplist(edge_term, Edges, Terms).

%! 'graph-neighbours'(+Graph:list, +Vertex:any, -Neighbours:list) is det.
%
% The vertices this one points at, as a set. A vertex the graph does not hold is
% a refusal naming it, because an empty answer there reads as a sink and a typo
% would go unnoticed.
'graph-neighbours'(Graph, Vertex, Neighbours) :-
    ugraph_argument('graph-neighbours', Graph, Ugraph),
    known_vertex('graph-neighbours', Ugraph, Vertex),
    neighbours(Vertex, Ugraph, Neighbours).

%! 'graph-add-vertices'(+Graph:list, +Vertices:list, -Bigger:list) is det.
%
% The graph with those vertices, each with no neighbours unless it had some
% already. Adding a vertex that is there changes nothing.
'graph-add-vertices'(Graph, Vertices, Bigger) :-
    ugraph_argument('graph-add-vertices', Graph, Ugraph),
    vertex_list('graph-add-vertices', Vertices),
    add_vertices(Ugraph, Vertices, Added),
    graph_form(Added, Bigger).

%! 'graph-remove-vertices'(+Graph:list, +Vertices:list, -Smaller:list) is det.
%
% The graph without those vertices AND without every edge that touched one, which
% is what keeps the answer a graph. Removing a vertex that is not there changes
% nothing.
'graph-remove-vertices'(Graph, Vertices, Smaller) :-
    ugraph_argument('graph-remove-vertices', Graph, Ugraph),
    vertex_list('graph-remove-vertices', Vertices),
    del_vertices(Ugraph, Vertices, Deleted),
    graph_form(Deleted, Smaller).

%! 'graph-add-edges'(+Graph:list, +Edges:list, -Bigger:list) is det.
%
% The graph with those edges, and with any vertex they mention that it did not
% hold. An edge that is there changes nothing.
'graph-add-edges'(Graph, Edges, Bigger) :-
    ugraph_argument('graph-add-edges', Graph, Ugraph),
    edge_list('graph-add-edges', Edges),
    maplist(edge_term, Edges, Terms),
    add_edges(Ugraph, Terms, Added),
    graph_form(Added, Bigger).

%! 'graph-remove-edges'(+Graph:list, +Edges:list, -Smaller:list) is det.
%
% The graph without those edges. The vertices stay, because removing the last
% edge of a vertex leaves the vertex; graph-remove-vertices is how a vertex goes.
'graph-remove-edges'(Graph, Edges, Smaller) :-
    ugraph_argument('graph-remove-edges', Graph, Ugraph),
    edge_list('graph-remove-edges', Edges),
    maplist(edge_term, Edges, Terms),
    del_edges(Ugraph, Terms, Deleted),
    graph_form(Deleted, Smaller).

%! 'graph-transpose'(+Graph:list, -Transposed:list) is det.
%
% The graph with every edge reversed and the same vertices. The union of a graph
% and its transpose is the undirected reading of it.
'graph-transpose'(Graph, Transposed) :-
    ugraph_argument('graph-transpose', Graph, Ugraph),
    transpose_ugraph(Ugraph, Reversed),
    graph_form(Reversed, Transposed).

%! 'graph-union'(+Left:list, +Right:list, -Union:list) is det.
%
% Every vertex and every edge of either, once.
'graph-union'(Left, Right, Union) :-
    ugraph_argument('graph-union', Left, LeftGraph),
    ugraph_argument('graph-union', Right, RightGraph),
    ugraph_union(LeftGraph, RightGraph, Joined),
    graph_form(Joined, Union).

%! 'graph-closure'(+Graph:list, -Closure:list) is det.
%
% The transitive closure: an edge for every path of one step or more, so a
% vertex's neighbours in the answer are everything it can reach. A vertex on a
% cycle reaches itself, which is how graph-is-acyclic and the ordering's refusal
% find one.
'graph-closure'(Graph, Closure) :-
    ugraph_argument('graph-closure', Graph, Ugraph),
    transitive_closure(Ugraph, Closed),
    graph_form(Closed, Closure).

%! 'graph-reachable'(+Graph:list, +Vertex:any, -Reachable:list) is det.
%
% Every vertex reachable from this one, itself included, as a set. The vertex
% itself is always in the answer, whether or not a path returns to it, which is
% the reflexive reading the host's reachable/3 takes.
'graph-reachable'(Graph, Vertex, Reachable) :-
    ugraph_argument('graph-reachable', Graph, Ugraph),
    known_vertex('graph-reachable', Ugraph, Vertex),
    reachable(Vertex, Ugraph, Reachable).

%! 'graph-topological-order'(+Graph:list, -Order:list) is det.
%
% The vertices in an order that puts every edge's tail before its head. A graph
% with a cycle has no such order, and this refuses NAMING a vertex on a cycle,
% where the host's top_sort/2 simply fails and a caller reads that as "no answer".
'graph-topological-order'(Graph, Order) :-
    ugraph_argument('graph-topological-order', Graph, Ugraph),
    (   top_sort(Ugraph, Order)
    ->  true
    ;   cyclic_vertex(Ugraph, Vertex),
        throw(error(domain_error(acyclic_graph, Vertex),
                    context('graph-topological-order',
                            'a graph with a cycle has no topological order; the named vertex reaches itself')))
    ).

%! 'graph-is-acyclic'(+Graph:list, -Answer:boolean) is det.
%
% Whether the graph has no cycle, which is exactly whether it has a topological
% order. This is the total question beside the ordering's refusal.
'graph-is-acyclic'(Graph, Answer) :-
    ugraph_argument('graph-is-acyclic', Graph, Ugraph),
    (   top_sort(Ugraph, _)
    ->  Answer = true
    ;   Answer = false
    ).

% A vertex that reaches itself, which is one on a cycle. The closure answers the
% question directly, and this runs only on the refusal path, where one walk over
% the graph costs nothing worth saving.
cyclic_vertex(Ugraph, Vertex) :-
    transitive_closure(Ugraph, Closed),
    member(Vertex-Reached, Closed),
    memberchk(Vertex, Reached),
    !.

% The two conversions. A host graph is a list of Vertex-Neighbours COMPOUNDS,
% which cross into MeTTa as opaque values that a written form cannot hold, so the
% library's own shape is the pair written as an expression: everything above
% converts on the way in and on the way out [source:
% docs/journal/2026-09-11-a-standard-library-for-a-language.md, the 2026-09-12
% datastructures entry measuring what bind! does to a compound].
graph_form(Ugraph, Graph) :-
    maplist(graph_row, Ugraph, Graph).

graph_row(Vertex-Neighbours, [Vertex, Neighbours]).

ugraph_argument(Head, Graph, Ugraph) :-
    (   graph_shape(Graph)
    ->  maplist(graph_row, Ugraph, Graph)
    ;   is_list(Graph)
    ->  throw(error(type_error(graph, Graph),
                    context(Head,
                            'a graph is a collection of (Vertex Neighbours) pairs, vertices as a set and every neighbour a vertex of the graph; graph-of builds one from edges')))
    ;   throw(error(type_error(list, Graph),
                    context(Head, 'a graph is a collection of (Vertex Neighbours) pairs')))
    ).

known_vertex(Head, Ugraph, Vertex) :-
    vertices(Ugraph, Vertices),
    (   memberchk(Vertex, Vertices)
    ->  true
    ;   throw(error(existence_error(vertex, Vertex),
                    context(Head,
                            'the graph has no such vertex; graph-vertices lists the ones it has')))
    ).

vertex_list(Head, Vertices) :-
    (   is_list(Vertices)
    ->  true
    ;   throw(error(type_error(list, Vertices),
                    context(Head, 'the vertices are a collection')))
    ).

edge_list(Head, Edges) :-
    (   is_list(Edges)
    ->  forall(member(Edge, Edges),
               (   is_list(Edge), Edge = [_, _]
               ->  true
               ;   throw(error(type_error(edge, Edge),
                               context(Head, 'every edge is a two-element expression, (From To)')))
               ))
    ;   throw(error(type_error(list, Edges),
                    context(Head, 'the edges are a collection of (From To) pairs')))
    ).

% Every head answers exactly once: a refusal raises, and the two Bool heads
% answer a Bool rather than failing.
:- det('graph-of'/3).
:- det('graph-is'/2).
:- det('graph-vertices'/2).
:- det('graph-edges'/2).
:- det('graph-neighbours'/3).
:- det('graph-add-vertices'/3).
:- det('graph-remove-vertices'/3).
:- det('graph-add-edges'/3).
:- det('graph-remove-edges'/3).
:- det('graph-transpose'/2).
:- det('graph-union'/3).
:- det('graph-closure'/2).
:- det('graph-reachable'/3).
:- det('graph-topological-order'/2).
:- det('graph-is-acyclic'/2).
