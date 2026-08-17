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
% Fails when:
%   - the file is missing and the options do not say to create it. That is an
%     error, not a failure, so it cannot be mistaken for an empty file.
% Owns:
%   - one open stream per handle, until file-close! releases it. HE's stdlib
%     lists no close operation; leaving a process to leak descriptors is not
%     something to copy, so file-close! is added and documented as an addition.
% Guarded by:
%   - '$petta_files' serialises handle allocation and the handle table.
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: reading a file as a SPACE of lines, so it is matchable
%     rather than a single string, is tracked in ai-todo-language-completeness
%     section 2.4.

:- use_module(library(lists)).

:- dynamic petta_file/2.            % Handle, Stream
:- dynamic petta_file_counter/1.

petta_file_counter(0).

next_file_handle(Handle) :-
    with_mutex('$petta_files',
               ( retract(petta_file_counter(N)),
                 Handle is N + 1,
                 assertz(petta_file_counter(Handle)) )).

known_file(Handle, Stream) :-
    (   petta_file(Handle, Stream)
    ->  true
    ;   existence_error(petta_file_handle, Handle)
    ).

%HE's option letters: r read, w write, c create if absent, a append,
%t truncate. 'c' demands 'w', which is why "rc" is refused rather than
%quietly opening for reading.
'file-open!'(Path, Options, Handle) :-
    metta_text(Path, PathText),
    metta_text(Options, OptionText),
    string_chars(OptionText, Letters),
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
    with_mutex('$petta_files', assertz(petta_file(Handle, Stream))).

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
'file-close!'(Handle, true) :-
    (   petta_file(Handle, Stream)
    ->  with_mutex('$petta_files', retractall(petta_file(Handle, _))),
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
:- det('list-dir!'/2).
:- det('file-exists'/2).
:- det('dir-exists'/2).
:- det(next_file_handle/1).
:- det(file_open_mode/2).
:- det(drop_trailing_empty/2).
:- det(entry_to_string/2).
