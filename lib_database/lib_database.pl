% Purpose: own independent persistent stores and query their native MeTTa values.
% Assumes: a store directory and its contents remain managed through this API
% while open; native handles are used only by their owning database operations.
% Guarantees: one handle owns a store; requests serialize, queries preserve
% duplicate matches, and update/sync failures end the attachment.
% [tested: lib_database; commit=WORKTREE].
% Owns resources: each anonymous engine owns a lock stream, temporary schema,
% source registration and journal attachment. Close and scope cleanup finish
% those resources; native atom collection releases an abandoned engine.
% Guarded by: engine_post/3 serializes requests; a file-description lock protects
% competing handles and processes until the owning stream closes.
% Decides: stores contain journal.pl and a permanent lock file; journal-sync
% controls buffering. Writes survive caller backtracking and native transactions.
% [tested: lib_database; commit=WORKTREE].

:- module(lib_database,
          ['database-open!'/3,'database-query'/4,'database-add!'/3,
           'database-remove!'/3,'database-sync!'/2,'database-close!'/2,
           'with-database'/4]).
:- set_module(base(metta_engine)).
:- metta_requires(persistency).
:- use_module(library(persistency), []).
:- use_module(library(modules), [in_temporary_module/3]).
:- use_module(library(error), [must_be/2,domain_error/2,existence_error/2]).
:- use_module(library(filesex), [directory_file_path/3,make_directory_path/1]).
:- use_module(library(lists), [memberchk/2,append/3]).
:- use_module(library(apply), [maplist/2]).
:- use_module(library(readutil), [read_line_to_codes/2]).
:- use_module('../../engine/spaces', [metta_seq_head_plan/2]).
:- use_module('../lib_string/lib_string', [metta_text/2]).
:- use_module('../lib_csv/support/csv_codec', [utf8_text/2]).
:- use_module('../_support/owned_resources', [with_outcome_cleanup/3]).
:- use_module('support/native', [claim_stream/2]).

%! 'database-open!'(+Directory:any, +Sync:atom, -Handle:any) is det.
%
% Open or create a store directory and return an opaque native handle. The
% directory contains journal.pl and a permanent lock file. A second owner,
% including one reached through a directory alias, raises immediately. Keep
% the directory and its contents unchanged through other tools while open.
% Sync is none, flush or close from journal-sync: buffer writes, flush each
% write, or close its journal stream after each write. Flushing does not fsync.
% Close explicitly or use with-database to surface close errors. Atom garbage
% collection releases abandoned engines asynchronously. Malformed journals
% raise before native replay; repair from a verified copy before reopening.
'database-open!'(Directory,Sync,Handle) :-
    store_arguments(Directory,Sync,Path),
    setup_call_catcher_cleanup(
        engine_create(answer(true),once(store_owner(Path,Sync)),Engine),
        ( engine_next(Engine,ready),Handle=Engine ),
        Outcome,
        ( Outcome==exit -> true ; engine_destroy(Engine) )).

%! 'with-database'(+Directory:any, +Sync:atom, +Function:'Atom', -Answer:any) is nondet.
%
% Own opening directly, apply held Function to the native handle in the calling
% module, and yield its answers. Close on exhaustion, cut, failure or exception.
% Writes made before callback failure remain persistent. A callback may close
% early; closing an already completed store succeeds. Returned handles are
% closed when this scope ends.
'with-database'(Directory,Sync,Function,Answer) :-
    store_arguments(Directory,Sync,Path),current_metta_module(Module),
    State=owner(unpublished),
    setup_call_cleanup(
        engine_create(answer(true),once(store_owner(Path,Sync)),Engine),
        ( engine_next(Engine,ready),nb_setarg(1,State,published),
          eval_metta_in_module(Module,[Function,Engine],Answer) ),
        ( arg(1,State,published) -> 'database-close!'(Engine,true)
        ; engine_destroy(Engine) )).

%! 'database-add!'(+Handle:any, +Value:'Atom', -Done:boolean) is det.
%
% Append one held ground value, retaining duplicate occurrences. Values may
% contain native Symbols, Strings, Numbers and proper expression lists.
% Variables, cycles and foreign resource/Python objects raise before writing.
% Bind computed values before passing them to this held argument. A write
% error closes the store; its journal may need repair before reopening.
'database-add!'(Handle,Value,true) :-
    persistent_value(Value),database_request(Handle,add(Value),true).

%! 'database-remove!'(+Handle:any, +Value:'Atom', -Removed:boolean) is det.
%
% Remove one exactly equal held ground occurrence, returning False if absent.
% Duplicates need one removal each. Exact stored-value equality distinguishes
% integer 1 from float 1.0; database-query instead uses core numeric matching.
% A native write failure closes the store and propagates its error.
'database-remove!'(Handle,Value,Removed) :-
    persistent_value(Value),database_request(Handle,remove(Value),Removed).

