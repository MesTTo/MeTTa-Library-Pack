# String providers

The private String object builds from source for the installed SWI ABI.
It contains the adapters in `../support/string_native.cpp` and the sources below.
`SHA256SUMS` identifies the distributed provider files. No prebuilt object ships.

| Provider | Pinned source | License and changes |
|---|---|---|
| RapidFuzz C++ v3.3.4 | [82662f3623b3ca3645e543f677fc32fb8bd1fb95](https://github.com/rapidfuzz/rapidfuzz-cpp/tree/82662f3623b3ca3645e543f677fc32fb8bd1fb95) | MIT, reproduced in `RAPIDFUZZ-LICENSE`. The 21-header transitive include closure of `distance/Levenshtein.hpp` includes relative SIMD headers. Three files have normalized final newlines; algorithm text is unchanged. |
| KMP prefix fallback | [Boost 1.89.0](https://github.com/boostorg/algorithm/blob/boost-1.89.0/include/boost/algorithm/searching/knuth_morris_pratt.hpp) | Boost Software License 1.0, reproduced in `BOOST-LICENSE`. The adapter uses size_t prefix lengths, owns its pattern, emits overlapping or nonoverlapping matches during one scan, and checks pending signals. |
| Character-set splitting | [SWI 10.1.13 pl-string.c](https://github.com/SWI-Prolog/swipl-devel/blob/fc7ef84b949378b729052c3ade79c90ce5416abb/src/pl-string.c) | BSD, reproduced in `SWI-LICENSE`. The scan uses length-aware set membership and never reads a terminator as an input character. |
| Line and indentation utilities | [SWI 10.1.13 strings.pl](https://github.com/SWI-Prolog/swipl-devel/blob/fc7ef84b949378b729052c3ade79c90ce5416abb/library/strings.pl) | The source's BSD license is retained in `string_lines.pl`. The selected line/indentation predicates have a private module and call the corrected splitter. Dedent always empties blank lines, including when the common prefix is empty or shorter than the blank line. Quasiquotations, interpolation and sandbox hooks remain in the host. |
| ISub | [packages-nlp dd69ae95342d7a0429a0f8bcc7deab2bd514570e](https://github.com/SWI-Prolog/packages-nlp/blob/dd69ae95342d7a0429a0f8bcc7deab2bd514570e/isub.c) | LGPL-2.0-or-later, retained in `isub.hpp` and `LGPL-2.0`. The adaptation owns codepoint vectors, uses size_t lengths, preserves NUL, checks signals and computes length sums in floating point. The wrapper normalizes with the existing host lowercase operation. Substring selection and scoring retain the upstream algorithm. |

The ISub adaptation's source and license accompany its shared object so it can
be modified and rebuilt. Consumers load the shared object dynamically. Replace
or rebuild it through `../support/native_build.pl`; its cache watches every
vendor header, the adapter, recipe and shared builder. A changed or missing
input cannot silently reuse the old object.

RapidFuzz receives explicit uint32 iterator ranges, unit edit costs and no score
cutoff. It does not receive NUL-terminated convenience pointers. The adapter
checks signals before and after its synchronous distance calculation. Owned
search, conversion, splitting and ISub loops also check while walking.

Source distributions and wheels include these files and licenses. First use
requires SWI development tools and a C++11 compiler. To prebuild for a reduced
platform, use the same SWI ABI on a host with `library(process)`:

```sh
swipl -q -s lib/lib_string/support/native_build.pl \
  -g 'lib_string_native_build:native_object(_)' -t halt
```
