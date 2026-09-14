% Purpose: connect, listen, exchange datagrams and wait through owned sockets.
% Assumes: with-socket's acquisition expression transfers ownership of its first
% returned socket; functions accept its integer handle in the calling module.
% Guarantees: TCP bytes use File; datagrams retain packet boundaries, bytes and
% complete IPv4/IPv6 endpoints; scoped handles close on every exit.
% [tested: lib_socket; commit=7b42d5ee5cecb82709617b7ed08dfa2c1441f268].
% Owns resources: openers transfer streams to File; file-close! releases them.
% with-socket owns its handle until exhaustion, cut or exception. The native
% adapter owns accepted descriptors until their two stream halves close.
% Guarded by: File's handle mutex and native stream locks; callbacks and socket
% identities travel as arguments. One thread-local acquisition key exposes a
% call-local allocation set until the returned handle enters its callback scope.
% Decides: endpoint families are explicit, binding port zero asks the OS, waits
% use nonnegative seconds or infinite, and empty wait sets return immediately.
% [tested: lib_socket; commit=7b42d5ee5cecb82709617b7ed08dfa2c1441f268].

:- module(lib_socket,
          ['tcp-connect!'/2,'tcp-listen!'/3,'tcp-accept!'/2,
           'udp-bind!'/2,'udp-send!'/4,'udp-receive!'/2,
           'socket-kind'/2,'socket-endpoint'/3,'socket-wait!'/3,
           'socket-shutdown!'/3,'with-socket'/3]).
:- set_module(base(metta_engine)).
:- metta_requires(socket).
:- use_module(library(socket),
              [socket_create/2,tcp_bind/2,tcp_listen/2,tcp_connect/2,
               tcp_open_socket/2,tcp_close_socket/1,tcp_setopt/2,udp_send/4]).
:- use_module(library(error), [must_be/2,domain_error/2,permission_error/3]).
:- use_module(library(lists), [member/2,memberchk/2]).
:- use_module(library(apply), [maplist/3,maplist/4,include/3]).
:- use_module(library(assoc), [ord_list_to_assoc/2,get_assoc/3]).
:- use_module('../lib_file/lib_file',
              [known_file/2,adopt_file_stream/2,release_file_stream/1,'file-close!'/2]).
% Workaround: swi-relative-compound-source - resolve this atom relative to the
% importing file instead of reusing another directory's compound-path cache.
:- use_module('support/native', []).
:- meta_predicate open_socket(+,+,0,+,-).

%! 'tcp-connect!'(+Endpoint:list, -Handle:integer) is det.
%
% Connect to (endpoint ipv4|ipv6 HostString Port), resolving Host in that family.
% Port is 1..65535. Return a binary File handle: file-write-bytes! flushes bytes,
% file-read-bytes! reads a count or through EOF, and file-close! releases it.
% Native direct TCP bypasses proxy hooks. Openers refuse database transactions,
% whose rollback would lose File's ownership record without closing the socket.
'tcp-connect!'(Endpoint,Handle) :-
    outside_transaction('tcp-connect!'), endpoint_argument(Endpoint,1,Domain,Address),
    open_socket(Domain,stream,tcp_connect(Stream,Address),Stream,Handle).

%! 'tcp-listen!'(+Endpoint:list, +Backlog:integer, -Handle:integer) is det.
%
% Bind and listen at an endpoint, allowing port zero to request a free port.
% socket-endpoint local returns the actual bound address. Backlog is nonnegative;
% the OS applies its queue bound. tcp-accept! receives one connection at a time.
% The caller closes the listener with file-close!; accepted sockets live separately.
'tcp-listen!'(Endpoint,Backlog,Handle) :-
    outside_transaction('tcp-listen!'), endpoint_argument(Endpoint,0,Domain,Address),
    must_be(nonneg,Backlog),
    open_socket(Domain,stream,
                (tcp_bind(Stream,Address),tcp_listen(Stream,Backlog),tcp_setopt(Stream,nonblock)),
                Stream,Handle).

%! 'tcp-accept!'(+Listener:integer, -Handle:integer) is det.
%
% Wait for one connection and return its independent binary File handle.
% socket-endpoint peer reads the peer's actual address and source port. Closing
% the listener does not close accepted connections. Cancellation releases an
% accepted stream if its transfer to File has not completed. Keep the listener
% open until its acceptors have completed or have been cancelled and joined.
'tcp-accept!'(Listener,Handle) :-
    outside_transaction('tcp-accept!'), socket_handle(Listener,listener,Accept),
    must_be(var,Handle),accept_handle(Accept,Handle).

