% This source holds non-ASCII text, and the encoding is declared HERE, ahead
% of it, rather than inherited from the ambient locale: SWI decodes the file as
% a stream, so a directive placed after the first non-ASCII byte is already too
% late. A boot under LC_ALL=C warned `Illegal multibyte Sequence` without it,
% which is every perf-measured child, because measure_instructions builds its
% environment from a small allowlist carrying no locale.
:- encoding(utf8).

% Purpose: expose import records and undo alongside static data and Prolog imports.
% Guarantees: imports/2 enumerates committed (import Path) atoms and
%   'unimport!'/3 withdraws native source ownership through metta_unimport/2
%   [tested: lib_import_lifecycle; commit=4f2d6c0f8eb293b73f8dde30a1c84e24834f7393].
% Guarantees: static caches restore occurrence identity through the native
%   funnel and remain inert [tested: lib_import_tokens; commit=7f00ac7932fefa6f380fc8d14ec583ea0c58eff4].
% Owns resources: an imports descriptor owns no handle or copied rows.
%   static-import! releases its temporary static_import_image/1 payload after
%   success or failure [source: lib/lib_import/lib_import.pl:'static-import!'/3;
%   commit=7f00ac7932fefa6f380fc8d14ec583ea0c58eff4].
% Guarded by: metta_loader serializes static payload use; metta_unimport/2
%   owns a keyed source flight [source: engine/metta/interop.pl:metta_unimport/2;
%   commit=90ba93eb8f6e98ebfefc55416859bf13de6a8427].


:- module(lib_import,
          [ 'static-import!'/3,
            'unimport!'/3,
            'use-module!'/2,
            imports/2
          ]).

% Guarantees: private helpers and autoload declarations belong to this module.
% [tested: engine_modules; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
% Assumes: engine operations resolve through metta_engine's published exports.
% [source: engine/metta.pl:metta_engine_reexport/2; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
:- set_module(base(metta_engine)).

:- multifile seam:foreign_space/1, seam:foreign_capability/2,
             seam:foreign_atoms/2, seam:foreign_refuse/2.

imports(Space, View) :-
    must_be(ground, Space),
    format(atom(Encoded), '~k', [Space]),
    atom_concat('&imports:', Encoded, View).

import_view_space(View, Space) :-
    atom(View), atom_concat('&imports:', Encoded, View),
    catch(read_term_from_atom(Encoded, Space, [syntax_errors(error)]), _, fail),
    ground(Space).

seam:foreign_space(View) :- import_view_space(View, _).
seam:foreign_capability(View, enumerate) :- import_view_space(View, _).
seam:foreign_atoms(View, [import, Path]) :-
    import_view_space(View, Space), metta_import_record(Space, Path).
seam:foreign_refuse(View, Capability) :-
    import_view_space(View, Space),
    throw(error(permission_error(Capability, import_records, Space),
                context(imports, 'import records are read-only; use import! or unimport!'))).

'unimport!'(Space, File, true) :- metta_unimport(Space, File).

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
metta_file_to_prolog(Input, Output) :-
    read_file_to_string(Input, Source, [encoding(utf8)]),
    parse_metta_source(Source, ParsedForms),
    maplist(static_import_fact(Input), ParsedForms, Atoms),
    metta_static_import_image(Atoms, Image),
    setup_call_cleanup(open(Output, write, Out, [encoding(utf8)]),
                       write_static_import_image(Out, Image),
                       close(Out)).

write_static_import_image(Out, Image) :-
    portray_clause(Out, (:- encoding(utf8))),
    portray_clause(Out, (:- dynamic lib_import:static_import_image/1)),
    portray_clause(Out, lib_import:static_import_image(Image)).

%A data file holds data. A runnable cannot become an atom, and writing
%something else and hoping is how the truncated cache happened. Everything a
%space can hold is converted, expressions and scalars alike, through the same
%native storage funnel an ordinary add-atom uses.
static_import_fact(Input, Parsed, Atom) :-
    parsed_form_parts(Parsed, Kind, Text, Term),
    (   Kind == runnable
    ->  throw(error(metta_static_import_form(Input, Text),
                    context('static-import!',
                            'a runnable form cannot be imported as data')))
    ;   Atom = Term
    ).

:- multifile prolog:error_message//1.
prolog:error_message(metta_static_import_form(File, Text)) -->
    [ 'static-import! cannot turn this form in ~w into a fact: ~w'-[File, Text] ].
prolog:error_message(metta_static_import_failed(File)) -->
    [ 'static-import! could not convert ~w'-[File] ].
%The static import function that allows loading static data files fast:
'static-import!'(Space, File, true) :-
    atom_string(File, SFile),
    current_working_dir(Base),
    directory_file_path(Base, SFile, Stem),
    atom_concat(Stem, '.tokens-v1', Cache),
    file_name_extension(Cache, qlf, QlfFile),
    file_name_extension(Cache, pl, PlFile),
    file_name_extension(Stem, metta, MettaFile),
    with_mutex(metta_loader,
        setup_call_cleanup(
            retractall(static_import_image(_)),
            ( static_import_load_payload(MettaFile, PlFile, QlfFile),
              findall(Image, static_import_image(Image), Images),
              ( Images = [Only] -> metta_restore_static_import(QlfFile, Space, Only)
              ; throw(error(metta_static_import_failed(QlfFile),
                            context('static-import!', 'the cache must contain one image'))) ) ),
            retractall(static_import_image(_)))).

% qcompile already loads its input. The payload is held only while this
% serialized load validates and restores it; source ownership lives in the
% engine's existing journal, not in a second table of stored references.
% [source: https://github.com/SWI-Prolog/swipl-devel/blob/fc7ef84b949378b729052c3ade79c90ce5416abb/boot/qlf.pl:qcompile_/3; commit=7f00ac7932fefa6f380fc8d14ec583ea0c58eff4]
:- dynamic static_import_image/1.

static_import_load_payload(Source, PlFile, QlfFile) :-
    (   static_import_cache_fresh(Source, QlfFile)
    ->  consult(QlfFile)
    ;   ( static_import_cache_fresh(Source, PlFile) -> true
        ; static_import_generate(Source, PlFile) ),
        catch(qcompile(PlFile), Error,
              ( ( exists_file(QlfFile) -> delete_file(QlfFile) ; true ),
                throw(Error) ))
    ).

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
static_import_generate(MettaFile, PlFile) :-
    %The outcome is carried out of the catch as a term rather than as a
    %binding: a variable bound inside the CONDITION of an if-then-else is
    %unbound again on the way to the else branch, so reading it there always
    %saw an unbound error and reported every exception as "no output".
    catch(( metta_file_to_prolog(MettaFile, PlFile)
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
    ;   throw(error(metta_static_import_failed(MettaFile),
                    context('static-import!',
                            'the conversion produced no output')))
    ).


% The imported exports belong to the host tier that every space inherits.
% [tested: lib_import:use_module_imports_into_the_shared_host_tier; commit=ede2ac57e213a0d4502c6bbbca6227f97015b720]
'use-module!'(Module, true) :- user:use_module(library(Module)).
