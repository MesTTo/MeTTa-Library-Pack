% Purpose: expose execution observations as ordinary queryable MeTTa spaces.
% Owns resources: the result space belongs to the caller; a failed publication
%   releases its space before propagating the failure.
% Guarantees: trace-source records selected functions before applying recording
%   bounds [tested: lib_observe:filtered_events_are_queryable; commit=504f8dddfa890ced97e795a13ab10e239b1de2ce].
% Guarantees: a trace-event atom carries the engine's whole event, sequence
%   number and time included, in the tracer's own field order
%   [tested: lib_observe:filtered_events_are_queryable; commit=e54c3654b9e0d3d040560d12c105a54303f63af7].
% Guarantees: observe-source returns diagnostic atoms in a caller-owned space
%   [tested: test_error_frames_point_to_the_failing_subterm_and_its_caller; commit=df1367c75148ca6c7262134a8736b237e1150383].
% Guarantees: asking for an observation is what loads engine/source_observation.pl.
%   The engine does not load it at boot, so an engine that never calls
%   observe-source pays nothing for the observer
%   [tested: source_observation:the_observer_holds_no_hook_outside_an_observation;
%   measured 2026-09-05: engine boot 536,337 with the boot load against 532,641
%   without; commit=b96e1a15260b7538a8e42be613bcc5dd0dddd136].


:- module(lib_observe,
          [ 'observe-source'/4,
            'trace-source'/5
          ]).

% Guarantees: private helpers and autoload declarations belong to this module.
% [tested: engine_modules; commit=WORKTREE]
% Assumes: engine operations resolve through metta_engine's published exports.
% [source: engine/metta.pl:metta_engine_reexport/2; commit=WORKTREE]
:- set_module(base(metta_engine)).

:- use_module('../../engine/tracer', [metta_trace_source/6]).
:- use_module('../../engine/spaces', [metta_add_atoms/2, metta_release_space/1]).

% The engine records before serialization, so excluded calls spend no event
% budget. Function selection does not change evaluation or nesting depths.
'trace-source'(Space, Source, Filter, Maximum, Report) :-
    ( string(Source) -> true
    ; throw(error(type_error(string, Source),
                  context('trace-source', 'pass MeTTa source as a string'))) ),
    metta_trace_source(Source, Space, Maximum, Filter, Events, Stopped),
    maplist(observe_trace_atom, Events, Atoms),
    'new-space'(Report),
    catch(metta_add_atoms(Report, [['trace-stopped', Stopped]|Atoms]),
          Error, (metta_release_space(Report), throw(Error))).

%One atom per event, carrying the whole event: the sequence number and the
%wall nanoseconds since the run began lead, because a MeTTa program reading
%this space wants to ORDER and TIME what it reads and a space is a bag. Kind is
%one of call, exit and fail, and a fail's answer is '' as a call's is.
observe_trace_atom(event(Seq, Time, Depth, Kind, Term, Answer, _),
                   ['trace-event', Seq, Time, Depth, Kind, Term, Answer]).

% The report owns diagnostic state; ordinary arithmetic keeps its effect class.
% Asking for an observation is what loads the observer: engine/metta.pl does
% not load it at boot, so an engine nobody asks pays nothing for it.
'observe-source'(Space, Label, Source, Report) :-
    metta_ensure_source_observation,
    source_observation:observe_source(Space, Label, Source, Atoms),
    'new-space'(Report),
    catch(metta_add_atoms(Report, Atoms),
          Error, (metta_release_space(Report), throw(Error))).
