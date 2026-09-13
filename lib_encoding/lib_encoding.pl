% Purpose: supply strict byte/text boundaries and the shared UTF8/base64 codecs.
% Guarantees: complete finite bytes are validated before conversion. Only proven
% malformed decoder errors become domain errors; interruptions and unrelated
% provider exceptions retain their original terms.
% [tested: lib_encoding; commit=WORKTREE].
% Decides: standard base64 is padded; URL base64 is unpadded. Decoder acceptance
% follows the host codec, including its URL alphabet's classic fallback.
% [tested: lib_encoding:base64_is_the_hosts_own_encoding; commit=WORKTREE].

:- module(lib_encoding,
          [ 'utf8-encode'/2,
            'utf8-decode'/2,
            'encoding-bytes'/3,
            'encoding-text'/3,
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
% commit=2b8c0afd38dcfe3994d5047dba2d035970311d0e].
:- use_module('../lib_csv/support/csv_codec', [utf8_bytes/2, utf8_text/2]).
:- use_module(library(base64), [base64_encoded/3]).
:- use_module(library(lists), [member/2]).
:- multifile seam:extension_builtin/2.
seam:extension_builtin('encoding-bytes', pureStructural).
seam:extension_builtin('encoding-text', pureStructural).

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
    (   catch(utf8_text(Bytes, Decoded), Error,
              ( malformed_input(utf8, Error) -> fail ; throw(Error) ))
    ->  Text = Decoded
    ;   throw(error(domain_error(utf8_bytes, Bytes),
                    context('utf8-decode',
                            'these bytes are not UTF-8; hex-encode shows what they are')))
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
% The bytes that base64 spells under the named host decoder policy. Rejected text
% raises a named domain error. The host URL decoder also accepts classic digits;
% this operation does not impose an additional canonical-spelling check.
'base64-decode'(Alphabet, Text, Bytes) :-
    text_argument('base64-decode', Text),
    alphabet_options('base64-decode', Alphabet, Options),
    (   catch(base64_encoded(Plain, Text, Options), Error,
              ( malformed_input(base64, Error) -> fail ; throw(Error) ))
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

% These are the codec failures established by malformed-input probes. Catching
% any other error would turn cancellation or resource exhaustion into bad data.
% [tested: lib_encoding:provider_exceptions_keep_their_identity; commit=WORKTREE].
malformed_input(Kind, Error) :-
    malformed_pattern(Kind, Pattern), subsumes_term(Pattern, Error).

% Classification may not instantiate an unknown exception into a codec error.
malformed_pattern(utf8, error(representation_error(utf8), _)).
malformed_pattern(utf8, error(representation_error(unicode_scalar_value), _)).
malformed_pattern(base64, error(syntax_error(base64_char(_,_)), _)).
malformed_pattern(base64, error(representation_error(encoding),
                               context(system:string_bytes/3, _))).

%! 'encoding-bytes'(+Head:'Atom', +Bytes:'Atom', -Checked:list) is det.
%
% Return the caller's finite byte expression unchanged after strict validation.
% @private
'encoding-bytes'(Head, Bytes, Bytes) :- bytes_argument(Head, Bytes).

%! 'encoding-text'(+Head:'Atom', +Text:'Atom', -Checked:any) is det.
%
% Return text unchanged after the codec's strict text boundary.
% @private
'encoding-text'(Head, Text, Text) :- text_argument(Head, Text).

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
:- det('encoding-bytes'/3).
:- det('encoding-text'/3).
:- det('base64-encode'/3).
:- det('base64-decode'/3).
