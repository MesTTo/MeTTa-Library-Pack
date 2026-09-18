% Purpose: parse typed argument vectors and derive help from option declarations.
% Guarantees: literal arguments, defaults and occurrence order survive parsing;
% missing values, unknown names and ambiguous declarations raise with a repair.
% [tested: lib_cli; commit=83b7589a6766210414ceca14dfb9846b28c2ef78].
% Assumes: a custom decoder terminates before exhaustion or its second answer.
% Owns resources: bounded answer collection closes a custom decoder's generator
% on success, refusal or exception. No parser state outlives a call.
% [tested: lib_cli; commit=83b7589a6766210414ceca14dfb9846b28c2ef78].
% Decides: absent options without defaults contribute no pair; every occurrence
% is converted before the requested repeat policy selects results. Custom types
% use the calling module's ordinary argument checks, including gradual typing.
% [tested: lib_cli; commit=83b7589a6766210414ceca14dfb9846b28c2ef78].

:- module(lib_cli, ['cli-parse'/4,'cli-help'/2,'cli-types'/1,'cli-arguments!'/1]).
:- set_module(base(metta_engine)).
:- use_module(library(error), [must_be/2]).
:- use_module(library(lists), [member/2,memberchk/2,append/3]).
:- use_module(library(apply), [maplist/2,maplist/3]).
:- use_module(library(assoc), [empty_assoc/1,get_assoc/3,put_assoc/4]).
:- use_module(library(solution_sequences), [limit/2]).
:- use_module('vendor/lib_cli_optparse', [opt_parse/5,opt_help/2,remove_duplicates/3]).
:- multifile lib_cli_optparse:parse_type/3, lib_cli_optparse:format_default/2.
:- meta_predicate cli_check_option(+,0).

% Conversion functions stay in the call's declaration map. The provider only
% retains a printable type label and tags raw tokens separately from defaults.
lib_cli_optparse:parse_type(cli_value(_),Codes,raw_value(Text)) :- atom_codes(Text,Codes).
lib_cli_optparse:format_default(default_value(Value),Text) :- sdisplay(Value,Text).

%! 'cli-parse'(+Specification:'Atom', +Arguments:'Expression', +Duplicates:'Symbol', -Parsed:list) is det.
%
% Parse a held String argument vector into (Pairs Operands), where each pair
% is (Key Value). Bind computed declarations and arguments with let. A row is
% an expression of fields, for example ((opt count) (type integer)
% (shortflags (n)) (longflags (count)) (default 1) (help "Item count")).
% opt is required; the other fields are type, shortflags, longflags, default,
% meta and help. Each field occurs at most once. Type defaults to string;
% flags and help default to empty. Keys and complete dashed names are unique.
% Names are Strings or atoms. Short names have one character and cannot be a
% dash. Names contain no whitespace, control
% character or equals sign; digits and punctuation are otherwise permitted.
% Short and long namespaces are separate. Flagless default rows are allowed.
%
% Built-in types come from cli-types. boolean accepts lowercase true/false
% tokens and returns True/False; integer and float use native numeric parsing;
% atom returns a native atom, including its Boolean atoms true/false; string
% retains text; metta reads one literal form
% without evaluating it. A (parse Type Function) type applies the held function
% to the quoted String token in the calling module, requiring exactly one
% acyclic answer. Names, lambdas and partial applications work. The result and
% declared default must pass the engine's live argument-type check, including
% aliases, refinements and gradual typing. Defaults are ground literal values.
%
% Accept --name=value, --name value, -nvalue and -n value. A bare Boolean is
% true; --no-name is false unless that complete name has its own declaration.
% Short names do not cluster and -n=value is refused. -- ends option parsing;
% a lone dash and unclaimed signed numeric operands are data. Attach a dash-led value
% with equals or directly to a short name. Explicit empty tokens remain empty.
%
% Duplicates is keepfirst, keeplast or keepall. Defaults precede supplied
% occurrences; retained supplied occurrences keep their input order. An absent
% option without a default contributes no pair. Validate syntax, then convert
% every occurrence before selecting repeats. An invalid earlier value cannot
% hide behind a later one. Errors retain their cause, name the option and give
% the repair. Parsing itself prints nothing; custom functions keep their effects.
'cli-parse'(Specification,Arguments,Duplicates,[Pairs,Operands]) :-
    must_be(atom,Duplicates),
    % policy-inventory-exempt: documented-collision-decision; reason=the caller selects optparse's repeated-flag resolution; evidence=lib/lib_cli/vendor/lib_cli_optparse.pl:remove_duplicates/3
    ( memberchk(Duplicates,[keepfirst,keeplast,keepall]) -> true
    ; cli_refuse(domain_error(cli_duplicates,Duplicates),
                 'Choose keepfirst, keeplast or keepall.') ),
    must_be(list(string),Arguments),maplist(atom_string,Tokens,Arguments),
    cli_schema(Specification,Native,Declarations),
    opt_parse(Native,Tokens,Parsed,Positionals,
              [duplicated_flags(keepall),output_functor(opt)]),
    current_metta_module(Module),
    cli_values(Parsed,Declarations,Module,Converted),
    remove_duplicates(Duplicates,Converted,Selected),
    maplist(cli_pair,Selected,Pairs),maplist(atom_string,Positionals,Operands).

