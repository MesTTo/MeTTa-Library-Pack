/* Purpose: check OpenSSL operations at the SWI foreign-function boundary.
 * Guarantees: provider failures raise even with an empty error queue; file
 * digests read bounded buffers; password comparison uses CRYPTO_memcmp
 * [tested: test_native_provider_failures_raise, lib_crypto_surface; commit=WORKTREE].
 * Owns resources: each call frees its contexts and cleanses temporary secret
 * buffers on success, failure and output mismatch; stream locks are released
 * without closing the caller's stream
 * [tested: lib_crypto_surface; commit=WORKTREE].
 * Guarded by: state is call-local; OpenSSL owns the default thread-safe DRBG
 * [source: https://github.com/openssl/openssl/blob/openssl-3.5.0/doc/man3/RAND_bytes.pod; commit=WORKTREE].
 * Decides: PBKDF2-SHA512 derives SHA512_DIGEST_LENGTH bytes, matching SWI's
 * existing password record format
 * [tested: test_password_records_interoperate_with_swi_and_hashlib; commit=WORKTREE].
 */

#include <SWI-Prolog.h>
#include <SWI-Stream.h>
#include <openssl/bn.h>
#include <openssl/core_names.h>
#include <openssl/crypto.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/params.h>
#include <openssl/rand.h>
#include <openssl/sha.h>
#include <limits.h>
#include <string.h>

#if OPENSSL_VERSION_MAJOR < 3
#error lib_crypto requires OpenSSL 3 development headers
#endif

typedef struct { char *data; size_t length; } input_buffer;

static int get_buffer(term_t value, unsigned flags, input_buffer *buffer)
{ return PL_get_nchars(value, &buffer->length, &buffer->data,
                       flags | CVT_EXCEPTION | BUF_MALLOC);
}

static void release_buffer(input_buffer *buffer)
{ if ( buffer->data )
  { OPENSSL_cleanse(buffer->data, buffer->length);
    PL_free(buffer->data);
  }
}

static int native_error(const char *operation)
{ unsigned long code = ERR_get_error();
  char message[256];
  term_t error = PL_new_term_ref();

  if ( code )
    ERR_error_string_n(code, message, sizeof(message));
  else
    strcpy(message, "OpenSSL returned failure without an error-queue entry");
  if ( !PL_unify_term(error,
                     PL_FUNCTOR_CHARS, "error", 2,
                       PL_FUNCTOR_CHARS, "crypto_native_error", 3,
                         PL_CHARS, operation,
                         PL_INT64, (int64_t)code,
                         PL_UTF8_STRING, message,
                       PL_VARIABLE) )
    return FALSE;
  return PL_raise_exception(error);
}

typedef struct
{ EVP_MD *algorithm;
  EVP_MD_CTX *digest;
  EVP_MAC *mac_algorithm;
  EVP_MAC_CTX *mac;
  size_t size;
} digest_state;

static void release_digest(digest_state *state)
{ EVP_MD_CTX_free(state->digest);
  EVP_MAC_CTX_free(state->mac);
  EVP_MD_free(state->algorithm);
  EVP_MAC_free(state->mac_algorithm);
}

