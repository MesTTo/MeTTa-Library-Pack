/* Purpose: provide length-aware literal operations and exact String metrics.
   Assumes: public wrappers coerce text; foreign entry points still check types.
   [source: lib/lib_string/lib_string.pl:metta_text/2, lib/lib_string/support/string_native.cpp:text_codes; commit=3aaad3435292e4c7d5cc3a01bfda39430aacc6e8].
   Guarantees: NUL and supplementary scalars retain their codepoint positions.
   [tested: lib_string_surface, test_string_unicode_oracles; commit=3aaad3435292e4c7d5cc3a01bfda39430aacc6e8].
   Owns resources: local RAII buffers are released on success, failure and exception.
   No query state survives a call. [source: lib/lib_string/support/string_native.cpp:boundary; commit=3aaad3435292e4c7d5cc3a01bfda39430aacc6e8].
   Decides: literal matching shares KMP; pending signals are checked during owned
   walks and at RapidFuzz's call boundaries. [tested: lib_string_surface; commit=3aaad3435292e4c7d5cc3a01bfda39430aacc6e8].
*/
#include <SWI-Prolog.h>
#include <algorithm>
#include <climits>
#include <cstdint>
#include <exception>
#include <memory>
#include <stdexcept>
#include <unordered_set>
#include <vector>
#include <rapidfuzz/distance/Levenshtein.hpp>
#include "../vendor/isub.hpp"

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

bool unify_text(term_t output, Codes::const_iterator begin, Codes::const_iterator end,
                Signals& check)
{
    std::vector<pl_wchar_t> wide;
    wide.reserve(static_cast<size_t>(end - begin));
    for (auto it = begin; it != end; ++it) {
        const uint32_t code = *it;
#if WCHAR_MAX <= 0xffff
        if (code > 0xffff) {
            wide.push_back(static_cast<pl_wchar_t>(0xd800 + ((code - 0x10000) >> 10)));
            wide.push_back(static_cast<pl_wchar_t>(0xdc00 + ((code - 0x10000) & 1023)));
        } else
#endif
        wide.push_back(static_cast<pl_wchar_t>(code));
        check();
    }
    return PL_unify_wchars(output, PL_STRING, wide.size(), wide.empty() ? L"" : wide.data());
}

// Boost 1.89.0's prefix fallback, using sizes and preserving state after matches.
// https://github.com/boostorg/algorithm/blob/boost-1.89.0/include/boost/algorithm/searching/knuth_morris_pratt.hpp
// Copyright Marshall Clow 2010-2012. Distributed under the Boost Software License 1.0.
template <class Accept>
void occurrences(const Codes& text, const Codes& pattern, bool overlap,
                  Accept accept, Signals& check)
{
    if (pattern.empty()) {
        for (size_t i = 0;; ++i) {
            if (!accept(i) || i == text.size()) return;
            check();
        }
    }
    std::vector<size_t> prefix(pattern.size());
    for (size_t i = 1, matched = 0; i < pattern.size(); ++i) {
        while (matched && pattern[matched] != pattern[i]) {
            matched = prefix[matched - 1];
            check();
        }
        if (pattern[matched] == pattern[i]) ++matched;
        prefix[i] = matched;
        check();
    }
    for (size_t i = 0, matched = 0; i < text.size(); ++i) {
        while (matched && pattern[matched] != text[i]) {
            matched = prefix[matched - 1];
            check();
        }
        if (pattern[matched] == text[i]) ++matched;
        if (matched == pattern.size()) {
            if (!accept(i + 1 - matched)) return;
            matched = overlap ? prefix[matched - 1] : 0;
        }
        check();
    }
}

foreign_t find_index(term_t value, term_t needle, term_t reverse, term_t output)
{
    return boundary([&]() {
        Signals check;
        const Codes text = text_codes(value, check), pattern = text_codes(needle, check);
        int last;
        checked(PL_get_bool_ex(reverse, &last));
        bool found = false;
        size_t position = 0;
        occurrences(text, pattern, true, [&](size_t index) {
            found = true;
            position = index;
            return last != 0;
        }, check);
        return found ? PL_unify_uint64(output, position) : PL_unify_integer(output, -1);
    });
}

foreign_t count_matches(term_t value, term_t needle, term_t overlapping, term_t output)
{
    return boundary([&]() {
        Signals check;
        const Codes text = text_codes(value, check), pattern = text_codes(needle, check);
        int overlap;
        checked(PL_get_bool_ex(overlapping, &overlap));
        size_t count = 0;
        occurrences(text, pattern, overlap != 0, [&](size_t) { ++count; return true; }, check);
        return PL_unify_uint64(output, count);
    });
}

void append_part(term_t tail, term_t head, const Codes& text, size_t start, size_t end,
                  Signals& check)
{
    checked(PL_unify_list(tail, head, tail));
    checked(unify_text(head, text.begin() + start, text.begin() + end, check));
}

