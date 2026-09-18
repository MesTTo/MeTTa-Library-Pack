/* Copyright 2004-2011 by the National and Technical University of Athens

   This program is free software: you can redistribute it and/or modify it
   under the terms of the GNU Lesser General Public License as published by
   the Free Software Foundation, either version 2 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful, but
   WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
   GNU Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public License
   along with this program. If not, see <https://www.gnu.org/licenses/>.
*/

/* Purpose: apply SWI's ISub scoring to complete codepoint sequences.
   Adapted from packages-nlp dd69ae95342d7a0429a0f8bcc7deab2bd514570e/isub.c.
   See VENDOR.md for the length, normalization and cancellation changes. */
#pragma once
#include <algorithm>
#include <cstdint>
#include <vector>

template <class Check>
double isub_score(std::vector<uint32_t>& s1, std::vector<uint32_t>& s2,
                  size_t threshold, bool zero_to_one, Check& check)
{
    const size_t length1 = s1.size(), length2 = s2.size();
    if (!length1 && !length2) return 1.0;
    if (!length1 || !length2) return 0.0;
    size_t prefix = 0;
    while (prefix < std::min(length1, length2) && s1[prefix] == s2[prefix]) {
        ++prefix;
        check();
    }
    double common = 0.0;
    size_t best = 2;
    while (!s1.empty() && !s2.empty() && best) {
        size_t start1 = 0, end1 = 0, start2 = 0, end2 = 0;
        best = 0;
        for (size_t i = 0; i < s1.size() && s1.size() - i > best; ++i) {
            size_t j = 0;
            while (s2.size() - j > best) {
                size_t k = i;
                while (j < s2.size() && s1[k] != s2[j]) {
                    ++j;
                    check();
                }
                if (j != s2.size()) {
                    const size_t start = j;
                    ++j;
                    ++k;
                    while (j < s2.size() && k < s1.size() && s1[k] == s2[j]) {
                        ++j;
                        ++k;
                        check();
                    }
                    if (k - i > best) {
                        best = k - i;
                        start1 = i;
                        end1 = k;
                        start2 = start;
                        end2 = j;
                    }
                }
                check();
            }
        }
        s1.erase(s1.begin() + start1, s1.begin() + end1);
        s2.erase(s2.begin() + start2, s2.begin() + end2);
        if (best > threshold) common += static_cast<double>(best);
        else best = 0;
        check();
    }
    const double commonality = 2.0 * common / (static_cast<double>(length1) + length2);
    const double unmatched1 = (static_cast<double>(length1) - common) / length1;
    const double unmatched2 = (static_cast<double>(length2) - common) / length2;
    const double sum = unmatched1 + unmatched2, product = unmatched1 * unmatched2;
    const double dissimilarity = sum == product ? 0.0 : product / (0.6 + 0.4 * (sum - product));
    const double prefix_bonus = std::min<size_t>(4, prefix) * 0.1 * (1.0 - commonality);
    const double result = commonality - dissimilarity + prefix_bonus;
    return zero_to_one ? (result + 1.0) / 2.0 : result;
}
