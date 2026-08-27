% Purpose: the half of the minimal-MeTTa instruction set that cannot be written
%   in MeTTa. `function`/`return` need an evaluation loop, `collapse-bind` and
%   `superpose-bind` need each alternative's variable bindings, and all of them
%   need their arguments unevaluated.
%
%   This was Python. Registering the language's own inference control as
%   grounded Python operations cost the janus crossing on every step and made
%   the instruction set unavailable to any program run through run.sh or the
%   packaged CLI, where there is no Python in the loop at all. Measured
%   2026-08-15 on the trivial case (function (return 42)), which runs no
%   evaluation loop whatsoever: 36.1 inferences and 3.99us per call against 7.2
%   and 0.18 for a plain MeTTa function, so 5x by inferences and 22x by wall
%   clock. A real body costs one janus round trip per evaluation step on top.
% Assumes:
%   - a parameter declared Atom reaches a PROLOG-registered predicate
%     unevaluated, the same as it does a Python one [measured 2026-08-15:
%     with (: shape-of (-> Atom Atom)), (shape-of (+ 1 2)) answered
%     `expression` rather than `other`, so the argument arrived as the
%     expression rather than as 3]
%   - eval/2 evaluates to completion and offers one solution per answer
%     [source: engine/metta.pl, eval/2 compiles a runnable and runs it]
% Guarantees:
%   - `function` terminates: the loop is bounded and answers
%     (Error <atom> NoReturn) rather than looping [tested: examples/ch20-extending-the-engine/20-02-metta-written-in-metta/04-minimal_metta.metta]
%   - `(return x)` survives evaluation as data, because `return` is
%     deliberately NOT registered. Registering it as the identity its
%     (-> $t $t) signature suggests makes (return 3) reduce to 3 before
%     `function` can see it, and every function body answers NoReturn. [tested: examples/ch20-extending-the-engine/20-02-metta-written-in-metta/04-minimal_metta.metta]
% Fails when: an expression's evaluation does not converge within the step
%   bound, which answers NoReturn rather than the true result.
% Decides: 1000 evaluation steps for `function`, the bound the Python version
%   chose, kept so the two answer alike; the specification's Turing-machine
%   example uses 23.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- use_module(library(lists)).

metta_function_limit(1000).

%The specification: "It evaluates the <atom> until it becomes (return <atom>).
%Then (function (return <atom>)) expression returns the <atom>." A branch that
%ends without a return is (Error (function <body>) NoReturn), also the
%specification's, and it carries the ORIGINAL frame rather than wherever the
%walk stopped.
'function'(Body, Out) :-
    \+ is_list(Body),
    !,
    swrite([function, Body], Written),
    format(string(Message),
           "expected: (function (: <body> Expression)), found: ~w",
           [Written]),
    Out = ['Error', [function, Body], Message].
'function'(Body, Out) :-
    metta_function_limit(Limit),
    metta_function_loop(Body, Body, Limit, Out).

metta_function_loop(_Body, Current, _Fuel, Out) :-
    metta_return_value(Current, Value), !,
    Out = Value.
