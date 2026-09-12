/* Purpose: claim a store's lock file through its owning SWI stream.
 * Guarantees: separate descriptors compete for one exclusive claim; closing
 * the stream releases it. Native errors retain their OS code.
 * [tested: lib_database; commit=WORKTREE].
 * Owns resources: borrows and releases the stream lock; the caller owns the
 * descriptor and its lifetime. No resource is allocated by this adapter.
 * Guarded by: PL_get_stream protects the borrowed stream; the OS owns the claim.
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
