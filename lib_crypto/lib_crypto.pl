% Purpose: cryptographic hashes and secure randomness for MeTTa programs,
%   library(crypto)'s OpenSSL underneath: content keys, dedup identities,
%   nonces. Hashes answer lowercase hex strings; the algorithm argument is
%   library(crypto)'s own name (sha256, sha512, sha1, md5, blake2b512,
%   sha3_256, ...) and an unknown one errors loudly.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- use_module(library(crypto), [crypto_data_hash/3, crypto_n_random_bytes/2]).

crypto_hash(Algorithm, Text, Hex) :-
    ( atom(Algorithm) -> A = Algorithm ; atom_string(A, Algorithm) ),
    crypto_data_hash(Text, Hash, [algorithm(A)]),
    atom_string(Hash, Hex).

%N cryptographically secure random bytes as 2N hex characters.
crypto_random_hex(NBytes, Hex) :-
    must_be(positive_integer, NBytes),
    crypto_n_random_bytes(NBytes, Bytes),
    hex_bytes(HexAtom, Bytes),
    atom_string(HexAtom, Hex).
