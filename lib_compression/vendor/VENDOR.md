<!-- Purpose: pin the private archive binding, public headers and local changes. -->
# Archive binding sources

The binding is SWI-Prolog packages-archive
[`13a3f4af8f8219e10faf4895ce9fb189bc6aaefd`](https://github.com/SWI-Prolog/packages-archive/tree/13a3f4af8f8219e10faf4895ce9fb189bc6aaefd).
The public headers are libarchive 3.8.5 at
[`dd897a78c662a2c7a003e7ec158cea7909557bee`](https://github.com/libarchive/libarchive/tree/dd897a78c662a2c7a003e7ec158cea7909557bee).
Copied files retain their upstream licenses. The archive provider is built
privately from that pinned source snapshot and the ZIP source correction below.
LZ4's public headers come from version 1.10.0 at
[`ebb370ca83af193212df4dcbadcc5d87bc0de2f0`](https://github.com/lz4/lz4/tree/ebb370ca83af193212df4dcbadcc5d87bc0de2f0).
They permit linking an installed LZ4 runtime when development headers are absent;
installed headers take precedence.

| Upstream path | Original SHA-256 |
|---|---|
| archive4pl.c | d7adeeec46544440d949283f95653faa18b0e5fe5c7b179c406977b52baf6b43 |
| libarchive/archive.h | 2602e11644bbaa3281e32e33d5d92a6f1073c05083f6bba891ab35d00ebbb559 |
| libarchive/archive_entry.h | d7704746628f8147845fb5cae6619a2673d55f17ee23904971803c230d3d4c5b |
| libarchive source archive at the pinned commit | 8b3e4d4ac48fe36d0ef45d01ab1f740a247b4383a4c7c1dfdd565cfa7107af66 |
| libarchive/archive_read_support_format_zip.c | eb3301360a3c3d1f54bdf70746a3da2dda434e57e6cce0e81130677f28f3d595 |
| lib/lz4.h | 26b82efc53d1570f3b54eef02e9c4764c1ad374ff03cac04e2ced5ea4d4c552f |
| lib/lz4hc.h | e43824e8a9ba16f54100c4ccbccfa5782a858ca9ab83c48aac303fea3e76e21e |

The private module is `lib_compression_native` and its blob type is
`metta_compression_archive`; the system archive module can remain loaded.
An empty owner is acquired before opening the native reader. Cleanup consumes
partial acquisition and releases the borrowed parent exactly once. The enclosing
Prolog scope owns any parent file. Close errors are reported after their consumed
native object has been invalidated.

ZIP readers explicitly select CP437 for unflagged names, as specified by
[PKWARE APPNOTE 6.3.10, D.1-D.2](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT).
The corrected ZIP source saves the original filename CRC before converting its
characters, then checks Unicode extra fields against those original bytes.
UTF8 flags and valid extra fields retain precedence; stale fields and payload
CRC errors remain checked. The binding refuses a null wide pathname before the
SWI string API. Each correction has an independent host reproduction in
`docs/host-workarounds.md`.
The surrounding locale adapter selects a thread-local UTF8 character locale
and restores it after archive cleanup. Gzip validation remains in the Prolog
layer because libarchive omits its trailer checks.

The shared native builder tracks the CMake recipe, binding, headers, source
snapshot and corrected ZIP source. CMake verifies the snapshot checksum before
extracting it into an owned temporary build tree. The static provider's symbols
are hidden; only `install_lib_compression` is exported by the resulting Linux
object. The host's `library(archive)` keeps its own provider and blob type.

CMake 3.18 or newer, a C compiler, SWI development tools and development files
for the required codecs are needed. On Debian/Ubuntu these include
`build-essential cmake zlib1g-dev libbz2-dev liblzma-dev libzstd-dev liblz4-dev
libssl-dev libxml2-dev`. The native provider detects codecs through its existing
CMake configuration. Prebuild from the runtime root before deploying a read-only
installation:

```sh
swipl -q -s lib/lib_compression/support/native_build.pl \
  -g 'lib_compression_native_build:native_object(_)' -t halt
```

The cache is local to `lib_compression/.native` and the active SWI ABI. The
shared builder serializes threads and processes and publishes a complete object
atomically. Its qualified build callback joins each CMake process before closing
its output and removing the temporary build tree. The final binding is linked by
`swipl-ld` beside the active interpreter. A warm object needs no CMake or compiler.
Linux supplies the runtime verification; Windows and macOS locale paths have
source checks but have not run on those operating systems.
