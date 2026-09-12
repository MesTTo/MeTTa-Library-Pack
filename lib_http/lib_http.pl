% Purpose: exchange HTTP bytes and parsed fields through owned streams and servers.
% Assumes: a server handler accepts an Expression and supplies one http-response;
% its captured execution module remains alive until that server stops.
% Guarantees: non-2xx statuses remain data, framing is owned by the transport,
% repeated fields survive, and scopes release on exhaustion, cut and exception.
% [tested: lib_http; commit=781ee98e188c23ea7ef9298636d6e5e6c7fdc727].
% Owns resources: http-open! transfers its response stream to File's handle table.
% A started server belongs to its caller until http-server-stop!; with-http and
% with-http-server retain ownership for the lifetime of their answer streams.
% Each stop joins its temporary native worker before returning or unwinding.
% Guarded by: '$metta_http_start' serializes starts; each port has a stop mutex.
% File guards its shared handles. Server IDs, handlers and modules travel as
% arguments in the native port registry; a stale ID never stops a later server.
% Decides: redirects require an explicit option; the native timeout defaults
% remain. The transport supplies framing, host, connection and response date.
% [source: https://github.com/SWI-Prolog/packages-http/blob/8e6b758778aed1986f81a4a7a8efeb475faa35aa/http_open.pl:http_open/3; commit=0f22b69cfca5c108e4126bdd56ab9bb2e493744d].

:- module(lib_http,
          ['http-request!'/4, 'http-open!'/4, 'with-http'/5,
           'http-server-start!'/5, 'http-server-stop!'/2, 'with-http-server'/6,
           'http-server-url'/2, 'http-header'/3, 'http-methods'/1]).
:- set_module(base(metta_engine)).
:- metta_requires(http).
:- use_module('../lib_file/lib_file',
              [adopt_file_stream/2,release_file_stream/1,'file-close!'/2,'file-read-bytes!'/2]).
:- use_module(library(http/http_open), [http_open/3]).
:- use_module(library(http/thread_httpd),
              [http_server/2,http_stop_server/2,http_current_server/2,http_current_worker/2]).
:- use_module(library(http/http_client), [http_read_data/3]).
:- use_module(library(http/http_stream), [stream_range_open/3]).
:- use_module(library(http/http_header), [http_parse_header_value/3]).
:- use_module(library(socket),
              [socket_create/2,tcp_setopt/2,tcp_bind/2,tcp_listen/2,tcp_close_socket/1]).
:- use_module(library(uri), [uri_components/2,uri_data/3]).
:- use_module(library(error), [must_be/2,domain_error/2,permission_error/3]).
:- use_module(library(lists), [member/2,memberchk/2,append/3,select/3]).
:- use_module(library(apply), [maplist/2,maplist/3,maplist/4]).
:- if(exists_source(library(http/http_ssl_plugin))).
:- use_module(library(http/http_ssl_plugin), []).
:- endif.

%! 'http-methods'(-Methods:list) is det.
%
% The installed client's method symbols, including extensions registered with
% its native method map. The standard provider supplies delete/get/head/post/
% put/patch/options. A request refuses a method outside this catalog.
'http-methods'(Methods) :- findall(Method,http_open:map_method(Method,_),Methods).

%! 'http-open!'(+Method:atom, +URL:string, +Options:list, -Response:list) is det.
%
% Open (http-response Status Fields Handle). Handle is a binary File handle;
% file-read-bytes! reads it and file-close! releases it. HEAD and no-content
% statuses expose an empty stream. Status codes, including errors, are data.
% Options are (header Name Value), (body MediaType Bytes), (timeout Seconds),
% (redirect Bool) and (max-redirect Count). Headers repeat; other options do not.
% Timeout accepts positive seconds or infinite; the default is native infinite.
% Redirect defaults to False, with the native maximum of ten when enabled.
% Host, Connection, Content-Length and Transfer-Encoding belong to the client;
% Content-Type comes from body, and a User-Agent header replaces its default.
%
% Fields are String-key pairs in received order. Names use the native lowercase
% hyphen spelling. Values preserve parsed numbers, Strings, lists and compound
% structures, whose first element is their String name. Cookies and media
% preferences therefore remain data; fields are not the original wire text.
'http-open!'(Method, URL, Options, ['http-response',Status,Fields,Handle]) :-
    client_arguments(Method,URL,Options,Native),
    setup_call_catcher_cleanup(
        response_stream(Method,URL,Native,Status,Headers,Stream),
        ( header_rows(Headers,Fields),adopt_file_stream(Stream,Handle) ),
        Outcome,
        ( Outcome == exit -> true ; release_file_stream(Stream) )).

%! 'http-request!'(+Method:atom, +URL:string, +Options:list, -Response:list) is det.
%
% Read (http-response Status Fields Bytes) and close its stream before returning.
% The arguments and parsed fields are those of http-open!. Encode/decode text
% with lib_encoding, JSON with lib_json, and store bytes through lib_file.
'http-request!'(Method,URL,Options,['http-response',Status,Fields,Bytes]) :-
    setup_call_cleanup('http-open!'(Method,URL,Options,['http-response',Status,Fields,Handle]),
                       'file-read-bytes!'(Handle,Bytes),'file-close!'(Handle,_)).

%! 'with-http'(+Method:atom, +URL:string, +Options:list, +Function:'Atom', -Answer:any) is nondet.
%
% Apply a held Function to the evaluated streaming response and yield every
% answer. Its handle closes on exhaustion, early cut and exception. Function
% takes an Expression parameter; the response is quoted at the call boundary.
'with-http'(Method,URL,Options,Function,Answer) :-
    current_metta_module(Module),
    setup_call_cleanup('http-open!'(Method,URL,Options,Response),
                       eval_metta_in_module(Module,[Function,[quote,Response]],Answer),
                       close_response(Response)).

close_response(['http-response',_,_,Handle]) :- 'file-close!'(Handle,_).

% Keep the final owned stream in Setup so cancellation after adoption can
% still withdraw its File record, including a range filter and its parent.
% [tested: lib_http:post_adoption_cancellation_releases_filtered_responses; commit=781ee98e188c23ea7ef9298636d6e5e6c7fdc727].
response_stream(Method,URL,Native,Status,Headers,BodyStream) :-
    setup_call_catcher_cleanup(
        http_open(URL,Stream,[method(Method),status_code(Status),headers(Headers),
                             connection(close),authenticate(false)|Native]),
        ( set_stream(Stream,type(binary)),
          ( ( Method == head ; no_body_status(Status) )
          -> stream_range_open(Stream,BodyStream,[size(0),onclose(close_http_parent)])
          ; BodyStream=Stream ) ),
        Outcome,( Outcome==exit -> true ; close_if_open(Stream) )).

close_http_parent(Stream,_) :- close(Stream).

no_body_status(204).
no_body_status(205).
no_body_status(304).

close_if_open(Stream) :- ( is_stream(Stream) -> close(Stream) ; true ).

client_arguments(Method,URL,Options,Native) :-
    must_be(atom,Method),
    ( http_open:map_method(Method,_) -> true ; domain_error(http_method,Method) ),
    must_be(string,URL), string_codes(URL,Codes),
    ( forall(member(C,Codes),(C>32,C=\=127)) -> true ; domain_error(http_url,URL) ),
    uri_components(URL,Parts),uri_data(scheme,Parts,Scheme),uri_data(authority,Parts,Authority),
    ( nonvar(Authority),Authority\=='' -> true ; domain_error(http_url,URL) ),
    ( Scheme == https -> metta_require_platform('http-open!',https)
    ; Scheme == http -> true ; domain_error(http_url_scheme,Scheme) ),
    option_list(client,Options,Converted),
    ( memberchk(redirect(_),Converted) -> Native=Converted
    ; Native=[redirect(false)|Converted] ).

option_list(Kind,Options,Native) :-
    must_be(list,Options), maplist(http_option(Kind),Options,Keys,Native),
    single_options(Keys,[]).

single_options([], _).
single_options([header|Rest],Seen) :- !, single_options(Rest,Seen).
single_options([Key|Rest],Seen) :-
    ( memberchk(Key,Seen) -> domain_error(duplicate_http_option,Key) ; true ),
    single_options(Rest,[Key|Seen]).

http_option(client,[header,Name,Value],Key,Option) :- !,
    outgoing_header(Name,Value,Native,Atom),
    ( Native == user_agent -> Key=user_agent,Option=user_agent(Atom)
    ; client_owned_header(Native) -> domain_error(http_owned_request_header,Name)
    ; Key=header,header_name(Native,Wire),atom_string(WireAtom,Wire),
      Option=request_header(WireAtom=Atom) ).
http_option(client,[body,Type,Bytes],body,post(bytes(Media,Bytes))) :- !,
    media_type(Type,Media),byte_list(Bytes).
http_option(client,[redirect,Enabled],redirect,redirect(Enabled)) :- !,
    must_be(boolean,Enabled).
http_option(client,['max-redirect',Count],max_redirect,max_redirect(Count)) :- !,
    ( Count == infinite -> true ; must_be(nonneg,Count) ).
http_option(_, [timeout,Value],timeout,timeout(Seconds)) :- !,
    http_seconds(Value,Seconds).
http_option(server,[workers,Count],workers,workers(Count)) :- !,
    must_be(positive_integer,Count).
http_option(server,['keep-alive-timeout',Value],keep_alive_timeout,keep_alive_timeout(Seconds)) :- !,
    http_seconds(Value,Seconds).
http_option(Kind,Option,_,_) :- domain_error(http_options(Kind),Option).

http_seconds(Value,Seconds) :-
    ( Value == infinite -> Seconds=infinite
    ; must_be(number,Value), Seconds is float(Value),
      ( Seconds>0, float_class(Seconds,Class),memberchk(Class,[normal,subnormal])
      -> true ; domain_error(positive_finite_http_timeout,Value) ) ).

client_owned_header(host).
client_owned_header(content_type).
client_owned_header(Name) :- framing_header(Name).
framing_header(content_length).
framing_header(transfer_encoding).
framing_header(connection).

outgoing_header(Name,Value,Native,Atom) :-
    field_name(Name,Native),field_value(Value),atom_string(Atom,Value).

field_name(Name,Native) :-
    must_be(string,Name),string_codes(Name,Codes),
    ( Codes\==[],forall(member(C,Codes),(C>=33,C=<126)),
      phrase(http_header:field_name(Native),Codes)
    -> true ; domain_error(http_header_name,Name) ).

field_value(Value) :-
    must_be(string,Value),string_codes(Value,Codes),
    ( forall(member(C,Codes),(C=:=9;(C>=32,C=<255,C=\=127)))
    -> true ; domain_error(http_header_value,Value) ).

media_type(Text,Type) :-
    field_value(Text),atom_string(Type,Text),
    ( http_parse_header_value(content_type,Type,_) -> true
    ; domain_error(http_media_type,Text) ).

byte_list(Bytes) :- must_be(list(between(0,255)),Bytes).

header_rows([],[]).
header_rows([status_code(_)|Rest],Rows) :- !,header_rows(Rest,Rows).
header_rows([Field|Rest],[[Name,Value]|Rows]) :-
    Field=..[Native,Data],header_name(Native,Name),native_data(Data,Value),
    header_rows(Rest,Rows).

header_name(Native,Name) :-
    atomic_list_concat(Parts,'_',Native),atomic_list_concat(Parts,'-',Atom),
    atom_string(Atom,Name).

native_data(Data,Value) :-
    ( string(Data) -> Value=Data
    ; number(Data) -> Value=Data
    ; atom(Data) -> atom_string(Data,Value)
    ; is_list(Data) -> maplist(native_data,Data,Value)
    ; Data=..[Name|Args],atom_string(Name,Text),maplist(native_data,Args,Values),
      Value=[Text|Values] ).

%! 'http-header'(+Fields:list, +Name:string, -Value:any) is nondet.
%
% Enumerate every matching parsed field, case-insensitively and in received
% order. Missing fields give no answers. Values retain their parsed structure.
'http-header'(Fields,Name,Value) :-
    must_be(list,Fields),maplist(field_pair,Fields),
    field_name(Name,Native),header_name(Native,Canonical),
    member([Canonical,Value],Fields).

field_pair(Pair) :-
    ( nonvar(Pair),Pair=[Name,_],string(Name) -> true
    ; domain_error(http_field_pair,Pair) ).

%! 'http-server-start!'(+Host:string, +Port:integer, +Handler:'Atom', +Options:list, -Server:list) is det.
%
% Listen at Host and Port; zero asks the OS for a free port. Return
% (http-server Host BoundPort ID). ID distinguishes later reuse of the same port.
% The caller must stop it. Options are
% (workers Count), (timeout Seconds) and (keep-alive-timeout Seconds), retaining
% the native defaults of five workers, sixty seconds and two seconds.
% Handler and its calling module travel to each worker. Handler accepts an
% evaluated (http-request Method Path Target Fields Bytes), where Path is
% decoded and Target is the raw request URI. It supplies its first
% (http-response Status Headers Bytes). Routes are ordinary MeTTa equations.
% Headers are String/String pairs, with one optional Content-Type; other
% framing, Connection, Status and Date fields are owned by the server. Final
% statuses range 200..599. Statuses 204/205/304 require empty bytes. HEAD sends
% only the metadata of the returned bytes. An empty answer stream gives 404;
% malformed answers and handler exceptions become the host's error responses.
% Handler printing goes to standard error; only its response defines the wire.
% Start and stop refuse inside a transaction: its database snapshot cannot
% share lifecycle changes with workers. Start outside it and scope requests.
'http-server-start!'(Host,Requested,Handler,Options,['http-server',Host,Port,ID]) :-
    lifecycle_outside_transaction('http-server-start!'),
    host_argument(Host,Address),must_be(between(0,65535),Requested),
    ( var(Handler) -> must_be(nonvar,Handler) ; true ),
    ( acyclic_term(Handler) -> true ; domain_error(acyclic_http_handler,Handler) ),
    option_list(server,Options,Native),current_metta_module(Module),
    flag('$metta_http_server_id',ID,ID+1),
    with_mutex('$metta_http_start',
        setup_call_catcher_cleanup(listener(Address,Requested,Port,Socket,Queue),
            sig_atomic(http_server(serve(ID,Module,Handler),
                [port(Address:Port),tcp_socket(Socket),silent(true)|Native])),
            Outcome,failed_server(Outcome,ID,Module,Handler,Port,Socket,Queue))).

host_argument(Host,Address) :-
    must_be(string,Host),string_codes(Host,Codes),
    ( Codes\==[],forall(member(C,Codes),(C>32,C=\=127)) -> atom_string(Address,Host)
    ; domain_error(http_host,Host) ).

listener(Address,Requested,Port,Socket,Queue) :-
    thread_httpd:address_domain(Address:Port,Domain),
    setup_call_catcher_cleanup(socket_create(Socket,[domain(Domain)]),
        ( tcp_setopt(Socket,reuseaddr),
          ( Requested=:=0 -> true ; Port=Requested ),tcp_bind(Socket,Address:Port),
          tcp_listen(Socket,64),
          thread_httpd:make_addr_atom(httpd,Address:Port,Queue),
          ( http_current_server(_Owner:_Goal,Port) -> permission_error(create,http_server,Port)
          ; queue_exists(Queue) -> permission_error(create,message_queue,Queue)
          ; true ) ),
        Outcome,(Outcome==exit -> true ; tcp_close_socket(Socket))).

% Workaround: swi-http-partial-startup - release the fresh worker queue after a failed native start.
% http_server/2 creates workers before the accept thread and leaves them alive
% when thread creation fails. The listener already owns a unique bound port and
% queue name. A successful start transfers them to the native stop operation.
failed_server(exit,_,_,_,_,_,_) :- !.
failed_server(_,ID,Module,Handler,Port,Socket,Queue) :-
    ( http_current_server(serve(ID,Module,Handler),Port) -> stop_native_server(Port)
    ; setup_call_cleanup(true,discard_queue(Queue),tcp_close_socket(Socket)) ).

discard_queue(Queue) :-
    ( queue_exists(Queue)
    -> thread_httpd:resize_pool(Queue,0),
       retractall(thread_httpd:queue_options(Queue,_)),message_queue_destroy(Queue)
    ; true ).

queue_exists(Queue) :-
    catch(message_queue_property(Queue,size(_)),
          error(existence_error(message_queue,Queue),_),fail).

%! 'http-server-stop!'(+Server:list, -Done:boolean) is det.
%
% Finish active requests and release the server's workers, queue and listener.
% Repeated stop is harmless. A worker cannot stop its own server, and a handle
% whose ID is no longer live cannot stop a later server on the same port.
% Pending connections follow native stop. Stop refuses inside a transaction,
% whose database snapshot cannot observe the workers' lifecycle changes.
'http-server-stop!'(Server,true) :-
    lifecycle_outside_transaction('http-server-stop!'),
    server_endpoint(Server,_,Port,ID),thread_self(Self),
    ( http_current_server(serve(ID,_,_),Port),http_current_worker(Port,Self)
    -> permission_error(stop,current_http_server,Server)
    ; true ),
    format(atom(Mutex),'$metta_http_stop:~d',[Port]),
    with_mutex(Mutex,
        ( http_current_server(serve(ID,_,_),Port) -> stop_native_server(Port)
        ; true )).

lifecycle_outside_transaction(Operation) :-
    ( current_transaction(_)
    -> permission_error(access,http_server_in_transaction,Operation)
    ; true ).

% Workaround: swi-http-stop-ack - isolate the native untagged shutdown acknowledgement.
% A timeout followed by the wake-up connection leaves http_stopped in the
% native caller's mailbox. A new thread owns that entire stop protocol, and
% joining in cleanup lets the shutdown finish even when the caller unwinds.
stop_native_server(Port) :-
    setup_call_cleanup(thread_create(http_stop_server(Port,[]),Thread,[]),
                       true,thread_join(Thread,Outcome)),
    ( Outcome == true -> true
    ; Outcome=exception(Error) -> throw(Error)
    ; throw(error(http_server_stop_failed(Port,Outcome),_)) ).

server_endpoint(Server,Host,Port,ID) :-
    ( nonvar(Server),Server=['http-server',Host,Port,ID]
    -> host_argument(Host,_),must_be(between(1,65535),Port),must_be(nonneg,ID)
    ; domain_error(http_server,Server) ).

%! 'http-server-url'(+Server:list, -URL:string) is det.
%
% The server's HTTP origin, with IPv6 brackets when needed and a trailing slash.
% It remains endpoint data after the server stops; it does not check liveness.
'http-server-url'(Server,URL) :-
    server_endpoint(Server,Host,Port,_),
    ( sub_string(Host,_,_,_,":") -> format(string(URL),'http://[~s]:~d/',[Host,Port])
    ; format(string(URL),'http://~s:~d/',[Host,Port]) ).

%! 'with-http-server'(+Host:string, +Port:integer, +Handler:'Atom', +Options:list, +Function:'Atom', -Answer:any) is nondet.
%
% Apply held Function to the evaluated server value and yield every answer.
% Stop on exhaustion, cut or exception. Handler and Function take Expression
% parameters; their values are quoted at their respective call boundaries.
'with-http-server'(Host,Port,Handler,Options,Function,Answer) :-
    current_metta_module(Module),
    setup_call_cleanup('http-server-start!'(Host,Port,Handler,Options,Server),
                       eval_metta_in_module(Module,[Function,[quote,Server]],Answer),
                       'http-server-stop!'(Server,_)).

serve(_ID,Module,Handler,Request) :-
    memberchk(method(Method),Request),memberchk(path(PathAtom),Request),
    memberchk(request_uri(TargetAtom),Request),
    atom_string(PathAtom,Path),atom_string(TargetAtom,Target),
    ( append(_,[http_version(_)|Header],Request) -> header_rows(Header,Fields) ; Fields=[] ),
    ( ( memberchk(content_length(_),Request) ; memberchk(transfer_encoding(_),Request) )
    -> http_read_data(Request,Bytes,[to(codes),input_encoding(octet)])
    ; Bytes=[] ),
    dispatch(Module,Handler,['http-request',Method,Path,Target,Fields,Bytes]).

dispatch(Module,Handler,Request) :-
    ( with_output_to(user_error,
                     once(eval_metta_in_module(Module,[Handler,[quote,Request]],Response)))
    -> response_reply(Response,Reply,Headers)
    ; Reply=bytes('application/octet-stream',[]),Headers=[status(404)] ),
    throw(http_reply(Reply,[connection(close)|Headers])).

response_reply(Response,bytes(Type,Bytes),[status(Status)|Headers]) :-
    ( nonvar(Response),Response=['http-response',Status,Fields,Bytes] -> true
    ; domain_error(http_response,Response) ),
    must_be(between(200,599),Status),byte_list(Bytes),
    ( no_body_status(Status),Bytes\==[] -> domain_error(empty_http_response_body,Status) ; true ),
    must_be(list,Fields),maplist(response_header,Fields,Native),
    ( select(content_type(Type0),Native,Headers0)
    -> ( memberchk(content_type(_),Headers0) -> domain_error(duplicate_http_header,content_type)
       ; Type=Type0,Headers=Headers0 )
    ; Type='application/octet-stream',Headers=Native ).

response_header(Pair,Field) :-
    ( nonvar(Pair),Pair=[Name,Value] -> true ; domain_error(http_header_pair,Pair) ),
    outgoing_header(Name,Value,Native,Atom),
    ( ( framing_header(Native) ; Native==status ; Native==date )
    -> domain_error(http_owned_response_header,Name)
    ; ( Native==content_type -> media_type(Value,Atom) ; true ) ),
    Field=..[Native,Atom].

:- det('http-methods'/1).
:- det('http-open!'/4).
:- det('http-request!'/4).
:- det('http-server-start!'/5).
:- det('http-server-stop!'/2).
:- det('http-server-url'/2).
