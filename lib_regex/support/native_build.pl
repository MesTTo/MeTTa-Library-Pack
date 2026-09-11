% Purpose: build and locate lib_regex's private PCRE2 binding.
% Guarantees: a successful build replaces the object atomically; failed builds
% leave no stage and preserve an existing object
% [tested: test_native_build_is_atomic_and_reused; commit=WORKTREE].
% Owns resources: the file lock closes on every exit. An interrupted caller
% waits for its compiler before removing the temporary object
% [tested: test_cancelled_build_waits_for_its_compiler_and_discards_the_stage; commit=WORKTREE].
% Guarded by: lib_regex_native_build serializes threads; build.lock serializes
% processes sharing the same library directory
% [tested: test_concurrent_processes_and_threads_publish_one_native_object; commit=WORKTREE].
% Decides: the native object is local to the library and host SWI ABI
% [source: lib/lib_regex/support/native_build.pl:native_object; commit=WORKTREE].

:- module(lib_regex_native_build, [native_object/1]).
:- use_module(library(filesex), [directory_file_path/3, make_directory_path/1]).
:- use_module(library(process), [process_create/3, process_wait/2]).

native_object(Object) :-
    source_file(native_object(_), Recipe),
    file_directory_name(Recipe, Support),
    directory_file_path(Support, '../vendor/pcre4pl.c', Source),
    directory_file_path(Support, '../.native', Cache),
    current_prolog_flag(arch, Arch),
    current_prolog_flag(version, Version),
    current_prolog_flag(shared_object_extension, Extension),
    format(atom(Name), 'pcre-~w-~d.~w', [Arch, Version, Extension]),
    directory_file_path(Cache, Name, Object),
    catch(with_mutex(lib_regex_native_build,
                     ensure_object(Source, Recipe, Cache, Object)),
          Error,
          throw(error(regex_native_build(Error),
                      context(lib_regex_native_build:native_object/1,
                              'Install SWI-Prolog development tools, a C compiler and PCRE2 development headers (Debian/Ubuntu: build-essential swi-prolog-nox libpcre2-dev). Give the library .native directory write access, then run: swipl -q -s lib/lib_regex/support/native_build.pl -g "lib_regex_native_build:native_object(_)" -t halt')))).

ensure_object(Source, Recipe, _, Object) :-
    current_object(Source, Recipe, Object),
    !.
ensure_object(Source, Recipe, Cache, Object) :-
    make_directory_path(Cache),
    directory_file_path(Cache, 'build.lock', Lock),
    setup_call_cleanup(open(Lock, write, Stream, [lock(write)]),
                       build_locked(Source, Recipe, Object),
                       close(Stream)).

current_object(Source, Recipe, Object) :-
    exists_file(Object),
    time_file(Object, Built),
    time_file(Source, Changed),
    time_file(Recipe, RecipeChanged),
    Built >= max(Changed, RecipeChanged).

build_locked(Source, Recipe, Object) :-
    (   current_object(Source, Recipe, Object)
    ->  true
    ;   current_prolog_flag(pid, PID),
        file_name_extension(Base, Extension, Object),
        format(atom(Stage), '~w-~d.tmp.~w', [Base, PID, Extension]),
        setup_call_cleanup(true,
                           ( compile_object(Source, Stage),
                             rename_file(Stage, Object) ),
                           remove_stage(Stage))
    ).

compile_object(Source, Stage) :-
    current_prolog_flag(executable, SWI),
    file_directory_name(SWI, Bin),
    file_name_extension(_, Extension, SWI),
    file_name_extension('swipl-ld', Extension, Tool),
    directory_file_path(Bin, Tool, Compiler),
    setup_call_cleanup(
        process_create(Compiler,
                       ['-shared', '-O2', '-o', Stage, Source, '-lpcre2-8'],
                       [process(PID)]),
        process_wait(PID, Status),
        ( var(Status) -> process_wait(PID, _) ; true )),
    (   Status == exit(0)
    ->  true
    ;   throw(error(process_error('swipl-ld', Status), _))
    ).

remove_stage(Stage) :-
    ( exists_file(Stage) -> delete_file(Stage) ; true ).
