% Purpose: native digests, HMAC, secure values and password records.
% Guarantees: provider failures raise; the reduced platform retains five SHA
% digests and two HMAC algorithms; password mismatches return False
% [tested: lib_crypto_surface, test_native_provider_failures_raise; commit=28c6146d805b5adba3047ffc72b2508c11816636].
% Owns resources: file hashing closes its binary stream on success, failure
% and output mismatch; native temporary buffers remain within each call
% [tested: lib_crypto_surface; commit=28c6146d805b5adba3047ffc72b2508c11816636].
% Decides: byte lists are integers 0..255; integer intervals are [Lower, Upper).
% Password records use PBKDF2-SHA512, 16 random salt bytes and default cost 18
% [tested: test_password_records_interoperate_with_swi_and_hashlib; commit=28c6146d805b5adba3047ffc72b2508c11816636].

:- module(lib_crypto,
          [crypto_hash/3, 'crypto-hash'/3, crypto_random_hex/2,
           'crypto-random-hex'/2, 'crypto-hash-bytes'/3, 'crypto-hash-file!'/3,
           'crypto-hmac'/4, 'crypto-hmac-bytes'/4, 'crypto-random-bytes'/2,
           'crypto-random-integer'/3, 'crypto-password-hash'/2,
           'crypto-password-hash'/3, 'crypto-password-verify'/3]).
:- set_module(base(metta_engine)).
:- metta_platform_load(crypto, []).
:- if(metta_platform(crypto, present, _, _)).
:- use_module('support/native', []).
:- endif.
:- use_module(library(sha), [sha_hash/3, sha_new_ctx/2, sha_hash_ctx/4,
                             hmac_sha/4, hash_atom/2]).
:- use_module(library(base64), [base64_encoded/3]).
:- use_module(library(error), [must_be/2, domain_error/2]).
:- use_module(library(apply), [maplist/2]).

%! crypto_hash(+Algorithm:any, +Text:any, -Hex:string) is det.
%
% Hash UTF-8 text to lowercase hexadecimal. Text may be a String, Symbol or
% character-code expression. Use a fixed-output OpenSSL digest name such as
% sha256, sha512, sha3_256 or blake2b512. Unknown algorithms raise. A platform
% without crypto retains sha1, sha224, sha256, sha384 and sha512 through sha.
crypto_hash(Algorithm, Text, Hex) :- crypto_digest(Algorithm, utf8(Text), none, Hex).

%! 'crypto-hash'(+Algorithm:any, +Text:any, -Hex:string) is det.
%
% Hash UTF-8 text, with the same contract as crypto_hash.
'crypto-hash'(Algorithm, Text, Hex) :- crypto_hash(Algorithm, Text, Hex).

%! 'crypto-hash-bytes'(+Algorithm:any, +Bytes:list, -Hex:string) is det.
%
% Hash an expression of byte integers 0..255 without text transcoding. Empty
% bytes are valid. Algorithms and reduced-platform support match crypto-hash.
'crypto-hash-bytes'(Algorithm, Bytes, Hex) :-
    must_be(list(between(0,255)), Bytes),
    crypto_digest(Algorithm, octets(Bytes), none, Hex).

%! 'crypto-hash-file!'(+Algorithm:any, +Path:any, -Hex:string) is det.
%
% Hash a file's bytes through a bounded buffer. Missing files and read failures
% raise. The binary stream closes on every exit; the file is never modified.
'crypto-hash-file!'(Algorithm, Path, Hex) :-
    setup_call_cleanup(open(Path, read, Stream, [type(binary)]),
                       crypto_digest(Algorithm, stream(Stream), none, Hex),
                       close(Stream)).

%! 'crypto-hmac'(+Algorithm:any, +Key:any, +Text:any, -Hex:string) is det.
%
% Authenticate UTF-8 text with a UTF-8 key and a fixed-output digest. The
% result is lowercase hexadecimal. Empty keys/text are valid. Without crypto,
% sha1 and sha256 remain available; other algorithms name the missing capability.
'crypto-hmac'(Algorithm, Key, Text, Hex) :-
    text_bytes(Key, Bytes),
    crypto_digest(Algorithm, utf8(Text), Bytes, Hex).

