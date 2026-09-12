% Purpose: the three encodings a program moves bytes through: UTF-8, hex and
%   base64, each one head in and one head out.
%
%   Bytes are an expression of Numbers from 0 to 255, which is lib_file's own byte
%   shape, so what read-bytes! answers is what these heads take and what they
%   answer is what write-bytes! writes [source: lib/lib_file/lib_file.pl's byte
%   doors; commit=WORKTREE]. Text is a String throughout.
% Assumes:
%   - a byte collection really holds bytes. Every head checks, and a number outside
%     0..255 or a non-number is refused naming the value, because the host's own
%     writers turn a code point above 255 into several bytes and a caller who meant
%     bytes would never see it
%     [tested: lib_encoding:a_value_that_is_not_a_byte_is_refused_by_name;
%     commit=WORKTREE]
%   - malformed input is refused rather than repaired: a hex string of odd length or
%     with a character outside the alphabet, and base64 text the host's decoder
%     rejects, each raise
%     [tested: lib_encoding:malformed_text_is_refused_by_name; commit=WORKTREE]
% Guarantees:
%   - every encoding round-trips: the bytes of a text are that text again, the hex
%     of bytes is those bytes again, and so is the base64, in both alphabets, over
%     generated inputs
%     [tested: lib_encoding:every_encoding_round_trips; commit=WORKTREE]
%   - UTF-8 is the host's own encoding of the same text, byte for byte, which is
%     what makes a byte count a length in bytes rather than in characters
%     [tested: lib_encoding:utf8_is_the_hosts_own_encoding; commit=WORKTREE]
%   - hex answers lower case and accepts either case, which is what every hash and
%     every wire format that carries hex does
%     [tested: lib_encoding:hex_answers_lower_case_and_reads_either;
%     commit=WORKTREE]
% Fails when: a caller wants a struct layout, a protocol buffer or an integer of a
%   named width and endianness. Those are a host FFI concern and stay one; what is
%   here is the byte-level plumbing every such format is built out of.
% Owns resources: none; every answer is a new expression or String.
% Decides: base64 takes its ALPHABET as an argument, `standard` or `url`, rather
%   than publishing two pairs of heads. The url alphabet is the one RFC 4648 names
%   for a URL or a file name, and it is unpadded here, because that is what a URL
%   carries.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None


:- module(lib_encoding,
          [ 'utf8-encode'/2,
            'utf8-decode'/2,
            'hex-encode'/2,
            'hex-decode'/2,
            'base64-encode'/3,
            'base64-decode'/3
          ]).

