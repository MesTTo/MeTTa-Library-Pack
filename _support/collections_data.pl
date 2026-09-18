% Purpose: validate the finite expression boundary for collection rewrites.
% Guarantees: proper finite expressions retain terms and variable sharing;
% host-injected cycles, open tails and improper lists raise before traversal.
% [tested: lib_statistics, lib_math; commit=6fa571d1b7059b610f73e9feed657711414251e5].
% Owns resources: caller terms remain caller-owned; no copies or stored state.
% Guarantees: checking a term's shape has a structural effect.
% [tested: test_sample_program_recordings_replay_through_the_core_seed; commit=1d0b78a359f58de49f2f98bed50a6480d56cd5f6].
:- module(collections_data, ['collections-expression'/2]).
:- set_module(base(metta_engine)).
:- use_module(library(error), [must_be/2, representation_error/1]).
:- multifile seam:extension_builtin/2.
seam:extension_builtin('collections-expression', pureStructural).

% This private boundary returns the caller's checked expression unchanged.
% Finite expressions can contain variables and space handles, but cannot
% encode a cyclic Prolog term. Cycles through atoms in spaces remain valid.
'collections-expression'(Data, Data) :-
    catch((must_be(list,Data),
           (acyclic_term(Data) -> true ; representation_error(cyclic_expression))),
          Error,rethrow_metta_operation_error('collections-expression',Error)).
:- det('collections-expression'/2).
