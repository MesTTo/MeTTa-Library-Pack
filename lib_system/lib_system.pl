% Purpose: the environment, the working directory and what the host says about
%   itself, as data a program can read and write.
%
%   An environment variable's name and value are Strings, and the whole environment
%   is a relation of (Name Value) pairs, which is lib_pairs' shape: String keys are
%   also what keeps the relation inert, where a Symbol named like a function would
%   be evaluated where the relation is written
%   [source: docs/journal/2026-09-11-a-standard-library-for-a-language.md, the
%   2026-09-12 markup entry measuring that; commit=WORKTREE].
% Assumes:
%   - a variable that is not set has NO answer rather than an empty String, because
%     unset and empty are different states and a program that defaults one has to
%     be able to tell [tested: lib_system:an_unset_variable_has_no_answer;
%     commit=WORKTREE]
%   - the environment is process-wide. A write is visible to every space and to
%     every child process this one starts, which is the point of writing one, and
%     the library says so rather than pretending otherwise
% Guarantees:
%   - what env-set! writes, env-get answers and env-all holds, and what env-unset!
%     removes has no answer again
%     [tested: lib_system:a_write_is_visible_to_every_reader; commit=WORKTREE]
%   - platform-info answers what the host's own flags say, and an unknown key is
%     refused with every key listed, so a typo is not an absent platform
%     [tested: lib_system:platform_info_is_the_hosts_own_flags; commit=WORKTREE]
% Fails when: a caller wants a shell. There is no head here that hands text to a
%   shell to interpret: lib_process runs an executable with an argument vector,
%   which is the difference between running a program and letting a string become
%   one.
% Owns resources: the environment and the working directory are the PROCESS's, and
%   a write to either outlives the space that made it. Nothing here opens a handle.
% Decides: the working directory is read and changed here rather than in lib_file,
%   because it is a property of the process and not of a path; lib_file's own
%   operations take the paths a program computes from it.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None


:- module(lib_system,
          [ 'env-get'/2,
            'env-all'/1,
            'env-set!'/3,
            'env-unset!'/2,
            'platform-info'/2,
            'platform-keys'/1,
            'working-directory'/1,
            'change-directory!'/2
          ]).