static int initialize_digest(digest_state *state, char *name,
                             const input_buffer *key)
{ state->algorithm = EVP_MD_fetch(NULL, name, NULL);
  if ( !state->algorithm ) return native_error("EVP_MD_fetch");
  if ( EVP_MD_get_flags(state->algorithm) & EVP_MD_FLAG_XOF )
  { term_t algorithm = PL_new_term_ref();
    if ( !PL_put_atom_chars(algorithm, name) ) return FALSE;
    return PL_domain_error("fixed_output_digest", algorithm);
  }
  int size = EVP_MD_get_size(state->algorithm);
  if ( size <= 0 ) return native_error("EVP_MD_get_size");
  state->size = (size_t)size;
  if ( key )
  { state->mac_algorithm = EVP_MAC_fetch(NULL, "HMAC", NULL);
    if ( !state->mac_algorithm ) return native_error("EVP_MAC_fetch");
    state->mac = EVP_MAC_CTX_new(state->mac_algorithm);
    if ( !state->mac ) return native_error("EVP_MAC_CTX_new");
    OSSL_PARAM params[] =
    { OSSL_PARAM_construct_utf8_string(OSSL_MAC_PARAM_DIGEST, name, 0),
      OSSL_PARAM_construct_end()
    };
    if ( EVP_MAC_init(state->mac, (unsigned char *)key->data,
                      key->length, params) != 1 )
      return native_error("EVP_MAC_init");
    state->size = EVP_MAC_CTX_get_mac_size(state->mac);
    if ( !state->size ) return native_error("EVP_MAC_CTX_get_mac_size");
  } else
  { state->digest = EVP_MD_CTX_new();
    if ( !state->digest ) return native_error("EVP_MD_CTX_new");
    if ( EVP_DigestInit_ex2(state->digest, state->algorithm, NULL) != 1 )
      return native_error("EVP_DigestInit_ex2");
  }
  return TRUE;
}

static int update_digest(digest_state *state, const void *data, size_t length)
{ if ( state->mac )
  { if ( EVP_MAC_update(state->mac, data, length) != 1 )
      return native_error("EVP_MAC_update");
  } else if ( EVP_DigestUpdate(state->digest, data, length) != 1 )
    return native_error("EVP_DigestUpdate");
  return TRUE;
}

/* PL_get_stream acquires one lock. PL_release_stream reports recorded I/O
 * errors; its noerror variant preserves an earlier provider/signal exception.
 * https://github.com/SWI-Prolog/swipl-devel/blob/V10.1.13/src/os/pl-file.c#L596-L605
 */
static int digest_source(digest_state *state, term_t source)
{ atom_t kind;
  size_t arity;
  term_t value = PL_new_term_ref();
  if ( !PL_get_name_arity_sz(source, &kind, &arity) || arity != 1 )
    return PL_type_error("crypto_source", source);
  if ( !PL_get_arg(1, source, value) ) return FALSE;
  const char *name = PL_atom_chars(kind);
  if ( strcmp(name, "stream") == 0 )
  { IOSTREAM *stream;
    unsigned char chunk[65536];
    size_t read;
    if ( !PL_get_stream(value, &stream, SIO_INPUT) ) return FALSE;
    while ( (read = Sfread(chunk, 1, sizeof(chunk), stream)) != 0 )
    { if ( !update_digest(state, chunk, read) || PL_handle_signals() < 0 )
      { PL_release_stream_noerror(stream);
        OPENSSL_cleanse(chunk, sizeof(chunk));
        return FALSE;
      }
    }
    OPENSSL_cleanse(chunk, sizeof(chunk));
    return PL_release_stream(stream);
  }
  unsigned flags;
  if ( strcmp(name, "utf8") == 0 )
    flags = CVT_ATOM | CVT_STRING | CVT_LIST | REP_UTF8;
  else if ( strcmp(name, "octets") == 0 )
    flags = CVT_LIST | REP_ISO_LATIN_1;
  else
    return PL_domain_error("crypto_source", source);
  input_buffer input = {0};
  int result = get_buffer(value, flags, &input) &&
               update_digest(state, input.data, input.length);
  release_buffer(&input);
  return result;
}

