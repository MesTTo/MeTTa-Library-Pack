/* Purpose: lib_string's ISub half, the one native object that compiles the
   LGPL-2.0-or-later scorer in ../vendor/isub.hpp, kept apart from the
   permissive half (string_native.cpp) so that is the only object carrying it.
   It is built on the machine that runs it and loaded as a shared object the
   user can rebuild and replace (support/isub.pl), the arrangement LGPL 2.1
   section 6(b) describes, a version isub.hpp's "any later version" grant
   reaches [source 2026-09-27T20:56:56+10:00: https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt].
   No support/static.cmake names it, so a host that links foreign code
   statically, the WebAssembly one, carries none of it
   [source 2026-09-27T22:20:42+10:00: lib/lib_string/support/static.cmake].
   Assumes: lib_string.pl's string-isub hands it Strings, a nonnegative
   threshold no longer than the longer text, and a boolean
   [source 2026-09-27T22:20:42+10:00: lib/lib_string/lib_string.pl:'string-isub'/4].
   Guarantees: the score of the complete texts, NUL included, as
   isub_score/5 computes it [tested 2026-09-27T22:15:44+10:00: lib_string_surface].
*/
#include <SWI-Prolog.h>
#include <cstdint>
#include <vector>
#include "string_boundary.hpp"
#include "../vendor/isub.hpp"

namespace {
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

extern "C" install_t install_lib_string_isub()
{
    PL_register_foreign_in_module("lib_string_isub_native", "substring_similarity", 5, reinterpret_cast<pl_function_t>(substring_similarity), 0);
}