%! 'cli-help'(+Specification:'Atom', -Help:string) is det.
%
% Validate the same held declarations as cli-parse and render their aliases,
% types, literal defaults, metavariables and help. meta is a String label;
% help is a String or an expression of String lines. Empty and flagless
% declarations produce empty help. Custom converters do not run. Default type
% validation follows the ordinary type rules and can run a Predicate refinement.
'cli-help'(Specification,Help) :-
    cli_schema(Specification,Native,_),opt_help(Native,Text),atom_string(Text,Help).

%! 'cli-types'(-Types:list) is det.
%
% The built-in option conversion names, in declaration order. A custom
% (parse Type Function) descriptor also accepts any ordinary held MeTTa function.
'cli-types'(Types) :- findall(Type,cli_builtin_type(Type,_,_),Types).

%! 'cli-arguments!'(-Arguments:list) is det.
%
% The host process argument vector as Strings, preserving numeric spelling,
% empty tokens and order. Runner arguments remain present; the caller selects
% the tokens that belong to its application before passing them to cli-parse.
% This reads argv directly and performs no shell tokenization or process exit.
'cli-arguments!'(Arguments) :-
    current_prolog_flag(argv,Native),maplist(atom_string,Native,Arguments).

cli_builtin_type(boolean,boolean,native(boolean)).
cli_builtin_type(integer,integer,native(integer)).
cli_builtin_type(float,float,native(float)).
cli_builtin_type(atom,atom,native(atom)).
cli_builtin_type(string,cli_value(string),text).
cli_builtin_type(metta,cli_value(metta),syntax).

cli_schema(Specification,Native,Declarations) :-
    must_be(acyclic,Specification),must_be(list,Specification),
    copy_term(Specification,Rows),empty_assoc(Empty),
    cli_rows(Rows,Empty,Declarations,Empty,_,Native).

cli_rows([],Declarations,Declarations,Flags,Flags,[]).
cli_rows([Row|Rows],D0,D,F0,F,[Native|Rest]) :-
    must_be(list,Row),empty_assoc(Empty),cli_fields(Row,Empty,Fields),
    ( get_assoc(opt,Fields,Key) -> must_be(atom,Key)
    ; cli_refuse(existence_error(cli_field,opt),
                 'Add exactly one (opt Key) field to each declaration.') ),
    cli_check_option(Key,cli_row(Fields,Key,D0,D1,F0,F2,Native)),
    cli_rows(Rows,D1,D,F2,F,Rest).

cli_row(Fields,Key,D0,D1,F0,F2,Native) :-
    cli_field_value(Fields,type,string,Type),cli_type(Type,NativeType,Kind),
    % Workaround: swi-optparse-schema-ambiguity - index every declaration,
    % including identical copies that the native O1 \= O2 check overlooks.
    cli_unique(D0,Key,Kind,option_key,D1),
    cli_field_value(Fields,shortflags,[],ShortNames),
    cli_field_value(Fields,longflags,[],LongNames),
    cli_flags(ShortNames,short,Key,F0,F1,Short),
    cli_flags(LongNames,long,Key,F1,F2,Long),
    cli_field_value(Fields,meta,"",Meta),must_be(string,Meta),atom_string(MetaAtom,Meta),
    cli_field_value(Fields,help,"",Help),cli_help_text(Help,NativeHelp),
    ( get_assoc(default,Fields,Default)
    -> must_be(ground,Default),cli_validate_value(Kind,Default),
       Defaults=[default(default_value(Default))]
    ; Defaults=[] ),
    append([opt(Key),type(NativeType),shortflags(Short),longflags(Long),
            meta(MetaAtom),help(NativeHelp)],Defaults,Native).

cli_fields([],Fields,Fields).
cli_fields([Field|Rest],F0,F) :-
    ( nonvar(Field),Field=[Name,Value],atom(Name),cli_field_name(Name) -> true
    ; cli_refuse(domain_error(cli_field,Field),
                 'Use two-item fields named opt, type, shortflags, longflags, default, meta or help.') ),
    cli_unique(F0,Name,Value,field,F1),cli_fields(Rest,F1,F).
cli_field_name(opt).
cli_field_name(type).
cli_field_name(shortflags).
cli_field_name(longflags).
cli_field_name(default).
cli_field_name(meta).
cli_field_name(help).
cli_field_value(Fields,Name,Default,Value) :-
    ( get_assoc(Name,Fields,Value) -> true ; Value=Default ).