static foreign_t digest(term_t algorithm, term_t source,
                        term_t key_term, term_t output)
{ input_buffer name = {0}, key = {0};
  digest_state state = {0};
  unsigned char *bytes = NULL;
  int result = FALSE;
  char *key_name;
  int keyed = !(PL_get_atom_chars(key_term, &key_name) &&
                strcmp(key_name, "none") == 0);

  ERR_clear_error();
  if ( !get_buffer(algorithm, CVT_ATOM | CVT_STRING | REP_UTF8, &name) ) goto done;
  if ( strlen(name.data) != name.length )
  { PL_domain_error("crypto_algorithm", algorithm);
    goto done;
  }
  for ( size_t i = 0; i < name.length; i++ )
    if ( name.data[i] == '_' ) name.data[i] = '-';
  if ( keyed && !get_buffer(key_term, CVT_LIST | REP_ISO_LATIN_1, &key) ) goto done;
  if ( !initialize_digest(&state, name.data, keyed ? &key : NULL) ||
       !digest_source(&state, source) ) goto done;
  bytes = OPENSSL_malloc(state.size);
  if ( !bytes )
  { native_error("OPENSSL_malloc");
    goto done;
  }
  if ( state.mac )
  { size_t length = 0;
    if ( EVP_MAC_final(state.mac, bytes, &length, state.size) != 1 )
    { native_error("EVP_MAC_final");
      goto done;
    }
    if ( length != state.size )
    { native_error("EVP_MAC_final_length");
      goto done;
    }
  } else
  { unsigned int length = 0;
    if ( EVP_DigestFinal_ex(state.digest, bytes, &length) != 1 )
    { native_error("EVP_DigestFinal_ex");
      goto done;
    }
    if ( length != state.size )
    { native_error("EVP_DigestFinal_length");
      goto done;
    }
  }
  result = PL_unify_list_ncodes(output, state.size, (char *)bytes);
done:
  OPENSSL_clear_free(bytes, state.size);
  release_digest(&state);
  release_buffer(&name);
  release_buffer(&key);
  return result;
}

static foreign_t random_bytes(term_t count, term_t output)
{ size_t size;
  if ( !PL_get_size_ex(count, &size) ) return FALSE;
  if ( !size ) return PL_unify_nil(output);
  ERR_clear_error();
  unsigned char *bytes = OPENSSL_malloc(size);
  if ( !bytes ) return native_error("OPENSSL_malloc");
  int result;
  if ( RAND_priv_bytes_ex(NULL, bytes, size, 0) != 1 )
    result = native_error("RAND_priv_bytes_ex");
  else
    result = PL_unify_list_ncodes(output, size, (char *)bytes);
  OPENSSL_clear_free(bytes, size);
  return result;
}

/* OpenSSL's BN sampler supplies uniform rejection and its native error path.
 * Hexadecimal interchange follows SWI crypto's integer_serialized/2.
 * https://github.com/openssl/openssl/blob/openssl-3.5.0/crypto/bn/bn_rand.c
 */
static foreign_t random_below_hex(term_t bound, term_t output)
{ input_buffer hex = {0};
  BIGNUM *range = NULL, *sample = NULL;
  char *answer = NULL;
  int result = FALSE;
  ERR_clear_error();
  if ( !get_buffer(bound, CVT_ATOM | CVT_STRING | REP_ISO_LATIN_1, &hex) ) goto done;
  if ( hex.length > INT_MAX )
  { PL_representation_error("int");
    goto done;
  }
  int consumed = BN_hex2bn(&range, hex.data);
  if ( !consumed )
  { native_error("BN_hex2bn");
    goto done;
  }
  if ( (size_t)consumed != hex.length || BN_is_negative(range) || BN_is_zero(range) )
  { PL_domain_error("positive_hex_integer", bound);
    goto done;
  }
  sample = BN_new();
  if ( !sample )
  { native_error("BN_new");
    goto done;
  }
  if ( BN_priv_rand_range(sample, range) != 1 )
  { native_error("BN_priv_rand_range");
    goto done;
  }
  answer = BN_bn2hex(sample);
  if ( !answer )
  { native_error("BN_bn2hex");
    goto done;
  }
  result = PL_unify_chars(output, PL_STRING | REP_ISO_LATIN_1,
                         strlen(answer), answer);
done:
  if ( answer ) OPENSSL_clear_free(answer, strlen(answer) + 1);
  BN_clear_free(sample);
  BN_clear_free(range);
  release_buffer(&hex);
  return result;
}

