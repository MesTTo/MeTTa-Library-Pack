% Purpose: expose execution observations as ordinary queryable MeTTa spaces.
% Owns resources: the result space belongs to the caller; a failed publication
%   releases its space before propagating the failure.
% Guarantees: trace-source records selected functions before applying recording
%   bounds [tested: lib_observe:filtered_events_are_queryable; commit=WORKTREE].

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

observe_trace_atom(event(Depth, Kind, Term, Answer, _),
                   ['trace-event', Depth, Kind, Term, Answer]).