foreign_t split_exact(term_t value, term_t delimiter, term_t output)
{
    return boundary([&]() {
        Signals check;
        const Codes text = text_codes(value, check), pattern = text_codes(delimiter, check);
        if (pattern.empty()) return PL_domain_error("non_empty_string", delimiter);
        term_t tail = PL_copy_term_ref(output), head = PL_new_term_ref();
        size_t start = 0;
        occurrences(text, pattern, false, [&](size_t index) {
            append_part(tail, head, text, start, index, check);
            start = index + pattern.size();
            return true;
        }, check);
        append_part(tail, head, text, start, text.size(), check);
        return PL_unify_nil(tail);
    });
}

foreign_t replace_all(term_t value, term_t from, term_t to, term_t output)
{
    return boundary([&]() {
        Signals check;
        const Codes text = text_codes(value, check), pattern = text_codes(from, check);
        const Codes replacement = text_codes(to, check);
        if (pattern.empty()) return PL_unify(value, output);
        Codes result;
        size_t start = 0;
        occurrences(text, pattern, false, [&](size_t index) {
            result.insert(result.end(), text.begin() + start, text.begin() + index);
            result.insert(result.end(), replacement.begin(), replacement.end());
            start = index + pattern.size();
            return true;
        }, check);
        result.insert(result.end(), text.begin() + start, text.end());
        return unify_text(output, result.begin(), result.end(), check);
    });
}

// SWI-Prolog 10.1.13 split_string's scan, with length-aware set membership.
// https://github.com/SWI-Prolog/swipl-devel/blob/fc7ef84b949378b729052c3ade79c90ce5416abb/src/pl-string.c
// The SWI BSD license is reproduced in vendor/SWI-LICENSE.
// Workaround: swi-string-nul-membership - use complete character sets and explicit input bounds.
foreign_t split_text(term_t value, term_t separators, term_t padding, term_t output)
{
    return boundary([&]() {
        Signals check;
        const Codes text = text_codes(value, check), sep = text_codes(separators, check);
        const Codes pad = text_codes(padding, check);
        const std::unordered_set<uint32_t> sep_set(sep.begin(), sep.end()), pad_set(pad.begin(), pad.end());
        term_t tail = PL_copy_term_ref(output), head = PL_new_term_ref();
        size_t end = text.size();
        while (end && pad_set.count(text[end - 1])) { --end; check(); }
        size_t i = 0;
        bool skip_padding = true;
        for (;;) {
            if (skip_padding) {
                while (i < end && pad_set.count(text[i])) { ++i; check(); }
            }
            const size_t start = i;
            while (i < end && !sep_set.count(text[i])) { ++i; check(); }
            const size_t separator = i;
            while (i > start && pad_set.count(text[i - 1])) { --i; check(); }
            append_part(tail, head, text, start, i, check);
            if (separator == end) break;
            i = separator + 1;
            skip_padding = pad_set.count(text[separator]) || i == end || !sep_set.count(text[i]);
            check();
        }
        return PL_unify_nil(tail);
    });
}

foreign_t edit_distance(term_t first, term_t second, term_t output)
{
    return boundary([&]() {
        Signals check;
        const Codes left = text_codes(first, check), right = text_codes(second, check);
        const size_t distance = rapidfuzz::levenshtein_distance(left.begin(), left.end(),
                                                               right.begin(), right.end());
        return PL_unify_uint64(output, distance);
    });
}

// Workaround: swi-isub-nul-lengths - pass complete owned codepoint vectors to the adapted core.
foreign_t substring_similarity(term_t first, term_t second, term_t threshold,
                                term_t normalized, term_t output)
{
    return boundary([&]() {
        Signals check;
        Codes left = text_codes(first, check), right = text_codes(second, check);
        size_t minimum;
        int zero_to_one;
        checked(PL_get_size_ex(threshold, &minimum));
        checked(PL_get_bool_ex(normalized, &zero_to_one));
        return PL_unify_float(output, isub_score(left, right, minimum, zero_to_one != 0, check));
    });
}
} // namespace

extern "C" install_t install_lib_string()
{
    PL_register_foreign_in_module("lib_string_native", "find_index", 4, reinterpret_cast<pl_function_t>(find_index), 0);
    PL_register_foreign_in_module("lib_string_native", "count_matches", 4, reinterpret_cast<pl_function_t>(count_matches), 0);
    PL_register_foreign_in_module("lib_string_native", "split_exact", 3, reinterpret_cast<pl_function_t>(split_exact), 0);
    PL_register_foreign_in_module("lib_string_native", "replace_all", 4, reinterpret_cast<pl_function_t>(replace_all), 0);
    PL_register_foreign_in_module("lib_string_native", "split_text", 4, reinterpret_cast<pl_function_t>(split_text), 0);
    PL_register_foreign_in_module("lib_string_native", "edit_distance", 3, reinterpret_cast<pl_function_t>(edit_distance), 0);
    PL_register_foreign_in_module("lib_string_native", "substring_similarity", 5, reinterpret_cast<pl_function_t>(substring_similarity), 0);
}
