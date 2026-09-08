% Purpose: the runtime control plane for tabling MeTTa functions. Every
%   declaration is a constructed, module-qualified table/1 goal, never
%   interpolated source text, so hyphenated and uppercase names survive,
%   named spaces instrument their own implementation module, repeated
%   declarations are cumulative and idempotent, and every operation
%   verifies its effect and throws loudly when the engine disagrees.
%   Live declarations reflect into &metta as (tabled space name arity)
%   facts, input arity, asserted on declare and retracted on undeclare. On a
%   threaded SWI the tables are shared between engines, so a Python
%   Answers cursor and the term runner reach one answer trie and report one
%   set of statistics. A threads-disabled SWI, including swipl-wasm, owns its
%   table trie per engine instead: the Node seat's one-engine-per-run contract
%   reuses answers between forms in one run and recomputes them in the next
%   [tested: "recomputes across Node runs and reuses within one run";
%   commit=42df19d71823b963fce5594a42f57fd23a89b7a9].
%   A (cache Name Policy) row in &metta is the developer's word on HOW a
%   function is tabled: the catalog's cache-policy vocabulary is SWI's own
%   table/1 option list and answer-subsumption mode spelled as MeTTa words,
%   and this file compiles the row to `table Module:Spec as (...)` plus the
%   watch each read storage predicate carries. A row installs the table by
%   itself, for every compiled arity of the name, now or when the clauses
%   arrive; `tabled` installs under the standing row's policy or the default.
% Guarantees:
%   - a function change invalidates the tables MeTTa DECLARED and walks no
%     further: one equation change after a table of N answers was built and
%     dropped costs the same 377 inferences at N of 5,000, 20,000 and 80,000,
%     where abolish_all_tables/0 cost 2N [tested:
%     test_an_equation_change_does_not_pay_for_a_dropped_table; commit=57f21ba9edf94bcf28cde11f938bce2c241a3709]
%   - seam:forget_derived/0 drops every declared table's answers and keeps the
%     declarations, which is the abolition a changed equation already causes,
%     so a replay of a recorded run over a tabled head takes the first run's
%     path [tested: tabling_equation_change_drops_tables; commit=e54c3654b9e0d3d040560d12c105a54303f63af7].
%   - A declared table survives a write to a space it reads, and a change
%     to any equation drops it [tested: tabling_equation_change_drops_tables,
%     and end to end by examples/ch18-performance/18-02-memoisation-and-tabling/10-tabling_equation_change.metta and
%     examples/ch18-performance/18-02-memoisation-and-tabling/11-tabling_space_write.metta].
%   - A write the table's own subgoal does not read leaves it VALID, not
%     merely leaves its answers unchanged, so tabling over a space that is
%     written to often is worth having. This is finer than the manual's own
%     summary, which says invalidation "is done at the level of tables.
%     Notably asserting a clause invalidates all affected tables" and closes
%     with "Future versions may implement a more fine grained approach"
%     [source: SWI-Prolog 10.1 Reference Manual, 7.7]. Measured 2026-08-16 on
%     SWI 10 against a table for (reach a $y) over (edge a b): adding
%     (edge b d) and (unrelated x y) each left invalidated at 0, read BEFORE
%     the next call so re-evaluation cannot be what hides it, while adding
%     (edge a c) took it to 1 immediately
%     [tested: tabling_statistics_count_invalidations, and end to end by
%     examples/ch18-performance/18-02-memoisation-and-tabling/12-tabling_statistics.metta].
%   - A read that cannot be resolved to one space predicate, or that names
%     a foreign space, is refused rather than tabled without the guarantee
%     [tested: tabling_refuses_unresolvable_reads].
%   - Reads of a parametric native space resolve to its reserved predicate in
%     its canonical storage module [tested:
%     test_two_instances_of_a_parametric_space_answer_independently;
%     commit=3c7bcde6a0670ec5c563584b26977b41cc727580].
%   - A body whose effects the walk cannot classify is tabled PLAIN rather than
%     refused: the declaration is the developer's and this library builds the
%     strongest table it admits [tested: an_effectful_body_tables_plain,
%     a_higher_order_body_tables_plain; commit=ccad9f6d588270ec2f0810fc56c30e9e59207e7c].
%   - A (cache Name monotonic) row tables the name `as monotonic` and marks
%     every read storage predicate monotonic, so an add-atom propagates only
%     its consequences: over a 200-link chain the add costs 50 inferences and
%     the next read 415, where the incremental table re-evaluates at 2,350;
%     the storage predicate is NOT also marked incremental, because that
%     invalidates the monotonic table on every write and its next read then
%     costs 4,776 [measured 2026-09-07; command=the probe17 program recorded in
%     docs/journal/2026-09-06-cache-policies-are-the-engines-own-options.md;
%     tested: a_monotonic_table_takes_a_new_fact_without_re_evaluation,
%     test_a_monotonic_table_propagates_an_add_at_delta_cost; commit=eb6b4de8ea70a6b2fe8312a1a23d0593fa764d54]
%   - A (lattice Join) policy tables the head with Module:Join/3 in the
%     answer position, one aggregated answer per input variant, private and
%     watching nothing, because on SWI-Prolog 10.1.13 a shared moded table
%     raises type_error(trie, ...) on its second call and an incremental or
%     monotonic one re-evaluates to a wrong table [measured 2026-09-07;
%     tested: a_lattice_table_answers_the_minimum_over_a_cycle; commit=eb6b4de8ea70a6b2fe8312a1a23d0593fa764d54]
%   - A subsumptive policy reuses a completed general table for a specific
%     call, and is refused with a watch, whose re-evaluation raises
%     existence_error(reset, ...) on this SWI [measured 2026-09-07; tested:
%     a_subsumptive_table_answers_a_specific_call_from_the_general_one,
%     a_watched_subsumptive_policy_is_refused; commit=eb6b4de8ea70a6b2fe8312a1a23d0593fa764d54]
%   - A restraint stops the evaluation with metta_control_signal(restraint,
%     [Word, Bound, Call]) rather than answering a partial table: the two size
%     restraints through SWI's tripwire, max-answers through call_delays/2 on
%     the bounded-rationality answer SWI adds, because the per-predicate count
%     restraint never calls the tripwire on 10.1.13 [measured 2026-09-07;
%     tested: a_max_answers_restraint_signals_when_it_trips,
%     a_subgoal_abstract_restraint_signals_through_the_tripwire,
%     test_a_tripped_restraint_reaches_python_as_a_restraint_error;
%     commit=eb6b4de8ea70a6b2fe8312a1a23d0593fa764d54]
%   - A policy the engine cannot honour for a head is refused naming the
%     remedy and the row does not stand: an unclassifiable body under a watch,
%     a foreign read under a watch, a storage predicate already carrying the
%     other watch, lazy without monotonic, two words of one class, a shared or
%     watched lattice, a watched subsumptive [tested:
%     a_watched_policy_over_an_impure_body_is_refused,
%     one_storage_predicate_carries_one_watch,
%     a_refused_row_does_not_stand, test_the_refusals_name_their_remedy;
%     commit=eb6b4de8ea70a6b2fe8312a1a23d0593fa764d54]
%   - table-stats answers (policy Words) beside its five counters, the words
%     in force after compilation, and the storage watch is released when the
%     last table reading a predicate under it is dropped [tested:
%     the_policy_in_force_is_reported_and_released; commit=eb6b4de8ea70a6b2fe8312a1a23d0593fa764d54]
% Fails when:
%   - the caller depends on the ORDER of a function's answers. Tabling
%     changes it. An untabled MeTTa function answers in clause order, and a
%     tabled one answers from its trie: SWI puts it plainly, "Tabling
%     effectively inverts the execution order for this case" [source:
%     SWI-Prolog 10.1 Reference Manual, section 7.1]. Which order comes out
%     depends on the trie's layout, so it moves when something unrelated
%     moves. Measured 2026-08-15: (collapse (pick a)) over two equations
%     answered (one two), and adding three facts that NOTHING CALLS to
%     engine/translator.pl flipped it to (two one); removing them flipped it
%     back, deterministically, seven runs each way. Adding only comments
%     changed nothing, so it tracks new atoms rather than new lines.
%
%     So tabling preserves the answer SET, not the answer sequence. A
%     program that reads a collapse positionally, with car-atom or
%     index-atom, is not safe to table. sort-atom over the collapse is, and
%     is what the examples do.
%
%     Which is now DETECTED rather than only written down here. The live
%     (tabled Space Name Arity) facts this reflects into &metta are what
%     space.lint() reads to find a car-atom, cdr-atom or index-atom picking
%     out of a collapse of a tabled function, reported as
%     tabled-answer-order-read [tested:
%     test_a_positional_read_of_a_tabled_functions_answers]. A finding and
%     not a refusal, because a positional read is right whenever the
%     function is deterministic and nothing here knows whether it is; a
%     collapse that goes through sort-atom or unique-atom first is not
%     reported [tested:
%     test_a_canonicalised_read_of_a_tabled_function_is_not_a_finding].
%   - a lazy policy is read as deferring the propagation. On SWI-Prolog
%     10.1.13 the answer a write adds is in the lazy table before the next
%     call, exactly as in the eager one, and the table is marked invalid until
%     that call re-validates it at 545 inferences against 415; lazy is
%     compiled as written and reported, and buys nothing measurable here
%     [measured 2026-09-07; command=the probe17 program recorded in the same
%     journal thread].
% Decides: the default watch is incremental for a variant table over a body
%   the walk classifies and plain otherwise; a lattice or subsumptive table
%   defaults to plain and refuses when the body reads a space unless plain is
%   written, so a table that goes stale after a write is one the program said
%   so about; a lattice table defaults to private.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None


