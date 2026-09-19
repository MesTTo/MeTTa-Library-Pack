% Purpose: read native artifact contracts before package activation.
% Assumes: included in lib_package; native declarations use Prolog's reader.
% Guarantees: native inspection executes no directives; the existing claimant
% still loads the artifact and enforces its declared exports after loading.
% [tested: lib_package:contracts_refuse_before_native_directives; commit=WORKTREE].
% Owns resources: artifact streams close on success, failure and exceptions.

package_perform_row(Path, Space, [prolog, Locator, Names], [prolog, File, Names]) :- !,
    package_native_path(Path, Space, Locator, File).
package_perform_row(_, _, Row, Row).

% A home may already contain a required source's backing. Check that source
% before consulting another file, while its directives have made no changes.
package_native_admission(Path, Space, [prolog, Locator, _], Names, Contracts) :- !,
    package_native_path(Path, Space, Locator, File),
    metta_engine:check_prolog_function_names(Names, File, true),
    space_module(Space, Module),
    forall((member(contract(Name, Arity, _), Contracts), memberchk(Name, Names),
            metta_engine:metta_reference_prolog_head(Space, Name, Arity),
            functor(Head, Name, Arity), predicate_property(Module:Head, file(Owner))),
           ( Owner == File -> true
           ; throw(error(metta_name_owned_by_source(Name, Owner),
                         context(package, File))) )).
package_native_admission(_, _, _, _, _).

% Reusing the same artifact does not replace an occupied host predicate.
% Every other case passes through OPEN before the artifact can run directives.
package_open_head(Path, Space, [prolog, Locator, _], Name, Arity) :-
    package_native_path(Path, Space, Locator, File),
    space_module(Space, Module), functor(Head, Name, Arity),
    predicate_property(Module:Head, file(File)), !.
package_open_head(_, _, [Token|_], Name, Arity) :-
    metta_host_open_function(Name, Token, Arity).

% Native clauses have process lifetime; only their MeTTa registration belongs
% to the source. Direct load_files/2 keeps import offline even when a compiled
% artifact is stale and the ordinary loader would invoke a compiler child.
'package-prolog'(File, Names, true) :-
    metta_engine:check_prolog_function_names(Names, File, true),
    current_metta_space(Home), space_module(Home, Module),
    metta_engine:metta_reference_check_prolog_source(File),
    package_load_native(File, Owner),
    % Declarations also apply when SWI reuses an already-loaded module. Read
    % them before selecting exports, so an alternative cannot register names
    % assigned to an earlier backing or leak an undeclared arity.
    package_native_declarations(File, Home, Owner, Names),
    package_native_manifest(File, Declared, Inferred), append(Declared, Inferred, All),
    forall((member(Name, Names), package_named_contract(Name, Declared, All, Arity, _)),
           ( ( Owner == Module -> true
             ; Owner:export(Name/Arity), Module:import(Owner:Name/Arity) ),
             metta_engine:metta_reference_register_prolog(Home, Module, Name, Arity) )).

% Artifact clauses have process lifetime in their own namespace. Import only
% selected heads into the home: importing all exports also occupies unselected
% equation names, even though those predicates were never registered in MeTTa.
% SWI load_files/2 imports([]) separates loading from namespace publication:
% https://www.swi-prolog.org/pldoc/doc_for?object=load_files/2
% [tested: lib_package:unselected_native_exports_leave_equation_heads_free; commit=WORKTREE].
package_load_native(File, Owner) :-
    ( source_file_property(File, module(Context)) -> true
    ; source_file_property(File, load_context(Context, _, _)) -> true
    ; atom_concat('$metta_package:', File, Context),
      set_module(Context:base(metta_engine)) ),
    filereader:with_owning_source_load(none,
        metta_engine:loading_loudly(
            load_files(Context:File, [expand(true), if(changed), imports([])]))),
    ( source_file_property(File, module(Owner)) -> true ; Owner = Context ).