cli_unique(Before,Key,Value,Kind,After) :-
    ( get_assoc(Key,Before,_) ->
        format(atom(Repair),'Use each ~w once; rename or remove ~q.',[Kind,Key]),
        cli_refuse(domain_error(unique_cli_name(Kind),Key),Repair)
    ; put_assoc(Key,Before,Value,After) ).

cli_flags(Names,Kind,Key,F0,F,Atoms) :-
    must_be(list,Names),maplist(cli_flag_atom,Names,Atoms),
    cli_flag_rows(Atoms,Kind,Key,F0,F).
cli_flag_atom(Name,Atom) :-
    ( atom(Name) -> Atom=Name
    ; string(Name) -> atom_string(Atom,Name)
    ; cli_refuse(type_error(cli_flag_text,Name),'Write each flag name as a String or atom.') ).
cli_flag_rows([],_,_,Flags,Flags).
cli_flag_rows([Name|Names],Kind,Key,F0,F) :-
    atom_codes(Name,Codes),
    ( Codes=[_|_],maplist(cli_name_character,Codes),
      ( Kind==short -> Codes=[_],Name\=='-',atom_concat('-',Name,Flag)
      ; atom_concat('--',Name,Flag) ) -> true
    ; cli_refuse(domain_error(cli_flag(Kind),Name),
                 'Use a nonempty name with no whitespace, control character or =; short names need one character and cannot be -.') ),
    cli_unique(F0,Flag,Key,flag,F1),cli_flag_rows(Names,Kind,Key,F1,F).
cli_name_character(Code) :- Code=\=0'=,\+code_type(Code,space),\+code_type(Code,cntrl).

cli_help_text(Help,Native) :-
    ( string(Help) -> Native=Help
    ; must_be(list(string),Help),maplist(atom_string,Native,Help) ).

cli_type(Type,Native,Kind) :-
    ( nonvar(Type),cli_builtin_type(Type,Native,Kind) -> true
    ; nonvar(Type),Type=[parse,Expected,Function]
    -> must_be(ground,Expected),must_be(nonvar,Function),
       current_metta_module(Module),normalize_type_in(Module,Expected,Normalized),
       metta_argument_type_origins([Normalized],[Origin]),
       sdisplay(Expected,Label),Native=cli_value(Label),
       Kind=parsed(Normalized,Origin,Function)
    ; cli_refuse(domain_error(cli_type,Type),
                 'Use a name from cli-types or (parse Type Function).') ).

cli_values([],_,_,[]).
cli_values([opt(Key,Raw)|Rest],Declarations,Module,Values) :-
    ( var(Raw) -> Values=More
    ; get_assoc(Key,Declarations,Kind),
      cli_check_option(Key,cli_value(Raw,Kind,Module,Value)),
      Values=[opt(Key,Value)|More] ),
    cli_values(Rest,Declarations,Module,More).
cli_value(default_value(Value),_,_,Value) :- !.
cli_value(raw_value(Atom),Kind,Module,Value) :- !,
    atom_string(Atom,Text),cli_decode(Kind,Module,Text,Value),
    must_be(acyclic,Value),cli_validate_value(Kind,Value).
cli_value(Value,native(_),_,Value).

cli_decode(text,_,Text,Text).
cli_decode(syntax,_,Text,Value) :- sread(Text,Value).
cli_decode(parsed(_,_,Function),Module,Text,Value) :-
    findall(Answer,limit(2,eval_metta_in_module(Module,[Function,[quote,Text]],Answer)),Answers),
    ( Answers=[Value] -> true
    ; cli_refuse(domain_error(exactly_one_cli_answer,Answers),
                 'Make the decoder return exactly one value; the displayed bag contains at most its first two answers.') ).

cli_validate_value(native(Type),Value) :- must_be(Type,Value).
cli_validate_value(text,Value) :- must_be(string,Value).
cli_validate_value(syntax,Value) :- must_be(acyclic,Value).
cli_validate_value(parsed(Expected,Origin,_),Value) :-
    ( once(check_argument_type_under_live_policy(Value,Expected,Origin)) -> true
    ; cli_refuse(type_error(cli_value(Expected),Value),
                 'Return or declare a default that passes the specified MeTTa argument type.') ).

cli_pair(opt(Key,Value),[Key,Value]).
cli_refuse(Reason,Repair) :- throw(error(Reason,context('cli-parse',Repair))).
cli_check_option(Key,Goal) :-
    catch(Goal,Cause,
          throw(error(cli_option(Key,Cause),
                      context('cli-parse',
                              'Correct this option declaration or value; custom decoders return exactly one value of the declared type.')))).

:- det('cli-parse'/4).
:- det('cli-help'/2).
:- det('cli-types'/1).
:- det('cli-arguments!'/1).
