% Purpose: expose native clocks, calendar conversion, parsing and arithmetic.
% Guarantees: dates round-trip through visible records; calendar addition
% normalizes overflow and re-resolves local daylight saving
% [tested: lib_datetime; commit=9b22993447a5ddba93643895e3025661ba9f693e].
% Decides: legacy formatting returns Symbols; format-datetime returns String.
% Numeric timezone offsets are seconds west of Greenwich, as in SWI.

:- module(lib_datetime,
          [now/1, format_date/3, day_of_week/2,
           'format-date'/3, 'day-of-week'/2, 'format-datetime'/4,
           'parse-date'/2, 'parse-date'/3, 'timestamp-date'/3,
           'date-timestamp'/2, 'date-field'/3, 'date-fields'/2,
           'date-weekday'/2, 'date-year-day'/2, 'leap-year'/2,
           'month-days'/3, 'date-add'/4]).
:- set_module(base(metta_engine)).
:- use_module(library(date),
              [parse_time/2, parse_time/3, date_time_value/3,
               day_of_the_week/2, day_of_the_year/2]).
:- use_module(library(error), [must_be/2, domain_error/2, type_error/2]).
:- use_module(library(apply), [maplist/2]).

%! now(-Timestamp:number) is det.
%
% Read Unix seconds from the system wall clock. Clock adjustments can move it backwards.
now(Timestamp) :- get_time(Timestamp).

%! format_date(+Timestamp:number, +Pattern:any, -Formatted:atom) is det.
%
% Format Timestamp in UTC using SWI strftime directives; return a Symbol.
format_date(Timestamp, Pattern, Formatted) :-
    stamp_date_time(Timestamp, Date, 'UTC'),
    format_time(atom(Formatted), Pattern, Date).

%! 'format-date'(+Timestamp:number, +Pattern:any, -Formatted:atom) is det.
%
% Format Timestamp in UTC as a Symbol, with the same contract as format_date.
'format-date'(Timestamp, Pattern, Formatted) :- format_date(Timestamp, Pattern, Formatted).

%! day_of_week(+Timestamp:number, -Day:atom) is det.
%
% Return the UTC weekday name in the process locale as a Symbol.
day_of_week(Timestamp, Day) :- format_date(Timestamp, '%A', Day).

%! 'day-of-week'(+Timestamp:number, -Day:atom) is det.
%
% Return the UTC weekday name, with the same contract as day_of_week.
'day-of-week'(Timestamp, Day) :- day_of_week(Timestamp, Day).

%! 'format-datetime'(+Timestamp:number, +Pattern:any, +Zone:any, -Text:string) is det.
%
% Format Timestamp as String in UTC, local, or integer seconds west of UTC.
% Zone may be a Symbol or String; unsupported zones raise a native domain error.
'format-datetime'(Timestamp, Pattern, Zone0, Text) :-
    zone_value(Zone0, Zone),
    stamp_date_time(Timestamp, Date, Zone),
    format_time(string(Text), Pattern, Date).

%! 'parse-date'(+Text:any, -Timestamp:number) is det.
%! 'parse-date'(+Text:any, +Format:atom, -Timestamp:number) is det.
%
% Parse ISO 8601, RFC 1123, RFC 1036 or asctime text, optionally selecting
% iso_8601, rfc_1123, rfc_1036 or asctime. Invalid text or format raises.
% ISO dates alone use UTC; a time without a zone uses the process local zone.
'parse-date'(Text, Timestamp) :-
    ( parse_time(Text, Timestamp) -> true ; domain_error(date_text, Text) ).
'parse-date'(Text, Format, Timestamp) :-
    must_be(oneof([iso_8601, rfc_1123, rfc_1036, asctime]), Format),
    ( parse_time(Text, Format, Timestamp) -> true ; domain_error(date_text, Text) ).

%! 'timestamp-date'(+Timestamp:number, +Zone:any, -Parts:list) is det.
%
% Convert Unix seconds to (date Y M D H Min S Offset Zone DST). The input zone
% is UTC, local or integer seconds west of UTC. Unknown Zone and DST fields
% are the Symbol -. Fractional seconds survive at the host clock precision.
'timestamp-date'(Timestamp, Zone0, Parts) :-
    zone_value(Zone0, Zone),
    stamp_date_time(Timestamp, Date, Zone),
    Date =.. Parts.

%! 'date-timestamp'(+Parts:list, -Timestamp:number) is det.
%
% Convert (date Y M D) at UTC midnight or a full timestamp-date record to Unix
% seconds. Overflowing calendar fields normalize, as in SWI date_time_stamp.
'date-timestamp'(Parts, Timestamp) :-
    date_term(Parts, Date),
    date_time_stamp(Date, Timestamp).

