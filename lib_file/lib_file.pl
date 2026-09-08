% Purpose: file input and output, MeTTa HE's surface. Before this the whole of
%   it was exists_file, so a program could ask whether a file was there and
%   nothing else.
%
%   The names, argument order and option letters are HE's, because HE already
%   specified this and the fallback rule says an unexplored area takes HE's
%   answer [source 2026-08-15: MeTTa HE stdlib, File Input/Output].
% Assumes:
%   - a MeTTa string is an SWI string, so paths and contents cross as strings
%     [verified 2026-08-15, see lib_string.pl]
% Guarantees:
%   - a handle is a small integer, so it prints, compares and crosses the [tested: lib_file:the_handle_surface_reads_and_seeks]
%     Python boundary as an ordinary MeTTa value rather than as a blob
%   - every operation on an unknown or closed handle raises an existence error
%     naming the handle, rather than failing silently [tested: lib_file:using_a_closed_handle_raises]
%   - file-open! refuses a contradictory option set loudly, HE's own rule:
%     'c' demands 'w', so "rc" is an error rather than a silent read [tested: lib_file:create_without_write_is_refused, an_unknown_option_letter_is_refused]
%   - the HE file-mode alphabet is explicitly recorded as a language
%     mechanism rather than mistaken for an undeclared engine policy [tested:
%     test_a_planted_closed_policy_list_is_reported_by_the_inventory_lane;
%     commit=42b5d28232e75c32b20a1d5bf1f740fec134938d].
% Fails when:
%   - the file is missing and the options do not say to create it. That is an
%     error, not a failure, so it cannot be mistaken for an empty file.
% Owns:
%   - one open stream per handle, until file-close! releases it. HE's stdlib
%     lists no close operation; leaving a process to leak descriptors is not
%     something to copy, so file-close! is added and documented as an addition.
% Guarded by:
%   - '$metta_files' serialises handle allocation and the handle table.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: reading a file as a SPACE of lines, so it is matchable
%     rather than a single string, is tracked in ai-todo-language-completeness
%     section 2.4.


:- module(lib_file,
          [ 'append-file!'/3,
            'copy-file!'/3,
            'delete-dir!'/2,
            'delete-file!'/2,
            'dir-exists'/2,
            'exit!'/2,
            'file-close!'/2,
            'file-exists'/2,
            'file-get-size!'/2,
            'file-lines!'/2,
            'file-metadata!'/2,
            'file-open!'/3,
            'file-read-exact!'/3,
            'file-read-to-string!'/2,
            'file-seek!'/3,
            'file-space!'/2,
            'file-write!'/3,
            'list-dir!'/2,
            'make-dir!'/2,
            'path-extension'/2,
            'path-join'/3,
            'path-name'/2,
            'path-parent'/2,
            'read-file!'/2,
            'stderr!'/2,
            'stdin-to-string!'/1,
            'temp-dir!'/2,
            'temp-path!'/2,
            'write-file!'/3,
            stderr/1,
            stdin/1,
            stdout/1
          ]).

