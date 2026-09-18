% Purpose: provide UUID generation, strict representation validation and host time.
% Guarantees: validation accepts exactly 8-4-4-4-12 hexadecimal digits in a String,
% including nil and reserved bit patterns. RFC version1 timestamps retain the
% host's epoch and 100ns tick conversion.
% [tested: lib_uuid; commit=8fe20f1bdcde1af8b3e1753c545924f978246dba].
% Owns resources: the host UUID provider releases its temporary storage per call.
% Decides: random generation explicitly selects version4; time generation selects
% version1, which may expose the host's MAC address. Identifiers are not secrets.
% [source: https://github.com/SWI-Prolog/packages-clib/blob/2d74666697ba12af386644638b3e563390affbf6/uuid.c:pl_uuid; commit=8fe20f1bdcde1af8b3e1753c545924f978246dba].

:- module(lib_uuid,
          [ 'uuid-random!'/1, 'uuid-time!'/1, 'uuid-is'/2,
            'uuid-timestamp'/2, 'uuid-layout'/1
          ]).
:- set_module(base(metta_engine)).
:- use_module(library(uuid), [uuid/2, uuid_property/2]).
:- use_module(library(lists), [sum_list/2]).
:- use_module(library(apply), [maplist/3]).
:- multifile seam:extension_builtin/2.
seam:extension_builtin('uuid-layout', pureStructural).

%! 'uuid-layout'(-Widths:list) is det.
%
% Hexadecimal field widths shared by native validation and MeTTa formatting.
% @private
'uuid-layout'([8,4,4,4,12]).

%! 'uuid-random!'(-UUID:string) is det.
%
% Generate a version 4 random identifier. A UUID is not a secret; use
% crypto-random-bytes when unpredictability is a security requirement.
'uuid-random!'(UUID) :-
    uuid(Raw, [version(4)]), atom_string(Raw, UUID).

%! 'uuid-time!'(-UUID:string) is det.
%
% Generate a version 1 identifier using the host's OSSP provider. It contains a
% timestamp and may expose the host's MAC address. A host without that provider
% raises; uuid-random! is available independently of version 1 support.
'uuid-time!'(UUID) :-
    catch(uuid(Raw, [version(1)]), error(Formal, _),
          throw(error(Formal, context('uuid-time!',
              'version 1 needs an OSSP UUID build; uuid-random! generates version 4')))),
    atom_string(Raw, UUID).

%! 'uuid-is'(+Text:any, -Valid:boolean) is det.
%
% Whether Text is a UUID String with exactly 8-4-4-4-12 hexadecimal digits,
% accepting either case. This checks representation, not uniqueness or origin.
% Nil and reserved version/variant bit patterns remain valid 128-bit values.
'uuid-is'(Text, Valid) :-
    ( uuid_text_hex(Text, _) -> Valid = true ; Valid = false ).

%! 'uuid-timestamp'(+UUID:string, -Timestamp:float) is semidet.
%
% Seconds since the Unix epoch for an RFC version 1 UUID. Other layouts and
% versions have no answer. Malformed text raises, so absence is not a parse error.
'uuid-timestamp'(UUID, Timestamp) :-
    uuid_argument('uuid-timestamp', UUID, Hex),
    sub_string(Hex, 12, 1, _, "1"),
    sub_string(Hex, 16, 1, _, Digit), char_type(Digit, xdigit(Nibble)),
    Nibble >= 8, Nibble < 12,
    uuid_property(UUID, time(Timestamp)).

uuid_argument(Head, Text, Hex) :-
    (   uuid_text_hex(Text, Parsed)
    ->  Hex = Parsed
    ;   throw(error(domain_error(uuid, Text),
                    context(Head, 'use a String with 8-4-4-4-12 hexadecimal digits, or uuid-of-bytes')))
    ).

% Workaround: swi-uuid-nonhex-hyphens - validate group lengths and hexadecimal digits.
% is_uuid/1 accepts '-' at digit positions because hex_or_minus/1 accepts it
% everywhere, including the all-hyphen string. Validation and formatting use
% the same field widths, so their representations cannot drift independently.
uuid_text_hex(Text, Hex) :-
    string(Text), 'uuid-layout'(Widths),
    sum_list(Widths, Digits), length(Widths, Groups),
    Length is Digits+Groups-1, string_length(Text, Length),
    split_string(Text, "-", "", Parts),
    maplist(string_length, Parts, Widths),
    % Workaround: swi-string-nul-membership - require the original separator text.
    % A NUL in place of a hyphen passes the host splitter and all group lengths.
    atomics_to_string(Parts, "-", Rebuilt), Text == Rebuilt,
    atomics_to_string(Parts, Hex),
    forall(string_code(_, Hex, Code), code_type(Code, xdigit(_))).

:- det('uuid-random!'/1).
:- det('uuid-time!'/1).
:- det('uuid-is'/2).
:- det('uuid-layout'/1).
