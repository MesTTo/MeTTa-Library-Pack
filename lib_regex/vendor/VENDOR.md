<!-- Purpose: pin the private PCRE2 binding and record its local changes. -->
# PCRE2 binding source

The binding comes from SWI-Prolog packages-pcre commit
[`52a0e9486c4770f2fbfac3f4fb8a1cd9e8c77af1`](https://github.com/SWI-Prolog/packages-pcre/tree/52a0e9486c4770f2fbfac3f4fb8a1cd9e8c77af1),
the submodule used by SWI-Prolog V10.1.13. Each copied source retains its
upstream BSD license. The linked PCRE2 library remains the host installation.

| Upstream path | Original SHA-256 |
|---|---|
| pcre4pl.c | f7d95e3390bb0476a34b20e3c4a880489d5429a7f6a750c680da7738605a82f6 |
| pcre.pl | 34494125ad875ef79846dd7b1ee029ebb5fd4d0fec2f270f335797a101305566 |
| test_pcre.pl | 5d2a51ebebfdcfb9f4763ffa110995de71f79828309c418cd4802c85dd3ec1ab |
| input/pcre_load.pl | 56ae35470fa7d250582276c7184041da77454475ecc9a69b7f48063782b8ab01 |

The local module is `lib_regex_pcre`, its blob type is `metta_regex`, and its
entry point is `install_metta_pcre`. It does not install global goal expansion
hooks. The stock `library(pcre)` can remain loaded beside it.

The C changes fix end offsets and unset optional groups, return native errors
instead of aborting for unhandled match failures, check match-data allocation,
retain embedded NUL patterns by length, and index character boundaries once
when range projection needs them. Global
iteration follows
[PCRE2 10.46's reference loop](https://github.com/PCRE2Project/pcre2/blob/pcre2-10.46/src/pcre2demo.c),
including empty/nonempty alternatives, UTF-8, CRLF and the backtracking progress
guard. Match data and the boundary index are released after callback failures.
Range conversion uses O(subject bytes + capture count) time and O(subject bytes)
temporary space. Matching and returned values add their own costs. The host
binding rescans prefixes when nested captures revisit earlier positions.
`support/benchmark.pl` compares that case with equal result checksums.

The Prolog changes accept a compiled value for split and replacement, forward
execution options, and distinguish `range(Start,Length)` geometry from
`value(Term)` substitution. Counting requests no capture projection. Regular
capture values retain the upstream suffix rules. The upstream tests change
only their namespace and the end-offset test, which now expects a normal
failed match for dot at the end of the subject.

The loader builds a native object under `lib_regex/.native` on first import.
That directory is ignored by Git and wheel packaging. The build needs a C
compiler, SWI development tools and PCRE2 headers. On Debian/Ubuntu these are
`build-essential`, `swi-prolog-nox` and `libpcre2-dev`. Prebuild before making
an installed runtime read-only:

```sh
swipl -q -s lib/lib_regex/support/native_build.pl \
  -g 'lib_regex_native_build:native_object(_)' -t halt
```

Run from the runtime root, which is the repository root for a source checkout
and `metta/_runtime` in a wheel installation. Rebuilding uses the compiler next
to the active SWI executable, so it targets that installation's ABI. A file
lock serializes processes, a mutex serializes threads, and the completed
object replaces its sibling atomically. An interrupted caller waits for its
compiler before discarding the stage. No process receives a runtime deadline.