% Guarantees: private helpers and autoload declarations belong to this module.
% [tested: engine_modules; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
% Assumes: engine operations resolve through metta_engine's published exports.
% [source: engine/metta.pl:metta_engine_reexport/2; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
:- set_module(base(metta_engine)).

:- use_module(library(lists)).
:- use_module(library(filesex)).

:- dynamic metta_file/2.            % Handle, Stream
%The counter is a FLAG rather than a dynamic fact, and the difference is a
%WRONG ANSWER rather than a style. A fact is source, and importing this
%library into a SECOND space consults the file again, which put the counter
%back to zero and made the next mint hand out a name that was already in use:
%`(dict-space ((a 1) (b 2)))` in a second space answered a size of four,
%because it had added its two entries on top of the first dict's two in
%`&json-1` [tested: test_a_dict_is_a_space_a_comprehension_can_build;
%commit=657ae9672c07b628f8a20c7fe39aa43e58b0014f]. A flag lives outside the source, so re-loading cannot
%reset it, and its update is atomic, which is the whole of what the mutex was
%for [source: SWI-Prolog 10.1 Reference Manual, flag/3, "The update is
%atomic. This predicate can be used to create a shared global counter"].
% POSIX's own numbering, taken rather than invented: 0 is standard input, 1
% standard output and 2 standard error, in this table and in every process this
% engine runs in. So the handle surface that already reads, writes and measures
% a file reaches the three streams as well, and (file-read-to-string! (stdin))
% is the longhand stdin-to-string! is the short spelling of. The alias atoms
% ARE the streams: every SWI predicate that takes a stream takes an alias.
%
% These are a second SPELLING, not a second mechanism. stderr! and
% stdin-to-string! stay the way to write a diagnostic and read the input; the
% handles are what lets file-read-exact!, file-write! and file-get-size! reach
% the same three streams without a further operation each.
metta_file(0, user_input).
metta_file(1, user_output).
metta_file(2, user_error).

% Facts rather than one predicate over a list, because the numbering is POSIX's
% rather than a choice this engine makes, and three facts keep it out of the
% closed-policy scan.
standard_stream(0, stdin).
standard_stream(1, stdout).
standard_stream(2, stderr).

'stdin'(0).
'stdout'(1).
'stderr'(2).

% Minting starts at 3 because 0, 1 and 2 are taken, exactly as they are in a
% process. Nothing pins a particular handle number: every caller binds whatever
% file-open! answers.
next_file_handle(Handle) :-
    flag('$metta_file_handle', Previous, Previous + 1),
    Handle is Previous + 3.

known_file(Handle, Stream) :-
    (   metta_file(Handle, Stream)
    ->  true
    ;   existence_error(metta_file_handle, Handle)
    ).

%HE's option letters: r read, w write, c create if absent, a append,
%t truncate. 'c' demands 'w', which is why "rc" is refused rather than
%quietly opening for reading.
'file-open!'(Path, Options, Handle) :-
    metta_text(Path, PathText),
    metta_text(Options, OptionText),
    string_chars(OptionText, Letters),
    % policy-inventory-exempt: mechanism-internal; reason=r w c a and t are the fixed HE file-mode instruction alphabet; evidence=lib/lib_file/lib_file.pl:file-open!/3
    (   forall(member(Letter, Letters), memberchk(Letter, [r, w, c, a, t]))
    ->  true
    ;   throw(error(domain_error(file_open_options, Options),
                    context('file-open!'/2, 'options are drawn from r w c a t')))
    ),
    (   memberchk(c, Letters), \+ memberchk(w, Letters), \+ memberchk(a, Letters)
    ->  throw(error(domain_error(file_open_options, Options),
                    context('file-open!'/2, 'c demands w or a')))
    ;   true
    ),
    file_open_mode(Letters, Mode),
    (   Mode == read, \+ exists_file(PathText)
    ->  existence_error(source_sink, PathText)
    ;   true
    ),
    open(PathText, Mode, Stream, [encoding(utf8)]),
    next_file_handle(Handle),
    with_mutex('$metta_files', assertz(metta_file(Handle, Stream))).

%append wins over write because a caller asking for both means "add to it",
%and read plus write is SWI's update mode, which keeps the existing content.
file_open_mode(Letters, Mode) :-
    (   memberchk(a, Letters)
    ->  Mode = append
    ;   memberchk(w, Letters), memberchk(r, Letters), \+ memberchk(t, Letters)
    ->  Mode = update
    ;   memberchk(w, Letters)
    ->  Mode = write
    ;   Mode = read
    ).

'file-read-to-string!'(Handle, Content) :-
    known_file(Handle, Stream),
    read_string(Stream, _, Content).

%Reads AT MOST Count characters, HE's contract: a short read near the end of
%the file is the answer, not an error.
'file-read-exact!'(Handle, Count, Content) :-
    known_file(Handle, Stream),
    must_be(integer, Count),
    Wanted is max(0, Count),
    read_string(Stream, Wanted, Content).

'file-write!'(Handle, Content, true) :-
    known_file(Handle, Stream),
    metta_text(Content, Text),
    write(Stream, Text),
    flush_output(Stream).

'file-seek!'(Handle, Position, true) :-
    known_file(Handle, Stream),
    must_be(integer, Position),
    Target is max(0, Position),
    seek(Stream, Target, bof, _).

%The size of the FILE, not of what is left to read, so seeking does not change
%the answer. Falls back to measuring the stream when the handle has no name.
'file-get-size!'(Handle, Size) :-
    known_file(Handle, Stream),
    (   stream_property(Stream, file_name(Name)),
        exists_file(Name)
    ->  size_file(Name, Size)
    ;   stream_property(Stream, position(Position)),
        stream_position_data(char_count, Position, Size)
    ).

%Not in HE's stdlib. A process that can open files and never close them leaks
%descriptors until it dies, so this exists; closing twice is not an error,
%because a cleanup path should not have to check first.
%
% A standard stream is REFUSED rather than closed. Closing 1 or 2 takes stdout
% or stderr away from everything else in the process, the engine's own
% diagnostics included, and there is no way to put it back; a cleanup loop over
% every handle it has seen would do it by accident. So the one case where
% "closing twice is not an error" would be a disaster is the one case this says
% no to.
'file-close!'(Handle, _) :-
    standard_stream(Handle, Name),
    !,
    throw(error('standard-stream-not-closable'('file-close!', Name),
                context('file-close!',
                        'The process owns it; close a stream file-open! gave you'))).
'file-close!'(Handle, true) :-
    (   metta_file(Handle, Stream)
    ->  with_mutex('$metta_files', retractall(metta_file(Handle, _))),
        catch(close(Stream), _, true)
    ;   true
    ).

%Read a whole file without the open/close dance, which is what most callers
%actually want. Not HE's, and named so it cannot be mistaken for HE's.
'read-file!'(Path, Content) :-
    metta_text(Path, PathText),
    (   exists_file(PathText)
    ->  true
    ;   existence_error(source_sink, PathText)
    ),
    setup_call_cleanup(open(PathText, read, Stream, [encoding(utf8)]),
                       read_string(Stream, _, Content),
                       close(Stream)).

'write-file!'(Path, Content, true) :-
    metta_text(Path, PathText),
    metta_text(Content, Text),
    setup_call_cleanup(open(PathText, write, Stream, [encoding(utf8)]),
                       write(Stream, Text),
                       close(Stream)).

'append-file!'(Path, Content, true) :-
    metta_text(Path, PathText),
    metta_text(Content, Text),
    setup_call_cleanup(open(PathText, append, Stream, [encoding(utf8)]),
                       write(Stream, Text),
                       close(Stream)).

%The lines of a file, as an expression of strings. The MeTTa-native form,
%reading a file as a SPACE so it is matchable, is section 2.4 of the language
%todo and builds on this.
'file-lines!'(Path, Lines) :-
    'read-file!'(Path, Content),
    split_string(Content, "\n", "", Raw),
    drop_trailing_empty(Raw, Lines).

drop_trailing_empty(Lines, Kept) :-
    (   append(Front, [""], Lines)
    ->  Kept = Front
    ;   Kept = Lines
    ).

%A file as a SPACE, which is the mettafied reading of reading a file: its
%lines become (line Number Text) atoms, so the file is queryable with match
%instead of being one long string you then have to take apart.
%
%    (let $log (file-space! "app.log")
%      (match $log (line $n $text) ($n $text)))
%
%The line number is kept because a space is unordered, and losing which line
%came first would make the space strictly less useful than the string it
%replaced.
'file-space!'(Path, Space) :-
    'file-lines!'(Path, Lines),
    next_file_handle(Number),
    atom_concat('&file-', Number, Space),
    forall(nth1(Index, Lines, Text),
           'add-atom'(Space, [line, Index, Text], _)).

%A unique fresh path in the system temporary directory, mkstemp-grade:
%tmp_file_stream/3 creates the file exclusively, which is what makes the
%name safe against a concurrent runner minting at the same moment, and the
%caller owns the file from that point (write-file! truncates it, delete-file!
%ends it). The shipped text example uses it so two checkouts running the
%corpus at once cannot collide on a fixed name
%[tested: examples/ch08-data/08-03-the-shipped-libraries/03-text_lib.metta].
'temp-path!'(Prefix, PathString) :-
    metta_text(Prefix, PrefixText),
    tmp_file_stream(Path, Stream, [encoding(utf8), extension(txt)]),
    close(Stream),
    file_directory_name(Path, Dir),
    file_base_name(Path, Base),
    atomic_list_concat([Dir, '/', PrefixText, '-', Base], Unique),
    rename_file(Path, Unique),
    atom_string(Unique, PathString).

% A fresh DIRECTORY, the twin of temp-path!'s fresh file. Without it a caller
% who wants somewhere to put files derives a directory name from a temporary
% FILE name, which is what the shipped example does with
% (string-join "" (&seed "-directory")).
%
% make_directory/1 is the exclusive act here, as tmp_file_stream/3's exclusive
% create is for temp-path!: tmp_file/2 supplies a name and creates nothing, and
% mkdir refuses a name that is already taken, so two runners cannot both
% believe they own the directory.
%
% A prefix NAMES the directory and does not place it. tmp_file/2 pastes it into
% the path without sanitising, so tmp_file('../x', P) answers
% '/tmp/swipl_../x_PID_N', a path outside the temporary directory
% [measured 2026-09-05]. A separator is refused here rather than acted on.
'temp-dir!'(Prefix, PathString) :-
    metta_text(Prefix, PrefixText),
    (   sub_string(PrefixText, _, _, _, "/")
    ->  throw(error('file-name-not-a-path'('temp-dir!', PrefixText),
                    context('temp-dir!',
                            'Name the directory without a separator and place it with path-join')))
    ;   true
    ),
    atom_string(PrefixAtom, PrefixText),
    catch(( tmp_file(PrefixAtom, Path), make_directory(Path) ), Error,
          metta_file_refusal('temp-dir!', Error)),
    atom_string(Path, PathString).

'delete-file!'(Path, true) :-
    metta_text(Path, PathText),
    (   exists_file(PathText)
    ->  delete_file(PathText)
    ;   true
    ).

'list-dir!'(Path, Entries) :-
    metta_text(Path, PathText),
    (   exists_directory(PathText)
    ->  true
    ;   existence_error(directory, PathText)
    ),
    directory_files(PathText, Raw),
    exclude(dot_entry, Raw, Kept),
    maplist(entry_to_string, Kept, Entries).

%Named predicates rather than yall lambdas: yall copy_terms the lambda for
%every element, about four times the inferences of an ordinary call [measured
%2026-08-15, maplist over 100,000 elements: 1301283 against 300004].
dot_entry('.').
dot_entry('..').

entry_to_string(Name, Text) :- atom_string(Name, Text).

%Answers true or false rather than succeeding or failing, so it composes with
%if and with the rest of this library.
%
%The engine's own exists_file is not usable for this. It registers with zero
%inputs, so (exists_file "p") is a arity error, function_input_arities(
%exists_file,[0]) against 1, and the only spelling that works is the guard
%idiom (let $p (exists_file) ...) where a missing file FAILS the whole call.
%A library of file operations needs a question you can ask.
'file-exists'(Path, Answer) :-
    metta_text(Path, PathText),
    ( exists_file(PathText) -> Answer = true ; Answer = false ).

'dir-exists'(Path, Answer) :-
    metta_text(Path, PathText),
    ( exists_directory(PathText) -> Answer = true ; Answer = false ).

% Path operations use SWI's lexical POSIX path convention. No filesystem
% lookup occurs, including for nonexistent paths and dot components.
% [tested: lib_file_surface:lexical_paths; commit=504f8dddfa890ced97e795a13ab10e239b1de2ce]
'path-join'(Directory, Name, Path) :-
    metta_text(Directory, DirectoryText),
    metta_text(Name, NameText),
    atom_string(Dir, DirectoryText),
    atom_string(Base, NameText),
    directory_file_path(Dir, Base, Joined),
    atom_string(Joined, Path).

'path-parent'(Path, Parent) :-
    metta_text(Path, Text),
    file_directory_name(Text, Directory),
    atom_string(Directory, Parent).

'path-name'(Path, Name) :-
    metta_text(Path, Text),
    file_base_name(Text, Base),
    atom_string(Base, Name).

'path-extension'(Path, Extension) :-
    metta_text(Path, Text),
    file_base_name(Text, Base),
    file_name_extension(_, Ext, Base),
    atom_string(Ext, Extension).

'make-dir!'(Path, true) :-
    metta_text(Path, Text),
    atom_string(Directory, Text),
    catch(make_directory_path(Directory), Error,
          metta_file_refusal('make-dir!', Error)).

'delete-dir!'(Path, true) :-
    metta_text(Path, Text),
    catch(delete_directory(Text), Error,
          metta_file_refusal('delete-dir!', Error)).

% Acquire the staging directory with mkdir, which refuses an existing name.
% tmp_file/2 supplies a name only; no guessed filename is opened for writing.
% The destination changes only after both binary streams close successfully.
% [tested: lib_file_surface:copy_is_binary_and_replaces_only_after_success,
% lib_file_surface:failed_copy_preserves_destination; commit=504f8dddfa890ced97e795a13ab10e239b1de2ce]
'copy-file!'(Source, Destination, true) :-
    metta_text(Source, From),
    metta_text(Destination, To),
    catch(metta_copy_file(From, To), Error,
          metta_file_refusal('copy-file!', Error)).

metta_copy_file(From, To) :-
    (   exists_file(To), same_file(From, To)
    ->  throw(error(permission_error(copy, same_file, To),
                    context('copy-file!', 'Choose a different destination')))
    ;   true
    ),
    file_directory_name(To, Parent),
    tmp_file(metta_copy, Temp),
    file_base_name(Temp, Base),
    directory_file_path(Parent, Base, StageDirectory),
    setup_call_cleanup(
        make_directory(StageDirectory),
        ( directory_file_path(StageDirectory, contents, Stage),
          metta_copy_bytes(From, Stage),
          rename_file(Stage, To) ),
        delete_directory_and_contents(StageDirectory)).

metta_copy_bytes(From, Stage) :-
    setup_call_cleanup(
        open(From, read, Input, [type(binary)]),
        setup_call_cleanup(
            open(Stage, write, Output, [type(binary)]),
            copy_stream_data(Input, Output),
            close(Output)),
        close(Input)).

% Read all metadata before allocating the snapshot. A failed stat never
% leaves a partly populated space behind.
% [tested: lib_file_surface:metadata_is_queryable; commit=504f8dddfa890ced97e795a13ab10e239b1de2ce]
'file-metadata!'(Path, Space) :-
    metta_text(Path, Text),
    catch(metta_file_metadata(Text, Rows), Error,
          metta_file_refusal('file-metadata!', Error)),
    'new-space'(Space),
    catch(spaces:metta_add_atoms(Space, Rows), Error,
          (spaces:metta_release_space(Space), throw(Error))).

metta_file_metadata(Path, Rows) :-
    time_file(Path, Modified),
    (   exists_directory(Path)
    ->  Rows = [[kind, directory], [modified, Modified]]
    ;   size_file(Path, Size),
        Rows = [[kind, file], [size, Size], [modified, Modified]]
    ).

% Standard stream aliases follow the host's redirections and remain owned
% by the process. These operations never close them.
% [tested: test_standard_streams_and_explicit_exit; commit=504f8dddfa890ced97e795a13ab10e239b1de2ce]
'stderr!'(Content, true) :-
    metta_text(Content, Text),
    catch((write(user_error, Text), flush_output(user_error)), Error,
          metta_file_refusal('stderr!', Error)).

'stdin-to-string!'(Content) :-
    catch(read_string(user_input, _, Content), Error,
          metta_file_refusal('stdin-to-string!', Error)).

% This is process termination, including when embedded. SWI halt's unwind
% cannot be used as a catchable application-level return protocol.
% [tested: test_exit_is_process_termination_even_inside_catch; commit=504f8dddfa890ced97e795a13ab10e239b1de2ce]
'exit!'(Status, _) :-
    (   integer(Status), between(0, 255, Status)
    ->  halt(Status)
    ;   throw(error(domain_error(exit_status, Status),
                    context('exit!', 'Use an integer exit status from 0 to 255')))
    ).

metta_file_refusal(Operation, error(existence_error(Kind, Path), _)) :- !,
    throw(error('file-not-found'(Operation, Kind, Path),
                context(Operation, 'Create the missing path or correct its spelling'))).
metta_file_refusal(Operation, error(permission_error(Action, Kind, Path), _)) :- !,
    throw(error('file-permission-denied'(Operation, Action, Kind, Path),
                context(Operation, 'Check access permissions and choose a valid source or destination'))).
metta_file_refusal(Operation, Error) :-
    throw(error('file-operation-failed'(Operation, Error),
                context(Operation, 'Check the path, available storage and stream state before retrying'))).

:- multifile prolog:error_message//1.
prolog:error_message('file-not-found'(Operation, Kind, Path)) -->
    [ 'file-not-found: ~w could not find ~w ~q; create the path or correct its spelling'
      -[Operation, Kind, Path] ].
prolog:error_message('file-permission-denied'(Operation, Action, Kind, Path)) -->
    [ 'file-permission-denied: ~w cannot ~w ~w ~q; check permissions and choose a valid source or destination'
      -[Operation, Action, Kind, Path] ].
prolog:error_message('file-operation-failed'(Operation, Error)) -->
    [ 'file-operation-failed: ~w: ~q; check the path, storage and stream state before retrying'
      -[Operation, Error] ].
prolog:error_message('standard-stream-not-closable'(Operation, Name)) -->
    [ 'standard-stream-not-closable: ~w refuses ~w; the process owns it, so \c
       close a stream file-open! gave you'-[Operation, Name] ].
prolog:error_message('file-name-not-a-path'(Operation, Name)) -->
    [ 'file-name-not-a-path: ~w was given ~q, which contains a separator; name \c
       the file and place it with path-join'-[Operation, Name] ].

%Every file operation succeeds exactly once: a missing file raises rather than
%failing, and an unknown handle raises rather than failing, so there is no
%semidet case among them. det/1 turns that from a comment into a check.
%
%dot_entry/1 is absent on purpose. It is a two-clause table used as a filter,
%so it FAILS for every name that is not '.' or '..', which is its whole job.
:- det('file-open!'/3).
:- det('file-read-to-string!'/2).
:- det('file-read-exact!'/3).
:- det('file-write!'/3).
:- det('file-seek!'/3).
:- det('file-get-size!'/2).
:- det('file-close!'/2).
:- det('read-file!'/2).
:- det('write-file!'/3).
:- det('append-file!'/3).
:- det('file-lines!'/2).
:- det('file-space!'/2).
:- det('delete-file!'/2).
:- det('temp-path!'/2).
:- det('temp-dir!'/2).
:- det('stdin'/1).
:- det('stdout'/1).
:- det('stderr'/1).
:- det('list-dir!'/2).
:- det('file-exists'/2).
:- det('dir-exists'/2).
:- det('path-join'/3).
:- det('path-parent'/2).
:- det('path-name'/2).
:- det('path-extension'/2).
:- det('make-dir!'/2).
:- det('delete-dir!'/2).
:- det('copy-file!'/3).
:- det('file-metadata!'/2).
:- det('stderr!'/2).
:- det('stdin-to-string!'/1).
:- det(next_file_handle/1).
:- det(file_open_mode/2).
:- det(drop_trailing_empty/2).
:- det(entry_to_string/2).
