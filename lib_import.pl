%Translate a MeTTa S-expression file (no code, no bangs) to Prolog facts.
%
%Through the engine's own reader, not line by line. The line-based converter
%stripped one character from each end and rewrote characters, which made four
%silent assumptions the format does not carry: one form per line, no comment
%lines, no escape inside a string, and no runs of spaces. A BLANK line failed
%sub_string/5, which failed the whole conversion, and the partly written
%output was CLOSED rather than removed. The next run then found the .pl,
%qcompiled it and reported success with half the data, permanently and in
%binary: four facts with one blank line after the second gave two facts, no
%answer and no error on the first run, and [[True], [True]] on the second.
%
%parse_metta_source/2 consumes comments in its grammar, reads a form across as
%many lines as it takes, and hands back the term the engine itself would
%build, so a variable is a variable and a string with an escaped quote is one
%string. portray_clause/2 then writes it back as Prolog that reads as the same
%term [tested: import_converts_through_the_reader].
metta_file_to_prolog(Input, Space, Output) :-
    read_file_to_string(Input, Source, []),
    parse_metta_source(Source, ParsedForms),
    %The storage module, not user. Native atoms live in '$petta_atoms:<space>'
    %and the converter wrote its facts into user, so a static import loaded
    %clauses the space could never read and reported success: the data was
    %there, in the database, invisible to (match &self ...) and to get-atoms.
    ensure_native_storage_module(Space, Module),
    maplist(static_import_fact(Input, Space), ParsedForms, Facts),
    %Write only after every form has converted, and only into a file that is
    %removed on failure: a half-written .pl is indistinguishable from a
    %complete one on the next run.
    setup_call_cleanup(open(Output, write, Out),
                       write_static_import_facts(Out, Module, Facts),
                       close(Out)).

write_static_import_facts(Out, Module, Facts) :-
    %One declaration per arity actually present. The space predicate is
    %Space(Rel, Args...), so a file mixing (p x) with (p x y) needs both, and
    %dynamic is what keeps a later add-atom from raising a permission error on
    %a predicate the load had made static.
    setof(Name/Arity,
          Fact^( member(Fact, Facts), functor(Fact, Name, Arity) ),
          Indicators),
    forall(member(Indicator, Indicators),
           ( format(Out, ":- dynamic ~q:~q.~n", [Module, Indicator]),
             format(Out, ":- multifile ~q:~q.~n", [Module, Indicator]),
             format(Out, ":- discontiguous ~q:~q.~n", [Module, Indicator]) )),
    nl(Out),
    forall(member(Fact, Facts), portray_clause(Out, Module:Fact)).

%A data file holds data. A runnable cannot become an atom, and writing
%something else and hoping is how the truncated cache happened. Everything a
%space can hold is converted, expressions and scalars alike, through the same
%native_atom_clause/3 an ordinary add-atom uses.
static_import_fact(Input, Space, Parsed, Fact) :-
    parsed_form_parts(Parsed, Kind, Text, Term),
    (   Kind == runnable
    ->  throw(error(petta_static_import_form(Input, Text),
                    context('static-import!',
                            'a runnable form cannot be imported as data')))
    ;   native_atom_clause(Space, Term, Fact)
    ).

:- multifile prolog:error_message//1.
prolog:error_message(petta_static_import_form(File, Text)) -->
    [ 'static-import! cannot turn this form in ~w into a fact: ~w'-[File, Text] ].
prolog:error_message(petta_static_import_failed(File)) -->
    [ 'static-import! could not convert ~w'-[File] ].
%The static import function that allows loading static data files fast:
'static-import!'(Space, File, true) :- style_check(-discontiguous),
                                       atom_string(File, SFile),
                                       %current_working_dir/1, not the bare
                                       %working_dir/1: that has a clause only
                                       %while a .metta file load is active, so
                                       %a static import from anywhere else
                                       %simply FAILED, with no answer and no
                                       %error. The engine already keeps the
                                       %process directory as the fallback.
                                       current_working_dir(Base),
                                       atomic_list_concat([Base, '/', SFile, '.qlf'], QlfFile),
                                       atomic_list_concat([Base, '/', SFile, '.pl'], PlFile),
                                       atomic_list_concat([Base, '/', SFile, '.metta'], MettaFile),
                                       ( static_import_cache_fresh(MettaFile, QlfFile)
                                         -> % Case 1: a current .qlf → load fastest
                                            consult(QlfFile)
                                          ; static_import_cache_fresh(MettaFile, PlFile)
                                         -> % Case 2: a current .pl → compile to qlf and load
                                            qcompile(PlFile),
                                            consult(QlfFile)
                                          ; % Case 3: nothing current → generate, compile, load
                                            static_import_generate(MettaFile, Space, PlFile),
                                            qcompile(PlFile),
                                            consult(QlfFile) ).

%A cache older than the source it came from answers from data the file no
%longer holds, which is a wrong answer with no symptom. The old branches asked
%only whether the file EXISTED. When the source is gone the cache is all there
%is, and staying usable is the right reading of that.
static_import_cache_fresh(Source, Cache) :-
    exists_file(Cache),
    (   exists_file(Source)
    ->  time_file(Source, SourceTime),
        time_file(Cache, CacheTime),
        CacheTime >= SourceTime
    ;   true
    ).

%A conversion that does not finish must leave NO output behind. The old one
%wrote as it read and closed the partial file on failure, so the next run took
%the "a .pl exists" branch, qcompiled the truncated file and reported success
%with half the data, in binary, for good. Failing silently was the other half
%of it: 'static-import!' simply had no answer and said nothing
%[tested: import_removes_a_partial_conversion].
static_import_generate(MettaFile, Space, PlFile) :-
    %The outcome is carried out of the catch as a term rather than as a
    %binding: a variable bound inside the CONDITION of an if-then-else is
    %unbound again on the way to the else branch, so reading it there always
    %saw an unbound error and reported every exception as "no output".
    catch(( metta_file_to_prolog(MettaFile, Space, PlFile)
            -> Outcome = converted
            ;  Outcome = failed ),
          Error,
          Outcome = raised(Error)),
    static_import_outcome(Outcome, MettaFile, PlFile).

static_import_outcome(converted, _, _) :- !.
static_import_outcome(Outcome, MettaFile, PlFile) :-
    ( exists_file(PlFile) -> delete_file(PlFile) ; true ),
    (   Outcome = raised(Error)
    ->  throw(Error)
    ;   throw(error(petta_static_import_failed(MettaFile),
                    context('static-import!',
                            'the conversion produced no output')))
    ).


'use-module!'(Module, true) :- use_module(library(Module)).
