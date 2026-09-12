% Purpose: generate UUIDs, derive identifiers from names, and convert their text
% and bytes without losing a name's Unicode or embedded NUL characters.
% Assumes: uuid-time! needs the host's OSSP UUID provider; version 3 needs the
% crypto capability through lib_crypto, while version 5 retains its SHA provider.
% [source: lib/lib_crypto/lib_crypto.pl:portable_digest/4; commit=WORKTREE].
% Guarantees: standard and arbitrary namespaces follow the RFC name algorithm;
% text and all 128-bit byte values round-trip, with malformed text refused.
% [tested: lib_uuid; commit=WORKTREE].
% Owns resources: the host UUID and digest providers release their temporary
% storage within each call; no handle or scope is returned.
% Decides: uuid-random! explicitly selects version 4. uuid-time! selects version 1,
% which contains a timestamp and may expose the host's MAC address. The host's
% unqualified default is version 1 when OSSP is linked. UUIDs identify objects;
% use lib_crypto's crypto-random-bytes for secrets.
% [source: https://github.com/SWI-Prolog/packages-clib/blob/2d74666697ba12af386644638b3e563390affbf6/uuid.c:pl_uuid; commit=WORKTREE].

:- module(lib_uuid,
          [ 'uuid-random!'/1, 'uuid-time!'/1, 'uuid-name'/4,
            'uuid-namespaces'/1, 'uuid-is'/2, 'uuid-version'/2,
            'uuid-variant'/2, 'uuid-timestamp'/2, 'uuid-nil'/1,
            'uuid-bytes'/2, 'uuid-of-bytes'/2
          ]).
:- set_module(base(metta_engine)).
:- use_module(library(uuid), [uuid/2, uuid_property/2]).
:- use_module(library(lists), [append/3]).
:- use_module(library(error), [must_be/2]).
:- use_module('../lib_encoding/lib_encoding',
              ['utf8-encode'/2, 'hex-encode'/2, 'hex-decode'/2]).
:- use_module('../lib_crypto/lib_crypto', ['crypto-hash-bytes'/3]).

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

%! 'uuid-name'(+Version:integer, +Namespace:any, +Name:string, -UUID:string) is det.
%
% Derive a version 3 (MD5) or version 5 (SHA-1) UUID from a namespace and the
% complete UTF-8 name. Namespace is dns, url, oid or x500, or any UUID String.
% Equal inputs give equal identifiers. Empty names and embedded NULs are valid.
% Version 3 requires the crypto capability; these digests identify names and
% provide no authentication. Prefer version 5 for new name-based identifiers.
'uuid-name'(Version, Namespace, Name, UUID) :-
    (   integer(Version), name_algorithm(Version, Algorithm)
    ->  true
    ;   throw(error(domain_error(uuid_name_version, Version),
                    context('uuid-name', 'choose version 3 or 5')))
    ),
    namespace_bytes(Namespace, NamespaceBytes),
    must_be(string, Name),
    'utf8-encode'(Name, NameBytes),
    append(NamespaceBytes, NameBytes, Input),
    % Workaround: swi-uuid-name-encoding - hash complete namespace and UTF-8 bytes.
    % The host's OSSP boundary uses Latin-1 and a NUL-terminated name. The byte
    % algorithm also admits arbitrary namespace UUIDs. CPython follows the same
    % construction: https://github.com/python/cpython/blob/v3.14.0/Lib/uuid.py#L763-L790.
    'crypto-hash-bytes'(Algorithm, Input, Hex),
    sub_string(Hex, 0, 32, _, First),
    'hex-decode'(First, [A,B,C,D,E,F,VersionByte,G,VariantByte|Tail]),
    V is (VersionByte /\ 15) \/ (Version << 4),
    R is (VariantByte /\ 63) \/ 128,
    'uuid-of-bytes'([A,B,C,D,E,F,V,G,R|Tail], UUID).

name_algorithm(3, md5).
name_algorithm(5, sha1).

namespace(dns, "6ba7b810-9dad-11d1-80b4-00c04fd430c8").
namespace(url, "6ba7b811-9dad-11d1-80b4-00c04fd430c8").
namespace(oid, "6ba7b812-9dad-11d1-80b4-00c04fd430c8").
namespace(x500, "6ba7b814-9dad-11d1-80b4-00c04fd430c8").

namespace_bytes(Namespace, Bytes) :-
    (   string(Namespace)
    ->  UUID = Namespace
    ;   atom(Namespace), namespace(Namespace, UUID)
    ->  true
    ;   'uuid-namespaces'(Names),
        throw(error(domain_error(uuid_namespace, Namespace),
                    context('uuid-name', namespaces_or_uuid_string(Names))))
    ),
    uuid_argument('uuid-name', UUID, Hex), 'hex-decode'(Hex, Bytes).

%! 'uuid-namespaces'(-Namespaces:list) is det.
%
% The predefined namespace Symbols accepted by uuid-name. A UUID String supplies
% an application namespace, so identifiers can themselves name further namespaces.
'uuid-namespaces'(Namespaces) :- findall(Name, namespace(Name, _), Namespaces).

%! 'uuid-is'(+Text:any, -Valid:boolean) is det.
%
% Whether Text is a UUID String with exactly 8-4-4-4-12 hexadecimal digits,
% accepting either case. This checks representation, not uniqueness or origin.
% Nil and reserved version/variant bit patterns remain valid 128-bit values.
'uuid-is'(Text, Valid) :-
    ( uuid_text_hex(Text, _) -> Valid = true ; Valid = false ).

%! 'uuid-version'(+UUID:string, -Version:integer) is det.
%
% The four version bits as a Number from 0 to 15. Nil has zero; a bit pattern is
% not evidence that the identifier was generated according to that version.
'uuid-version'(UUID, Version) :-
    uuid_argument('uuid-version', UUID, _), uuid_property(UUID, version(Version)).

%! 'uuid-variant'(+UUID:string, -Variant:atom) is det.
%
% The layout selected by the variant bits: ncs, rfc, microsoft or future.
% Versions 1, 3, 4 and 5 generated here use rfc; nil uses ncs.
'uuid-variant'(UUID, Variant) :-
    uuid_argument('uuid-variant', UUID, Hex),
    sub_string(Hex, 16, 1, _, Digit), char_type(Digit, xdigit(Nibble)),
    (   Nibble < 8 -> Variant = ncs
    ;   Nibble < 12 -> Variant = rfc
    ;   Nibble < 14 -> Variant = microsoft
    ;   Variant = future
    ).

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

%! 'uuid-nil'(-UUID:string) is det.
%
% The all-zero identifier, distinct from a missing answer.
'uuid-nil'("00000000-0000-0000-0000-000000000000").

%! 'uuid-bytes'(+UUID:string, -Bytes:list) is det.
%
% The 16 bytes of a UUID in network order. These compose with hex-encode,
% base64-encode and write-bytes!, which use the same byte expression.
'uuid-bytes'(UUID, Bytes) :-
    uuid_argument('uuid-bytes', UUID, Hex), 'hex-decode'(Hex, Bytes).

%! 'uuid-of-bytes'(+Bytes:list, -UUID:string) is det.
%
% Exactly 16 byte integers as a canonical lower-case UUID String. Every 128-bit
% value is preserved; this conversion does not change version or variant bits.
'uuid-of-bytes'(Bytes, UUID) :-
    must_be(list(between(0,255)), Bytes),
    (   length(Bytes, 16)
    ->  true
    ;   throw(error(domain_error(uuid_bytes, Bytes),
                    context('uuid-of-bytes', 'a UUID contains exactly 16 bytes')))
    ),
    'hex-encode'(Bytes, Hex),
    sub_string(Hex, 0, 8, _, A), sub_string(Hex, 8, 4, _, B),
    sub_string(Hex, 12, 4, _, C), sub_string(Hex, 16, 4, _, D),
    sub_string(Hex, 20, 12, 0, E),
    atomics_to_string([A,B,C,D,E], "-", UUID).

uuid_argument(Head, Text, Hex) :-
    (   uuid_text_hex(Text, Parsed)
    ->  Hex = Parsed
    ;   throw(error(domain_error(uuid, Text),
                    context(Head, 'use a String with 8-4-4-4-12 hexadecimal digits, or uuid-of-bytes')))
    ).

% Workaround: swi-uuid-nonhex-hyphens - validate group lengths and hexadecimal digits.
% is_uuid/1 accepts '-' at digit positions because hex_or_minus/1 accepts it
% everywhere, including the all-hyphen string. A native digit check validates
% fields without allocating bytes for a version or variant query.
uuid_text_hex(Text, Hex) :-
    string(Text), string_length(Text, 36),
    split_string(Text, "-", "", [A,B,C,D,E]),
    string_length(A, 8), string_length(B, 4), string_length(C, 4),
    string_length(D, 4), string_length(E, 12),
    % Workaround: swi-string-nul-membership - require the original separator text.
    % A NUL in place of a hyphen passes the host splitter and all group lengths.
    atomics_to_string([A,B,C,D,E], "-", Rebuilt), Text == Rebuilt,
    atomics_to_string([A,B,C,D,E], Hex),
    forall(string_code(_, Hex, Code), code_type(Code, xdigit(_))).

:- det('uuid-random!'/1).
:- det('uuid-time!'/1).
:- det('uuid-name'/4).
:- det('uuid-namespaces'/1).
:- det('uuid-is'/2).
:- det('uuid-version'/2).
:- det('uuid-variant'/2).
:- det('uuid-nil'/1).
:- det('uuid-bytes'/2).
:- det('uuid-of-bytes'/2).