%! 'database-query'(+Handle:any, +Pattern:'Atom', +Template:'Atom', -Rows:list) is det.
%
% Match a held pattern against each stored value and collect the shared held
% template. Use the core matcher, including numeric promotion, equality guards
% and sequence variables. Stored marker-shaped values remain data. Queries
% match one row at a time; compose joins explicitly. Preserve insertion order,
% duplicates and all matches of each row. The result is a snapshot occupying
% memory proportional to its output. A query error leaves the store open.
'database-query'(Handle,Pattern,Template,Rows) :-
    persistent_syntax(Pattern),persistent_syntax(Template),
    current_metta_module(Caller),
    lift_pattern_modifiers(Pattern,Lifted,Guards,Segments),
    ( Segments==true -> metta_seq_head_plan(Lifted,Asked) ; Asked=Lifted ),
    database_request(Handle,query(Caller,Asked,Guards,Template),Rows).

%! 'database-sync!'(+Handle:any, -Done:boolean) is det.
%
% Flush and close the journal stream while retaining the store's lifetime
% lock. Subsequent writes reopen that stream under the selected sync policy.
% An I/O failure ends the attachment. This is a flush boundary, not fsync or
% a transaction commit; process or machine failure can still lose data.
'database-sync!'(Handle,true) :- database_request(Handle,sync,true).

%! 'database-close!'(+Handle:any, -Done:boolean) is det.
%
% Finish journal, schema and lock cleanup before answering. Requests already
% waiting on the native engine serialize with close; later requests raise.
% Close is idempotent for completed handles. A close error is propagated after
% cleanup, retaining any earlier operation error in database_cleanup/2.
'database-close!'(Handle,true) :-
    database_handle(Handle),
    catch(( engine_post(Handle,close,Response) -> database_response(Response,_) ; true ),
          error(existence_error(engine,Handle),_),true).

store_arguments(Directory,Sync,Path) :-
    metta_text(Directory,Text),
    ( Text=="" -> domain_error(database_directory,Directory) ; true ),
    % Workaround: swi-absolute-path-nul - refuse NUL before native canonicalization
    % can truncate the pathname and open a different store.
    ( string_code(_,Text,0) -> domain_error(database_directory,Directory) ; true ),
    must_be(atom,Sync),metta_vocabulary_values('journal-sync',Modes),
    ( memberchk(Sync,Modes) -> true ; domain_error(journal_sync(Modes),Sync) ),
    absolute_file_name(Text,Path,[expand(false)]).

database_handle(Handle) :-
    ( blob(Handle,thread),is_engine(Handle) -> true
    ; domain_error(database_handle,Handle) ).

database_request(Handle,Command,Reply) :-
    database_handle(Handle),
    catch(( engine_post(Handle,Command,Response) -> database_response(Response,Reply)
          ; existence_error(database,Handle) ),
          error(existence_error(engine,Handle),_),existence_error(database,Handle)).

database_response(Response,Value) :-
    ( nonvar(Response),Response=answer(Value) -> true
    ; nonvar(Response),Response=exception(Error) -> throw(Error)
    ; domain_error(database_response,Response) ).

store_owner(Directory,Sync) :-
    make_directory_path(Directory),
    directory_file_path(Directory,lock,Lock),
    directory_file_path(Directory,'journal.pl',Journal),
    setup_call_cleanup(open(Lock,append,Stream,[type(binary)]),
        ( claim_stream(Stream,Code),
          ( Code=:=0 -> true
          ; throw(error(database_lock_failed(Directory,Code),
                        context('database-open!',
                                'Close the other store handle or repair the filesystem lock service.'))) ),
          in_temporary_module(Module,true,store_schema(Module,Journal,Sync)) ),
        close(Stream)).

store_schema(Module,Journal,Sync) :-
    tmp_file(metta_database_source,Source),
    setup_call_cleanup(true,
        ( Text=":- use_module(library(persistency)).\n:- persistent row(value:any).\n",
          setup_call_cleanup(open_string(Text,Input),
                             load_files(Module:Source,[stream(Input)]),close(Input)),
          with_outcome_cleanup(true,
              ( validate_journal(Journal),
                Module:db_attach(Journal,[sync(Sync)]),
                database_yield(ready),database_loop(Module) ),
              finish_store(Module,Journal)) ),
        unload_file(Source)).

% Workaround: swi-persistency-detach - after a failed close, a second detach
% drains the bookkeeping left behind by the first, retaining both errors.
detach_store(Module,Errors) :-
    catch((Module:db_detach,Errors=[]),First,
          catch((Module:db_detach,Errors=[First]),Second,Errors=[First,Second])).

