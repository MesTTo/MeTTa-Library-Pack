% Purpose: run a program with an argument vector, capture what it wrote, and start,
%   watch, signal and wait for one that outlives the call.
%
%   There is no shell here and no string that becomes a command. A program is named
%   and its arguments are a collection, so a file called `; rm -rf /` is an argument
%   and never a second command; that is the difference this library exists to keep
%   [source: lib/lib_system/lib_system.pl's own Fails-when field, which points here;
%   commit=623a2848ef49a936cd82b07adfbed2999d8548a4].
% Assumes:
%   - the program is found on PATH unless the name holds a separator, in which case
%     it is a path. That is the host's own rule, and the refusal for a program that
%     is not there names it [tested: lib_process:a_program_that_is_not_there_is_named;
%     commit=623a2848ef49a936cd82b07adfbed2999d8548a4]
%   - the build has library(process). The `subprocess` capability already in the
%     engine's census is what says so, and the declaration below refuses this library
%     before it loads where it is absent
%     [source: engine/metta.pl:metta_platform_capability/3; commit=623a2848ef49a936cd82b07adfbed2999d8548a4]
% Guarantees:
%   - a nonzero exit is a STATUS and not an error: process-run! answers
%     (process-result Code Output Error) whatever the program exited with, and only a
%     launch that could not happen raises
%     [tested: lib_process:a_nonzero_exit_is_a_status; commit=623a2848ef49a936cd82b07adfbed2999d8548a4]
%   - every stream process-run! opens it closes, on every path, so a program that
%     writes megabytes and one that writes nothing both leave no descriptor behind
%     [tested: lib_process:every_captured_stream_is_closed; commit=623a2848ef49a936cd82b07adfbed2999d8548a4]
%   - a started process is waited for or signalled through its own identifier, and
%     process-status answers without blocking, so a program can poll one and kill it
%     [tested: lib_process:a_started_process_is_watched_and_signalled;
%     commit=623a2848ef49a936cd82b07adfbed2999d8548a4]
% Fails when: a caller wants a pipeline, a pseudo-terminal or a shell's expansion.
%   Those are the shell's own features, and running a shell is the caller's explicit
%   choice: (process-run! "sh" ("-c" "...")) says so in the program's own name.
% Owns resources: process-run! owns the pipes it opens and closes them before it
%   answers. A process process-start! begins is the CALLER's: its streams are this
%   process's own, and it has to be waited for, or the host keeps its exit status
%   until this process ends.
% Decides: a captured run reads both streams to completion before it waits, which is
%   what keeps a program that fills a pipe from deadlocking against a wait that
%   cannot return.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None


:- module(lib_process,
          [ 'process-run!'/3,
            'process-run-input!'/4,
            'process-start!'/3,
            'process-wait!'/2,
            'process-status'/2,
            'process-signal!'/3,
            'process-signals'/1
          ]).

