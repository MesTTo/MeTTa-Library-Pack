/* Purpose: the call boundary lib_string's two native halves share: owned
   codepoint vectors read from Prolog text, the pending-signal check a long walk
   makes, and the wrapper that turns every C++ failure into a Prolog answer.
   Assumes: each half includes this once, in one translation unit, so each
   object carries its own internal copy; string_native.cpp and isub_native.cpp
   build into separate objects [source 2026-09-27T22:20:42+10:00: lib/lib_string/support/native_build.pl:native_object/1, isub_object/1].
   Guarantees: text_codes/2 answers every scalar of a String, NUL and
   supplementary scalars included, and refuses a lone surrogate with
   representation_error(unicode_scalar_value); boundary/1 answers false for a
   pending signal or a failed PL_* call, a resource error for exhausted memory,
   and string_native_error(Message) for any other C++ exception
   [tested 2026-09-27T22:15:44+10:00: lib_string_surface, test_string_unicode_oracles].
   Owns resources: the buffer text_codes/2 asks SWI for, released on every exit.
*/
#ifndef LIB_STRING_BOUNDARY_HPP
#define LIB_STRING_BOUNDARY_HPP

#include <SWI-Prolog.h>
#include <climits>
#include <cstdint>
#include <exception>
#include <memory>
#include <new>
#include <stdexcept>
#include <vector>

namespace {
using Codes = std::vector<uint32_t>;
struct Pending {};

void checked(bool result)
{
    if (!result) throw Pending{};
}

struct Signals {
    size_t ticks = 0;
    void operator()()
    {
        if ((++ticks & 16383) == 0) checked(PL_handle_signals() >= 0);
    }
};

template <class Operation>
foreign_t boundary(Operation operation)
{
    try {
        checked(PL_handle_signals() >= 0);
        const bool result = operation();
        checked(PL_handle_signals() >= 0);
        return result;
    } catch (const Pending&) {
        return false;
    } catch (const std::bad_alloc&) {
        return PL_resource_error("memory");
    } catch (const std::length_error&) {
        return PL_resource_error("memory");
    } catch (const std::exception& error) {
        term_t exception = PL_new_term_ref();
        if (!PL_unify_term(exception, PL_FUNCTOR_CHARS, "error", 2,
                          PL_FUNCTOR_CHARS, "string_native_error", 1,
                          PL_UTF8_CHARS, error.what(), PL_VARIABLE)) return false;
        return PL_raise_exception(exception);
    } catch (...) {
        return PL_resource_error("string_native_exception");
    }
}

Codes text_codes(term_t value, Signals& check)
{
    pl_wchar_t* raw = nullptr;
    size_t length = 0;
    checked(PL_get_wchars(value, &length, &raw, CVT_STRING | CVT_EXCEPTION | BUF_MALLOC));
    std::unique_ptr<pl_wchar_t, decltype(&PL_free)> owned(raw, &PL_free);
    Codes codes;
    codes.reserve(length);
    for (size_t i = 0; i < length; ++i) {
        uint32_t code = static_cast<uint32_t>(raw[i]);
#if WCHAR_MAX <= 0xffff
        if (code >= 0xd800 && code <= 0xdbff && i + 1 < length) {
            const uint32_t low = static_cast<uint32_t>(raw[i + 1]);
            if (low >= 0xdc00 && low <= 0xdfff) {
                code = 0x10000 + ((code - 0xd800) << 10) + low - 0xdc00;
                ++i;
            }
        }
#endif
        if (code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff))
            checked(PL_representation_error("unicode_scalar_value"));
        codes.push_back(code);
        check();
    }
    return codes;
}
} // namespace

#endif