% Workaround: swi-persistency-stream-owner - cancellation may leave a journal
% stream outside db_stream/2. The exclusive store owner also owns those streams.
finish_store(Module,Journal,Outcome) :-
    detach_store(Module,DetachErrors),
    findall(Stream,stream_property(Stream,file_name(Journal)),Streams),
    close_journal_streams(Streams,CloseErrors),append(DetachErrors,CloseErrors,Errors),
    ( Errors==[] -> true
    ; throw(error(database_cleanup(Outcome,Errors),
                  context('database-close!','The store has been closed; inspect the journal before reopening.'))) ).

close_journal_streams([],[]).
close_journal_streams([Stream|Streams],Errors) :-
    catch((close(Stream),Errors=Rest),Error,Errors=[Error|Rest]),
    close_journal_streams(Streams,Rest).

database_loop(Module) :-
    engine_fetch(Command),
    ( Command==close -> true
    ; database_apply(Module,Command,Response),database_yield(Response),database_loop(Module) ).

% Suspended engines retain their stacks as atom-GC roots. Clear dead temporary
% thread_self/1 values before yielding, then release unused stack capacity.
% https://github.com/SWI-Prolog/swipl-devel/blob/fc7ef84b949378b729052c3ade79c90ce5416abb/man/engines.plx#L285-L288
database_yield(Response) :- garbage_collect,trim_stacks,engine_yield(Response).

database_apply(Module,query(Caller,Pattern,Guards,Template),Response) :-
    catch(( findall(Template,
                    ( Module:row(Value),metta_match_atoms(Pattern,Value),
                      maplist(query_guard(Caller),Guards),acyclic_term(Template) ),Rows),
            Response=answer(Rows) ),Error,Response=exception(Error)).
% Workaround: swi-persistency-write-memory - an update or sync exception ends
% the owning engine, discarding the native attachment's partially changed memory.
database_apply(Module,add(Value),answer(true)) :- Module:assert_row(Value).
database_apply(Module,remove(Value),answer(Removed)) :-
    ( Module:retract_row(Value) -> Removed=true ; Removed=false ).
database_apply(Module,sync,answer(true)) :- Module:db_sync(close).

query_guard(Caller,Goal) :- call(Caller:Goal).

persistent_value(Value) :-
    ( ground(Value),acyclic_term(Value),persistent_term(Value) -> true
    ; domain_error(persistent_value,Value) ).

persistent_syntax(Value) :-
    ( acyclic_term(Value),persistent_term(Value) -> true
    ; domain_error(persistent_pattern,Value) ).

persistent_term(Value) :-
    ( var(Value) -> true
    ; Value==[] -> true
    ; string(Value) -> true
    ; number(Value) -> true
    ; atom(Value) -> true
    ; is_list(Value),maplist(persistent_term,Value) ).

% Workaround: swi-persistency-replay - reject unsupported records before the
% native replay loop can print a diagnostic and continue past them.
validate_journal(Path) :-
    ( exists_file(Path)
    -> catch((setup_call_cleanup(open(Path,read,Bytes,[type(binary)]),
                                 journal_utf8(Bytes),close(Bytes)),
              setup_call_cleanup(open(Path,read,Stream,[encoding(utf8)]),
                                 journal_records(Stream,first),close(Stream))),
             Error,
             throw(error(database_journal(Path,Error),
                         context('database-open!','Restore or repair the journal from a verified copy; no record was skipped.'))))
    ; true ).

% Workaround: swi-utf8-journal-repair - validate original bytes with the existing
% strict codec before the host text reader can replace or normalize them. ASCII
% line endings cannot split a valid UTF-8 sequence; storage is bounded by a line.
journal_utf8(Stream) :-
    read_line_to_codes(Stream,Bytes),
    ( Bytes==end_of_file -> true ; utf8_text(Bytes,_),journal_utf8(Stream) ).

journal_records(Stream,Position) :-
    read_term(Stream,Action,[module(db),quasi_quotations(Quotes)]),
    ( Quotes==[] -> true ; domain_error(database_journal_quotation,Action) ),
    ( Action==end_of_file,stream_property(Stream,end_of_stream(at)) -> true
    ; ( ground(Action),journal_record(Position,Action) -> true
      ; domain_error(database_journal_record,Action) ),
      journal_records(Stream,later) ).

journal_record(first,created(Time)) :- number(Time).
journal_record(_,assert(row(Value))) :- persistent_value(Value).
journal_record(_,retract(row(Value))) :- persistent_value(Value).

:- det('database-open!'/3).
:- det('database-add!'/3).
:- det('database-remove!'/3).
:- det('database-query'/4).
:- det('database-sync!'/2).
:- det('database-close!'/2).