static foreign_t password_iterations(term_t cost_term, term_t output)
{ int cost;
  if ( !PL_get_integer_ex(cost_term, &cost) ) return FALSE;
  if ( cost < 0 ) return PL_domain_error("not_less_than_zero", cost_term);
  if ( (unsigned)cost >= sizeof(int) * CHAR_BIT - 1 )
    return PL_representation_error("int");
  return PL_unify_integer(output, (int)(1U << cost));
}

/* Match CPython's input bounds and checked return before publishing a digest.
 * https://github.com/python/cpython/blob/v3.14.0/Modules/_hashopenssl.c
 */
static int derive_password(term_t password, term_t salt_term,
                           term_t iteration_term, unsigned char *derived)
{ input_buffer text = {0}, salt = {0};
  int iterations, result = FALSE;
  ERR_clear_error();
  if ( !PL_get_integer_ex(iteration_term, &iterations) ) return FALSE;
  if ( iterations < 1 ) return PL_domain_error("positive_integer", iteration_term);
  if ( !get_buffer(password, CVT_ATOM | CVT_STRING | CVT_LIST | REP_UTF8, &text) ||
       !get_buffer(salt_term, CVT_LIST | REP_ISO_LATIN_1, &salt) ) goto done;
  if ( text.length > INT_MAX || salt.length > INT_MAX )
  { PL_representation_error("int");
    goto done;
  }
  if ( PKCS5_PBKDF2_HMAC(text.data, (int)text.length,
                         (unsigned char *)salt.data, (int)salt.length,
                         iterations, EVP_sha512(), SHA512_DIGEST_LENGTH,
                         derived) != 1 )
  { native_error("PKCS5_PBKDF2_HMAC");
    goto done;
  }
  result = TRUE;
done:
  release_buffer(&text);
  release_buffer(&salt);
  return result;
}

static foreign_t password_hash(term_t password, term_t salt,
                               term_t iterations, term_t output)
{ unsigned char derived[SHA512_DIGEST_LENGTH];
  int result = derive_password(password, salt, iterations, derived) &&
               PL_unify_list_ncodes(output, sizeof(derived), (char *)derived);
  OPENSSL_cleanse(derived, sizeof(derived));
  return result;
}

static foreign_t password_verify(term_t password, term_t salt,
                                 term_t iterations, term_t expected_term,
                                 term_t output)
{ input_buffer expected = {0};
  unsigned char derived[SHA512_DIGEST_LENGTH];
  int result = FALSE;
  if ( !get_buffer(expected_term, CVT_LIST | REP_ISO_LATIN_1, &expected) ) goto done;
  if ( expected.length != sizeof(derived) )
  { PL_domain_error("sha512_digest_length", expected_term);
    goto done;
  }
  if ( !derive_password(password, salt, iterations, derived) ) goto done;
  int equal = CRYPTO_memcmp(derived, expected.data, sizeof(derived)) == 0;
  result = PL_unify_bool(output, equal);
done:
  release_buffer(&expected);
  OPENSSL_cleanse(derived, sizeof(derived));
  return result;
}

install_t install_lib_crypto(void)
{ PL_register_foreign_in_module("lib_crypto_native", "digest", 4, digest, 0);
  PL_register_foreign_in_module("lib_crypto_native", "random_bytes", 2, random_bytes, 0);
  PL_register_foreign_in_module("lib_crypto_native", "random_below_hex", 2, random_below_hex, 0);
  PL_register_foreign_in_module("lib_crypto_native", "password_iterations", 2, password_iterations, 0);
  PL_register_foreign_in_module("lib_crypto_native", "password_hash", 4, password_hash, 0);
  PL_register_foreign_in_module("lib_crypto_native", "password_verify", 5, password_verify, 0);
}