%! 'date-field'(+Parts:list, +Field:atom, -Value:any) is semidet.
%
% Read year, month, day, hour, minute, second, utc_offset, time_zone,
% daylight_saving, date or time. Missing or unknown fields have no answer;
% date and time fields are visible expressions.
'date-field'(Parts, Field, Value) :-
    must_be(atom, Field),
    date_term(Parts, Date),
    date_time_value(Field, Date, Native),
    field_value(Native, Value).

%! 'date-fields'(+Parts:list, -Pair:list) is nondet.
%
% Enumerate (Field Value) pairs from a date record, omitting unknown zone/DST.
'date-fields'(Parts, [Field, Value]) :-
    date_term(Parts, Date),
    date_time_value(Field, Date, Native),
    field_value(Native, Value).

%! 'date-weekday'(+Parts:list, -Day:integer) is det.
%
% Return the weekday of a normalized calendar date: Monday 1 through Sunday 7.
'date-weekday'(Parts, Day) :- calendar_date(Parts, Date), day_of_the_week(Date, Day).

%! 'date-year-day'(+Parts:list, -Day:integer) is det.
%
% Return the one-based day of the normalized year, including leap days.
'date-year-day'(Parts, Day) :- calendar_date(Parts, Date), day_of_the_year(Date, Day).

%! 'leap-year'(+Year:integer, -Leap:boolean) is det.
%
% Test the proleptic Gregorian leap-year rule, including negative years.
'leap-year'(Year, Leap) :-
    must_be(integer, Year),
    ( 0 is Year mod 4, (Year mod 100 =\= 0 ; 0 is Year mod 400)
    -> Leap = true ; Leap = false ).

%! 'month-days'(+Year:integer, +Month:integer, -Days:integer) is det.
%
% Count days in Month 1 through 12 of the proleptic Gregorian Year.
'month-days'(Year, Month, Days) :-
    must_be(integer, Year), must_be(between(1, 12), Month),
    Next is Month + 1,
    date_time_stamp(date(Year, Next, 0, 0, 0, 0, 0, -, -), Stamp),
    stamp_date_time(Stamp, date(_, _, Days, _, _, _, _, _, _), 'UTC').

%! 'date-add'(+Timestamp:number, +Delta:list, +Zone:any, -Shifted:number) is det.
%
% Add (Years Months Days Hours Minutes Seconds) in Zone's calendar, then
% normalize overflow. January 31 plus one month can enter March. Local time
% recomputes daylight saving using the host's mktime policy; fixed offsets
% stay fixed. The first five deltas are integers; seconds may be fractional.
'date-add'(Timestamp, Delta, Zone0, Shifted) :-
    ( Delta = [DY, DM, DD, DH, DMin, DS]
    -> maplist(must_be(integer), [DY, DM, DD, DH, DMin]), must_be(number, DS)
    ; type_error(calendar_delta, Delta) ),
    zone_value(Zone0, Zone),
    stamp_date_time(Timestamp, date(Y, M, D, H, Min, S, Offset, _, _), Zone),
    Y1 is Y + DY, M1 is M + DM, D1 is D + DD,
    H1 is H + DH, Min1 is Min + DMin, S1 is S + DS,
    ( Zone == local -> Date = date(Y1, M1, D1, H1, Min1, S1, _, _, _)
    ; Date = date(Y1, M1, D1, H1, Min1, S1, Offset, -, -) ),
    date_time_stamp(Date, Shifted).

zone_value(Value, Zone) :-
    ( string(Value) -> atom_string(Zone, Value) ; Zone = Value ).

% SWI owns normalization and DST policy; retain its record representation.
% https://github.com/SWI-Prolog/swipl-devel/blob/V10.1.13/man/builtin.doc
date_term(Parts, Date) :-
    must_be(list, Parts),
    ( Parts = [date, Y, M, D]
    -> Date = date(Y, M, D, 0, 0, 0, 0, -, -)
    ; Parts = [date, Y, M, D, H, Min, S, Offset, TZ, DST]
    -> Date = date(Y, M, D, H, Min, S, Offset, TZ, DST)
    ; type_error(date_record, Parts) ),
    Date = date(Y, M, D, H0, Min0, S0, Offset0, TZ0, DST0),
    maplist(must_be(integer), [Y, M, D, H0, Min0, Offset0]),
    must_be(number, S0), must_be(atom, TZ0),
    must_be(oneof([true, false, -]), DST0).

field_value(Native, Value) :-
    ( compound(Native) -> Native =.. Value ; Value = Native ).

calendar_date(Parts, date(Y, M, D)) :-
    date_term(Parts, Date),
    Date = date(_, _, _, _, _, _, Offset, _, _),
    date_time_stamp(Date, Stamp),
    stamp_date_time(Stamp, date(Y, M, D, _, _, _, _, _, _), Offset).
