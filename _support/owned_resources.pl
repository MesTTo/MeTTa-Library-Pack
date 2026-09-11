% Purpose: preserve an operation's outcome while its owner releases resources.
% Assumes: Goal is deterministic or semideterministic; streaming enumeration
% uses setup_call_cleanup/3 directly. An accidental choice point is refused.
% [tested: lib_csv_surface:resource_guard_refuses_nondeterministic_operations; commit=WORKTREE].
% Guarantees: Cleanup receives exit, fail or exception(Error) before that
% outcome is restored, so a combined cleanup error is not suppressed by SWI.
% [tested: lib_json_surface:cleanup_retains_a_write_exception_beside_release_failures,
% lib_csv_surface:snapshot_release_failure_keeps_the_primary_outcome; commit=WORKTREE].
% Owns resources: Setup establishes the owner's scope; Cleanup runs once
% after successful Setup, including asynchronous interruption of Goal.
% [tested: lib_csv_surface:cancelling_a_writer_rolls_back_and_releases_its_lock; commit=WORKTREE].

:- module(owned_resources, [with_outcome_cleanup/3]).
:- meta_predicate with_outcome_cleanup(0, 0, 1).

with_outcome_cleanup(Setup, Goal, Cleanup) :-
    setup_call_catcher_cleanup(Setup,
        catch(( call_cleanup(Goal, Deterministic = true),
                require_deterministic(Deterministic)
              -> Outcome = exit
              ;  Outcome = fail ),
              Error, Outcome = exception(Error)),
        Catcher,
        ( nonvar(Outcome) -> call(Cleanup, Outcome) ; call(Cleanup, Catcher) )),
    restore_outcome(Outcome).

require_deterministic(Deterministic) :-
    ( Deterministic == true -> true
    ; throw(error(nondet_resource_operation, context(with_outcome_cleanup/3, _))) ).

restore_outcome(exit).
restore_outcome(fail) :- fail.
restore_outcome(exception(Error)) :- throw(Error).

:- multifile prolog:error_message//1.
prolog:error_message(nondet_resource_operation) -->
    ['nondet_resource_operation: use setup_call_cleanup/3 for a streaming operation; this owner requires one deterministic outcome'-[]].
