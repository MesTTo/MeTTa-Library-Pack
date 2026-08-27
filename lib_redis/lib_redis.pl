% Purpose: shared spaces over Redis, SWI's own library(redis) underneath,
%   plugged into the engine's foreign-space seam. (redis-attach &shared
%   "host:port") binds a space name to a Redis set: adds SADD, removes
%   SREM, enumeration SMEMBERS, match enumerates and unifies engine-side,
%   and the engine's foreign clauses already split conjunctions per
%   conjunct and fire the write hooks, so joins and subscriptions behave
%   like any space. Every write also publishes on a per-space channel
%   that every attached process subscribes to; events carry the writer's
%   process nonce, so remote writes fire this process's hooks
%   asynchronously and local writes fire them synchronously through the
%   engine, each write heard exactly once per process.
%   [tested: test_subscriptions_fire_across_processes; commit=dcfc20be4933c19140ccb5759291401d13058301]
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- use_module(library(redis)).
:- use_module(library(broadcast)).

%Space, command connection, pub/sub connection, subscription thread,
%listener identity, set key, channel.
:- dynamic redis_space_conn/7.
:- dynamic redis_space_nonce/1.

:- ( redis_space_nonce(_) -> true
   ; uuid(Nonce), assertz(redis_space_nonce(Nonce)) ).

:- multifile seam:foreign_space/1.
:- multifile seam:foreign_add/2.
:- multifile seam:foreign_remove/3.
:- multifile seam:foreign_atoms/2.
:- multifile seam:foreign_match/3.
:- multifile seam:foreign_clear/1.

redis_space_address(Address, Host:Port) :-
    ( atom(Address) -> A = Address ; atom_string(A, Address) ),
    atomic_list_concat([Host, PortAtom], ':', A),
    atom_number(PortAtom, Port).

'redis-attach'(Space, Address, true) :-
    with_mutex(metta_redis_spaces, redis_space_attach(Space, Address)).

redis_space_attach(Space, Address) :-
    ( redis_space_conn(Space, _, _, _, _, _, _)
      -> throw(error(permission_error(attach, redis_space, Space),
                     context(Space, 'already attached; redis-detach first')))
    ; true ),
    redis_space_address(Address, HostPort),
    atom_concat('metta:space:', Space, Key),
    atom_concat('metta:events:', Space, Channel),
    redis_connect(HostPort, Conn, [reconnect(true)]),
    catch(redis_space_attach_subscription(Space, HostPort, Conn, Key, Channel),
          Error,
          ( redis_disconnect(Conn, [force(true)]), throw(Error) )).

redis_space_attach_subscription(Space, HostPort, Conn, Key, Channel) :-
    redis_connect(HostPort, SubConn, []),
    catch(redis_space_start_subscription(Space, Conn, SubConn, Key, Channel),
          Error,
          ( redis_disconnect(SubConn, [force(true)]), throw(Error) )).

redis_space_start_subscription(Space, Conn, SubConn, Key, Channel) :-
    uuid(ListenerId),
    Listener = redis_space_listener(ListenerId),
    listen(Listener, redis(SubConn, Channel, Payload),
           redis_space_event(Space, Payload)),
    catch(redis_space_register_subscription(
              Space, Conn, SubConn, ListenerId, Key, Channel),
          Error,
          ( unlisten(Listener), throw(Error) )).

%A unique second channel is a readiness handshake. redis_subscribe/4 starts
%its worker asynchronously, so the command connection publishes until the
%worker broadcasts one message back through SWI's listener. Seeing the
%message proves redis_listen/2 has registered before unsubscribe or detach.
redis_space_register_subscription(
        Space, Conn, SubConn, ListenerId, Key, Channel) :-
    uuid(ReadyId),
    atom_concat('metta:subscription-ready:', ReadyId, ReadyChannel),
    setup_call_cleanup(
        message_queue_create(ReadyQueue),
        setup_call_cleanup(
            listen(redis_space_ready(ReadyId),
                   redis(SubConn, ReadyChannel, _),
                   thread_send_message(ReadyQueue, ready)),
            redis_space_register_ready_subscription(
                Space, Conn, SubConn, ListenerId, Key, Channel,
                ReadyChannel, ReadyQueue),
            unlisten(redis_space_ready(ReadyId))),
        message_queue_destroy(ReadyQueue)).