%Only a marker PRODUCED by a completed equation is the protocol result.  The
%initial body is required to be an expression above, so reaching this atomic
%state proves an evaluation step returned it.  By contrast, an irreducible
%call makes metta_function_eval/3 report `not-reducible` below and earns
%NoReturn [source: MettaHyperonFull/Minimal/Interpreter.lean:3673-3674 and
%7533-7564; tested: conformance2:a_function_distinguishes_a_marker_result_from_an_irreducible_body;
%commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
metta_function_loop(_, 'NotReducible', _, 'NotReducible') :- !.
metta_function_loop(Body, _Current, 0, Out) :- !,
    Out = ['Error', [function, Body], 'NoReturn'].
%A BODY THAT ANSWERED NOTHING IS NOT A BODY THAT FAILED TO RETURN. The two
%were one case while eval/2 could not answer nothing: now that a nested
%evaluation prunes an `Empty` branch, a body whose branch died has no result,
%and a function over it has none either, where a body that reached a normal
%form without a return still earns the specification's NoReturn.
%
%Reporting the dead branch as NoReturn turns a pruned traversal into an error
%atom: `!(collapse (stratego-all some-only-a (h a b)))` is `()` on the arbiter,
%because a child the strategy declines removes the branch, and it was the whole
%`(Error (chain ...) NoReturn)` term here [measured 2026-08-24 against LeaTTa
%9ea9f9d, running the reference's own strategy basis].
%
%Every evaluation answer is a separate function branch.  Committing to the
%first step erased equation multiplicity: two identical `(= (mt-dup) mt-red)`
%rules produced two evalc answers but only one result through `metta-call`.
%[source: MettaHyperonFull/Minimal/Interpreter.lean:419-448,
%`evalResult` maps every queried equation result; commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87]
metta_function_loop(Body, Current, Fuel, Out) :-
    metta_function_eval(Current, Next, Status),
    (   Status == 'not-reducible'
    ->  Out = ['Error', [function, Body], 'NoReturn']
    ;   Next \== Current
    ->  Next1 is Fuel - 1,
        metta_function_loop(Body, Next, Next1, Out)
    ;   Out = ['Error', [function, Body], 'NoReturn']
    ).

%(return X) with exactly one argument. The arity gate matters: (return a b) is
%ordinary data.
metta_return_value(Term, Value) :-
    is_list(Term),
    Term = [Head, Value],
    Head == return.

%Every alternative evaluation of the atom, each with the values its own branch
%bound, as the specification's (<atom> <bindings>) pairs.
%
%Prolog has the bindings natively, which is the whole reason this belongs here:
%the Python version could not see them and reconstructed them by collapsing a
%probe expression that mentioned the atom and its own free variables.
%
%The shape is LeaTTa's: one expression holding every surfaced alternative
%paired with its encoded bindings, and each binding entry (<- name value)
%[source: LeaTTa MettaHyperonFull/Minimal/Interpreter.lean, collapseBindStep,
%`atoms.map fun p => Atom.expr [p.1, encodeUnified p.2]`, and Core/SeqRuntime
%.lean encodeUnified, `Atom.expr [Atom.sym "<-", Atom.var p.1, p.2.toSurface]`].
%
%The left of each (<- var value) entry is THE CALLER'S OWN VARIABLE, not a
%name for it, and that is what makes superpose-bind able to do its job. The
%specification's whole point for this pair of instructions is that
%"superpose-bind applied to the result of collapse-bind will restore the value
%of this variable in each context" [source: LeaTTa minimal_metta.md, the
%collapse-bind and superpose-bind section], and a name cannot restore anything
%in Prolog: unifying is what restores.
%
%Which is why the pairs are built OUTSIDE the findall. Inside it the variables
%are bound to the branch's values, so an entry made there renders (<- b b) and
%says nothing; and findall COPIES, so an entry made there refers to a copy the
%caller never sees. Collecting values first and pairing them with the live
%variables afterwards gets both: the entry names a variable the caller shares,
%bound to nothing yet, beside the value that branch gave it.
%
%That the variable renders as $_0 rather than $a is the one thing MeTTa cannot
%match here. The parser resolves $x to a plain Prolog variable and keeps the
%name only inside the parse [source: engine/parser.pl, var_symbol//3 threads a
%Name-Var environment that sread/2 does not return], so no name reaches
%runtime. LeaTTa renders $a because its atoms carry the name [source:
%Core/SeqRuntime.lean, encodeUnified,
%`Atom.expr [Atom.sym "<-", Atom.var p.1, p.2.toSurface]`]. Cosmetic: the
%restore works on identity, not spelling.
'collapse-bind'(Atom, Out) :-
    term_variables(Atom, Variables),
    findall(Value-Variables, eval(Atom, Value), Rows),
    maplist(metta_binding_row(Variables), Rows, Out).

metta_binding_row(Variables, Value-Values, [Value, [bindings|Pairs]]) :-
    maplist(metta_binding_pair, Variables, Values, Pairs).

metta_binding_pair(Variable, Value, ['<-', Variable, Value]).

%Put a collapse-bind result back into the plan, one answer per row, RESTORING
%that row's bindings into the caller's context as it goes. Its argument is the
%result of a collapse-bind call and must arrive EVALUATED, which is why its
%parameter is declared Expression rather than Atom: an Atom declaration hands
%over the literal expression (collapse-bind ...) and the loop yields its head
%symbols.
%
%Restoring is one unification per entry, undone by backtracking into member/2,
%which is what lets the next row bind the same variable to its own value. The
%row's own value is answered whether or not it carries bindings, so a list
%that did not come from collapse-bind still superposes
%[source: MettaHyperonFull/Minimal/Stdlib.lean:915;
%tested: examples/ch20-extending-the-engine/20-02-metta-written-in-metta/04-minimal_metta.metta and
%builtin_input_guards:every_builtin_refuses_an_unbound_input_by_name;
%commit=b77e3ce5233e5f6032cfc8546ff83ecf4dc3de87].
'superpose-bind'(Rows, _) :- var(Rows), !,
                            refuse_unbound_input('superpose-bind', 1).
'superpose-bind'(Rows, Out) :-
    is_list(Rows),
    member(Row, Rows),
    (   is_list(Row), Row = [Value, Bindings]
    ->  metta_restore_bindings(Bindings), Out = Value
    ;   is_list(Row), Row = [Value|_]
    ->  Out = Value
    ;   Out = Row
    ).

metta_restore_bindings(Bindings) :-
    (   is_list(Bindings), Bindings = [Head|Pairs], Head == bindings
    ->  maplist(metta_restore_binding, Pairs)
    ;   true
    ).

metta_restore_binding(['<-', Variable, Value]) :- !, Variable = Value.
metta_restore_binding(_).

%unify extended with the two things the specification names as open and LeaTTa
%resolved: (:= x) matches by equality, so a free variable is not Empty, and
%... matches any number of atoms, so (A ... D ...) matches (A B C D E).
'unify-mod'(Atom, Pattern, Then, Else, Out) :-
    (   metta_mm_match(Pattern, Atom)
    ->  once(eval(Then, Out))
    ;   once(eval(Else, Out))
    ).

%One-way match. The pattern's variables bind to the atom's subterms, and
%because they are the same Prolog variables the chosen branch already mentions,
%binding them IS the substitution the specification asks for: "it returns
%<then> atom and merges bindings of the original <atom> to resulting variable
%bindings".
metta_mm_match(Pattern, Target) :-
    metta_mm_equality_argument(Pattern, Wanted), !,
    Wanted == Target.
metta_mm_match(Pattern, Target) :-
    var(Pattern), !,
    Pattern = Target.
metta_mm_match(Pattern, Target) :-
    is_list(Pattern), !,
    is_list(Target),
    metta_mm_match_sequence(Pattern, Target).
metta_mm_match(Pattern, Target) :-
    Pattern = Target.

%(:= x) with exactly one argument is the match-by-equality modifier. The arity
%gate is forced by real corpora where (:= (Green Sam) T) already appears as
%data, so recognising := by name alone would reinterpret existing programs.
metta_mm_equality_argument(Pattern, Wanted) :-
    nonvar(Pattern),
    is_list(Pattern),
    Pattern = [Head, Wanted],
    Head == ':='.

%Element-wise, with ... standing for any number of atoms, tried shortest first.
metta_mm_match_sequence([], []).
metta_mm_match_sequence([Head|PatternRest], Values) :-
    nonvar(Head), Head == '...', !,
    append(_, Tail, Values),
    metta_mm_match_sequence(PatternRest, Tail).
metta_mm_match_sequence([Head|PatternRest], [Value|ValueRest]) :-
    metta_mm_match(Head, Value),
    metta_mm_match_sequence(PatternRest, ValueRest).
