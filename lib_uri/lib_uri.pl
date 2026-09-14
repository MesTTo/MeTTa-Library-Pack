% Purpose: parse, compose, normalize and resolve URI references and query pairs.
% Guarantees: absent components differ from empty ones; reserved percent octets,
% userinfo case, duplicate query keys and strict UTF8 survive their stated doors.
% [tested: lib_uri; commit=24b96f8ec8468bc97cec35e1d71ce689ede7fdcf].
% Decides: RFC3986 generic structure, ASCII URI spelling, encoded authorities,
% native encoding contexts and explicit uri/form plus convention. Relative path
% normalization keeps dot segments until resolution supplies a base.
% [source: https://www.rfc-editor.org/rfc/rfc3986#section-5; commit=24b96f8ec8468bc97cec35e1d71ce689ede7fdcf].

:- module(lib_uri,
          [ 'uri-parts'/2, 'uri-build'/2, 'uri-normalize'/2, 'uri-resolve'/3,
            'uri-contexts'/1, 'uri-encode'/3, 'uri-decode'/2,
            'uri-query-parse'/3, 'uri-query-build'/3
          ]).
:- set_module(base(metta_engine)).
:- metta_requires(uri).
:- use_module(library(uri), [uri_encoded/3]).
:- use_module(library(error), [must_be/2, domain_error/2]).
:- use_module(library(lists), [append/3, memberchk/2, reverse/2]).
:- use_module(library(apply), [maplist/2, maplist/3]).
:- use_module('../lib_encoding/lib_encoding', ['utf8-encode'/2, 'utf8-decode'/2]).

%! 'uri-parts'(+URI:string, -Parts:list) is det.
%
% Encoded String pairs in scheme/authority/path/query/fragment order. Path is
% always present. Other missing components have no row; ("query" "") retains
% the question mark. URNs have an ordinary opaque path. References use ASCII
% URI spelling and valid percent triples; uri-encode carries Unicode data.
% Authorities remain encoded text: this is not a DNS or IP address validator.
'uri-parts'(URI, Parts) :-
    parse_reference(URI, Record), record_rows(Record, Parts).

%! 'uri-build'(+Parts:list, -URI:string) is det.
%
% Compose encoded String pairs. Their order is immaterial; missing path means
% empty. Unknown or repeated keys and ambiguous component separators raise.
% Encode component data before building; this operation does not encode it.
'uri-build'(Parts, URI) :-
    must_be(list, Parts), rows_record(Parts, Record), validate_record(Record),
    compose_reference(Record, URI).

%! 'uri-normalize'(+URI:string, -Normalized:string) is det.
%
% Lowercase the scheme and host, decode unreserved percent bytes and uppercase
% other escape digits. Preserve userinfo case, reserved bytes and empty query
% delimiters. Remove dot segments from anchored paths; a relative path keeps
% its dots until uri-resolve supplies a base. No scheme-specific port or URN
% namespace rules are guessed, and percent bytes need not represent UTF8.
'uri-normalize'(URI, Normalized) :-
    parse_reference(URI, uri(S,A,P,Q,F)),
    normalize_optional(scheme,S,NS), normalize_optional(authority,A,NA),
    normalize_percent(P,NP),
    ( ( S \== none ; A \== none ; P = [0'/|_] ) -> remove_dots(NP,DP)
    ; DP=NP ),
    normalize_optional(query,Q,NQ),
    normalize_optional(fragment,F,NF), render_target(uri(NS,NA,DP,NQ,NF),Normalized).

%! 'uri-resolve'(+Reference:string, +Base:string, -Absolute:string) is det.
%
% Resolve by RFC3986 section5.2. Base must have a scheme. An explicit reference
% scheme wins, including http:g; empty query replaces the base query. Resolution
% removes literal dot segments but does not decode percent escapes or fold case.
'uri-resolve'(Reference, Base, Absolute) :-
    parse_reference(Reference,R), parse_reference(Base,B),
    B = uri(BS,_,_,_,_),
    ( BS == none -> domain_error(absolute_uri_base,Base) ; true ),
    resolve_record(R,B,Target), render_target(Target,Absolute).

%! 'uri-contexts'(-Contexts:list) is det.
%
% Encoding contexts: path keeps slash; segment encodes it; query-value protects
% pair separators and plus; fragment retains its own reserved punctuation.
'uri-contexts'(Contexts) :- findall(Context, encoding_context(Context,_), Contexts).

%! 'uri-encode'(+Context:'Symbol', +Text:string, -Encoded:string) is det.
%
% Encode Unicode text as UTF8 percent octets in a context from uri-contexts.
% A literal percent is encoded too; encode raw data exactly once. NUL is %00.
'uri-encode'(Context, Text, Encoded) :-
    must_be(atom,Context), must_be(string,Text),
    ( encoding_context(Context,Native) -> true
    ; domain_error(uri_encoding_context,Context) ),
    'utf8-encode'(Text,_), uri_encoded(Native,Text,Atom), atom_string(Atom,Encoded).

%! 'uri-decode'(+Encoded:string, -Text:string) is det.
%
% Decode percent octets exactly once as strict UTF8. Literal plus stays plus.
% Malformed escapes, overlong UTF8, surrogate scalars and truncated sequences
% raise. Unescaped Unicode and encoded NUL survive. Decode after splitting the
% reference, since decoding a reserved slash or question mark changes structure.
'uri-decode'(Encoded, Text) :-
    'utf8-encode'(Encoded,Raw), percent_bytes(Raw,Bytes), 'utf8-decode'(Bytes,Text).

%! 'uri-query-parse'(+Style:'Symbol', +Query:string, -Pairs:list) is det.
%
% Decode an ampersand-separated query into String pairs, preserving order,
% duplicates and empty values. Bare keys get an empty value; empty segments
% are ignored. uri preserves literal plus; form reads plus as space in both
% keys and values. A semicolon is data. Escapes and UTF8 are checked strictly.
'uri-query-parse'(Style, Query, Pairs) :-
    query_style(Style), must_be(string,Query), string_codes(Query,Codes),
    query_rows(Codes,Style,Pairs).

%! 'uri-query-build'(+Style:'Symbol', +Pairs:list, -Query:string) is det.
%
% Encode String pairs in order using the native query-value safe characters.
% uri spells spaces %20; form spells them plus. Literal plus and pair separators
% are always escaped. Slash and question mark can remain within a value.
% Every pair gets an equals sign, including an empty key or value.
'uri-query-build'(Style, Pairs, Query) :-
    query_style(Style), must_be(list,Pairs), maplist(query_pair(Style),Pairs,Rows),
    atomics_to_string(Rows,"&",Query).

encoding_context(path,path).
encoding_context(segment,segment).
encoding_context('query-value',query_value).
encoding_context(fragment,fragment).

component_names([scheme,authority,path,query,fragment]).

record_rows(uri(S,A,P,Q,F), Rows) :-
    component_names(Names), row_options(Names,[S,A,some(P),Q,F],Rows).
row_options([],[],[]).
row_options([_|Names],[none|Options],Rows) :- !, row_options(Names,Options,Rows).
row_options([Name|Names],[some(Codes)|Options],[[Key,Text]|Rows]) :-
    atom_string(Name,Key), string_codes(Text,Codes), row_options(Names,Options,Rows).

rows_record(Rows,uri(S,A,P,Q,F)) :-
    maplist(component_pair,Rows,Native), unique_components(Native,[]),
    component_names(Names), maplist(component_option(Native),Names,[S,A,some(P),Q,F]).
component_pair(Row,Name-Codes) :-
    ( Row = [Key,Text] -> must_be(string,Key), must_be(string,Text)
    ; domain_error(uri_component_pair,Row) ),
    atom_string(Name,Key), component_names(Names),
    ( memberchk(Name,Names) -> string_codes(Text,Codes)
    ; domain_error(uri_component_key,Key) ).
unique_components([], _).
unique_components([Name-_|Rest],Seen) :-
    ( memberchk(Name,Seen) -> domain_error(unique_uri_component,Name) ; true ),
    unique_components(Rest,[Name|Seen]).
component_option(Rows,Name,Option) :-
    ( memberchk(Name-Codes,Rows) -> Option=some(Codes)
    ; Name == path -> Option=some([])
    ; Option=none ).

% RFC3986 AppendixB and section5.3 distinguish undefined from defined-empty.
% Native URN parsing uses a different record; keep one generic grammar.
parse_reference(Text,Record) :-
    must_be(string,Text), string_codes(Text,Codes),
    split_optional(Codes,0'#,BeforeFragment,F),
    split_optional(BeforeFragment,0'?,BeforeQuery,Q),
    take_until(BeforeQuery,[0':,0'/],Candidate,AfterScheme),
    ( AfterScheme = [0':|Root] -> S=some(Candidate)
    ; S=none, Root=BeforeQuery ),
    ( Root = [0'/,0'/|AuthorityPath]
    -> take_until(AuthorityPath,[0'/],Authority,P), A=some(Authority)
    ; A=none, P=Root ),
    Record=uri(S,A,P,Q,F), validate_record(Record).

split_optional(Codes,Separator,Before,Option) :-
    take_until(Codes,[Separator],Before,Rest),
    ( Rest = [_|After] -> Option=some(After) ; Option=none ).
take_until([],_,[],[]) :- !.
take_until([C|Rest],Stops,Before,After) :-
    ( memberchk(C,Stops) -> Before=[], After=[C|Rest]
    ; Before=[C|More], take_until(Rest,Stops,More,After) ).

validate_record(uri(S,A,P,Q,F)) :-
    component_names(Names), maplist(valid_optional,Names,[S,A,some(P),Q,F]),
    ( S=some(SC) -> ( SC=[First|_], ascii_alpha(First) -> true
                   ; domain_error(uri_scheme,SC) ) ; true ),
    ( A \== none -> ( P=[] ; P=[0'/|_] )
    ; P \= [0'/,0'/|_],
      ( S == none -> take_until(P,[0'/],FirstSegment,_), \+ memberchk(0':,FirstSegment)
      ; true ) ), !.
validate_record(Record) :- domain_error(unambiguous_uri_components,Record).
valid_optional(_,none) :- !.
valid_optional(Name,some(Codes)) :- valid_component(Codes,Name).
valid_component([], _).
valid_component([0'%,H,L|Rest],Name) :- Name \== scheme, !,
    hex_value(H,_), hex_value(L,_), valid_component(Rest,Name).
valid_component([Code|Rest],Name) :-
    ( component_char(Name,Code) -> true
    ; domain_error(uri_character(Name),Code) ), valid_component(Rest,Name).
% policy-inventory-exempt: mechanism-internal; reason=RFC3986 section3.1 permits these scheme punctuation characters; evidence=lib/lib_uri/lib_uri.pl:valid_component/2
component_char(scheme,C) :- !, ( ascii_alnum(C) ; memberchk(C,[0'+,0'-,0'.]) ).
component_char(_,C) :- unreserved(C), !.
% policy-inventory-exempt: mechanism-internal; reason=RFC3986 section2.2 defines this sub-delims production; evidence=lib/lib_uri/lib_uri.pl:valid_component/2
component_char(_,C) :- memberchk(C,[0'!,0'$,0'&,0'\',0'(,0'),0'*,0'+,0',,0';,0'=]), !.
component_char(authority,C) :- memberchk(C,[0':,0'@,0'[,0']]).
% policy-inventory-exempt: mechanism-internal; reason=RFC3986 section3.3 extends pchar with slash for paths; evidence=lib/lib_uri/lib_uri.pl:valid_component/2
component_char(path,C) :- memberchk(C,[0':,0'@,0'/]).
% policy-inventory-exempt: mechanism-internal; reason=RFC3986 section3.4 extends pchar with slash and question mark for queries; evidence=lib/lib_uri/lib_uri.pl:valid_component/2
component_char(query,C) :- memberchk(C,[0':,0'@,0'/,0'?]).
% policy-inventory-exempt: mechanism-internal; reason=RFC3986 section3.5 extends pchar with slash and question mark for fragments; evidence=lib/lib_uri/lib_uri.pl:valid_component/2
component_char(fragment,C) :- memberchk(C,[0':,0'@,0'/,0'?]).
ascii_alpha(C) :- ( C>=0'A, C=<0'Z ; C>=0'a, C=<0'z ).
ascii_alnum(C) :- ( ascii_alpha(C) ; C>=0'0, C=<0'9 ).
% policy-inventory-exempt: mechanism-internal; reason=RFC3986 section2.3 defines these unreserved punctuation characters; evidence=lib/lib_uri/lib_uri.pl:valid_component/2
unreserved(C) :- ( ascii_alnum(C) ; memberchk(C,[0'-,0'.,0'_,0'~]) ).
hex_value(C,V) :-
    ( code_type(C,xdigit(V)) -> true ; domain_error(uri_percent_digit,C) ).

% Workaround: swi-uri-empty-query - native construction drops a defined-empty
% query; compose every present component with its delimiter.
compose_reference(uri(S,A,P,Q,F), Text) :-
    phrase(reference_codes(S,A,P,Q,F),Codes), string_codes(Text,Codes).
reference_codes(S,A,P,Q,F) -->
    optional_codes(S,[],[0':]), optional_codes(A,[0'/,0'/],[]), sequence(P),
    optional_codes(Q,[0'?],[]), optional_codes(F,[0'#],[]).
optional_codes(none,_,_) --> [].
optional_codes(some(C),Before,After) --> sequence(Before),sequence(C),sequence(After).
sequence([]) --> [].
sequence([C|Rest]) --> [C], sequence(Rest).

% Dot removal can expose a leading // in a path without an authority. Its
% equivalent /.// spelling keeps the same five components when parsed again.
render_target(uri(S,none,[0'/,0'/|P],Q,F),Text) :- !,
    compose_reference(uri(S,none,[0'/,0'.,0'/,0'/|P],Q,F),Text).
render_target(Record,Text) :- compose_reference(Record,Text).

% Workaround: swi-uri-normalization-data - the native normalizer folds userinfo
% and URN content and decodes reserved octets through a liberal UTF8 decoder.
normalize_optional(_,none,none) :- !.
normalize_optional(Name,some(C),some(N)) :-
    normalize_percent(C,Escaped),
    ( Name == scheme -> lower_ascii(Escaped,N)
    ; Name == authority -> lower_host(Escaped,N)
    ; N=Escaped ).
normalize_percent([],[]).
normalize_percent([0'%,H,L|Rest],Out) :- !,
    hex_value(H,Hi),hex_value(L,Lo),Byte is Hi*16+Lo,
    ( unreserved(Byte) -> Out=[Byte|More]
    ; upper_hex(Hi,CH), upper_hex(Lo,CL), Out=[0'%,CH,CL|More] ),
    normalize_percent(Rest,More).
normalize_percent([C|Rest],[C|More]) :- normalize_percent(Rest,More).
upper_hex(Value,Code) :- ( Value<10 -> Code is 0'0+Value ; Code is 0'A+Value-10 ).
lower_ascii([],[]).
lower_ascii([0'%,H,L|Rest],[0'%,H,L|More]) :- !, lower_ascii(Rest,More).
lower_ascii([C|Rest],[L|More]) :-
    ( C>=0'A, C=<0'Z -> L is C+32 ; L=C ), lower_ascii(Rest,More).
lower_host(Codes,Lower) :-
    reverse(Codes,Rev), take_until(Rev,[0'@],HostRev,UserRev),
    reverse(HostRev,Host), lower_ascii(Host,LowerHost),
    reverse(UserRev,User), append(User,LowerHost,Lower).

% RFC3986 section5.2; optional values are copied without inventing delimiters.
% Workaround: swi-uri-urn-resolution - native resolution loses namespace
% content in an absolute URN; copy its generic path as RFC3986 requires.
resolve_record(uri(some(S),A,P,Q,F),_,uri(some(S),A,D,Q,F)) :- !, remove_dots(P,D).
resolve_record(uri(none,some(A),P,Q,F),uri(S,_,_,_,_),uri(S,some(A),D,Q,F)) :-
    !, remove_dots(P,D).
resolve_record(uri(none,none,[],Q,F),uri(S,A,P,BQ,_),uri(S,A,P,TQ,F)) :- !,
    ( Q == none -> TQ=BQ ; TQ=Q ).
% Workaround: swi-uri-empty-base-path - native resolution fails to transfer
% its merged path buffer when the base has an authority and an empty path.
resolve_record(uri(none,none,P,Q,F),uri(S,A,BP,_,_),uri(S,A,D,Q,F)) :-
    ( P=[0'/|_] -> Merged=P
    ; A \== none, BP==[] -> Merged=[0'/|P]
    ; reverse(BP,ReverseBase), take_until(ReverseBase,[0'/],_,ReversePrefix),
      reverse(ReversePrefix,Prefix), append(Prefix,P,Merged) ),
    remove_dots(Merged,D).

% RFC3986 section5.2.4 with a reversed output stack: each character is pushed
% and removed at most once, so long paths and repeated parents take linear work.
remove_dots(Codes,Result) :- dot_segments(Codes,[],Rev), reverse(Rev,Result).
dot_segments([],Stack,Stack) :- !.
dot_segments([0'.,0'.,0'/|Rest],Stack,Out) :- !, dot_segments(Rest,Stack,Out).
dot_segments([0'.,0'/|Rest],Stack,Out) :- !, dot_segments(Rest,Stack,Out).
dot_segments([0'/,0'.,0'/|Rest],Stack,Out) :- !, dot_segments([0'/|Rest],Stack,Out).
dot_segments([0'/,0'.],Stack,Out) :- !, dot_segments([0'/],Stack,Out).
dot_segments([0'/,0'.,0'.,0'/|Rest],Stack,Out) :- !,
    pop_segment(Stack,Parent), dot_segments([0'/|Rest],Parent,Out).
dot_segments([0'/,0'.,0'.],Stack,Out) :- !,
    pop_segment(Stack,Parent), dot_segments([0'/],Parent,Out).
dot_segments([0'.],Stack,Stack) :- !.
dot_segments([0'.,0'.],Stack,Stack) :- !.
dot_segments([0'/|Rest],Stack,Out) :- !,
    take_until(Rest,[0'/],Segment,Tail), push_codes(Segment,[0'/|Stack],Next),
    dot_segments(Tail,Next,Out).
dot_segments(Codes,Stack,Out) :-
    take_until(Codes,[0'/],Segment,Tail), push_codes(Segment,Stack,Next),
    dot_segments(Tail,Next,Out).
pop_segment(Stack,Parent) :- take_until(Stack,[0'/],_,Rest),
    ( Rest=[_|Parent] -> true ; Parent=[] ).
push_codes([],Stack,Stack).
push_codes([C|Rest],Stack,Out) :- push_codes(Rest,[C|Stack],Out).

percent_bytes([],[]).
percent_bytes([0'%,H,L|Rest],[Byte|Bytes]) :- !,
    hex_value(H,Hi),hex_value(L,Lo),Byte is Hi*16+Lo,percent_bytes(Rest,Bytes).
percent_bytes([0'%|Rest],_) :- !, domain_error(uri_percent_escape,[0'%|Rest]).
percent_bytes([C|Rest],[C|Bytes]) :- percent_bytes(Rest,Bytes).
query_style(Style) :-
    must_be(atom,Style),
    % policy-inventory-exempt: mechanism-internal; reason=URI and form codecs differ in their treatment of a literal plus; evidence=lib/lib_uri/lib_uri.pl:query_decode/3
    ( memberchk(Style,[uri,form]) -> true
    ; domain_error(uri_query_style,Style) ).
query_rows([],_,[]) :- !.
query_rows(Codes,Style,Pairs) :-
    split_optional(Codes,0'&,Part,Tail),
    ( Part == [] -> Pairs=More
    ; split_optional(Part,0'=,Key,Value),
      ( Value=some(VC) -> true ; VC=[] ),
      query_decode(Style,Key,K),query_decode(Style,VC,V), Pairs=[[K,V]|More] ),
    ( Tail=some(Rest) -> query_rows(Rest,Style,More) ; More=[] ).
query_decode(Style,Codes,Text) :-
    ( Style == form -> maplist(plus_space,Codes,Plain) ; Plain=Codes ),
    string_codes(Encoded,Plain), 'uri-decode'(Encoded,Text).
plus_space(0'+,0' ) :- !.
plus_space(C,C).
query_pair(Style,Pair,Encoded) :-
    ( Pair=[Key,Value] -> must_be(string,Key),must_be(string,Value)
    ; domain_error(uri_query_pair,Pair) ),
    query_encode(Style,Key,K), query_encode(Style,Value,V), atomics_to_string([K,"=",V],Encoded).
query_encode(Style,Text,Encoded) :-
    'uri-encode'('query-value',Text,URI),
    ( Style == form -> string_codes(URI,Codes), form_spaces(Codes,Form),string_codes(Encoded,Form)
    ; Encoded=URI ).
form_spaces([],[]).
form_spaces([0'%,0'2,0'0|Rest],[0'+|More]) :- !, form_spaces(Rest,More).
form_spaces([C|Rest],[C|More]) :- form_spaces(Rest,More).

:- det('uri-parts'/2).
:- det('uri-build'/2).
:- det('uri-normalize'/2).
:- det('uri-resolve'/3).
:- det('uri-contexts'/1).
:- det('uri-encode'/3).
:- det('uri-decode'/2).
:- det('uri-query-parse'/3).
:- det('uri-query-build'/3).