%! 'crypto-hmac-bytes'(+Algorithm:any, +Key:list, +Bytes:list, -Hex:string) is det.
%
% Authenticate raw bytes with a raw byte key; both expressions contain only
% integers 0..255. Algorithms and reduced support match crypto-hmac.
'crypto-hmac-bytes'(Algorithm, Key, Bytes, Hex) :-
    must_be(list(between(0,255)), Key),
    must_be(list(between(0,255)), Bytes),
    crypto_digest(Algorithm, octets(Bytes), Key, Hex).

crypto_digest(Algorithm0, Source, Key, Hex) :-
    ( atom(Algorithm0) -> Algorithm = Algorithm0 ; atom_string(Algorithm, Algorithm0) ),
    (   metta_platform(crypto, present, _, _)
    ->  lib_crypto_native:digest(Algorithm, Source, Key, Bytes)
    ;   portable_digest(Algorithm, Source, Key, Bytes)
    ),
    hash_atom(Bytes, Atom),
    atom_string(Atom, Hex).

portable_digest(Algorithm, Source, none, Bytes) :- !,
    ( sha_algorithm(Algorithm) -> true ; metta_require_platform('(crypto-hash ...)', crypto) ),
    portable_hash(Source, Algorithm, Bytes).
portable_digest(Algorithm, Source, Key, Bytes) :-
    ( hmac_algorithm(Algorithm) -> true ; metta_require_platform('(crypto-hmac ...)', crypto) ),
    source_bytes(Source, Data),
    hmac_sha(Key, Data, Bytes, [algorithm(Algorithm), encoding(octet)]).

sha_algorithm(sha1).
sha_algorithm(sha224).
sha_algorithm(sha256).
sha_algorithm(sha384).
sha_algorithm(sha512).
hmac_algorithm(sha1).
hmac_algorithm(sha256).

portable_hash(utf8(Text), Algorithm, Bytes) :-
    sha_hash(Text, Bytes, [algorithm(Algorithm), encoding(utf8)]).
portable_hash(octets(Data), Algorithm, Bytes) :-
    sha_hash(Data, Bytes, [algorithm(Algorithm), encoding(octet)]).
portable_hash(stream(Stream), Algorithm, Bytes) :-
    sha_new_ctx(Context, [algorithm(Algorithm), encoding(octet)]),
    sha_stream(Stream, Context, Bytes).

sha_stream(Stream, Context, Bytes) :-
    read_string(Stream, 65536, Chunk),
    (   Chunk == ""
    ->  sha_hash_ctx(Context, "", _, Bytes)
    ;   sha_hash_ctx(Context, Chunk, Next, _),
        sha_stream(Stream, Next, Bytes)
    ).

source_bytes(utf8(Text), Bytes) :- text_bytes(Text, Bytes).
source_bytes(octets(Bytes), Bytes).

text_bytes(Text, Bytes) :-
    ( is_list(Text) -> string_codes(String, Text) ; String = Text ),
    string_bytes(String, Bytes, utf8).

%! crypto_random_hex(+Count:integer, -Hex:string) is det.
%
% Return Count secure random bytes as 2*Count lowercase hexadecimal characters.
% Count may be zero. Negative counts and absent crypto capability raise.
crypto_random_hex(Count, Hex) :-
    secure_bytes(Count, '(crypto-random-hex ...)', Bytes),
    hash_atom(Bytes, Atom),
    atom_string(Atom, Hex).

%! 'crypto-random-hex'(+Count:integer, -Hex:string) is det.
%
% Return secure random hexadecimal, with the same contract as crypto_random_hex.
'crypto-random-hex'(Count, Hex) :- crypto_random_hex(Count, Hex).

%! 'crypto-random-bytes'(+Count:integer, -Bytes:list) is det.
%
% Return Count cryptographically secure byte integers. Zero returns (). Negative
% or unrepresentable sizes raise; native allocation and entropy failures raise.
'crypto-random-bytes'(Count, Bytes) :-
    secure_bytes(Count, '(crypto-random-bytes ...)', Bytes).

secure_bytes(Count, Operation, Bytes) :-
    must_be(nonneg, Count),
    metta_require_platform(Operation, crypto),
    lib_crypto_native:random_bytes(Count, Bytes).

