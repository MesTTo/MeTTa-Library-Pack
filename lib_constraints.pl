% Purpose: reach SWI's other two constraint solvers, CLP(Q) over the rationals
%   and CLP(B) over the booleans, from MeTTa. The engine already has CLP(FD)
%   under the `#` prefix; this is the rest of the family, as a library rather
%   than as engine surface.
% Assumes:
%   - library(clpq) and library(clpb) are present in this SWI
%     [measured 2026-08-16: both load beside clpfd with no operator clash].
% Guarantees:
%   - a constraint reaches the solver AS WRITTEN, so it may mention unbound
%     variables [tested: each_constraint_domain_answers].
%   - a list argument stays a list, so card/2's count list is not read as an
%     operator application [tested: a_list_argument_stays_a_list].
%   - library(clpq)'s and library(clpb)'s own internal, undeclared
%     references into library(ugraphs), library(lists), library(pairs) and
%     library(apply) work under autoload=false, not only the engine's
%     default [measured 2026-08-18: NO_AUTOLOAD=1 sh test.sh,
%     examples/basics/constraint_domains.metta].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- use_module(library(clpq), [entailed/1]).
:- use_module(library(clpb), [sat/1, labeling/1, taut/2]).
%library(clpq) pulls in library(ugraphs) for its own variable-elimination
%ordering (clpqr/ordering.pl); ugraphs.pl declares
%:- autoload(library(lists),[append/3]) but its top_sort/2 also calls the
%OTHER append/2 (concatenate a list of lists), undeclared, so that one
%resolves by GLOBAL autoload today. With autoload=false, extracting a
%solved CLP(Q) system's residual goals raises
%existence_error(procedure,ugraphs:append/2) from inside
%clpqr_ordering:arrangement/2 [measured 2026-08-18:
%examples/basics/constraint_domains.metta's residual-goals test, under
%NO_AUTOLOAD=1]. Same trap, same fix, as lib_memo.pl's independent use of
%library(ugraphs): inject the missing import into ugraphs's own namespace
%once its real file is loaded, since ugraphs.pl itself is not this repo's
%to patch and use_module is idempotent regardless of which caller (this
%file's clpq, or lib_memo.pl) reaches library(ugraphs) first in a given
%process.
:- ugraphs:use_module(library(lists), [append/2]).
%library(clpb) does not declare library(lists) at all, not even a local
%:- autoload like ugraphs's partial one above, and calls six of its
%predicates unqualified across its sat/1 compilation, labeling/1 and
%weighted-labeling steps: same_length/2 and member/2 confirmed by running
%the corpus [measured 2026-08-18:
%examples/basics/constraint_domains.metta's card/2 and sat/1 tests, under
%NO_AUTOLOAD=1: existence_error(procedure,clpb:same_length/2), then
%clpb:member/2]; append/3, memberchk/2, reverse/2 and sum_list/2 read from
%clpb.pl directly (lines 833-1639) rather than found by crashing on each
%in turn.
:- clpb:use_module(library(lists),
                   [same_length/2, member/2, memberchk/2, append/3,
                    reverse/2, sum_list/2]).
%Same gap, library(pairs): clpb.pl's sat/1 variable-weight bookkeeping
%calls pairs_values/2, pairs_keys_values/3 and pairs_keys/2 unqualified
%[measured 2026-08-18: examples/basics/constraint_domains.metta under
%NO_AUTOLOAD=1, existence_error(procedure,clpb:pairs_values/2)].
:- clpb:use_module(library(pairs),
                   [pairs_values/2, pairs_keys_values/3, pairs_keys/2]).
%Same gap, library(apply): clpb.pl calls apply_macros's own targets
%(maplist, foldl, include, exclude, partition) unqualified too, and
%apply_macros's compile-time inlining evidently does not cover every
%call shape here (a Goal built from a partial application like
%exclude(eq_1) or maplist(monotonic_variable) is not the literal
%lambda/named-predicate pattern it inlines), so at least foldl/5 falls
%through to a real, uninlined call and needs the predicate to exist
%[measured 2026-08-18: examples/basics/constraint_domains.metta under
%NO_AUTOLOAD=1, existence_error(procedure,clpb:foldl/5)]. The full set
%below is every arity clpb.pl (lines 348-1784) actually calls, read
%directly rather than found by crashing on each in turn.
:- clpb:use_module(library(apply),
                   [maplist/2, maplist/3, maplist/4, foldl/4, foldl/5,
                    include/3, exclude/3, partition/4, partition/5]).

%ONE ENTRY POINT EACH, taking the constraint as an expression, rather than a
%prefixed operator family like the engine's `#`. That is a decision about the
%surface and it is worth stating the arithmetic behind it: mirroring `#`'s
%shape would need fourteen names for CLP(Q) and a further handful for CLP(B),
%about thirty, where these are five. Each solver already HAS a single entry
%point, `{}/1` and sat/1, so this exposes what the library exposes instead of
%re-spelling it operator by operator.
%
%It also follows the rule the engine set for `dif` beside `!=`: a new
%capability arrives under its own name rather than by changing what an
%existing operator means. `#` is untouched.
%
%A LIBRARY and not stdlib. `#` is engine surface because the engine's own
%duals read it, `comparison_dual/2` extending to it for free. Nothing in the
%engine reads these, so they belong where a program opts into them.
%
%WHY THE OTHER TWO ARE WORTH HAVING, measured 2026-08-16.
%
%CLP(Q) gives three things the integer solver cannot. Exact rationals, so
%`(clpq (= (* 2 $x) 1))` binds $x to 1r2 where clpfd has no answer at all.
%PROJECTION, which is quantifier elimination: state a relation over four
%variables and read back the implied relation between two, with the others
%eliminated, `{A>=0, B=3-A, A=<3}` from `A+B+C+D=10, A>=0, B>=0, C=3, D=4`.
%And disequations over rationals, `{A =\= B}`, which is dif/2's numeric
%analogue and what Colmerauer's square-tiling program is built on.
%
%CLP(B) is worth having at SIZE and not below it. The engine's own relational
%and/or/not are generate-and-test over bool/1, which is cheaper than building
%a BDD until the formula constrains every variable at once. On "exactly one of
%N is true" the crossover is at TWELVE variables: 243 inferences against
%clpb's 5,408 at N=4, 65,498 against 59,443 at N=12, and 16,777,154 against
%289,037 at N=20.

%The constraint as written, translated into the solver's own term language.
%Every operator these solvers accept, =, <, >, =<, >=, =\=, +, -, *, /, ~, is
%already an ordinary MeTTa symbol, so the translation is structural.
%
%A list whose head is a SYMBOL is an operator application and becomes a
%compound; any other list stays a list, because these solvers take lists as
%arguments too. `(card (1) ($a $b))` is card/2 over the list [1] and the list
%[A, B], and reading the inner `(1)` as an operator application would make it
%1/0 and fail in the solver rather than here.
metta_constraint_term(Expr, Term) :-
    (   var(Expr)         -> Term = Expr
    ;   \+ is_list(Expr)  -> Term = Expr
    ;   Expr = [Op|Args], atom(Op), Args \== []
    ->  maplist(metta_constraint_term, Args, Terms),
        Term =.. [Op|Terms]
    ;   maplist(metta_constraint_term, Expr, Term)
    ).

clpq(Expr, true) :-
    metta_constraint_term(Expr, Term),
    catch(clpq:{Term}, E, rethrow_metta_operation_error(clpq, E)).

%Whether the constraint is ENTAILED by what is already posted, which is the
%question projection makes answerable and the one a plain post cannot ask.
'clpq-entailed'(Expr, Out) :-
    metta_constraint_term(Expr, Term),
    (   catch(clpq:entailed(Term), E,
              rethrow_metta_operation_error('clpq-entailed', E))
    ->  Out = true
    ;   Out = false
    ).

clpb(Expr, true) :-
    metta_constraint_term(Expr, Term),
    catch(sat(Term), E, rethrow_metta_operation_error(clpb, E)).

%Every assignment satisfying what is posted, as the variables' values, which
%is what makes clpb usable from MeTTa: the solver's own labeling/1 binds in
%place and MeTTa needs the answers back.
'clpb-labeling'(Vars, Out) :-
    must_be(list, Vars),
    catch(( labeling(Vars), Out = Vars ),
          E, rethrow_metta_operation_error('clpb-labeling', E)).

%Whether the formula is a tautology, a contradiction, or neither, which clpb
%answers without enumerating anything.
'clpb-taut'(Expr, Out) :-
    metta_constraint_term(Expr, Term),
    (   catch(taut(Term, T), E, rethrow_metta_operation_error('clpb-taut', E))
    ->  ( T =:= 1 -> Out = true ; Out = false )
    ;   Out = unknown
    ).

%clpq/2 and clpb/2 are SEMIDET, not det: posting a contradiction has to FAIL,
%which is how a constraint says no, and det/1 raises on failure as well as on
%a choice point. The three that always answer are declared.
:- det('clpq-entailed'/2).
:- det('clpb-taut'/2).
:- det(metta_constraint_term/2).
