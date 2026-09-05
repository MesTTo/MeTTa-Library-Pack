% Purpose: expose execution observations as ordinary queryable MeTTa spaces.
% Owns resources: the result space belongs to the caller; a failed publication
%   releases its space before propagating the failure.
% Guarantees: trace-source records selected functions before applying recording
%   bounds [tested: lib_observe:filtered_events_are_queryable; commit=504f8dddfa890ced97e795a13ab10e239b1de2ce].
% Guarantees: observe-source returns diagnostic atoms in a caller-owned space
%   [tested: test_error_frames_point_to_the_failing_subterm_and_its_caller; commit=df1367c75148ca6c7262134a8736b237e1150383].

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

% The report owns diagnostic state; ordinary arithmetic keeps its effect class.
'observe-source'(Space, Label, Source, Report) :-
    source_observation:observe_source(Space, Label, Source, Atoms),
    'new-space'(Report),
    catch(metta_add_atoms(Report, Atoms),
          Error, (metta_release_space(Report), throw(Error))).
