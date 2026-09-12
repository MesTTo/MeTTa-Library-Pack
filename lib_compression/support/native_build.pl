% Purpose: build the private archive reader with the shared atomic builder.
% Guarantees: a failed build raises with a repair and prebuild command.
% [tested: lib_compression; commit=7b42d5ee5cecb82709617b7ed08dfa2c1441f268].
% Owns resources: native_build:native_object/6 owns compiler, stage and locks.
% Each CMake subprocess is joined before its output closes; its temporary tree
% is removed on success, failure and cancellation. Warm objects need no compiler.

:- module(lib_compression_native_build, [native_object/1]).
:- use_module(library(filesex), [directory_file_path/3,delete_directory_and_contents/1]).
:- use_module(library(apply), [maplist/3]).
:- use_module(library(readutil), [read_file_to_string/3]).
:- if(absolute_file_name(library(process),_,[access(read),file_type(prolog),file_errors(fail)])).
:- autoload(library(process), [process_create/3,process_wait/2]).
:- endif.
:- use_module('../../_support/native_build', []).

native_object(Object) :-
    source_file(native_object(_),Recipe),file_directory_name(Recipe,Support),
    directory_file_path(Support,'archive_locale.c',Source),
    directory_file_path(Support,'../vendor',Vendor),
    maplist(directory_file_path(Vendor),
            ['archive4pl.c','config.h','archive.h','archive_entry.h',
             'libarchive-3.8.5.tar.gz','archive_read_support_format_zip.c',
             'lz4/lz4.h','lz4/lz4hc.h'],VendorInputs),
    directory_file_path(Support,'CMakeLists.txt',Project),
    catch(native_build:native_object(Source,[Project|VendorInputs],Recipe,archive_locale,
                                     builder(lib_compression_native_build:compile_archive),Object),Error,
          throw(error(compression_native_build(Error),
              context(lib_compression_native_build:native_object/1,
                  'Install SWI-Prolog development tools, a C compiler, CMake 3.18 or newer, and development files for the required archive codecs (Debian/Ubuntu: build-essential cmake zlib1g-dev libbz2-dev liblzma-dev libzstd-dev liblz4-dev libssl-dev libxml2-dev). The pinned libarchive source is bundled. Give lib_compression/.native write access, then run: swipl -q -s lib/lib_compression/support/native_build.pl -g "lib_compression_native_build:native_object(_)" -t halt. Prebuild with library(process) and the same SWI ABI before deploying a reduced platform.')))).

compile_archive(Source,Stage) :-
    (absolute_file_name(library(process),Process,[access(read),file_type(prolog),file_errors(fail)])
    -> use_module(Process,[process_create/3,process_wait/2])
    ; throw(error(existence_error(library,process),
                   context(compile_archive/2,'Prebuild with library(process) and the same SWI ABI.'))) ),
    current_prolog_flag(executable,SWI),file_directory_name(SWI,Bin),
    file_name_extension(_,Extension,SWI),file_name_extension('swipl-ld',Extension,Tool),
    directory_file_path(Bin,Tool,Compiler),file_directory_name(Source,Support),
    atom_concat('-DSWIPL_LD=',Compiler,CompilerOption),
    atom_concat('-DNATIVE_SOURCE=',Source,SourceOption),
    atom_concat('-DNATIVE_STAGE=',Stage,StageOption),
    current_prolog_flag(cpu_count,CPUs),atom_number(Jobs,CPUs),
    tmp_file(compression_build,Build),
    setup_call_cleanup(make_directory(Build),
        (run_cmake(Build,configure,['--log-level=ERROR','-S',Support,'-B',Build,
                                   CompilerOption,SourceOption,StageOption]),
         run_cmake(Build,compile,['--build',Build,'--target',native_object,'--parallel',Jobs])),
        delete_directory_and_contents(Build)).

run_cmake(Build,Phase,Arguments) :-
    file_name_extension(Phase,log,Name),directory_file_path(Build,Name,Log),
    setup_call_cleanup(open(Log,write,Output,[type(binary)]),
        setup_call_cleanup(process_create(path(cmake),Arguments,
                              [stdout(stream(Output)),stderr(stream(Output)),process(PID)]),
                           process_wait(PID,Status),
                           (var(Status) -> process_wait(PID,_) ; true)),close(Output)),
    read_file_to_string(Log,Text,[]),
    (Status==exit(0) -> format(user_error,'~s',[Text])
    ;throw(error(process_error(cmake,Status),context(Phase,Text)))).