%! 'crypto-random-integer'(+Lower:integer, +Upper:integer, -Value:integer) is det.
%
% Uniformly sample Lower <= Value < Upper with secure randomness. Bounds may
% be arbitrary-size signed integers. Empty/reversed intervals raise. A singleton
% returns its sole integer without drawing entropy. Requires crypto capability.
'crypto-random-integer'(Lower, Upper, Value) :-
    must_be(integer, Lower),
    must_be(integer, Upper),
    ( Lower < Upper -> true ; domain_error(nonempty_integer_interval, [Lower, Upper]) ),
    metta_require_platform('(crypto-random-integer ...)', crypto),
    Span is Upper - Lower,
    format(string(Bound), '~16r', [Span]),
    lib_crypto_native:random_below_hex(Bound, Hex),
    string_concat("0x", Hex, Literal),
    number_string(Offset, Literal),
    Value is Lower + Offset.

%! 'crypto-password-hash'(+Password:any, -Record:string) is det.
%! 'crypto-password-hash'(+Password:any, +Cost:integer, -Record:string) is det.
%
% Derive a PBKDF2-SHA512 password record from UTF-8 Password with 16 random salt
% bytes and 2^Cost iterations. Default Cost is 18 (262144 iterations). Explicit
% costs must fit the provider's positive C int iteration count (0..30 on this
% ABI); low costs are for fixtures, not stored credentials. The record preserves
% SWI's format. Native failures and absent crypto capability raise.
'crypto-password-hash'(Password, Record) :- 'crypto-password-hash'(Password, 18, Record).
'crypto-password-hash'(Password, Cost, Record) :-
    metta_require_platform('(crypto-password-hash ...)', crypto),
    lib_crypto_native:password_iterations(Cost, Iterations),
    lib_crypto_native:random_bytes(16, Salt),
    lib_crypto_native:password_hash(Password, Salt, Iterations, Digest),
    bytes_base64(Salt, Salt64),
    bytes_base64(Digest, Digest64),
    format(string(Record), '$pbkdf2-sha512$t=~d$~s$~s', [Iterations, Salt64, Digest64]).

%! 'crypto-password-verify'(+Password:any, +Record:any, -Matches:bool) is det.
%
% Verify a PBKDF2-SHA512 record, returning True or False for a valid record.
% Malformed records, invalid iteration counts and native failures raise. Legacy
% salt lengths remain valid. Parsing checks the complete envelope and canonical
% unpadded Base64; the equal-length digest comparison uses CRYPTO_memcmp.
'crypto-password-verify'(Password, Record, Matches) :-
    metta_require_platform('(crypto-password-verify ...)', crypto),
    password_record(Record, Iterations, Salt, Digest),
    lib_crypto_native:password_verify(Password, Salt, Iterations, Digest, Matches).

password_record(Record, Iterations, Salt, Digest) :-
    split_string(Record, "$", "", Parts),
    (   Parts = ["", "pbkdf2-sha512", Parameters, Salt64, Digest64],
        sub_string(Parameters, 0, 2, _, "t="),
        sub_string(Parameters, 2, _, 0, Decimal),
        string_codes(Decimal, Codes), Codes = [_|_], maplist(decimal_digit, Codes),
        number_string(Iterations, Decimal), Iterations > 0
    ->  true
    ;   domain_error(crypto_password_record, envelope)
    ),
    canonical_base64(Salt64, Salt),
    canonical_base64(Digest64, Digest),
    ( length(Digest, 64) -> true ; domain_error(crypto_password_record, digest_length) ).

decimal_digit(Code) :- Code >= 0'0, Code =< 0'9.

bytes_base64(Bytes, Encoded) :-
    string_codes(String, Bytes),
    base64_encoded(String, Encoded, [padding(false), encoding(iso_latin_1)]).

canonical_base64(Encoded, Bytes) :-
    (   base64_encoded(String, Encoded, [padding(false), encoding(iso_latin_1)]),
        base64_encoded(String, Canonical, [padding(false), encoding(iso_latin_1)]),
        Canonical == Encoded
    ->  string_codes(String, Bytes)
    ;   domain_error(crypto_password_record, base64)
    ).

:- multifile prolog:error_message//1.
prolog:error_message(crypto_native_error(Operation, Code, Message)) -->
    ['crypto native operation ~w failed (~d): ~w'-[Operation, Code, Message]].
