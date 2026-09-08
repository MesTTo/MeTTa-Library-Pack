% Purpose: cryptographic hashes and secure randomness for MeTTa programs.
%   library(crypto) supplies every algorithm and secure randomness where the
%   platform has it; library(sha) preserves SHA-1, SHA-224, SHA-256, SHA-384
%   and SHA-512 where it does not.
% Guarantees:
%   - hashes answer lowercase hex strings, and the five shared SHA providers
%     agree byte for byte [tested:
%     platform_capabilities_reduced:sha_hashing_survives_without_crypto,
%     test_hashes_are_deterministic_and_agree_with_hashlib;
%     commit=59792b524568755a2fbfe1c5f7cdb571bd78a3bf]
%   - a build without library(crypto) refuses secure randomness and a
%     non-SHA hash by the crypto capability's name instead of calling an
%     undefined predicate [tested:
%     platform_capabilities_reduced:crypto_only_operations_refuse_by_name_without_crypto;
%     commit=59792b524568755a2fbfe1c5f7cdb571bd78a3bf]
% Fails when: a requested algorithm is unknown. Where library(crypto) is
%   present its own domain error remains authoritative; where it is absent an
%   algorithm outside the five portable SHA names needs that capability.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None


:- module(lib_crypto,
          [ crypto_hash/3,
            crypto_random_hex/2
          ]).

% Guarantees: private helpers and autoload declarations belong to this module.
% [tested: engine_modules; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
% Assumes: engine operations resolve through metta_engine's published exports.
% [source: engine/metta.pl:metta_engine_reexport/2; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
:- set_module(base(metta_engine)).

%The load and census are one act, as they are for library(json). A missing
%crypto library records the capability absent without swallowing any failure
%from a library that did resolve. library(sha) is part of the reduced seat and
%is the deliberately narrow fallback for hashing, not for randomness.
%hex_bytes/2 is on this list because crypto_random_hex/2 calls it. It was not,
%and the library-index autoloader was what had been finding it: with the
%autoloader off, on a platform that HAS crypto, `(crypto-random-hex 4)` raised
%`Unknown procedure: hex_bytes/2` while the same form answered "edf2d01d" with
%autoload on [measured 2026-09-07: NO_AUTOLOAD=1 sh run.sh over
%`!(import! &self (library lib_crypto))` and `!(println! (crypto-random-hex 4))`,
%exit 2 against exit 0; commit=e52b9b2eeb4b303b57c93e6e6844664a25ce0da3]. No corpus example calls it, so the
%no-autoload GATE never reached the line; the lib-autoload lane reads every
%shipped library's clauses instead of waiting for an example to
%[tested: sh check.sh lib-autoload; commit=e52b9b2eeb4b303b57c93e6e6844664a25ce0da3].
:- metta_platform_load(crypto, [crypto_data_hash/3, crypto_n_random_bytes/2,
                                hex_bytes/2]).
:- use_module(library(sha), [sha_hash/3, hash_atom/2]).

crypto_hash(Algorithm, Text, Hex) :-
    ( atom(Algorithm) -> A = Algorithm ; atom_string(A, Algorithm) ),
    (   metta_platform(crypto, present, _, _)
    ->  crypto_data_hash(Text, Hash, [algorithm(A)]),
        atom_string(Hash, Hex)
    ;   crypto_sha_hash(A, Text, Hex)
    ).

crypto_sha_hash(Algorithm, Text, Hex) :-
    (   crypto_sha_algorithm(Algorithm)
    ->  sha_hash(Text, Bytes, [algorithm(Algorithm)]),
        hash_atom(Bytes, Hash),
        atom_string(Hash, Hex)
    ;   metta_require_platform('(crypto-hash ...)', crypto)
    ).

crypto_sha_algorithm(sha1).
crypto_sha_algorithm(sha224).
crypto_sha_algorithm(sha256).
crypto_sha_algorithm(sha384).
crypto_sha_algorithm(sha512).

%N cryptographically secure random bytes as 2N hex characters.
crypto_random_hex(NBytes, Hex) :-
    must_be(positive_integer, NBytes),
    metta_require_platform('(crypto-random-hex ...)', crypto),
    crypto_n_random_bytes(NBytes, Bytes),
    hex_bytes(HexAtom, Bytes),
    atom_string(HexAtom, Hex).