% Guarantees: private helpers and autoload declarations belong to this module.
% [tested: engine_modules; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
% Assumes: engine operations resolve through metta_engine's published exports.
% [source: engine/metta.pl:metta_engine_reexport/2; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
:- set_module(base(metta_engine)).
:- metta_requires(subprocess).

:- use_module(library(lists), [append/3, member/2, memberchk/2]).
:- use_module(library(process), [process_create/3, process_kill/2, process_wait/2,
                                process_wait/3]).
% read_string/3 is a system builtin rather than one of library(readutil)'s exports,
% so importing it warns `not exported (still imported into lib_process)` and nothing
% is gained; the builtin resolves here as it does everywhere.

%! 'process-run!'(+Program:string, +Arguments:list, -Result:list) is det.
%
% Run the program with those arguments, wait for it, and answer
% (process-result Code Output Error): the exit code as a Number, and everything it
% wrote to its two streams as Strings. A nonzero code is a STATUS, because a program
% that ran and failed is not the same as one that could not run; only a launch that
% could not happen raises, naming the program.
%
% The arguments are a collection and never a command line, so nothing in them can
% become a second command. Both streams are read to completion before the wait,
% which is what keeps a program that fills a pipe from deadlocking.
'process-run!'(Program, Arguments, Result) :-
    captured_run('process-run!', Program, Arguments, no_input, Result).

%! 'process-run-input!'(+Program:string, +Arguments:list, +Input:string, -Result:list) is det.
%
% The same, with that text written to the program's standard input and the stream
% closed, which is how a program that reads its input is fed without a temporary
% file.
'process-run-input!'(Program, Arguments, Input, Result) :-
    text_argument('process-run-input!', Input),
    captured_run('process-run-input!', Program, Arguments, input(Input), Result).

captured_run(Head, Program, Arguments, Input, [ 'process-result', Code, Output, Error ]) :-
    executable(Head, Program, Executable),
    argument_vector(Head, Arguments, Vector),
    input_options(Input, InputOptions, Writer),
    append(InputOptions,
           [stdout(pipe(Out)), stderr(pipe(Err)), process(Process)],
           Options),
    % The LAUNCH is the setup, because that is what creates the two pipes: with it
    % anywhere else there is a window in which the descriptors exist and the cleanup
    % that closes them is not installed yet.
    setup_call_cleanup(
        launched(Head, Program, Executable, Vector, Options),
        ( call(Writer),
          read_string(Out, _, Output),
          read_string(Err, _, Error),
          process_wait(Process, Status),
          exit_code(Status, Code) ),
        ( close(Out, [force(true)]), close(Err, [force(true)]) )).

input_options(no_input, [], true).
input_options(input(Text), [stdin(pipe(In))], write_and_close(In, Text)).

write_and_close(Stream, Text) :-
    call_cleanup(format(Stream, '~w', [Text]), close(Stream, [force(true)])).

% A status is an exit code or a signal. A signalled program answers the negative of
% its signal number, which is the convention every shell reports and the one thing a
% single Number can carry; process-status answers the same shape unblocked.
exit_code(exit(Code), Code).
exit_code(killed(Signal), Code) :- Code is -Signal.

%! 'process-start!'(+Program:string, +Arguments:list, -Process:number) is det.
%
% Start the program and answer its identifier without waiting. Its three streams are
% this process's own, so what it writes appears where this program's output does; a
% run whose output matters is process-run!'s job. The caller has to wait for it or
% signal it: until it does, the host keeps the exit status.
'process-start!'(Program, Arguments, Process) :-
    executable('process-start!', Program, Executable),
    argument_vector('process-start!', Arguments, Vector),
    launched('process-start!', Program, Executable, Vector, [process(Process)]).

%! 'process-wait!'(+Process:number, -Code:number) is det.
%
% Wait for the process and answer its exit code, or the negative of the signal that
% ended it. Waiting twice for one process raises, because the host has already
% forgotten it.
'process-wait!'(Process, Code) :-
    process_argument('process-wait!', Process),
    (   catch(process_wait(Process, Status), error(Formal, _),
              throw(error(existence_error(process, Process),
                          context('process-wait!', Formal))))
    ->  exit_code(Status, Code)
    ;   throw(error(existence_error(process, Process),
                    context('process-wait!',
                            'this process has already been waited for, or was never started here')))
    ).

%! 'process-status'(+Process:number, -Status:any) is det.
%
% Whether the process is still running, without waiting for it: the Symbol `running`
% while it is, and its exit code once it is not. This is what a program polls.
'process-status'(Process, Status) :-
    process_argument('process-status', Process),
    (   catch(process_wait(Process, Raw, [timeout(0)]), _, fail)
    ->  (   Raw == timeout
        ->  Status = running
        ;   exit_code(Raw, Status)
        )
    ;   throw(error(existence_error(process, Process),
                    context('process-status',
                            'this process has already been waited for, or was never started here')))
    ).

%! 'process-signal!'(+Process:number, +Signal:'Symbol', -Done:boolean) is det.
%
% Send one of the signals this library names: `term` asks a program to stop, `kill`
% takes it away without asking, `int` is what a terminal's interrupt sends and `hup`
% is what a closed terminal sends. A signal the library does not know is refused with
% the four listed; the process still has to be waited for afterwards.
'process-signal!'(Process, Signal, true) :-
    process_argument('process-signal!', Process),
    (   signal(Signal)
    ->  true
    ;   findall(Known, signal(Known), Signals),
        throw(error(domain_error(process_signal, Signal),
                    context('process-signal!', Signals)))
    ),
    catch(process_kill(Process, Signal), error(Formal, _),
          throw(error(existence_error(process, Process),
                      context('process-signal!', Formal)))).

%! 'process-signals'(-Signals:list) is det.
%
% Every signal process-signal! sends, as data: the same list its refusal names.
'process-signals'(Signals) :-
    findall(Signal, signal(Signal), Signals).

signal(term).
signal(kill).
signal(int).
signal(hup).

% A program with no separator in its name is looked for on PATH, and one with a
% separator is a path: that is the host's own rule, spelled here so a reader does not
% have to guess which it gets [source: SWI-Prolog Reference Manual,
% process_create/3's `path(File)` and plain-path forms].
executable(Head, Program, Executable) :-
    text_argument(Head, Program),
    atom_string(Atom, Program),
    (   sub_atom(Atom, _, _, _, '/')
    ->  Executable = Atom
    ;   Executable = path(Atom)
    ).

argument_vector(Head, Arguments, Vector) :-
    (   is_list(Arguments)
    ->  findall(Text,
                ( member(Argument, Arguments), argument_text(Head, Argument, Text) ),
                Vector)
    ;   throw(error(type_error(list, Arguments),
                    context(Head,
                            'the arguments are a collection, never a command line; a shell is (process-run! "sh" ("-c" "..."))')))
    ).

argument_text(Head, Argument, Text) :-
    (   string(Argument)
    ->  Text = Argument
    ;   atom(Argument)
    ->  atom_string(Argument, Text)
    ;   number(Argument)
    ->  number_string(Argument, Text)
    ;   throw(error(type_error(process_argument, Argument),
                    context(Head, 'an argument is a String, a Symbol or a Number')))
    ).

% A launch that could not happen names the program, where the host raises an
% existence error over its own path term: a caller reads the program's name, not the
% search form it was wrapped in.
launched(Head, Program, Executable, Vector, Options) :-
    catch(process_create(Executable, Vector, Options),
          error(existence_error(source_sink, _), _),
          throw(error(existence_error(program, Program),
                      context(Head,
                              'no such program on PATH, or no such file; a name with a separator is a path')))).

process_argument(Head, Process) :-
    (   integer(Process)
    ->  true
    ;   throw(error(type_error(integer, Process),
                    context(Head, 'a process is the Number process-start! answered')))
    ).

text_argument(Head, Text) :-
    (   ( string(Text) ; atom(Text) )
    ->  true
    ;   throw(error(type_error(string, Text),
                    context(Head, 'the program and the input are strings')))
    ).

:- det('process-run!'/3).
:- det('process-run-input!'/4).
:- det('process-start!'/3).
:- det('process-wait!'/2).
:- det('process-status'/2).
:- det('process-signal!'/3).
:- det('process-signals'/1).