% Guarantees: private helpers and autoload declarations belong to this module.
% [tested: engine_modules; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
% Assumes: engine operations resolve through metta_engine's published exports.
% [source: engine/metta.pl:metta_engine_reexport/2; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
:- set_module(base(metta_engine)).

:- use_module(library(error), [must_be/2]).
:- use_module(library(lists), [member/2, memberchk/2]).
% environ/1 is library(unix)'s, which is SWI's ext/clib pack and absent from a wasm
% build, and it is the only way to enumerate the whole environment: getenv/2
% answers one variable a caller can already name. The census load records the
% absence rather than leaving the call to the autoloader, and env-all refuses by
% name where the capability is lost [source: engine/metta.pl:metta_platform_load/2;
% commit=WORKTREE].
:- metta_platform_load('environment-listing', [environ/1]).

%! 'env-get'(+Name:string, -Value:string) is semidet.
%
% One environment variable's value, with NO answer when it is not set: unset and
% empty are different states, and a program that defaults one has to be able to
% tell. A collapse over this is the presence test, and if-empty over the collapse
% is the default.
'env-get'(Name, Value) :-
    name_argument('env-get', Name),
    atom_string(Atom, Name),
    getenv(Atom, Raw),
    atom_string(Raw, Value).

%! 'env-all'(-Variables:list) is det.
%
% The whole environment as a relation of (Name Value) pairs, names and values both
% Strings, in the order the host reports. This is lib_pairs' shape, so pairs-lookup
% and pairs-sort-by-key answer over it.
'env-all'(Variables) :-
    (   current_predicate(environ/1)
    ->  true
    ;   metta_require_platform('env-all', 'environment-listing')
    ),
    environ(Pairs),
    findall([Name, Value],
            ( member(Raw = RawValue, Pairs),
              atom_string(Raw, Name),
              atom_string(RawValue, Value) ),
            Variables).

%! 'env-set!'(+Name:string, +Value:string, -Done:boolean) is det.
%
% Set the variable for this PROCESS: every space sees it and so does every child
% process started afterwards. Answers True, because a set that failed raises.
'env-set!'(Name, Value, true) :-
    name_argument('env-set!', Name),
    value_argument('env-set!', Value),
    atom_string(NameAtom, Name),
    atom_string(ValueAtom, Value),
    setenv(NameAtom, ValueAtom).

%! 'env-unset!'(+Name:string, -Done:boolean) is det.
%
% Remove the variable from this process. Removing one that is not set is silent,
% because a cleanup path should not have to check first.
'env-unset!'(Name, true) :-
    name_argument('env-unset!', Name),
    atom_string(Atom, Name),
    unsetenv(Atom).

%! 'platform-info'(+Key:'Symbol', -Value:any) is semidet.
%
% What the host says about itself: the architecture, the operating-system family,
% the SWI-Prolog version as a String and as its three numbers, this process's
% identifier, how many cores the host reports, whether integers are bounded, and the
% executable and home directory of the running system. The host NAME is not among
% them: gethostname/1 is library(socket)'s, and a whole network library is too much
% to link for one string. A key the
% library does not know is refused with every key listed, because a typo would
% otherwise read as a platform that does not have it.
'platform-info'(Key, Value) :-
    (   platform_key(Key)
    ->  platform_value(Key, Value)
    ;   findall(Known, platform_key(Known), Keys),
        throw(error(domain_error(platform_key, Key),
                    context('platform-info', Keys)))
    ).

%! 'platform-keys'(-Keys:list) is det.
%
% Every key platform-info answers for, as data: the same list its refusal names.
'platform-keys'(Keys) :-
    findall(Key, platform_key(Key), Keys).

platform_key(architecture).
platform_key(family).
platform_key(version).
platform_key('version-numbers').
platform_key(dialect).
platform_key(pid).
platform_key(cores).
platform_key('bounded-integers').
platform_key(executable).
platform_key('prolog-home').

% Each value from the host's own flag or predicate, converted to a MeTTa value: a
% String for text, a Number for a count, a Bool for a yes-or-no
% [source: SWI-Prolog Reference Manual, current_prolog_flag/2].
platform_value(architecture, Value) :-
    current_prolog_flag(arch, Atom), atom_string(Atom, Value).
platform_value(family, Value) :-
    (   current_prolog_flag(windows, true) -> Value = "windows"
    ;   current_prolog_flag(apple, true) -> Value = "apple"
    ;   current_prolog_flag(unix, true) -> Value = "unix"
    ;   Value = "unknown"
    ).
platform_value(version, Value) :-
    current_prolog_flag(version_data, swi(Major, Minor, Patch, _)),
    format(atom(Atom), '~w.~w.~w', [Major, Minor, Patch]),
    atom_string(Atom, Value).
platform_value('version-numbers', [Major, Minor, Patch]) :-
    current_prolog_flag(version_data, swi(Major, Minor, Patch, _)).
platform_value(dialect, Value) :-
    current_prolog_flag(dialect, Atom), atom_string(Atom, Value).
platform_value(pid, Value) :-
    current_prolog_flag(pid, Value).
platform_value(cores, Value) :-
    current_prolog_flag(cpu_count, Value).
platform_value('bounded-integers', Value) :-
    current_prolog_flag(bounded, Value).
platform_value(executable, Value) :-
    current_prolog_flag(executable, Atom), atom_string(Atom, Value).
platform_value('prolog-home', Value) :-
    current_prolog_flag(home, Atom), atom_string(Atom, Value).

%! 'working-directory'(-Path:string) is det.
%
% The process's current directory, as an absolute path with no trailing separator.
% Every relative path a program writes is read against this one.
'working-directory'(Path) :-
    working_directory(Raw, Raw),
    atom_string(Raw, WithSeparator),
    (   string_concat(Without, "/", WithSeparator), Without \== ""
    ->  Path = Without
    ;   Path = WithSeparator
    ).

%! 'change-directory!'(+Path:string, -Done:boolean) is det.
%
% Change the process's current directory. This is process-wide, like the
% environment: every space and every later relative path sees it. A path that is not
% a directory raises, naming it.
'change-directory!'(Path, true) :-
    name_argument('change-directory!', Path),
    atom_string(Atom, Path),
    (   exists_directory(Atom)
    ->  working_directory(_, Atom)
    ;   throw(error(existence_error(directory, Path),
                    context('change-directory!',
                            'the path is not a directory this process can enter')))
    ).

name_argument(Head, Name) :-
    (   ( string(Name) ; atom(Name) )
    ->  true
    ;   throw(error(type_error(string, Name),
                    context(Head, 'the name is a string')))
    ).

value_argument(Head, Value) :-
    (   ( string(Value) ; atom(Value) ; number(Value) )
    ->  true
    ;   throw(error(type_error(string, Value),
                    context(Head, 'the value is a string')))
    ).

:- det('env-all'/1).
:- det('env-set!'/3).
:- det('env-unset!'/2).
:- det('platform-keys'/1).
:- det('working-directory'/1).
:- det('change-directory!'/2).
