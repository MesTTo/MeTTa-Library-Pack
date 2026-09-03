;Cryptographic hashes and secure randomness. library(crypto), with OpenSSL
;underneath, supplies every operation where the platform has it. A reduced
;platform keeps SHA-1, SHA-224, SHA-256, SHA-384 and SHA-512 through
;library(sha), and refuses randomness or any other algorithm by the missing
;crypto capability's name.
;
;(crypto-hash sha256 "text") answers the lowercase hex digest; the
;algorithm is any library(crypto) name (sha256, sha512, sha1, md5,
;blake2b512, sha3_256, ...) on a full platform; an unknown one errors loudly.
;Hashes make content keys: the same text always answers the same digest, so a
;fact can carry the digest of its payload as an identity.
;(crypto-random-hex 16) answers 32 hex characters from 16
;cryptographically secure random bytes, a nonce or a fresh id.

!(import! &self (library lib_import))
!(import_prolog_functions_from_file (library lib_crypto.pl)
  (crypto_hash crypto_random_hex))

(= (crypto-hash $algorithm $text) (crypto_hash $algorithm $text))
(= (crypto-random-hex $nbytes) (crypto_random_hex $nbytes))