%! 'udp-bind!'(+Endpoint:list, -Handle:integer) is det.
%
% Bind an IPv4 or IPv6 datagram socket, allowing port zero. Return a File handle
% closed by file-close!. Use udp-send!/udp-receive! to preserve datagram boundaries;
% File's byte stream operations are intended for TCP connections.
'udp-bind!'(Endpoint,Handle) :-
    outside_transaction('udp-bind!'), endpoint_argument(Endpoint,0,Domain,Address),
    open_socket(Domain,dgram,(tcp_bind(Stream,Address),tcp_setopt(Stream,nonblock)),Stream,Handle).

%! 'udp-send!'(+Handle:integer, +Endpoint:list, +Bytes:list, -Done:boolean) is det.
%
% Send one datagram, including an empty one. Validate every byte in 0..255 before
% sending. The destination family must match the socket; its port is positive.
% Oversized packets and network failures raise the native error.
'udp-send!'(Handle,Endpoint,Bytes,true) :-
    socket_handle(Handle,udp,Stream), endpoint_argument(Endpoint,1,Domain,Address),
    lib_socket_native:endpoint(Stream,local,Family,_,_), family_domain(Family,Actual),
    ( Domain==Actual -> true ; domain_error(socket_destination_family(Family),Endpoint) ),
    must_be(list(between(0,255)),Bytes),
    udp_send(Stream,Bytes,Address,[as(codes),encoding(octet)]).

%! 'udp-receive!'(+Handle:integer, -Datagram:list) is det.
%
% Wait for (datagram Endpoint Bytes), retaining a complete numeric sender
% endpoint, empty packets and arbitrary bytes. Receive up to the ordinary UDP
% protocol bound; oversized packets raise instead of returning truncated data.
% Use socket-wait! for a finite readiness wait. Native input is nonblocking;
% concurrent readers retry through readiness and cancellation remains observable.
'udp-receive!'(Handle,[datagram,[endpoint,Family,Host,Port],Bytes]) :-
    socket_handle(Handle,udp,Stream), receive_packet(Stream,Bytes,Family,Host,Port).

%! 'socket-kind'(+Handle:integer, -Kind:'Symbol') is det.
%
% Return listener, tcp or udp from the live descriptor. A closed handle or an
% ordinary File stream raises. File's single table owns all three kinds.
'socket-kind'(Handle,Kind) :-
    must_be(integer,Handle), known_file(Handle,Stream), lib_socket_native:kind(Stream,Kind).

%! 'socket-endpoint'(+Handle:integer, +Side:'Symbol', -Endpoint:list) is det.
%
% Return (endpoint ipv4|ipv6 NumericHostString Port) for local or peer. IPv6
% scoped addresses retain their zone suffix. An unconnected socket has no peer
% and raises instead of inventing an address. Ephemeral ports are actual OS values.
'socket-endpoint'(Handle,Side,[endpoint,Family,Host,Port]) :-
    socket_handle(Handle,_,Stream), lib_socket_native:endpoint(Stream,Side,Family,Host,Port).

%! 'socket-wait!'(+Handles:list, +Timeout:any, -Ready:list) is det.
%
% Wait for readable sockets using nonnegative finite seconds or infinite. Zero
% polls once; an empty list returns immediately. Ready preserves input order and
% duplicate handles. Listener readiness means accept can proceed; TCP EOF is
% readable. Readiness alone does not promise a full application message. Waits
% check cancellation between native intervals of at most a quarter second.
'socket-wait!'(Handles,Timeout,Ready) :-
    must_be(list,Handles), wait_seconds(Timeout,Seconds), maplist(handle_stream,Handles,Streams),
    ( Streams==[] -> Ready=[]
    ; wait_readable(Streams,Seconds,Available),
      sort(Available,Unique),maplist(ready_pair,Unique,Marks),ord_list_to_assoc(Marks,Index),
      maplist(handle_pair,Handles,Streams,Pairs), include(pair_ready(Index),Pairs,Selected),
      maplist(pair_handle,Selected,Ready) ).

%! 'socket-shutdown!'(+Handle:integer, +Direction:'Symbol', -Done:boolean) is det.
%
% Shut down a TCP connection's read, write or both directions. Flush before a
% write shutdown so the peer receives pending bytes followed by EOF. The handle
% and descriptor remain owned until file-close!; a write shutdown retains input.
'socket-shutdown!'(Handle,Direction,true) :-
    socket_handle(Handle,tcp,Stream),must_be(atom,Direction),
    ( shutdown_direction(Direction,Native) -> true ; domain_error(socket_shutdown_direction,Direction) ),
    ( Direction==read -> true ; flush_output(Stream) ),
    lib_socket_native:shutdown(Stream,Native).