package_native_declarations(File, Home, Module, Names) :-
    retractall(metta_engine:pending_metta_export(File, _, _)),
    ( module_property(Owner, file(File)) -> true ; Owner = Module ),
    setup_call_cleanup(open(File, read, Input, [encoding(utf8)]),
        metta_engine:metta_reference_read_exports(Input, File, Owner), close(Input)),
    findall(File-Name-Type, retract(metta_engine:pending_metta_export(File, Name, Type)), Pending),
    include(package_named_declaration(Names), Pending, Selected),
    forall(member(File-Name-Type, Selected),
           ( ( Type = arity(_) -> true ; metta_add_atom(Home, [':', Name, Type], _) ),
             metta_engine:record_extension_membership(File, Name) )).

package_named_declaration(Names, _-Name-_) :- memberchk(Name, Names).

package_contract(Path, Space, [prolog, Locator, Pattern], Pattern, Names, Contracts) :- !,
    package_native_path(Path, Space, Locator, File),
    package_native_manifest(File, Declared, Inferred),
    ( ( var(Pattern) ; package_segment_pattern(Pattern, _, _) )
    -> package_native_exports(Declared, Exports),
       package_heads_pattern(Pattern, Exports, Names),
       include(package_contract_named(Names), Declared, Contracts)
    ; must_be(list, Pattern), maplist(must_be(atom), Pattern), Names = Pattern,
      append(Declared, Inferred, All),
      findall(contract(Name, Arity, Type),
              ( member(Name, Names),
                package_named_contract(Name, Declared, All, Arity, Type) ), Raw),
      sort(Raw, Contracts),
      forall(member(Name, Names),
             ( memberchk(contract(Name, _, _), Contracts) -> true
             ; throw(error(existence_error(procedure, Name),
                           context(package, File))) )) ).
package_contract(_, _, [_, _, []], [], [], []) :- !.
package_contract(_, _, Row, Pattern, Names, Contracts) :-
    Row = [_, Artifact, _],
    ( nonvar(Artifact), 'is-space'(Artifact, true)
    -> metta_engine:metta_reference_face(Artifact, [], Face),
       findall(contract(Name, Arity, Type),
           ( member(Name/Arity-_, Face), integer(Arity),
             ( metta_host_stored(Artifact, [':', Name, Type]) -> true
             ; package_unknown_arrow(Arity, Type) ) ), All)
    ; package_claim('package-contract', Row, _)
    -> metta_engine:metta_package_normalise('&metta', ['package-contract', Row], Exported),
       must_be(list, Exported), maplist(package_contract_row, Exported, All)
    ; throw(error(existence_error(package_export_contract, Row),
                  context(package, 'the claimant must supply package-contract equations or an artifact space'))) ),
    findall(Name, member(contract(Name, _, _), All), ExportNames), sort(ExportNames, Exports),
    ( is_list(Pattern), maplist(atom, Pattern)
    -> Names = Pattern,
       forall(member(Name, Names),
              (memberchk(Name, Exports) -> true
              ; throw(error(existence_error(package_export, Name), none))))
    ; package_heads_pattern(Pattern, Exports, Names) ),
    include(package_contract_named(Names), All, Contracts).

package_contract_row([':', Name, Type], contract(Name, Arity, Type)) :-
    !,
    must_be(atom, Name),
    ( metta_engine:declared_predicate_arity(Type, Arity) -> true
    ; throw(error(type_error(package_export_arrow, Type), none)) ).
package_contract_row(Row, _) :- throw(error(type_error(package_export_contract, Row), none)).

package_named_contract(Name, Declared, All, Arity, Type) :-
    ( memberchk(export_declaration, Declared)
    -> member(contract(Name, Arity, Type), Declared)
    ; member(contract(Name, Arity, Type), All) ).

package_contract_named(Names, contract(Name, _, _)) :- memberchk(Name, Names).

package_native_exports(Contracts, Names) :-
    findall(Name, member(contract(Name, _, _), Contracts), All), sort(All, Names),
    ( Names == [], \+ memberchk(export_declaration, Contracts)
    -> throw(error(existence_error(package_export_declaration, prolog),
                   context(package, 'variable heads require the artifact export declaration')))
    ; true ).

package_segment_pattern(Pattern, Prefix, Tail) :-
    nonvar(Pattern), is_list(Pattern),
    append(Prefix, [[':seg', Tail]], Pattern).