% Guarantees: private helpers and autoload declarations belong to this module.
% [tested: engine_modules; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
% Assumes: engine operations resolve through metta_engine's published exports.
% [source: engine/metta.pl:metta_engine_reexport/2; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
:- set_module(base(metta_engine)).

% The UTF-8 codec is lib_csv's, which vendored SWI's own and is the tree's one
% implementation of it: a fourth copy of "text to bytes" would be a fourth place
% for it to disagree [source: lib/lib_csv/support/csv_codec.pl:utf8_bytes/2;
% commit=WORKTREE].
:- use_module('../lib_csv/support/csv_codec', [utf8_bytes/2, utf8_text/2]).
:- use_module(library(base64), [base64_encoded/3]).
:- use_module(library(error), [must_be/2]).
:- use_module(library(lists), [member/2, memberchk/2]).

%! 'utf8-encode'(+Text:string, -Bytes:list) is det.
%
% The UTF-8 bytes of the text, as an expression of Numbers from 0 to 255. This is
% the length a wire format and a file both count in: an accented letter is two
% bytes, an emoji four, where string-length counts one character each.
'utf8-encode'(Text, Bytes) :-
    text_argument('utf8-encode', Text),
    utf8_bytes(Text, Bytes).

%! 'utf8-decode'(+Bytes:list, -Text:string) is det.
%
% The text those UTF-8 bytes spell. A byte sequence that is not UTF-8 is refused,
% because the alternative is a string holding whatever the bytes happened to mean.
'utf8-decode'(Bytes, Text) :-
    bytes_argument('utf8-decode', Bytes),
    (   catch(utf8_text(Bytes, Decoded), _, fail)
    ->  Text = Decoded
    ;   throw(error(domain_error(utf8_bytes, Bytes),
                    context('utf8-decode',
                            'these bytes are not UTF-8; hex-encode shows what they are')))
    ).

%! 'hex-encode'(+Bytes:list, -Text:string) is det.
%
% The bytes as hexadecimal, two lower-case digits each and nothing between them,
% which is how a hash, a key and a wire dump are all written.
'hex-encode'(Bytes, Text) :-
    bytes_argument('hex-encode', Bytes),
    findall(Digits,
            ( member(Byte, Bytes), format(atom(Digits), '~|~`0t~16r~2|', [Byte]) ),
            Pairs),
    atomic_list_concat(Pairs, Joined),
    atom_string(Joined, Text).

%! 'hex-decode'(+Text:string, -Bytes:list) is det.
%
% The bytes that hexadecimal spells, in either case. An odd number of digits or a
% character outside 0-9a-fA-F is refused naming it, because a truncated or
% mistyped dump is not bytes.
'hex-decode'(Text, Bytes) :-
    text_argument('hex-decode', Text),
    string_codes(Text, Codes),
    length(Codes, Length),
    (   Length mod 2 =:= 0
    ->  true
    ;   throw(error(domain_error(hex_text, Text),
                    context('hex-decode',
                            'hexadecimal spells one byte in two digits, so the text has an even length')))
    ),
    hex_bytes(Codes, Text, Bytes).

hex_bytes([], _, []).
hex_bytes([High, Low|Rest], Text, [Byte|Bytes]) :-
    hex_digit(High, Text, HighValue),
    hex_digit(Low, Text, LowValue),
    Byte is HighValue * 16 + LowValue,
    hex_bytes(Rest, Text, Bytes).

hex_digit(Code, Text, Value) :-
    (   Code >= 0'0, Code =< 0'9
    ->  Value is Code - 0'0
    ;   Code >= 0'a, Code =< 0'f
    ->  Value is Code - 0'a + 10
    ;   Code >= 0'A, Code =< 0'F
    ->  Value is Code - 0'A + 10
    ;   char_code(Char, Code),
        throw(error(domain_error(hex_digit, Char),
                    context('hex-decode', Text)))
    ).

%! 'base64-encode'(+Alphabet:'Symbol', +Bytes:list, -Text:string) is det.
%
% The bytes as base64 in one of the two RFC 4648 alphabets: `standard`, padded with
% `=` as mail and JSON carry it, or `url`, which uses `-` and `_` and no padding,
% as a URL and a file name carry it. An alphabet the library does not know is
% refused with both named.
'base64-encode'(Alphabet, Bytes, Text) :-
    bytes_argument('base64-encode', Bytes),
    alphabet_options('base64-encode', Alphabet, Options),
    string_codes(Plain, Bytes),
    base64_encoded(Plain, Encoded, Options),
    atom_string(Encoded, Text).

%! 'base64-decode'(+Alphabet:'Symbol', +Text:string, -Bytes:list) is det.
%
% The bytes that base64 spells, in the named alphabet. Text the decoder rejects,
% which includes a character outside the alphabet and a truncated group, is refused
% naming the text.
'base64-decode'(Alphabet, Text, Bytes) :-
    text_argument('base64-decode', Text),
    alphabet_options('base64-decode', Alphabet, Options),
    (   catch(base64_encoded(Plain, Text, Options), _, fail)
    ->  plain_bytes(Plain, Bytes)
    ;   throw(error(domain_error(base64_text, Text),
                    context('base64-decode',
                            'this text is not base64 in that alphabet; standard uses + and / with = padding and url uses - and _ without')))
    ).

% The host's base64 works over TEXT, and its default encoding is utf8: passed a
% string whose code points ARE the bytes, it base64s that string's UTF-8 instead,
% so (255 254) encoded as "w7/Dvg==" rather than "//4=". The
% `encoding(iso_latin_1)` option in both alphabets is what makes a code point a
% byte, which is the encoding base64 is defined over
% [measured 2026-09-12: both answers, before and after the option;
% source: /usr/lib/swi-prolog/library/base64.pl:base64_encoded/3, "Encoding to use
% for translation between (Unicode) text and _bytes_"].
plain_bytes(Plain, Bytes) :-
    string_codes(Plain, Codes),
    (   forall(member(Code, Codes), ( Code >= 0, Code =< 255 ))
    ->  Bytes = Codes
    ;   throw(error(domain_error(base64_text, Plain),
                    context('base64-decode',
                            'the decoder answered a character above 255, which is not a byte')))
    ).

alphabet_options(Head, Alphabet, Options) :-
    (   alphabet(Alphabet, Options)
    ->  true
    ;   findall(Known, alphabet(Known, _), Alphabets),
        throw(error(domain_error(base64_alphabet, Alphabet),
                    context(Head, Alphabets)))
    ).

alphabet(standard, [padding(true), charset(classic), as(string), encoding(iso_latin_1)]).
alphabet(url, [padding(false), charset(url), as(string), encoding(iso_latin_1)]).

% Bytes are an expression of Numbers from 0 to 255, and the check names the value
% that is not one: a code point above 255 is the common mistake, and it arrives
% from string-codes over text rather than from utf8-encode.
bytes_argument(Head, Bytes) :-
    (   is_list(Bytes)
    ->  forall(member(Byte, Bytes),
               (   integer(Byte), Byte >= 0, Byte =< 255
               ->  true
               ;   throw(error(type_error(byte, Byte),
                               context(Head,
                                       'a byte is a Number from 0 to 255; string-codes answers code points, and utf8-encode answers bytes')))
               ))
    ;   throw(error(type_error(list, Bytes),
                    context(Head, 'the bytes are a collection of Numbers')))
    ).

text_argument(Head, Text) :-
    (   ( string(Text) ; atom(Text) )
    ->  true
    ;   throw(error(type_error(string, Text),
                    context(Head, 'the text is a string')))
    ).

:- det('utf8-encode'/2).
:- det('utf8-decode'/2).
:- det('hex-encode'/2).
:- det('hex-decode'/2).
:- det('base64-encode'/3).
:- det('base64-decode'/3).