%! 'with-socket'(+Acquire:'Atom', +Function:'Atom', -Answer:any) is nondet.
%
% Evaluate held Acquire once and take ownership of its returned socket handle.
% Apply held Function to that integer in the calling module and yield every
% answer. Close on exhaustion, cut, exception or an invalid acquired File kind.
% Acquisition runs with signals enabled. Until it returns, the scope owns new
% sockets opened in that calling engine; a failed acquisition closes them all.
% Separate cursors and worker tasks remain responsible for their allocations.
% After selection it owns the returned socket, and other acquisition effects
% remain the acquisition's responsibility. Exception cleanup shuts down TCP
% before close; buffered output is not promised delivery on an exceptional exit.
% Cleanup failures retain the original outcome and every failed handle in
% error(socket_cleanup(Outcome,Failures),Context), after all closes were attempted.
% Nest scopes to keep listeners, clients and accepted connections independent.
% Cancel and join operations borrowing a handle before its owner closes it.
'with-socket'(Acquire,Function,Answer) :-
    outside_transaction('with-socket'), current_metta_module(Module),
    acquisition_context(Previous),Owned=owned([]),
    setup_call_catcher_cleanup(true,
        ( b_setval('$metta_socket_acquisition',Owned),
          once(eval_metta_in_module(Module,Acquire,Handle)),
          sig_atomic(select_acquired(Owned,Handle)),
          b_setval('$metta_socket_acquisition',Previous),
          eval_metta_in_module(Module,[Function,Handle],Answer) ),
        Outcome,
        ( b_setval('$metta_socket_acquisition',Previous),
          arg(1,Owned,Handles),close_owned(Outcome,Handles) )).

endpoint_argument(Endpoint,Minimum,Domain,Host:Port) :-
    ( Endpoint=[endpoint,Family,Text,Port] -> true ; domain_error(socket_endpoint,Endpoint) ),
    must_be(atom,Family),
    ( family_domain(Family,Domain) -> true ; domain_error(socket_family,Family) ),
    must_be(string,Text),string_codes(Text,Codes),
    ( Codes\==[], \+ memberchk(0,Codes) -> atom_string(Host,Text)
    ; domain_error(socket_host,Text) ),
    must_be(between(Minimum,65535),Port).

family_domain(ipv4,inet).
family_domain(ipv6,inet6).
shutdown_direction(read,0).
shutdown_direction(write,1).
shutdown_direction(both,2).

outside_transaction(Operation) :-
    ( current_transaction(_) -> permission_error(open,transaction_socket,Operation)
    ; true ).

open_socket(Domain,Type,Initialise,Stream,Handle) :-
    must_be(var,Handle),
    setup_call_catcher_cleanup(new_stream(Domain,Type,Stream),
        ( set_stream(Stream,type(binary)),call(Initialise),
          sig_atomic(publish_handle(Stream,Handle)) ),
        Outcome,release_unpublished(Outcome,Stream)).

new_stream(Domain,Type,Stream) :-
    setup_call_catcher_cleanup(socket_create(Socket,[domain(Domain),type(Type)]),
                              tcp_open_socket(Socket,Stream),Outcome,release_raw(Outcome,Socket)).
release_raw(exit,_) :- !.
release_raw(_,Socket) :- tcp_close_socket(Socket).

publish_handle(Stream,Handle) :-
    adopt_file_stream(Stream,Handle),acquisition_context(Current),
    ( Current=owned(Handles) -> nb_linkarg(1,Current,[Handle-Stream|Handles]) ; true ).

release_unpublished(exit,_) :- !.
release_unpublished(_,Stream) :-
    call_cleanup(lib_socket_native:abort(Stream),release_file_stream(Stream)).

accept_handle(Listener,Handle) :-
    Publication=stream(none),
    setup_call_catcher_cleanup(lib_socket_native:accept_owner(Owner),
        sig_atomic(accept_once(Owner,Listener,Publication,Result)),Outcome,
        finish_accept(Outcome,Owner,Publication)),
    ( Result==blocked -> wait_readable([Listener],infinite,_),accept_handle(Listener,Handle)
    ; Handle=Result ).