:- module(lib_tabling,
          [ metta_table_clear/2,
            metta_table_clear_all/1,
            metta_table_statistics/2,
            metta_tabled_decl/2,
            metta_tabling_reads/4,
            metta_tabling_target/4,
            metta_untabled_decl/2
          ]).

% Guarantees: private helpers and autoload declarations belong to this module.
% [tested: engine_modules; commit=WORKTREE]
% Assumes: engine operations resolve through metta_engine's published exports.
% [source: engine/metta.pl:metta_engine_reexport/2; commit=WORKTREE]
:- set_module(base(metta_engine)).

:- multifile prolog:error_message//1.

%A tabled call is another owner of the universal call-dispatch seam. Like
%lib_memo, install one indexed handler only for names that are enabled: an
%ordinary program that imports this library and tables nothing pays nothing at
%a call site.
:- multifile seam:dispatch_call/4.
:- dynamic seam:dispatch_call/4.
:- dynamic metta_tabling_dispatch_installed/1.
:- dynamic metta_tabling_registration/3.
%What each registered table was built from and to: the declared policy (the
%row's members, or `default`), the words in force after compilation, the
%storage predicates it watches, and whether a (tabled ...) call ever asked for
%it (`call`) or only a (cache ...) row did (`row`). The 3-argument registration
%above stays the dispatch guard's one indexed lookup; this is read once per
%dispatch resolution and by table-stats.
:- dynamic metta_tabling_policy_installed/7.
%Which watch a storage predicate carries and for whom. One predicate carries
%one watch: a monotonic table over a predicate that is also incremental is
%invalidated by the incremental wrapper on every write and re-evaluates at
%4,776 inferences where the pure monotonic read costs 415 and the pure
%incremental re-evaluation 2,350 [measured 2026-09-07, probe17 in the journal
%thread], so the second watch is refused naming the first reader, and the
%property is turned back off when the last reader under it is dropped.
:- dynamic metta_tabling_storage_watch/3.

%table_statistics/3 is tableutil's, and it is not autoloaded.
:- use_module(library(tableutil)).

%call_delays/2 is library(wfs)'s, not library(tabling)'s, and the library-index
%autoloader is what had been finding it: with autoload off the restraint
%dispatch raised `Unknown procedure: call_delays/2` and the no-autoload lane
%stopped on
%examples/ch18-performance/18-02-memoisation-and-tabling/16-cache_policy_restraints.metta.
%That lane exists for exactly this, a module boundary broken with every other
%lane still green.
%
% Load wfs when a restraint needs call_delays/2. This declaration belongs to
% lib_tabling and cannot replace metta_engine's library(uuid) autoload table.
% Explicit autoload declarations also work when general autoload is disabled.
% [tested: engine_modules:the_engines_autoload_table_survives_a_librarys,
% sh check.sh no-autoload; commit=WORKTREE]

:- autoload(library(wfs), [call_delays/2]).


%A MeTTa call form arrives as a list, possibly under one quote; the
%function name is its head atom and the compiled arity is the input
%arity plus the output argument the translator appends.
metta_tabling_target(Call0, Module, Name, CompiledArity) :-
    ( Call0 = [quote, Call] -> true ; Call = Call0 ),
    ( is_list(Call), Call = [Name|Args], atom(Name)
      -> true
    ; throw(error(type_error(metta_function_call, Call0), none)) ),
    length(Args, InputArity),
    CompiledArity is InputArity + 1,
    metta_tabling_module(Name, CompiledArity, Module).

%The function's clauses live in the module that owns the predicate visible at
%the call site. A named space may import a function from its parent; tabling
%the call-site module in that case wraps a shadow the executable call does not
%enter. imported_from/1 is SWI's published ownership question and is the same
%late-bound resolution pattern used by lib_memo's dispatch owner.
%
%A definition that has arrived but not been translated has no predicate to
%find yet, and asking current_predicate/1 is not a call, so the engine's
%undefined-predicate net does not fire for it. None visible is a loud refusal:
%declare after defining, because tabling a name that does not exist yet tables
%nothing.
metta_tabling_module(Name, CompiledArity, Module) :-
    metta_ensure_compiled(Name),
    current_metta_module(CallModule),
    (   metta_tabling_visible_owner(Name, CompiledArity, CallModule, Module)
    ->  true
    ;   metta_self_module(Self),
        Self \== CallModule,
        metta_tabling_visible_owner(Name, CompiledArity, Self, Module)
    ->  true
    ;   throw(error(existence_error(metta_function, Name/CompiledArity), none))
    ).

metta_tabling_visible_owner(Name, CompiledArity, CallModule, Module) :-
    current_predicate(CallModule:Name/CompiledArity),
    functor(Head, Name, CompiledArity),
    (   predicate_property(CallModule:Head, imported_from(From))
    ->  Module = From
    ;   Module = CallModule
    ).

%The same ownership decision drives execution. A ground-headed seam clause
%claims only a name with at least one live declaration, resolves the owner from
%the current call-site module at call time, and returns that exact qualified
%predicate. Late imports and two spaces defining the same name therefore keep
%their own tables.
%
%A table declared with (max-answers N) answers through metta_tabling_restrained/2
%instead, which is where the count restraint becomes a signal: SWI's
%per-predicate max_answers never calls the tripwire and adds an undefined answer
%to the table (bounded rationality), so the wrapper reads each answer's delay
%condition and raises the signal on the one that carries it.
metta_tabling_dispatch_call(Name, Args, Out, Goal) :-
    current_metta_module(CallModule),
    length(Args, InputArity),
    CompiledArity is InputArity + 1,
    metta_tabling_visible_owner(Name, CompiledArity, CallModule, Module),
    metta_tabling_registration(Name, Module, CompiledArity),
    functor(Head, Name, CompiledArity),
    predicate_property(Module:Head, tabled),
    append(Args, [Out], FullArgs),
    Direct =.. [Name|FullArgs],
    (   metta_tabling_policy_installed(Name, Module, CompiledArity, _, InForce, _, _),
        memberchk(['max-answers', Bound], InForce)
    ->  Goal = lib_tabling:metta_tabling_restrained(Module:Direct, Bound)
    ;   Goal = Module:Direct
    ).

metta_tabling_register(Name, Module, CompiledArity, Declared, InForce, Reads, Origin) :-
    (   metta_tabling_registration(Name, Module, CompiledArity)
    ->  true
    ;   assertz(metta_tabling_registration(Name, Module, CompiledArity))
    ),
    retractall(metta_tabling_policy_installed(Name, Module, CompiledArity, _, _, _, _)),
    assertz(metta_tabling_policy_installed(Name, Module, CompiledArity,
                                           Declared, InForce, Reads, Origin)),
    metta_tabling_install_dispatch_handler(Name).

%A (tabled ...) call on a table a row already installed makes it the
%caller's too: on row removal a table somebody asked for by call reverts to
%the default policy instead of leaving.
metta_tabling_note_origin(Name, Module, CompiledArity, Origin) :-
    (   Origin == call,
        retract(metta_tabling_policy_installed(Name, Module, CompiledArity,
                                               Declared, InForce, Reads, row))
    ->  assertz(metta_tabling_policy_installed(Name, Module, CompiledArity,
                                               Declared, InForce, Reads, call))
    ;   true
    ).

metta_tabling_install_dispatch_handler(Name) :-
    metta_tabling_dispatch_installed(Name),
    !.
metta_tabling_install_dispatch_handler(Name) :-
    assertz(seam:(dispatch_call(Name, Args, Out, Goal) :-
                      lib_tabling:metta_tabling_dispatch_call(Name, Args, Out,
                                                              Goal))),
    assertz(metta_tabling_dispatch_installed(Name)).

metta_tabling_unregister(Name, Module, CompiledArity) :-
    retractall(metta_tabling_registration(Name, Module, CompiledArity)),
    retractall(metta_tabling_policy_installed(Name, Module, CompiledArity, _, _, _, _)),
    metta_tabling_release_storage(Name, Module, CompiledArity),
    (   metta_tabling_registration(Name, _, _)
    ->  true
    ;   retractall(seam:(dispatch_call(Name, Args, Out, Goal) :-
                            lib_tabling:metta_tabling_dispatch_call(Name, Args,
                                                                    Out, Goal))),
        retractall(metta_tabling_dispatch_installed(Name))
    ).

%A table over a space also has to survive writes to that space, and SWI
%does that when both the table and the dynamic predicates it reads carry
%the incremental property [source: SWI-Prolog 10.1 Reference Manual 7.7].
%The predicates it reads are recoverable exactly: a match compiles to
%match(Space, Pattern, _, _) with a literal space identifier and list pattern.
%An atomic space uses its name as the storage functor; a parametric space uses
%the reserved functor in its canonical module. The walk follows the calls the
%body makes. Deriving them costs nothing per write,
%where a flag consulted on the write path measured two inferences of
%every five that add_sexp/3 spends [measured 2026-08-15].
%
%A read this cannot resolve is refused rather than tabled without the
%guarantee: a computed space or pattern, or a foreign space, whose atoms
%do not live in an SWI dynamic predicate at all.
%A DECLARATION MAY PRECEDE ITS DEFINITION. `!(tabled (fib $N))` written above
%`(= (fib $N) ...)` is the reading order upstream's own
%examples/tabling_fib.metta uses, and refusing it there refused a name the
%very next form defines. The declaration is HELD and installed when the
%function's clauses arrive, which is exactly what
%seam:function_clauses_changed/1 announces: "a handler that acts on the
%compiled predicate ... listens here instead, because at definition time there
%may be nothing to wrap and at materialisation time nothing else fires"
%[source: engine/ext_points.pl]. A name that is never defined never tables,
%and its held row is visible to the same (match &metta (tabled ...)) question
%the installed ones are [tested:
%examples/ch18-performance/18-02-memoisation-and-tabling/09-tabling_fib.metta].
%
%The handler clause is GROUND-HEADED and installed per held name, the shape
%lib_memo uses for seam:function_removed/1, because a resident handler costs
%four inferences on every compiled equation in the process
%[source: engine/ext_points.pl, measured 2026-08-15].
:- dynamic metta_tabling_held/1.

metta_tabled_decl(Call, true) :-
    \+ metta_tabling_resolvable(Call),
    !,
    metta_tabling_hold(Call).
metta_tabled_decl(Call, true) :-
    metta_tabling_target(Call, Module, Name, CompiledArity),
    metta_tabling_policy_for(Name, Declared),
    metta_tabling_guarded(
        metta_tabling_declare_checked(Module, Name, CompiledArity, Declared, call)).

%The policy a table of Name is built under: the standing (cache Name ...)
%row's members when they are a tabling policy, else the default.
metta_tabling_policy_for(Name, Declared) :-
    (   metta_tabling_declared_policy(Name, Members)
    ->  Declared = Members
    ;   Declared = default
    ).

metta_tabling_resolvable(Call) :-
    catch(metta_tabling_target(Call, _, _, _),
          error(existence_error(metta_function, _), _),
          fail).

metta_tabling_hold(Call) :-
    metta_tabling_call_name(Call, Name),
    (   metta_tabling_held(Call)
    ->  true
    ;   assertz(metta_tabling_held(Call)),
        assertz(seam:(function_clauses_changed(Name) :-
                          lib_tabling:metta_tabling_release(Name)))
    ).

metta_tabling_call_name(Call0, Name) :-
    ( Call0 = [quote, Call] -> true ; Call = Call0 ),
    ( is_list(Call), Call = [Name|_], atom(Name)
      -> true
    ; throw(error(type_error(metta_function_call, Call0), none)) ).

%Every held declaration for this name, tried once its clauses exist. A
%declaration that still cannot resolve stays held: a function may be defined
%at one arity and declared at another, and the later definition is what
%decides.
metta_tabling_release(Name) :-
    forall(( metta_tabling_held(Call),
             metta_tabling_call_name(Call, Name) ),
           (   metta_tabling_resolvable(Call)
           ->  retract(metta_tabling_held(Call)),
               retractall(seam:(function_clauses_changed(Name) :-
                                    lib_tabling:metta_tabling_release(Name))),
               metta_tabled_decl(Call, _)
           ;   true
           )).

%One table, brought to the declared policy. Three shapes: it already stands
%under this policy and only the origin note may move; it stands under another
%policy and is rebuilt, with the old one put back if the new one is refused,
%so a refusal never leaves a function untabled that was tabled; or it is new,
%and a refusal takes the fresh table back out.
metta_tabling_declare_checked(Module, Name, CompiledArity, Declared, Origin) :-
    (   metta_tabling_policy_installed(Name, Module, CompiledArity, Declared, _, _, _)
    ->  metta_tabling_note_origin(Name, Module, CompiledArity, Origin)
    ;   metta_tabling_policy_installed(Name, Module, CompiledArity,
                                       Previous, _, _, PreviousOrigin)
    ->  metta_tabling_uninstall(Name, Module, CompiledArity),
        catch(metta_tabling_declare(Module, Name, CompiledArity, Declared, Origin),
              Error,
              ( metta_tabling_declare(Module, Name, CompiledArity,
                                      Previous, PreviousOrigin),
                throw(Error) )),
        metta_tabling_note_origin(Name, Module, CompiledArity, PreviousOrigin)
    ;   functor(Head, Name, CompiledArity),
        ( predicate_property(Module:Head, tabled) -> WasTabled = true
                                                   ; WasTabled = false ),
        catch(metta_tabling_declare(Module, Name, CompiledArity, Declared, Origin),
              Error,
              ( metta_tabling_unregister(Name, Module, CompiledArity),
                metta_tabling_rollback_new_table(WasTabled, Module, Name,
                                                 CompiledArity),
                throw(Error) ))
    ).

%Registration precedes the reflection write on purpose: the &metta write
%fires seam:cache_policy_changed/1 for the (tabled ...) row, and the reconcile
%that answers it must find the table it is being told about.
metta_tabling_declare(Module, Name, CompiledArity, Declared, Origin) :-
    metta_tabling_install(Module, Name, CompiledArity, Declared, InForce, Reads),
    metta_tabling_register(Name, Module, CompiledArity, Declared, InForce, Reads,
                           Origin),
    metta_tabling_reflect(Module, Name, CompiledArity, Fact),
    metta_tabling_reflection_ensure(Fact).

%Take a table out without touching its catalog row: the row is the caller's
%business (untabled removes it, a rebuild keeps it).
metta_tabling_uninstall(Name, Module, CompiledArity) :-
    metta_tabling_unregister(Name, Module, CompiledArity),
    catch(untable(Module:Name/CompiledArity), _, true).

metta_tabling_rollback_new_table(true, _, _, _) :- !.
metta_tabling_rollback_new_table(false, Module, Name, CompiledArity) :-
    catch(untable(Module:Name/CompiledArity), _, true).

%untabled contradicts a standing (cache Name ...) row, which would put the
%table straight back the next time the name's clauses move; the row is the
%declaration, so removing it is the door.
metta_untabled_decl(Call, true) :-
    metta_tabling_target(Call, Module, Name, CompiledArity),
    (   metta_tabling_declared_policy(Name, _),
        'get-atoms'('&metta', [cache, Name, Raw])
    ->  throw(error(metta_tabling_row_governs(Name, Raw), none))
    ;   true
    ),
    untable(Module:Name/CompiledArity),
    functor(Head, Name, CompiledArity),
    ( predicate_property(Module:Head, tabled)
      -> throw(error(metta_untabling_failed(Module:Name/CompiledArity), none))
    ; true ),
    metta_tabling_reflect(Module, Name, CompiledArity, Fact),
    catch(metta_tabling_reflection_write(remove, Fact),
          Error,
          ( metta_tabling_policy_for(Name, Declared),
            metta_tabling_install(Module, Name, CompiledArity, Declared, _, _),
            throw(Error) )),
    metta_tabling_unregister(Name, Module, CompiledArity).

prolog:error_message(metta_tabling_row_governs(Name, Raw)) -->
    { sdisplay([cache, Name, Raw], Text) },
    [ 'untabling ~w contradicts the standing declaration ~w, which would \c
       table it again the next time its clauses move. Remove the row to \c
       untable it: !(remove-atom &metta ~w)'-[Name, Text, Text] ].

%%%% Policies: the (cache Name Policy) row compiled to table/1's options %%%%
%
%A policy row's members arrive from the catalog's own parser
%(metta_policy_members/3, engine/spaces/catalog.pl), a bare word or
%[Word, Argument], and compile through ONE table: each word's class, and the
%SWI spelling it becomes. The classes are the slots of a table declaration:
%
%  watch      what a write to a read space does to the table: nothing (plain),
%             invalidate and re-evaluate (incremental), propagate the new
%             consequences (monotonic)
%  thread     shared between engines or private to the one that fills it
%  variant    one table per call variant, or subsumptive
%  lazy       queue a monotonic table's propagation until its next use
%  moded      an answer-subsumption mode in the output position, lattice(Join)
%  restraint  a bound on the table, SWI's three, each with an integer
%
%One word per slot except the restraints, which stack. The consequences the
%engine forces are refused at compile time with the measurement that forced
%them, so a refusal never depends on the body; what the body decides (the
%default watch, the reads a watch needs) is resolved at install.
%
%The table is the reusable half: a later carrier that tables a provenance
%polynomial in the answer position adds one `moded` row here and one
%vocabulary member, and metta_tabling_moded_head/4 below builds its head.
metta_tabling_policy_word(plain,              watch,     plain).
metta_tabling_policy_word(incremental,        watch,     incremental).
metta_tabling_policy_word(monotonic,          watch,     monotonic).
metta_tabling_policy_word(lazy,               lazy,      lazy).
metta_tabling_policy_word(shared,             thread,    shared).
metta_tabling_policy_word(private,            thread,    private).
metta_tabling_policy_word(subsumptive,        variant,   subsumptive).
metta_tabling_policy_word(lattice,            moded,     lattice).
metta_tabling_policy_word('max-answers',      restraint, max_answers).
metta_tabling_policy_word('subgoal-abstract', restraint, subgoal_abstract).
metta_tabling_policy_word('answer-abstract',  restraint, answer_abstract).

%The watch words that make SWI TRACK a table's dependencies, derived from the
%table above rather than listed again: `plain` is the third watch word and the
%one that tracks nothing, so it takes no `as` option and conflicts with
%nothing. A fourth watch word cannot be added without deciding this, which is
%what a second closed list of the same two names would have let happen.
metta_tabling_watched(Watch) :-
    metta_tabling_policy_word(Watch, watch, _),
    Watch \== plain.

%SWI's tripwire names for the two size restraints, and the count restraint's
%name under the process-wide flag; the per-predicate count restraint is caught
%on its answer instead (metta_tabling_restrained/2).
metta_tabling_wire(max_table_subgoal_size, 'subgoal-abstract').
metta_tabling_wire(max_table_answer_size,  'answer-abstract').
metta_tabling_wire(max_answers_for_subgoal, 'max-answers').

%policy(Watch, Thread, Variant, Lazy, Moded, Restraints): Watch is `none`
%until install resolves the default, Thread `none` until compile picks the
%default, Restraints a list of Word-Bound in declared order.
metta_tabling_compile(_, default, policy(none, shared, variant, false, none, [])) :-
    !.
metta_tabling_compile(Name, Members, Policy) :-
    foldl(metta_tabling_policy_slot(Name), Members,
          policy(none, none, variant, false, none, []), Slots),
    Slots = policy(Watch, Thread0, Variant, Lazy, Moded, Restraints0),
    reverse(Restraints0, Restraints),
    (   Lazy == true, Watch \== monotonic
    ->  metta_tabling_refuse(Name, needs(lazy, monotonic))
    ;   true
    ),
    (   Moded \== none, metta_tabling_watched(Watch)
    ->  metta_tabling_refuse(Name, cannot_watch(lattice, Watch))
    ;   true
    ),
    (   Variant == subsumptive, metta_tabling_watched(Watch)
    ->  metta_tabling_refuse(Name, cannot_watch(subsumptive, Watch))
    ;   true
    ),
    (   Moded \== none, Thread0 == shared
    ->  metta_tabling_refuse(Name, moded_shared)
    ;   true
    ),
    (   Thread0 == none
    ->  ( Moded == none -> Thread = shared ; Thread = private )
    ;   Thread = Thread0
    ),
    Policy = policy(Watch, Thread, Variant, Lazy, Moded, Restraints).

metta_tabling_policy_slot(Name, Member, Policy0, Policy) :-
    ( Member = [Word|Args] -> true ; Word = Member, Args = [] ),
    (   metta_tabling_policy_word(Word, Class, _)
    ->  true
    ;   metta_tabling_refuse(Name, not_a_tabling_word(Word))
    ),
    metta_tabling_policy_place(Class, Word, Args, Name, Policy0, Policy).

metta_tabling_policy_place(watch, Word, [], _,
                           policy(none, T, V, L, M, R), policy(Word, T, V, L, M, R)) :- !.
metta_tabling_policy_place(watch, Word, [], Name, policy(W0, _, _, _, _, _), _) :-
    metta_tabling_refuse(Name, two_of(W0, Word)).
metta_tabling_policy_place(thread, Word, [], _,
                           policy(W, none, V, L, M, R), policy(W, Word, V, L, M, R)) :- !.
metta_tabling_policy_place(thread, Word, [], Name, policy(_, T0, _, _, _, _), _) :-
    metta_tabling_refuse(Name, two_of(T0, Word)).
metta_tabling_policy_place(variant, subsumptive, [], _,
                           policy(W, T, _, L, M, R), policy(W, T, subsumptive, L, M, R)).
metta_tabling_policy_place(lazy, lazy, [], _,
                           policy(W, T, V, _, M, R), policy(W, T, V, true, M, R)).
metta_tabling_policy_place(moded, lattice, [Join], _,
                           policy(W, T, V, L, none, R),
                           policy(W, T, V, L, lattice(Join), R)) :- !.
metta_tabling_policy_place(moded, lattice, [Join], Name,
                           policy(_, _, _, _, lattice(J0), _), _) :-
    metta_tabling_refuse(Name, two_of([lattice, J0], [lattice, Join])).
metta_tabling_policy_place(restraint, Word, [Bound], Name,
                           policy(W, T, V, L, M, R), policy(W, T, V, L, M, [Word-Bound|R])) :-
    (   integer(Bound), Bound >= 0
    ->  true
    ;   metta_tabling_refuse(Name, restraint_bound(Word, Bound))
    ),
    (   memberchk(Word-Bound0, R)
    ->  metta_tabling_refuse(Name, two_of([Word, Bound0], [Word, Bound]))
    ;   true
    ).

metta_tabling_refuse(Name, Reason) :-
    throw(error(metta_tabling_policy_refused(Name, Reason), none)).

%The watch the body admits. An explicit plain skips the walk: the developer
%said watch nothing, and a foreign or computed read is then no obstacle. An
%explicit incremental or monotonic needs every read resolved, so a body the
%walk cannot classify is refused rather than tabled plain under a word that
%promised a watch. The default is the strongest table the body admits, which
%for a variant table is incremental over the reads and plain when the walk
%gives up, as it was before policies existed; a lattice or subsumptive table
%cannot carry a watch on this SWI, so its default is plain, and when the body
%reads a space the program has to write plain, because a table that goes
%stale after a write is the failure the 2026-08-16 measurements found and
%should never be a default's doing.
metta_tabling_resolve_watch(_, _, _, policy(plain, T, V, L, M, R),
                            policy(plain, T, V, L, M, R), []) :-
    !.
metta_tabling_resolve_watch(Module, Name, CompiledArity,
                            policy(Watch0, T, V, L, M, R),
                            policy(Watch, T, V, L, M, R), Reads) :-
    metta_tabling_incremental_reads(Module, Name, CompiledArity, Outcome),
    (   Outcome = reads(Found)
    ->  (   Watch0 == none
        ->  (   metta_tabling_unwatchable(V, M, Kind)
            ->  (   Found == []
                ->  Watch = plain, Reads = []
                ;   metta_tabling_refuse(Name, reads_unwatched(Kind, Found))
                )
            ;   Watch = incremental, Reads = Found
            )
        ;   Watch = Watch0, Reads = Found
        )
    ;   Outcome = unclassified(Formal),
        (   Watch0 == none
        ->  Watch = plain, Reads = []
        ;   metta_tabling_refuse(Name, unclassified(Formal, Watch0))
        )
    ).

metta_tabling_unwatchable(subsumptive, _, subsumptive) :- !.
metta_tabling_unwatchable(_, lattice(_), lattice).

%A watched table over storage another table watches the other way: refused
%before anything is declared, so a refusal changes nothing.
metta_tabling_storage_conflict(Watch, Reads, Name, Module, CompiledArity) :-
    Watch \== plain,
    member(Storage:Predicate, Reads),
    metta_tabling_storage_watch(Storage:Predicate, Other, reader(N, M, A)),
    Other \== Watch,
    \+ ( N == Name, M == Module, A == CompiledArity ),
    !,
    metta_tabling_refuse(Name, storage_watched(Storage:Predicate, Other, N/A)).
metta_tabling_storage_conflict(_, _, _, _, _).

metta_tabling_watch_storage(plain, _, _, _, _) :- !.
metta_tabling_watch_storage(Watch, Storage:Predicate, Name, Module, CompiledArity) :-
    (   metta_tabling_storage_watch(Storage:Predicate, Watch,
                                    reader(Name, Module, CompiledArity))
    ->  true
    ;   metta_tabling_storage_declare(Storage:Predicate, Watch),
        assertz(metta_tabling_storage_watch(Storage:Predicate, Watch,
                                            reader(Name, Module, CompiledArity)))
    ).

metta_tabling_storage_declare(Storage:Predicate, incremental) :-
    dynamic(Storage:Predicate as incremental).
metta_tabling_storage_declare(Storage:Predicate, monotonic) :-
    dynamic(Storage:Predicate as monotonic).

%The last reader under a watch takes the property with it. incremental has
%the documented door; monotonic's dynamic/2 option monotonic(false) is
%accepted and leaves the property standing on 10.1.13 [measured 2026-09-07,
%probe18 in the journal thread], so it goes through the attribute untable/1
%itself clears and the wrapper refresh dynamic/1 runs
%[source: /usr/lib/swi-prolog/boot/tabling.pl, untable/2 and
%'$set_table_wrappers'/1]. A predicate that left with its space is no error.
metta_tabling_release_storage(Name, Module, CompiledArity) :-
    forall(retract(metta_tabling_storage_watch(Storage:Predicate, Watch,
                                               reader(Name, Module, CompiledArity))),
           (   metta_tabling_storage_watch(Storage:Predicate, Watch, _)
           ->  true
           ;   metta_tabling_storage_undeclare(Storage:Predicate, Watch)
           )).

metta_tabling_storage_undeclare(Storage:Predicate, incremental) :-
    catch(dynamic([Storage:Predicate], [incremental(false)]), _, true).
metta_tabling_storage_undeclare(Storage:Functor/Arity, monotonic) :-
    functor(Head, Functor, Arity),
    catch(( '$set_predicate_attribute'(Storage:Head, monotonic, false),
            '$set_table_wrappers'(Storage:Head) ),
          _, true).

%What table/1 is asked to table: the predicate indicator, or for a lattice
%policy the head with the join in the answer position, which is the output
%argument the translator appends. The join is a MeTTa function of two inputs,
%(= (join $old $new) ...), compiled to Join/3 in the space's module; SWI
%calls Module:Join(Old, New, Aggregate) on every new answer and keeps
%Aggregate [source: SWI-Prolog 10.1 Reference Manual 7.3, lattice(PI)]. That
%is one aggregated answer per input variant, which is the developer's word
%when they write the policy. Same shape as lib_memo's sum coefficient, which
%is the counting case of a lattice.
metta_tabling_table_spec(Module, Name, CompiledArity, Moded, Spec) :-
    (   Moded = lattice(Join)
    ->  metta_tabling_join_visible(Module, Name, Join),
        metta_tabling_moded_head(Name, CompiledArity, lattice(Module:Join/3), Spec)
    ;   Spec = Name/CompiledArity
    ).

metta_tabling_join_visible(Module, Name, Join) :-
    metta_ensure_compiled(Join),
    (   current_predicate(Module:Join/3)
    ->  true
    ;   metta_tabling_refuse(Name, join_missing(Join, Module))
    ).

%A moded head: every input argument tabled as a variant, the output argument
%carrying the mode term. Reusable for any mode SWI knows (lattice, po, min,
%max, sum, first, last), which is what a later carrier's compile row hands it.
metta_tabling_moded_head(Name, CompiledArity, Mode, ModeHead) :-
    functor(ModeHead, Name, CompiledArity),
    arg(CompiledArity, ModeHead, Mode).

%The `as` list, in the order table/1 documents them. The thread word is
%always written, so a default never depends on SWI's table_shared flag.
metta_tabling_as_options(policy(Watch, Thread, Variant, Lazy, _, Restraints), Options) :-
    findall(Option,
            (   metta_tabling_watched(Watch), Option = Watch
            ;   Lazy == true, Option = lazy
            ;   Variant == subsumptive, Option = subsumptive
            ;   Option = Thread
            ;   member(Word-Bound, Restraints),
                metta_tabling_policy_word(Word, restraint, Swi),
                Option =.. [Swi, Bound]
            ),
            Options).

metta_tabling_comma_term([Option], Option) :- !.
metta_tabling_comma_term([Option|Rest], (Option, Term)) :-
    metta_tabling_comma_term(Rest, Term).

%Build the table the policy names, then read it back. Every property the
%policy asked for is checked through predicate_property/2 where SWI reports
%it and through the predicate attribute where it does not: lazy and the three
%restraint bounds are attributes table/1 sets and predicate_property/2 leaves
%out [source: /usr/lib/swi-prolog/boot/syspred.pl, '$predicate_property'/2
%for tabled(Flag); boot/tabling.pl, set_pattributes/2].
metta_tabling_install(Module, Name, CompiledArity, Declared, InForce, Reads) :-
    metta_tabling_compile(Name, Declared, Policy0),
    metta_tabling_resolve_watch(Module, Name, CompiledArity, Policy0, Policy, Reads),
    Policy = policy(Watch, _, _, _, Moded, _),
    metta_tabling_storage_conflict(Watch, Reads, Name, Module, CompiledArity),
    metta_tabling_table_spec(Module, Name, CompiledArity, Moded, Spec),
    metta_tabling_as_options(Policy, Options),
    forall(member(Read, Reads),
           metta_tabling_watch_storage(Watch, Read, Name, Module, CompiledArity)),
    metta_tabling_comma_term(Options, As),
    table(Module:Spec as As),
    functor(Head, Name, CompiledArity),
    metta_tabling_verify(Module:Head, Name/CompiledArity, Policy),
    metta_tabling_in_force(Policy, InForce).

metta_tabling_verify(Head, Indicator, policy(Watch, Thread, Variant, Lazy, _, Restraints)) :-
    (   predicate_property(Head, tabled),
        metta_tabling_property_holds(Thread, Head),
        metta_tabling_property_holds(Watch, Head),
        metta_tabling_property_holds(Variant, Head),
        (   Lazy == true
        ->  '$get_predicate_attribute'(Head, lazy, 1)
        ;   true
        ),
        forall(member(Word-Bound, Restraints),
               ( metta_tabling_policy_word(Word, restraint, Attribute),
                 '$get_predicate_attribute'(Head, Attribute, Bound) ))
    ->  true
    ;   throw(error(metta_tabling_failed(Indicator), none))
    ).

metta_tabling_property_holds(shared, Head)      :- predicate_property(Head, tabled(shared)).
metta_tabling_property_holds(private, Head)     :- \+ predicate_property(Head, tabled(shared)).
metta_tabling_property_holds(incremental, Head) :- predicate_property(Head, tabled(incremental)).
metta_tabling_property_holds(monotonic, Head)   :- predicate_property(Head, tabled(monotonic)).
metta_tabling_property_holds(plain, Head)       :- \+ predicate_property(Head, tabled(incremental)),
                                                   \+ predicate_property(Head, tabled(monotonic)).
metta_tabling_property_holds(variant, Head)     :- predicate_property(Head, tabled(variant)).
metta_tabling_property_holds(subsumptive, Head) :- predicate_property(Head, tabled(subsumptive)).

%The policy in force, as the MeTTa words a program can match: watch and
%thread first, then whatever else the table carries, in the vocabulary's
%order.
metta_tabling_in_force(policy(Watch, Thread, Variant, Lazy, Moded, Restraints),
                       [Watch, Thread|Rest]) :-
    findall(Word,
            (   Variant == subsumptive, Word = subsumptive
            ;   Lazy == true, Word = lazy
            ;   Moded = lattice(Join), Word = [lattice, Join]
            ;   member(Name-Bound, Restraints), Word = [Name, Bound]
            ),
            Rest).

%The tabling policy a standing (cache Name ...) row declares, if it declares
%one: the catalog admitted the row, so its members parse, and a row whose one
%member is lib_memo's force or refuse is not this library's business.
metta_tabling_declared_policy(Name, Members) :-
    'get-atoms'('&metta', [cache, Name, Raw]),
    metta_policy_members('cache-policy', Raw, Members),
    \+ ( member(Member, Members), metta_tabling_memo_word(Member) ),
    !.

metta_tabling_memo_word(force).
metta_tabling_memo_word(refuse).

prolog:error_message(metta_tabling_policy_refused(Name, Reason)) -->
    [ 'the cache policy declared for ~w cannot be built: '-[Name] ],
    metta_tabling_refusal(Name, Reason).

metta_tabling_refusal(_, two_of(A, B)) -->
    { sdisplay(A, TextA), sdisplay(B, TextB) },
    [ '~w and ~w are both written and a table takes one of them; keep one'-[TextA, TextB] ].
metta_tabling_refusal(Name, needs(lazy, monotonic)) -->
    [ 'lazy queues a monotonic table\'s propagation until its next use, so \c
       it needs monotonic beside it; write (cache ~w (monotonic lazy))'-[Name] ].
metta_tabling_refusal(Name, cannot_watch(Kind, Watch)) -->
    [ 'a ~w table cannot be ~w on SWI-Prolog 10.1.13, where re-evaluating \c
       one after a write answers a wrong table or raises existence_error(reset, ...) \c
       [measured 2026-09-07]; write plain, as (cache ~w (plain ...)), and \c
       clear the table with (table-clear (~w ...)) after a write'-[Kind, Watch, Name, Name] ].
metta_tabling_refusal(Name, moded_shared) -->
    [ 'a shared lattice table fails on its second call on SWI-Prolog 10.1.13 \c
       (type_error(trie, ...) from trie_gen/2 [measured 2026-09-07]); write \c
       private, or leave the thread word out of (cache ~w ...) and private is \c
       chosen'-[Name] ].
metta_tabling_refusal(Name, reads_unwatched(Kind, Reads)) -->
    { metta_tabling_reads_text(Reads, Text) },
    [ 'its body reads ~w and a ~w table cannot watch a read on SWI-Prolog \c
       10.1.13; write plain, as (cache ~w (plain ...)), to say the table is \c
       cleared by hand with (table-clear (~w ...)) after a write to that \c
       space'-[Text, Kind, Name, Name] ].
metta_tabling_refusal(Name, unclassified(metta_impure_goal(Goal), Watch)) -->
    [ 'its body calls ~w, which the effect walk cannot classify, so there \c
       is no read to hang the ~w property on; write (cache ~w plain) to table \c
       it without watching its reads, or make the body pure'-[Goal, Watch, Name] ].
metta_tabling_refusal(Name, unclassified(metta_higher_order_goal(Goal), Watch)) -->
    [ 'its body calls ~w through a value rather than a name, which the effect \c
       walk cannot follow, so there is no read to hang the ~w property on; \c
       write (cache ~w plain) to table it without watching its reads'-[Goal, Watch, Name] ].
metta_tabling_refusal(Name, storage_watched(Storage:Predicate, Other, Reader/Arity)) -->
    { InputArity is Arity - 1,
      metta_tabling_reads_text([Storage:Predicate], Space) },
    [ 'it reads ~w, which ~w (~w inputs) already watches ~w, and one space \c
       predicate carries one watch: carrying both re-evaluates the monotonic \c
       reader on every write, 4,776 inferences against 415 [measured \c
       2026-09-07]. Declare (cache ~w ~w), or (cache ~w plain), or untable ~w \c
       first'-[Space, Reader, InputArity, Other, Name, Other, Name, Reader] ].
metta_tabling_refusal(_, restraint_bound(Word, Bound)) -->
    [ '(~w ~w) needs a non-negative integer bound'-[Word, Bound] ].
metta_tabling_refusal(_, join_missing(Join, Module)) -->
    { ( metta_module_space(Module, Space) -> true ; Space = Module ) },
    [ '(lattice ~w) names ~w, which is not a function of two inputs visible \c
       from ~w; define (= (~w $old $new) ...) there before the policy'-[Join, Join, Space, Join] ].
metta_tabling_refusal(_, not_a_tabling_word(Word)) -->
    [ '~w is not a tabling policy word; the cache-policy vocabulary row in \c
       &metta lists the words this library compiles'-[Word] ].

metta_tabling_reads_text(Reads, Text) :-
    findall(Space,
            ( member(Storage:_, Reads),
              ( native_storage_module_cache(Space, Storage) -> true
              ; Space = Storage ) ),
            Spaces0),
    sort(Spaces0, Spaces),
    sdisplay(Spaces, Text).

%The engine walk raises two balls when it cannot classify a body, and lib
%tabling's own read resolution raises two more. Only the first pair is a
%judgement about the developer's body; the second pair says this library cannot
%build what it promised, so those keep raising
%[tested: tabling_refuses_unresolvable_reads].
metta_tabling_incremental_reads(Module, Name, CompiledArity, Outcome) :-
    catch(( metta_tabling_reads(Module, Name, CompiledArity, Reads),
            Outcome = reads(Reads) ),
          Error,
          (   metta_tabling_unclassified_body(Error, Formal)
          ->  Outcome = unclassified(Formal)
          ;   throw(Error)
          )).

metta_tabling_unclassified_body(error(metta_impure_goal(Goal), _),
                                metta_impure_goal(Goal)).
metta_tabling_unclassified_body(error(metta_higher_order_goal(Goal), _),
                                metta_higher_order_goal(Goal)).

%Every space storage predicate this function can read, following the calls
%its clauses make. The walk carries a seen-set over predicate indicators
%and collects as it goes: what is wanted is the reads gathered along the
%way, not the set of reachable predicates.
metta_tabling_reads(Module, Name, CompiledArity, Reads) :-
    metta_effect_walk(Module, [Name/CompiledArity], Found),
    foldl(metta_tabling_resolve, Found, [], Raw),
    sort(Raw, Reads).

%The walk is the ENGINE's, metta_effect_walk/3. What stays here is what tabling
%does with the reads it reports, which is the half that is genuinely tabling's:
%resolve each to the storage predicates that answer it, so the table can carry
%the incremental property against them. A read that will not resolve is refused
%by metta_tabling_read/4 below, and that refusal is this library saying it
%cannot build the table it promises, not a judgement about the body
%[source: engine/metta.pl, metta_effect_walk/3].
metta_tabling_resolve(read(Operation, Space, Pattern), Reads0, Reads) :-
    metta_tabling_read(Operation, Space, Pattern, Found),
    append(Found, Reads0, Reads).

%One space read, resolved to the dynamic predicates that answer it: one
%per conjunct, since a conjunction reads each of its patterns.
metta_tabling_read(Operation, Space, Pattern, Reads) :-
    ( metta_space_name(Space) -> true
    ; throw(error(metta_tabling_unresolved_read(Operation, Space), none)) ),
    ( seam:foreign_space(Space)
      -> throw(error(metta_tabling_foreign_space(Operation, Space), none))
    ; true ),
    native_storage_module(Space, Storage),
    native_storage_functor(Space, Functor),
    metta_tabling_patterns(Operation, Pattern, Shapes),
    findall(Storage:Functor/Arity,
            ( member(Shape, Shapes),
              length(Shape, Count),
              Arity is Count + 1 ),
            Reads).

%The argument lists a pattern reads. A conjunction contributes one per
%conjunct; anything whose shape is not fixed cannot be resolved.
metta_tabling_patterns(Operation, Pattern, _) :-
    \+ is_list(Pattern), !,
    throw(error(metta_tabling_unresolved_read(Operation, Pattern), none)).
metta_tabling_patterns(Operation, [Comma|Conjuncts], Shapes) :-
    nonvar(Comma), Comma == ',', !,
    foldl(metta_tabling_conjunct(Operation), Conjuncts, [], Shapes).
metta_tabling_patterns(Operation, [Head|Arguments], [Arguments]) :-
    ( nonvar(Head) -> true
    ; throw(error(metta_tabling_unresolved_read(Operation, [Head|Arguments]), none)) ).

metta_tabling_conjunct(Operation, Conjunct, Shapes0, Shapes) :-
    metta_tabling_patterns(Operation, Conjunct, Found),
    append(Found, Shapes0, Shapes).

prolog:error_message(metta_tabling_unresolved_read(Operation, Culprit)) -->
    { sdisplay(Culprit, Text) },
    [ 'a tabled function reads ~w with ~w, which cannot be resolved to one \c
       space predicate, so writes to it could not invalidate the table. \c
       Name the space and the pattern shape, declare the function\'s cache \c
       policy plain to table it without watching its reads, or do not table \c
       it.'-[Operation, Text] ].
prolog:error_message(metta_tabling_foreign_space(Operation, Space)) -->
    [ 'a tabled function reads the foreign space ~w with ~w. Its atoms do \c
       not live in this engine, so a write there cannot invalidate or \c
       propagate into the table. Declare the function\'s cache policy plain \c
       to table it without watching that space, or read a native \c
       space.'-[Space, Operation] ].

%The live-declaration record in &metta: the space whose module holds the
%predicate, the function name, and its INPUT arity, the arity a MeTTa caller
%sees. A standing exact record is the idempotent case, so repetition never
%writes or duplicates it.
metta_tabling_reflect(Module, Name, CompiledArity, [tabled, Space, Name, InputArity]) :-
    metta_module_space(Module, Space),
    InputArity is CompiledArity - 1.

%A reflection fact already standing is the idempotent case and needs no write.
%Every actual write must answer `true`, the answer this engine's effectful
%operations give (engine/metta/runtime.pl's note above 'println!'/2 carries the
%family). Failure, an error answer, or an exception is rethrown under one named
%tabling error so a caller cannot receive True from a declaration whose catalog
%state did not land.
metta_tabling_reflection_ensure(Fact) :-
    (   once('get-atoms'('&metta', Fact))
    ->  true
    ;   metta_tabling_reflection_write(add, Fact)
    ).

metta_tabling_reflection_write(Operation, Fact) :-
    catch((   metta_tabling_reflection_goal(Operation, Fact, Result)
          ->  Outcome = result(Result)
          ;   Outcome = failed
          ),
          Error,
          Outcome = exception(Error)),
    (   Outcome == result(true)
    ->  true
    ;   throw(error(metta_tabling_reflection_write_failed(Operation, Fact,
                                                          Outcome), none))
    ).

metta_tabling_reflection_goal(add, Fact, Result) :-
    'add-atom'('&metta', Fact, Result).
metta_tabling_reflection_goal(remove, Fact, Result) :-
    'remove-atom'('&metta', Fact, Result).

prolog:error_message(metta_tabling_reflection_write_failed(Operation, Fact,
                                                            Outcome)) -->
    { sdisplay(Fact, Text) },
    [ 'tabling could not ~w its reflection row ~w: the &metta write answered \c
       ~w. The table declaration and its catalog row must change together.'-
      [Operation, Text, Outcome] ].

%The engine's ordinary atom-removed event also covers pooled-space cleanup,
%which removes every (tabled Space ...) row after untabling its predicates. It
%therefore retires the indexed dispatch handler without a tabling-specific
%lifecycle callback or an engine edit.
:- multifile seam:atom_removed/2.
seam:atom_removed('&metta', Fact) :-
    (   Fact = [tabled, Space, Name, InputArity],
        atom(Name),
        integer(InputArity),
        space_module(Space, Module)
    ->  CompiledArity is InputArity + 1,
        metta_tabling_unregister(Name, Module, CompiledArity)
    ;   true
    ).

%%%% The row as the declaration %%%%
%
%A (cache Name Policy) row lands or leaves and the engine says so through
%seam:cache_policy_changed/1, the event lib_memo's automatic memo already
%answers. The same event fires for this library's own (tabled ...) reflection
%rows, so the answer is a RECONCILE rather than an action: bring every table of
%the name to the policy the standing row declares, install the row's tables
%where the name's clauses are visible, and take the row's own tables out when
%it leaves. Consistent state is a no-op, which is what makes the reflection
%rows' events harmless.
%
%While a tabling row stands, a ground-headed function_clauses_changed/1 handler
%stands with it, so a name defined after its row, or defined again in a new
%space after its old one was dropped, is tabled when the clauses arrive; the
%handler is the same shape the held (tabled ...) calls use and costs the
%process nothing for other names. A row this library cannot honour is removed
%before the refusal is raised, so the catalog never carries a declaration
%that is not in force.
%
%The bulk removal event carries no name, and reconciles every name a row,
%a table or a hold mentions.
:- multifile seam:cache_policy_changed/1.
seam:cache_policy_changed(Name) :-
    lib_tabling:metta_tabling_policy_changed(Name).

:- thread_local metta_tabling_reconciling/0.
:- dynamic metta_tabling_row_held/1.

%once/1, because the flag lives exactly as long as the goal: a choice point
%left inside would postpone the cleanup and leave every later policy event
%silently ignored, which is how the first version of this lost a row written
%after a (tabled ...) call.
metta_tabling_guarded(Goal) :-
    (   metta_tabling_reconciling
    ->  once(Goal)
    ;   setup_call_cleanup(asserta(metta_tabling_reconciling, Ref),
                           once(Goal),
                           erase(Ref))
    ).

metta_tabling_policy_changed(_) :-
    metta_tabling_reconciling,
    !.
metta_tabling_policy_changed(Name) :-
    var(Name),
    !,
    findall(Subject, metta_tabling_policy_subject(Subject), Subjects0),
    sort(Subjects0, Subjects),
    forall(member(Subject, Subjects), metta_tabling_policy_changed(Subject)).
metta_tabling_policy_changed(Name) :-
    metta_tabling_guarded(metta_tabling_reconcile(Name)).

metta_tabling_policy_subject(Name) :-
    'get-atoms'('&metta', [cache, Name, _]),
    atom(Name).
metta_tabling_policy_subject(Name) :-
    metta_tabling_policy_installed(Name, _, _, _, _, _, _).
metta_tabling_policy_subject(Name) :-
    metta_tabling_row_held(Name).

metta_tabling_reconcile(Name) :-
    (   metta_tabling_declared_policy(Name, Members)
    ->  metta_tabling_row_hold(Name),
        catch(metta_tabling_apply_row(Name, Members),
              Error,
              ( metta_tabling_row_release(Name),
                metta_tabling_withdraw_row(Name),
                'remove-atom'('&metta', [cache, Name, _], _),
                throw(Error) ))
    ;   metta_tabling_row_release(Name),
        metta_tabling_withdraw_row(Name)
    ).

%Tables already standing move to the row's policy; every compiled arity the
%speaking module can see and no table covers is installed as the row's own.
metta_tabling_apply_row(Name, Members) :-
    forall(( metta_tabling_policy_installed(Name, Module, CompiledArity,
                                            Declared, _, _, Origin),
             Declared \== Members ),
           metta_tabling_declare_checked(Module, Name, CompiledArity, Members,
                                         Origin)),
    metta_tabling_row_targets(Name, Targets),
    forall(( member(Module-CompiledArity, Targets),
             \+ metta_tabling_policy_installed(Name, Module, CompiledArity,
                                               _, _, _, _) ),
           metta_tabling_declare_checked(Module, Name, CompiledArity, Members,
                                         row)).

%The arities the ENGINE recorded for the name (arity/2 is written when a
%function is defined or an operation registered) that the speaking module or
%&self can see. The record is the filter that keeps a Prolog predicate the
%module happens to import, member/2 for a function named member, from being
%read as an arity of the MeTTa name.
metta_tabling_row_targets(Name, Targets) :-
    metta_ensure_compiled(Name),
    current_metta_module(CallModule),
    metta_self_module(Self),
    findall(Module-CompiledArity,
            ( arity(Name, CompiledArity),
              member(From, [CallModule, Self]),
              current_predicate(From:Name/CompiledArity),
              metta_tabling_visible_owner(Name, CompiledArity, From, Module) ),
            Targets0),
    sort(Targets0, Targets).

%A row leaving takes its own tables with it; a table a (tabled ...) call also
%asked for goes back to the default policy.
metta_tabling_withdraw_row(Name) :-
    forall(metta_tabling_policy_installed(Name, Module, CompiledArity,
                                          Declared, _, _, Origin),
           (   Origin == row
           ->  metta_tabling_uninstall(Name, Module, CompiledArity),
               metta_tabling_reflect(Module, Name, CompiledArity, Fact),
               ( once('get-atoms'('&metta', Fact))
               -> metta_tabling_reflection_write(remove, Fact)
               ;  true )
           ;   Declared == default
           ->  true
           ;   metta_tabling_declare_checked(Module, Name, CompiledArity,
                                             default, Origin)
           )).

metta_tabling_row_hold(Name) :-
    metta_tabling_row_held(Name),
    !.
metta_tabling_row_hold(Name) :-
    assertz(metta_tabling_row_held(Name)),
    assertz(seam:(function_clauses_changed(Name) :-
                      lib_tabling:metta_tabling_policy_changed(Name))).

metta_tabling_row_release(Name) :-
    retractall(metta_tabling_row_held(Name)),
    retractall(seam:(function_clauses_changed(Name) :-
                         lib_tabling:metta_tabling_policy_changed(Name))).

%%%% Restraints %%%%
%
%A restraint is a bound the program declared for one table, and reaching it
%is a control signal of the same family as an inference limit: the
%evaluation stops with metta_control_signal(restraint, [Word, Bound, Call]),
%which engine/metta/registration.pl lists as a control exception and the
%host seats classify beside the other limits. Two routes, because SWI takes
%two: the size restraints call prolog:tripwire/2 when the exact size is met,
%and the per-predicate answer-count restraint never does on 10.1.13 (it
%takes the bounded-rationality path whatever the action flag says, measured
%2026-09-07) and instead completes the table with one answer that binds
%nothing and is conditional on answer_count_restraint/0 [source: SWI-Prolog
%10.1 Reference Manual 7.11.3]. That answer's delay condition is what
%call_delays/2 reads, so a restrained table's dispatch goal reads it on every
%answer and raises the signal on the conditional one.
%
%The hook is global to the process; it claims only wires whose context is a
%table this library installed with that restraint, and fails otherwise so SWI's
%own action applies to everybody else's tables.
:- multifile prolog:tripwire/2.
prolog:tripwire(Wire, Context) :-
    metta_tabling_wire(Wire, Word),
    metta_tabling_wire_head(Context, Module, Head),
    functor(Head, Name, CompiledArity),
    metta_tabling_policy_installed(Name, Module, CompiledArity, _, InForce, _, _),
    memberchk([Word, Bound], InForce),
    metta_tabling_restraint_signal(Word, Bound, Head).

%The subgoal-size wire carries the abstracted goal; the answer-size wire
%carries the answer trie, whose variant table names the predicate, through
%the moded-implementation map when the table is moded
%[source: /usr/lib/swi-prolog/library/tables.pl, get_calls/3].
metta_tabling_wire_head(Module:Head, Module, Head) :-
    callable(Head),
    !.
metta_tabling_wire_head(Trie, Module, Head) :-
    is_trie(Trie),
    '$tbl_table_status'(Trie, _Status, Module:Variant, _Skeleton),
    (   current_predicate(Module:'$table_mode'/3),
        Module:'$table_mode'(Head0, Variant, _)
    ->  Head = Head0
    ;   Head = Variant
    ).

metta_tabling_restrained(Goal, Bound) :-
    call_delays(Goal, Delays),
    (   Delays == true
    ->  true
    ;   Goal = _:Head,
        metta_tabling_restraint_signal('max-answers', Bound, Head)
    ).

metta_tabling_restraint_signal(Word, Bound, Head) :-
    Head =.. [Name|Arguments],
    append(Inputs, [_Output], Arguments),
    sdisplay([Name|Inputs], Call),
    throw(error(metta_control_signal(restraint, [Word, Bound, Call]),
                context(metta, restraint))).

%Clear answers, keep the declaration: unifying subgoal tables of this
%predicate are abolished and every other table stands.
metta_table_clear(Call, true) :-
    metta_tabling_target(Call, Module, Name, CompiledArity),
    functor(Head, Name, CompiledArity),
    metta_tabling_table_variant(Module:Head, Variant),
    abolish_table_subgoals(Variant).

metta_table_clear_all(true) :-
    abolish_all_tables.

%The goal a table's answer trie is filed under. A lattice table's tables live
%on a generated implementation predicate, so abolish_table_subgoals/1 and
%table_statistics/3 asked with the wrapper head find nothing; library(tables)
%does this same two-step translation before it reads answers, and lib_memo does
%it for its sum tables [source: /usr/lib/swi-prolog/library/tables.pl,
%get_calls/3; lib/lib_memo/lib_memo.pl, reset_exact_memo_table/3]. A plain
%table maps to itself.
metta_tabling_table_variant(Module:Head, TableModule:Variant) :-
    (   catch('$tbl_implementation'(Module:Head, TableModule:Implementation),
              _, fail),
        current_predicate(TableModule:'$table_mode'/3),
        TableModule:'$table_mode'(Implementation, Variant0, _)
    ->  Variant = Variant0
    ;   TableModule = Module,
        Variant = Head
    ).

%What the incremental machinery actually did, rather than what it is
%supposed to do. A table over a space is invalidated by a write and
%re-evaluated on the next call, and until now nothing could see either
%happen: the guarantee was tested by its EFFECT, a fresh answer, which is
%also what an accidentally-rebuilt-from-scratch table produces.
%
%library(tableutil) already counts both, per subgoal variant, and its
%wording is the definition: invalidated is "Number of times an incremental
%table was invalidated", reevaluated is "Number of times an invalidated
%table was reevaluated. If lower than invalidated this implies that
%dependent nodes of the IDG were reevaluated to the same answer set"
%[source: SWI-Prolog 10.1 Reference Manual, A.59 library(tableutil)].
%That last sentence is the one worth surfacing: a gap between the two is
%SWI deciding a dependency changed without changing this table's answers,
%which is the incremental win being visible rather than assumed.
%
%The stat list is fixed rather than open. table_statistics/3 enumerates
%whatever it has, and answering all of it would publish trie-internal
%numbers that move with SWI's implementation; these five are the ones a
%caller can act on [tested: tabling_statistics_count_invalidations]. The
%policy in force follows them as (policy Words) while the table is declared,
%so a reader learns what a write does to this table from the same answer
%that counts what writes did.
metta_table_statistics(Call, Stats) :-
    metta_tabling_target(Call, Module, Name, CompiledArity),
    functor(Head, Name, CompiledArity),
    metta_tabling_table_variant(Module:Head, Variant),
    findall([Reported, Value],
            reportable_table_statistic(Variant, Reported, Value),
            Counters),
    (   metta_tabling_policy_installed(Name, Module, CompiledArity, _, InForce, _, _)
    ->  append(Counters, [[policy, InForce]], Stats)
    ;   Stats = Counters
    ).

%SWI's own spelling on the left, MeTTa's on the right: complete_call reads
%as complete-call beside every other name a MeTTa program sees.
reportable_table_statistic(Variant, Reported, Value) :-
    % policy-inventory-exempt: documented-collision-decision; reason=the pairs pin the documented SWI statistic names to their public MeTTa spellings including complete_call to complete-call; evidence=lib/lib_tabling/lib_tabling.pl:reportable_table_statistic/3
    member(Stat-Reported, [tables-tables, answers-answers,
                           complete_call-'complete-call',
                           invalidated-invalidated, reevaluated-reevaluated]),
    ( catch(table_statistics(Variant, Stat, Value), _, fail) -> true ; Value = 0 ).

%A table answers from the equations that were compiled when it was built,
%so changing any equation makes every table that could have read it stale.
%Measured before this, in the workspace review's P07: tabling a one-clause
%function, adding a second equation, then calling it answered only the
%cached first answer, and only an explicit abolish exposed both.
%
%Every table goes, not the changed function's alone. Deciding which tables
%could have read a given equation needs a call graph over compiled clauses
%that the engine does not keep, and answering that question wrongly is a
%stale answer with no symptom. Definition changes are rare beside calls,
%tables rebuild lazily on the next call, and this is the same funnel that
%already invalidates the specializer and the memo cache
%[tested: tabling_equation_change_drops_tables].
:- multifile seam:function_changed/1.
%If-then-else, not a cut. Every caller of this hook enumerates the whole
%predicate with forall/2, so a cut in one clause's body cuts THAT predicate's
%clause choice points and no handler ordered after this one runs. Clause order
%among multifile contributors is load order, and engine/duals.pl installs its
%handler with assertz, which appends: with tabling declared, a changed
%function abolished the tables and never dropped the stale dual, so
%(not-provable (pq 2)) answered both False from the recompiled path and True
%from the dual that was never dropped [tested: duals_survive_tabling].
seam:function_changed(_) :-
    ( metta_tabling_declared -> metta_tabling_abolish_declared ; true ).

:- multifile seam:function_removed/1.
seam:function_removed(_) :-
    ( metta_tabling_declared -> metta_tabling_abolish_declared ; true ).

%Every answer this library derived, dropped, which is the same abolition a
%changed function already causes. A replay of a recorded run asks for it: a
%tabled head answers a second run from its table in fewer reductions than the
%first, so the recorded event stream and the replayed one would differ over
%the same answers. The DECLARATIONS survive, as they do above, so the tables
%fill again from the next call.
:- multifile seam:forget_derived/0.
seam:forget_derived :-
    ( metta_tabling_declared -> metta_tabling_abolish_declared ; true ).

%Every table a MeTTa declaration made, and nothing else.
%
%abolish_all_tables/0 walks the WHOLE variant trie, which keeps a variant for
%every table the process has ever built. After one space tabled a
%200,000-answer recursion and was dropped, each call still cost 73ms with no
%live table left anywhere, and these two hooks fire once per compiled
%equation: one library import paid 13 walks and 0.9 seconds, and the 60-cycle
%drop test above spent 156 seconds
%[measured 2026-08-31: 5,266,337 inferences for one import, 2,600,026
%'$tbl_destroy_table'/1 calls under 13 abolish_all_tables/0 walks].
%
%abolish_table_subgoals/1 walks the same trie indexed by the predicate, so the
%cost is the tables a declared function actually has and a dropped space's
%variants are never walked again. abolish_module_tables/1 is NOT the
%narrowing: it misses `as shared` tables entirely, which is what every MeTTa
%table is [measured 2026-08-31: 50 tables before it and 50 after,
%0 after abolish_table_subgoals/1].
%
%The scope this drops is the tables of OTHER libraries, which own their own
%invalidation: lib_memo carries a generation argument rather than abolishing
%(its own comment says a private table cannot be selectively abolished across
%carriers), and engine/parser.pl abolishes metta_symbol_writable/1 itself.
metta_tabling_abolish_declared :-
    forall(metta_tabling_declared_table(Module, Head),
           ( metta_tabling_table_variant(Module:Head, Variant),
             abolish_table_subgoals(Variant) )).

%metta_exec_module_known/2 rather than space_module/2: this is a READ, and
%space_module/2 would ENSURE a module for a space that has none, which is a
%space with no table to abolish.
metta_tabling_declared_table(Module, Head) :-
    'get-atoms'('&metta', [tabled, Space, Name, InputArity]),
    atom(Name),
    integer(InputArity),
    metta_exec_module_known(Space, Module),
    CompiledArity is InputArity + 1,
    functor(Head, Name, CompiledArity).

%Nothing is tabled in the overwhelming majority of programs, and this hook
%runs on every equation the loader compiles, so the test that decides it is
%one indexed lookup on a predicate that is usually empty.
metta_tabling_declared :- 'get-atoms'('&metta', [tabled|_]), !.