redis_space_register_ready_subscription(
        Space, Conn, SubConn, ListenerId, Key, Channel,
        ReadyChannel, ReadyQueue) :-
    redis_subscribe(SubConn, [Channel, ReadyChannel], SubId,
                    [ detached(true),
                      at_exit(user:redis_space_subscription_exit(SubConn))
                    ]),
    catch(( redis_space_wait_until_subscribed(
                Space, Conn, SubId, ReadyChannel, ReadyQueue),
            redis_unsubscribe(SubId, [ReadyChannel]),
            assertz(redis_space_conn(
                Space, Conn, SubConn, SubId, ListenerId, Key, Channel)) ),
          Error,
          ( redis_space_abort_subscription(
                SubId, [Channel, ReadyChannel]),
            throw(Error) )).

redis_space_wait_until_subscribed(
        Space, Conn, SubId, ReadyChannel, ReadyQueue) :-
    catch(call_with_time_limit(
              10,
              redis_space_wait_for_ready(
                  Space, Conn, SubId, ReadyChannel, ReadyQueue)),
          time_limit_exceeded,
          throw(error(resource_error(redis_subscription),
                      context(Space,
                              'timed out waiting for Redis subscription')))).

redis_space_wait_for_ready(
        Space, Conn, SubId, ReadyChannel, ReadyQueue) :-
    repeat,
    ( thread_property(SubId, status(Status))
      -> ( Status == running
           -> redis(Conn, publish(ReadyChannel, ready), _),
              ( thread_get_message(ReadyQueue, ready, [timeout(0.01)])
                -> !
              ; fail )
         ; throw(error(redis_subscription_terminated(Status),
                       context(Space,
                               'Redis subscription stopped during attach'))) )
    ; throw(error(existence_error(redis_subscription, SubId),
                  context(Space,
                          'Redis subscription vanished during attach'))) ).

%Rollback an attachment whose subscription worker was already created.
%The worker's exit hook owns its pub/sub connection on every exit path.
redis_space_abort_subscription(SubId, Channels) :-
    ( catch(redis_unsubscribe(SubId, Channels), _, fail)
      -> true
    ; catch(thread_signal(SubId, throw(abort)), _, true) ).

redis_space_subscription_exit(SubConn) :-
    redis_disconnect(SubConn, [force(true)]).

'redis-detach'(Space, true) :-
    with_mutex(metta_redis_spaces, redis_space_detach(Space)).

redis_space_detach(Space) :-
    ( retract(redis_space_conn(
          Space, Conn, _SubConn, SubId, ListenerId, _, Channel))
      -> unlisten(redis_space_listener(ListenerId)),
         setup_call_cleanup(
             true,
             redis_space_unsubscribe(Space, SubId, [Channel]),
             redis_disconnect(Conn))
    ; throw(error(existence_error(redis_space, Space),
                  context(Space, 'not attached'))) ).

redis_space_unsubscribe(Space, SubId, Channels) :-
    catch(redis_unsubscribe(SubId, Channels),
          Error,
          ( ( thread_property(SubId, status(running))
              -> catch(thread_signal(SubId, throw(abort)),
                       SignalError,
                       throw(error(
                           redis_subscription_cleanup_failed(
                               Error, SignalError),
                           context(Space,
                                   'could not stop Redis subscription'))))
              ; true ),
            throw(Error) )).

%Event wire shape: op character, one space, writer nonce, one space,
%the atom's text. Own-nonce events are the echo of a local write whose
%hooks the engine already fired.
redis_space_publish(Conn, Channel, Op, AtomText) :-
    redis_space_nonce(Nonce),
    format(string(Event), "~w ~w ~w", [Op, Nonce, AtomText]),
    redis(Conn, publish(Channel, Event), _).

