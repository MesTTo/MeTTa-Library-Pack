% Purpose: build a library's native object for the current SWI ABI.
% Guarantees: current objects need no subprocess service; publication is atomic
% and a failed rebuild preserves the previous object
% [tested: test_native_build_is_atomic_and_reused,
% test_warm_native_build_needs_no_process_library; commit=WORKTREE].
% Owns resources: the file lock closes on every exit; cancellation joins the
% compiler before removing its stage
% [tested: test_cancelled_build_waits_for_its_compiler_and_discards_the_stage; commit=WORKTREE].
% Guarded by: an object-path mutex protects threads; build.lock protects processes
% [tested: test_concurrent_processes_and_threads_publish_one_native_object; commit=WORKTREE].

:- module(native_build, [native_object/6]).
:- use_module(library(filesex), [directory_file_path/3, make_directory_path/1]).
:- use_module(library(lists), [append/3]).
:- if(absolute_file_name(library(process), _,
                        [access(read), file_type(prolog), file_errors(fail)])).
:- autoload(library(process), [process_create/3, process_wait/2]).
:- endif.

native_object(Source, Dependencies, Recipe, Stem, Links, Object) :-
    file_directory_name(Recipe, Support),
    directory_file_path(Support, '../.native', Cache),
    current_prolog_flag(arch, Arch),
    current_prolog_flag(version, Version),
    current_prolog_flag(shared_object_extension, Extension),
    format(atom(Name), '~w-~w-~d.~w', [Stem, Arch, Version, Extension]),
    directory_file_path(Cache, Name, Object),
    source_file(native_object(_, _, _, _, _, _), Builder),
    Inputs = [Source, Recipe, Builder|Dependencies],
    with_mutex(Object, ensure_object(Inputs, Links, Cache, Object)).

ensure_object(Inputs, _, _, Object) :- current_object(Inputs, Object), !.
ensure_object(Inputs, Links, Cache, Object) :-
    make_directory_path(Cache),
    directory_file_path(Cache, 'build.lock', Lock),
    setup_call_cleanup(open(Lock, write, Stream, [lock(write)]),
                       build_locked(Inputs, Links, Object),
                       close(Stream)).

current_object(Inputs, Object) :-
    exists_file(Object),
    time_file(Object, Built),
    inputs_older(Inputs, Built).

inputs_older([], _).
inputs_older([Input|Rest], Built) :-
    time_file(Input, Changed),
    Built >= Changed,
    inputs_older(Rest, Built).

build_locked(Inputs, Links, Object) :-
    (   current_object(Inputs, Object)
    ->  true
    ;   current_prolog_flag(pid, PID),
        file_name_extension(Base, Extension, Object),
        format(atom(Stage), '~w-~d.tmp.~w', [Base, PID, Extension]),
        Inputs = [Source|_],
        setup_call_cleanup(true,
                           ( compile_object(Source, Links, Stage),
                             rename_file(Stage, Object) ),
                           remove_stage(Stage))
    ).

compile_object(Source, Links, Stage) :-
    (   absolute_file_name(library(process), Process,
                           [access(read), file_type(prolog), file_errors(fail)])
    ->  use_module(Process, [process_create/3, process_wait/2])
    ;   throw(error(existence_error(library, process),
                    context(native_build:compile_object/3,
                            'Prebuild this object on a host with library(process) and the same SWI ABI before deploying the reduced platform.')))
    ),
    current_prolog_flag(executable, SWI),
    file_directory_name(SWI, Bin),
    file_name_extension(_, Extension, SWI),
    file_name_extension('swipl-ld', Extension, Tool),
    directory_file_path(Bin, Tool, Compiler),
    append(['-shared', '-O2', '-o', Stage, Source], Links, Arguments),
    setup_call_cleanup(
        process_create(Compiler, Arguments, [process(PID)]),
        process_wait(PID, Status),
        ( var(Status) -> process_wait(PID, _) ; true )),
    (   Status == exit(0)
    ->  true
    ;   throw(error(process_error('swipl-ld', Status), _))
    ).

remove_stage(Stage) :-
    ( exists_file(Stage) -> delete_file(Stage) ; true ).
