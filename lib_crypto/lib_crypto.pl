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

%The load and census are one act, as they are for library(json). A missing
%crypto library records the capability absent without swallowing any failure
%from a library that did resolve. library(sha) is part of the reduced seat and
%is the deliberately narrow fallback for hashing, not for randomness.
:- metta_platform_load(crypto, [crypto_data_hash/3, crypto_n_random_bytes/2]).
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
