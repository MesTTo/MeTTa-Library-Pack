/*  Part of SWI-Prolog

    Author:        Jan Wielemaker
    E-mail:        jan@swi-prolog.org
    WWW:           https://www.swi-prolog.org
    Copyright (c)  2009-2026, VU University Amsterdam
                              CWI, Amsterdam,
                              SWI-Prolog Solutions b.v.
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:
    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in
       the documentation and/or other materials provided with the
       distribution.
    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
    COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
*/

% Purpose: parse and emit one lossless CSV record over UTF-8 bytes.
% Assumes: syntax(Separator, Quote, Newline) holds validated UTF-8 byte lists;
% separators and present quotes encode distinct single Unicode scalars.
% [source: lib/lib_csv/lib_csv.pl:csv_compile/4; commit=bd027d8b7a9ef1d96fb4cdb160c9b3eb4157d52e].
% Guarantees: quoted newlines and NUL survive; malformed UTF-8 is refused;
% zero fields and one empty field have different encodings.
% [tested: lib_csv_surface; commit=bd027d8b7a9ef1d96fb4cdb160c9b3eb4157d52e].
% Decides: adapt the field, doubled-quote and emitter grammar from SWI's
% pinned csv.pl, retaining its license. VENDOR.md records the changes.
% [source: https://github.com/SWI-Prolog/swipl-devel/blob/fc7ef84b949378b729052c3ade79c90ce5416abb/library/csv.pl; commit=bd027d8b7a9ef1d96fb4cdb160c9b3eb4157d52e].

:- module(csv_codec, [record//2, encoded_record/3, utf8_text/2, utf8_bytes/2]).
:- use_module(library(error), [must_be/2, domain_error/2]).
:- use_module(library(apply), [maplist/2, maplist/3]).
:- use_module(library(lists), [append/3, memberchk/2]).

record([], _) --> line_end, !.
record(Fields, Syntax) --> fields(Fields, Syntax).

fields([Field|More], Syntax) -->
    field(Field, Syntax),
    (   { Syntax = syntax(Separator, _, _) }, literal(Separator)
    ->  fields(More, Syntax)
    ;   end_of_record
    ->  { More = [] }
    ).

field(Value, syntax(_, Quote, _)) -->
    { Quote \== [] }, literal(Quote), !,
    quoted_bytes(Bytes, Quote),
    { utf8_text(Bytes, Value) }.
field(Value, syntax(Separator, _, _)) -->
    field_bytes(Bytes, Separator),
    { utf8_text(Bytes, Value) }.

% SWI's string_codes//1 commits a doubled quote before considering the close.
% A UTF-8 scalar is a prefix-free byte sequence, so the same grammar applies.
quoted_bytes(Bytes, Quote) -->
    literal(Quote), !,
    (   literal(Quote)
    ->  { append(Quote, Tail, Bytes) }, quoted_bytes(Tail, Quote)
    ;   { Bytes = [] }
    ).
quoted_bytes([Byte|Tail], Quote) --> [Byte], quoted_bytes(Tail, Quote).

field_bytes([], Separator, Input, Input) :-
    % policy-inventory-exempt: mechanism-internal; reason=CR and LF close an unquoted CSV field; evidence=lib/lib_csv/support/csv_codec.pl:field_bytes/4
    ( Input = [] ; Input = [Byte|_], memberchk(Byte, [10,13])
    ; phrase(literal(Separator), Input, _) ), !.
field_bytes([Byte|Tail], Separator) --> [Byte], field_bytes(Tail, Separator).

literal([]) --> [].
literal([Byte|Tail]) --> [Byte], literal(Tail).

line_end --> "\r\n", !.
line_end --> "\n", !.
line_end --> "\r".
end_of_record --> line_end, !.
end_of_record([], []).

utf8_text(Bytes, Text) :-
    string_bytes(Text, Bytes, utf8),
    string_bytes(Text, Canonical, utf8),
    ( Bytes == Canonical
    -> unicode_text(Text)
    ;  throw(error(representation_error(utf8), context(csv_codec, _))) ).

utf8_bytes(Text, Bytes) :-
    must_be(string, Text), unicode_text(Text), string_bytes(Text, Bytes, utf8).

unicode_text(Text) :-
    string_codes(Text, Codes),
    ( maplist(scalar, Codes)
    -> true
    ;  throw(error(representation_error(unicode_scalar_value), context(csv_codec, _))) ).
scalar(Code) :- Code >= 0, Code =< 0x10ffff, (Code < 0xd800 ; Code > 0xdfff).

encoded_record(Fields, Syntax, Bytes) :-
    must_be(list, Fields), maplist(utf8_bytes, Fields, Encoded),
    phrase(emit_record(Encoded, Syntax), Bytes).

emit_record([[]], syntax(_, Quote, Ending)) -->
    !, { require_quote(Quote, "") }, literal(Quote), literal(Quote), literal(Ending).
emit_record(Fields, Syntax) -->
    emit_fields(Fields, Syntax), { Syntax = syntax(_, _, Ending) }, literal(Ending).

emit_fields([], _) --> [].
emit_fields([Field|More], Syntax) -->
    emit_field(Field, Syntax),
    (   { More == [] }
    ->  []
    ;   { Syntax = syntax(Separator, _, _) }, literal(Separator), emit_fields(More, Syntax)
    ).

emit_field(Bytes, syntax(Separator, Quote, _)) -->
    (   { needs_quotes(Bytes, Separator, Quote) }
    ->  { utf8_text(Bytes, Text), require_quote(Quote, Text) },
        literal(Quote), emit_quoted(Bytes, Quote), literal(Quote)
    ;   literal(Bytes)
    ).

needs_quotes(Bytes, Separator, Quote) :-
    ( memberchk(10, Bytes) ; memberchk(13, Bytes)
    ; contains(Bytes, Separator) ; Quote \== [], contains(Bytes, Quote) ), !.

contains(Bytes, Needle) :- append(_, Tail, Bytes), append(Needle, _, Tail), !.

require_quote([], Text) :- !, domain_error(csv_unquoted_field, Text).
require_quote(_, _).

emit_quoted([], _) --> !.
emit_quoted(Bytes, Quote) -->
    { append(Quote, Tail, Bytes) }, !,
    literal(Quote), literal(Quote), emit_quoted(Tail, Quote).
emit_quoted([Byte|Tail], Quote) --> [Byte], emit_quoted(Tail, Quote).