package_heads_pattern(Pattern, Exports, Exports) :- var(Pattern), !, Pattern = Exports.
package_heads_pattern(Pattern, Exports, Exports) :-
    package_segment_pattern(Pattern, Prefix, Tail), !,
    maplist(must_be(atom), Prefix),
    forall(member(Name, Prefix),
           ( memberchk(Name, Exports) -> true
           ; throw(error(existence_error(package_export, Name), none)) )),
    subtract(Exports, Prefix, Rest),
    ( Tail = Rest -> true
    ; throw(error(domain_error(package_export_pattern, Pattern), none)) ).
package_heads_pattern(Pattern, _, _) :-
    throw(error(domain_error(package_export_pattern, Pattern), none)).

package_native_path(Path, Space, Locator, File) :-
    ( nonvar(Locator), Locator = [library|_]
    -> metta_engine:resolve_module_form(Locator, Resolved)
    ; atomic(Locator) -> Resolved = Locator
    ; metta_engine:metta_package_normalise(Space, Locator, Resolved) ),
    ( (atom(Resolved) ; string(Resolved)) -> true
    ; throw(error(type_error(package_artifact_path, Resolved), context(package, Path))) ),
    file_directory_name(Path, Directory),
    absolute_file_name(Resolved, File,
                       [relative_to(Directory), file_type(prolog), access(none)]),
    ( exists_file(File) -> true
    ; throw(error(existence_error(source_sink, File),
                  context(package, 'backing artifact is missing; run !(setup! (library X))'))) ).

% O(t) Prolog terms in a selected artifact. Source declarations are read once
% per plan. Clause heads are the compatibility contract for an explicit name
% list; a variable head pattern requires actual module/metta_export declarations.
package_native_manifest(File, Declared, Inferred) :-
    setup_call_cleanup(open(File, read, Stream, [encoding(utf8)]),
        package_native_terms(Stream, [], Exports0, [], Heads0), close(Stream)),
    sort(Exports0, Exported), sort(Heads0, Inferred),
    findall(Contract,
        ( member(Export, Exported),
          ( Export == export_declaration -> Contract = export_declaration
          ; ( Export = contract(Name, Arity, Type)
            ; Export = Name/Arity,
              \+ member(contract(Name, Arity, _), Exported),
              package_unknown_arrow(Arity, Type) ),
            Contract = contract(Name, Arity, Type) ) ), Declared).

package_native_terms(Stream, Exports0, Exports, Heads0, Heads) :-
    read_term(Stream, Term, [module(user), syntax_errors(error)]),
    ( Term == end_of_file -> Exports = Exports0, Heads = Heads0
    ; package_native_term(Term, ExportRows, HeadRows),
      append(ExportRows, Exports0, Exports1), append(HeadRows, Heads0, Heads1),
      package_native_terms(Stream, Exports1, Exports, Heads1, Heads) ).

package_native_term((:- module(_, Exports)), [export_declaration|Exports], []) :- !.
package_native_term((:- metta_export(Text)), [export_declaration|Contracts], []) :- !,
    parse_metta_source(Text, Forms),
    findall(contract(Name, Arity, Type),
        ( member(Form, Forms), parsed_form_parts(Form, _, _, Row),
          ( Row = [':', Name, Type], metta_engine:declared_predicate_arity(Type, Arity)
          ; Row = [export, Name, Inputs], integer(Inputs), Inputs >= 0,
            Arity is Inputs + 1,
            package_unknown_arrow(Arity, Type) ) ), Contracts).
package_native_term((:- _), [], []) :- !.
package_native_term((Head :- _), [], Contracts) :- !, package_native_head(Head, Contracts).
package_native_term(Head, [], Contracts) :- package_native_head(Head, Contracts).

package_native_head(Head, [contract(Name, Arity, Type)]) :-
    callable(Head), \+ Head = (_:_), functor(Head, Name, Arity), Arity > 0,
    package_unknown_arrow(Arity, Type), !.
package_native_head(_, []).

package_unknown_arrow(Arity, [->|Types]) :-
    length(Types, Arity), maplist(=('%Undefined%'), Types).
