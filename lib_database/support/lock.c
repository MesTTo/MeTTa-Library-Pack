/* Purpose: claim a store's lock file through its owning SWI stream.
 * Guarantees: separate descriptors compete for one exclusive claim; closing
 * the stream releases it. Native errors retain their OS code.
 * [tested: lib_database; commit=060bea3199e9f504c6d425f60841f229fc96e861].
 * Under emscripten the claim is this file's own table rather than flock(2):
 * that libc's flock() always answers 0, "Pretend that the locking is
 * successful ... Emscripten programs are a single process"
 * [source: emsdk 6.0.9 system/lib/libc/emscripten_libc_stubs.c:flock], which
 * would let a second handle open a store the first still owns. The table
 * gives the same answers Linux gives. The stream that holds a claim may claim
 * again [source: claim_file below, which answers 0 to the claim's owner]; any
 * other stream on the same file is refused with EWOULDBLOCK, and the claim
 * goes when its stream closes [measured 2026-09-24: 42-database_lib.metta ran
 * 84 of 84 forms under tsmetta on the host tools/wasm-host/build.sh built,
 * its second open of a held store refused and its reopen after close
 * accepted; commit=5930ea15c2380f898219c3c89ab7b8a1192e13e6].
 * Assumes: under emscripten the files a claim names belong to this process,
 * which holds for a filesystem the program alone mounts; a directory shared
 * with another process through NODEFS is not claimed against it.
 * Owns resources: borrows and releases the stream lock; the caller owns the
 * descriptor and its lifetime. Under emscripten each claim owns one table
 * entry, freed by the close hook of the stream that made it.
 * Guarded by: PL_get_stream protects the borrowed stream; the OS owns the
 * claim. The emscripten table needs no lock because that host runs one
 * thread (SWI's cmake/port/Emscripten.cmake sets MULTI_THREADED OFF).
 */
#include <SWI-Prolog.h>
#include <SWI-Stream.h>
#ifdef _WIN32
#include <windows.h>
#include <io.h>
#else
#include <sys/file.h>
#include <errno.h>
#endif
#ifdef __EMSCRIPTEN__
#include <stdlib.h>
#include <sys/stat.h>

typedef struct claim
{ struct claim *next;
  dev_t device;
  ino_t inode;
  IOSTREAM *owner;
} claim;

static claim *claims;
static int release_hooked;

/* SWI runs every Sclosehook with the stream it is closing, before freeing it
 * [source: swipl-devel src/os/pl-stream.c:run_close_hooks]. */
static void release_claims(IOSTREAM *stream)
{
    claim **at = &claims;
    while (*at) {
        if ((*at)->owner == stream) {
            claim *gone = *at;
            *at = gone->next;
            free(gone);
        } else
            at = &(*at)->next;
    }
}

/* Time: one pass over the live claims, so O(open stores). */
static int64_t claim_file(int fd, IOSTREAM *owner)
{
    struct stat status;
    if (fstat(fd, &status) != 0) return errno;
    for (claim *held = claims; held; held = held->next)
        if (held->device == status.st_dev && held->inode == status.st_ino)
            return held->owner == owner ? 0 : EWOULDBLOCK;
    if (!release_hooked) {
        if (Sclosehook(release_claims) != 0) return ENOMEM;
        release_hooked = 1;
    }
    claim *made = malloc(sizeof *made);
    if (!made) return ENOMEM;
    made->device = status.st_dev;
    made->inode = status.st_ino;
    made->owner = owner;
    made->next = claims;
    claims = made;
    return 0;
}
#endif

/* File-description ownership matches separate opens, including one process.
 * Linux man-pages 6.19, flock(2), DESCRIPTION; Windows LockFileEx remarks:
 * https://github.com/MicrosoftDocs/sdk-api/blob/554e06be52a53ae819b1011353303a6c72fbdb5d/sdk-api-src/content/fileapi/nf-fileapi-lockfileex.md
 */
static foreign_t claim_stream(term_t input, term_t code)
{
    IOSTREAM *stream;
    if (!PL_get_stream(input, &stream, SIO_OUTPUT)) return false;
    int fd = Sfileno(stream);
    if (fd < 0) {
        if (!PL_release_stream(stream)) return false;
        return PL_domain_error("file_stream", input);
    }
    int64_t result;
#ifdef _WIN32
    OVERLAPPED offset = {0};
    HANDLE file = (HANDLE)_get_osfhandle(fd);
    result = LockFileEx(file, LOCKFILE_EXCLUSIVE_LOCK | LOCKFILE_FAIL_IMMEDIATELY,
                        0, MAXDWORD, MAXDWORD, &offset) ? 0 : GetLastError();
#elif defined(__EMSCRIPTEN__)
    result = claim_file(fd, stream);
#else
    for (;;) {
        if (flock(fd, LOCK_EX | LOCK_NB) == 0) { result = 0; break; }
        result = errno;
        if (result != EINTR) break;
        if (PL_handle_signals() < 0) {
            (void)PL_release_stream(stream);
            return false;
        }
    }
#endif
    if (!PL_release_stream(stream)) return false;
    return PL_unify_int64(code, result);
}

install_t install_lib_database(void)
{
    PL_register_foreign("claim_stream", 2, claim_stream, 0);
}
