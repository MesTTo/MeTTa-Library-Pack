
:- module(lib_datetime,
          [ day_of_week/2,
            format_date/3,
            now/1
          ]).

% Guarantees: private helpers and autoload declarations belong to this module.
% [tested: engine_modules; commit=WORKTREE]
% Assumes: engine operations resolve through metta_engine's published exports.
% [source: engine/metta.pl:metta_engine_reexport/2; commit=WORKTREE]
:- set_module(base(metta_engine)).

now(TimeStamp) :-
    get_time(TimeStamp).

format_date(TimeStamp, Format, Formatted) :-
    stamp_date_time(TimeStamp, DateTime, 'UTC'),
    format_time(atom(Formatted), Format, DateTime).

day_of_week(TimeStamp, DayName) :-
    stamp_date_time(TimeStamp, DateTime, 'UTC'),
    format_time(atom(DayName), '%A', DateTime).