accept_once(Owner,Listener,Publication,Handle) :-
    lib_socket_native:try_accept(Owner,Listener,In,Out),
    ( In==blocked -> Handle=blocked
    ; stream_pair(Stream,In,Out),nb_linkarg(1,Publication,Stream),
      publish_handle(Stream,Handle) ).

finish_accept(exit,Owner,_) :- !,lib_socket_native:finish_accept(Owner,true).
finish_accept(_,Owner,Publication) :-
    call_cleanup(
        ( lib_socket_native:abort_accept(Owner),arg(1,Publication,Stream),
          ( Stream==none -> true ; release_file_stream(Stream) ) ),
        lib_socket_native:finish_accept(Owner,false)).

socket_handle(Handle,Expected,Stream) :-
    must_be(integer,Handle), known_file(Handle,Stream),lib_socket_native:kind(Stream,Actual),
    ( var(Expected) -> Expected=Actual
    ; Expected==Actual -> true ; domain_error(socket_kind(Expected),Handle) ).

receive_packet(Stream,Bytes,Family,Host,Port) :-
    lib_socket_native:receive(Stream,Packet,F,H,P),
    ( Packet==blocked -> wait_readable([Stream],infinite,_),receive_packet(Stream,Bytes,Family,Host,Port)
    ; Bytes=Packet,Family=F,Host=H,Port=P ).

wait_seconds(Value,Seconds) :-
    ( Value==infinite -> Seconds=infinite
    ; must_be(number,Value), Seconds is float(Value),
      % policy-inventory-exempt: mechanism-internal; reason=nonnegative finite IEEE waits include immediate zero but exclude infinities and NaN; evidence=lib/lib_socket/lib_socket.pl:wait_seconds/2
      ( Seconds>=0, float_class(Seconds,Class),memberchk(Class,[zero,normal,subnormal])
      -> true ; domain_error(nonnegative_finite_socket_timeout,Value) ) ).
handle_stream(Handle,Stream) :- socket_handle(Handle,_,Stream).
handle_pair(Handle,Stream,Handle-Stream).
ready_pair(Stream,Stream-true).
pair_ready(Ready,_-Stream) :- get_assoc(Stream,Ready,_).
pair_handle(Handle-_,Handle).

% The clib provider also checks pending signals between 250ms waits.
% https://github.com/SWI-Prolog/packages-clib/blob/a69cf00dcf0dd2e3ac1aa9565fbebf4aa4ceb5da/nonblockio.c#L452
wait_readable(Streams,Seconds,Ready) :-
    ( Seconds==infinite -> Deadline=infinite
    ; lib_socket_native:monotonic(Now),Deadline is Now+Seconds ),
    wait_until(Streams,Deadline,Ready).
wait_until(Streams,Deadline,Ready) :-
    ( Deadline==infinite -> Slice=0.25
    ; lib_socket_native:monotonic(Now),Slice is max(0.0,min(0.25,Deadline-Now)) ),
    wait_for_input(Streams,Available,Slice),
    ( Available\==[] -> Ready=Available
    ; Slice=:=0 -> Ready=[]
    ; wait_until(Streams,Deadline,Ready) ).

acquisition_context(Current) :-
    ( nb_current('$metta_socket_acquisition',Value) -> Current=Value ; Current=none ).
select_acquired(Owned,Handle) :-
    must_be(integer,Handle),known_file(Handle,Stream),
    ( Handle>=3 -> arg(1,Owned,Handles),nb_linkarg(1,Owned,[Handle-Stream|Handles]) ; true ),
    lib_socket_native:kind(Stream,_),nb_linkarg(1,Owned,[Handle-Stream]).
close_owned(Outcome,Handles) :-
    findall(Handle-Error,
        ( member(Handle-Stream,Handles),
          catch(call_cleanup(( exceptional_exit(Outcome) -> lib_socket_native:abort(Stream) ; true ),
                             'file-close!'(Handle,_)),Error,true),nonvar(Error) ),
        Failures),
    ( Failures==[] -> true
    ; throw(error(socket_cleanup(Outcome,Failures),
                  context('with-socket','Every owned handle was offered to file-close!'))) ).
exceptional_exit(exception(_)).
exceptional_exit(external_exception(_)).

:- det('tcp-connect!'/2).
:- det('tcp-listen!'/3).
:- det('tcp-accept!'/2).
:- det('udp-bind!'/2).
:- det('udp-send!'/4).
:- det('udp-receive!'/2).
:- det('socket-kind'/2).
:- det('socket-endpoint'/3).
:- det('socket-wait!'/3).
:- det('socket-shutdown!'/3).
