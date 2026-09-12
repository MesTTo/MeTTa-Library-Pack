/* Purpose: load a private archive reader and run calls with UTF8 name decoding.
 * Assumes: the private callback is a synchronous native archive operation;
 * it does not change the thread's C locale or retain an answer cursor.
 * Guarantees: nested calls restore their caller's locale, including exceptions.
 * [tested: test_archive_locale_restoration; commit=WORKTREE].
 * Owns resources: each C frame restores its locale and frees its duplicate after
 * PL_call_predicate closes the callback query; no locale handles escape.
 * Guarded by: locale changes affect only the calling OS thread.
 * [source: https://pubs.opengroup.org/onlinepubs/9799919799/functions/uselocale.html; commit=WORKTREE].
 * Decides: C.UTF-8 on POSIX, UTF-8 on macOS and .UTF8 on Windows name the
 * required character locale; other locale categories keep their caller's values.
 * Windows uses UCRT's per-thread mode; Linux supplies the runtime test evidence.
 * [source: https://github.com/MicrosoftDocs/cpp-docs/blob/643eebdd20762af785a8f4303dec445d0cd93d2f/docs/c-runtime-library/reference/configthreadlocale.md; commit=WORKTREE].
 */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <SWI-Prolog.h>
#include <locale.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include "../vendor/archive4pl.c"
#ifdef __APPLE__
#include <xlocale.h>
#endif

static int locale_error(const char *operation, int code)
{
    term_t error=PL_new_term_ref();
    if (!PL_unify_term(error,PL_FUNCTOR_CHARS,"error",2,
            PL_FUNCTOR_CHARS,"compression_locale_error",2,PL_CHARS,operation,PL_INT,code,
            PL_FUNCTOR_CHARS,"context",2,PL_CHARS,"lib_compression_native:with_utf8/1",
            PL_CHARS,"Provide a UTF8 character locale: C.UTF-8 on POSIX, UTF-8 on macOS, or a UTF8-capable Windows UCRT."))
        return FALSE;
    return PL_raise_exception(error);
}

/* Workaround: libarchive-utf8-locale - the reader converts Unicode names through
 * its current C character locale before returning wide strings.
 * POSIX ownership follows mpv's archive wrapper; duplicate the caller's other
 * categories instead of replacing them with the C locale.
 * https://github.com/mpv-player/mpv/blob/14f2d48cbc7dda61adb4bd181e107a1f3f76e533/stream/stream_libarchive.c#L322
 */
static foreign_t with_utf8(term_t goal)
{
    module_t context=NULL;
    term_t plain=PL_new_term_ref();
    if (!PL_strip_module(goal,&context,plain)) return FALSE;
#ifdef __WINDOWS__
    int mode=_configthreadlocale(_ENABLE_PER_THREAD_LOCALE);
    if (mode==-1) return locale_error("thread_mode",errno);
    const char *name=setlocale(LC_CTYPE,NULL);
    char *previous=name ? _strdup(name) : NULL;
    if (!previous) {
        _configthreadlocale(mode);
        return PL_resource_error("memory");
    }
    if (!setlocale(LC_CTYPE,".UTF8")) {
        int code=errno;
        free(previous);
        _configthreadlocale(mode);
        return locale_error("UTF8",code);
    }
#else
    locale_t previous=uselocale((locale_t)0);
    locale_t base=duplocale(previous);
    if (!base) return locale_error("duplicate",errno);
#ifdef __APPLE__
    const char *name="UTF-8";
#else
    const char *name="C.UTF-8";
#endif
    locale_t owned=newlocale(LC_CTYPE_MASK,name,base);
    if (!owned) {
        int code=errno;
        freelocale(base);
        return locale_error(name,code);
    }
    if (!uselocale(owned)) {
        int code=errno;
        freelocale(owned);
        return locale_error("activate",code);
    }
#endif
    int result=PL_call_predicate(context,PL_Q_PASS_EXCEPTION,
                                 PL_predicate("call",1,"system"),plain);
#ifdef __WINDOWS__
    setlocale(LC_CTYPE,previous);
    free(previous);
    _configthreadlocale(mode);
#else
    uselocale(previous);
    freelocale(owned);
#endif
    return result;
}

install_t install_lib_compression(void)
{
    install_private_archive();
    PL_register_foreign("with_utf8",1,with_utf8,PL_FA_META,"0");
}