redis_space_event(Space, Payload) :-
    atom_string(Payload, Text),
    split_string(Text, " ", "", [Op, Nonce | Rest]),
    atomics_to_string(Rest, " ", AtomText),
    redis_space_nonce(Own),
    ( atom_string(Own, Nonce)
      -> true
    ; sread(AtomText, Atom),
      ( Op == "+" -> forall(seam:atom_added(Space, Atom), true)
      ; Op == "-" -> forall(seam:atom_removed(Space, Atom), true)
      ; true ) ).

seam:foreign_space(Space) :-
    redis_space_conn(Space, _, _, _, _, _, _).

%Everything, declared rather than inferred. A set in Redis can be read, added
%to, removed from, enumerated and deleted, so this space answers all five.
%Saying so is what lets the engine refuse an operation a DIFFERENT provider
%does not answer instead of reading the failure as "there is nothing there".
:- multifile seam:foreign_capability/2.
seam:foreign_capability(Space, Capability) :-
    redis_space_conn(Space, _, _, _, _, _, _),
    % policy-inventory-exempt: mechanism-internal; reason=a Redis set implements the five fixed foreign-provider protocol hooks rather than choosing an engine policy; evidence=lib/lib_redis/lib_redis.pl:foreign_capability/2
    member(Capability, [add, remove, match, enumerate, clear]).

%What an attached space's change events promise, which is the sixth
%capability and the one no method could have answered: a Redis set can be
%written by a process that is not this one, so whether a watcher here hears
%that write is a fact about the CHANNEL rather than about these five hooks.
%
%at-most-once, because Redis pub/sub is fire and forget: a message published
%while this process's subscriber connection is down is gone, there being no
%persistence and no acknowledgement [source: redis.io, Pub/Sub, "Redis
%Pub/Sub is fire and forget"]. Unordered, because a local write fires the
%hooks synchronously inside the write while a remote one arrives on the
%listener thread, so two writers' events interleave with no promised order.
%What the channel does give is no DOUBLE delivery: an event carries the
%writer's process nonce and the publisher's own echo is dropped, so a local
%write is heard exactly once and a remote one at most once
%[tested: test_local_writes_fire_subscriptions_exactly_once,
%test_subscriptions_fire_across_processes].
:- multifile seam:context_events/3.
seam:context_events(Space, 'at-most-once', unordered) :-
    redis_space_conn(Space, _, _, _, _, _, _).

seam:foreign_add(Space, Atom) :-
    redis_space_conn(Space, Conn, _, _, _, Key, Channel), !,
    swrite(Atom, S),
    redis(Conn, sadd(Key, S), _),
    redis_space_publish(Conn, Channel, "+", S).

seam:foreign_remove(Space, Atom, Removed) :-
    redis_space_conn(Space, Conn, _, _, _, Key, Channel), !,
    swrite(Atom, S),
    redis(Conn, srem(Key, S), N),
    ( N > 0
      -> Removed = true,
         redis_space_publish(Conn, Channel, "-", S)
    ; Removed = false ).

seam:foreign_atoms(Space, Pattern) :-
    redis_space_conn(Space, Conn, _, _, _, Key, _), !,
    redis(Conn, smembers(Key), Members),
    member(Text, Members),
    sread(Text, Pattern).

%The engine's foreign match clause hands one non-conjunctive pattern at
%a time; candidates enumerate here and unify in place. The options are ignored:
%a Redis set has no way to answer fewer members than a SMEMBERS returns, and
%ignoring a bound is always correct because the engine applies its own.
seam:foreign_match(Space, Pattern, _Options) :-
    redis_space_conn(Space, Conn, _, _, _, Key, _), !,
    redis(Conn, smembers(Key), Members),
    member(Text, Members),
    sread(Text, Candidate),
    Pattern = Candidate.

%Clearing deletes the whole set; the facts were shared, so this is a
%deliberate cross-process act.
seam:foreign_clear(Space) :-
    redis_space_conn(Space, Conn, _, _, _, Key, _), !,
    redis(Conn, del(Key), _).
