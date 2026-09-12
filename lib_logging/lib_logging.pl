% Purpose: route structured topic/level messages through the host message hooks.
% Assumes: a log-to! handler accepts an evaluated Expression and answers Bool;
% the first answer is its verdict. The payload itself is held.
% Guarantees: disabled topics invoke no handler; enabled messages follow the
% host hook order, preserve payload syntax and propagate handler exceptions.
% [tested: lib_logging; commit=WORKTREE].
% Owns resources: topic settings persist in the host debug registry until
% changed. A handler and its module are arguments owned by one message call.
% Guarded by: prolog_debug serializes topic declaration, changes and snapshots.
% Decides: topics start disabled; debug, informational, warning and error use
% the corresponding host message kinds, including host printing and halt policy.
% [source: https://github.com/SWI-Prolog/swipl-devel/blob/fc7ef84b949378b729052c3ade79c90ce5416abb/boot/messages.pl:print_message_guarded/2; commit=WORKTREE].

:- module(lib_logging,
          [ 'log!'/4, 'log-to!'/5, 'log-topic!'/3, 'log-enabled'/2,
            'log-topics'/1, 'log-levels'/1, 'log-format'/4
          ]).
:- set_module(base(metta_engine)).
:- use_module(library(debug), [debug/1, nodebug/1, debugging/2]).
:- use_module(library(error), [must_be/2]).
:- multifile prolog:message//1, user:message_hook/3.

%! 'log-topic!'(+Topic:string, +Enabled:boolean, -Unit:list) is det.
%
% Enable or disable this exact topic for every level. Settings are process-wide
% in the host debug registry under metta_log(Topic); unrelated host topics are
% untouched. Configured topics remain discoverable when disabled.
'log-topic!'(Topic, Enabled, []) :-
    must_be(string, Topic), must_be(boolean, Enabled),
    with_mutex(prolog_debug,
               ( prolog_debug:debug_topic(metta_log(Topic)),
                 ( Enabled == true -> debug(metta_log(Topic))
                 ; nodebug(metta_log(Topic)) ) )).

%! 'log-enabled'(+Topic:string, -Enabled:boolean) is det.
%
% Whether the exact topic is enabled. An unknown topic answers False without
% registering it. The setting is sampled once for each log! or log-to! call.
'log-enabled'(Topic, Enabled) :-
    must_be(string, Topic),
    ( debugging(metta_log(Topic), true) -> Enabled = true ; Enabled = false ).

%! 'log-topics'(-Topics:list) is det.
%
% A sorted snapshot of configured (log-topic Name Enabled) rows. The names are
% Strings and disabled topics remain in the snapshot.
'log-topics'(Topics) :-
    with_mutex(prolog_debug,
               findall(['log-topic',Name,Enabled],
                       debugging(metta_log(Name),Enabled), Rows)),
    sort(Rows, Topics).

%! 'log-levels'(-Levels:list) is det.
%
% The supported host message levels. informational follows SWI's verbose flag;
% unhandled warnings and errors follow the host on_warning and on_error flags.
'log-levels'(Levels) :- findall(Level, log_level(Level), Levels).

log_level(debug).
log_level(informational).
log_level(warning).
log_level(error).

%! 'log!'(+Topic:string, +Level:atom, +Payload:'Atom', -Unit:list) is det.
%
% Send a held payload through print_message/2 when its topic is enabled. The
% structured host term contains (log-event Topic Level Payload). Host hooks can
% capture it; otherwise the host prints the diagnostic text from log-format.
'log!'(Topic, Level, Payload, []) :-
    log_message(default, Topic, Level, Payload).

%! 'log-to!'(+Handler:'Atom', +Topic:string, +Level:atom, +Payload:'Atom', -Unit:list) is det.
%
% Send through the host message mechanism with an explicit MeTTa handler. It
% takes an evaluated Expression (log-event Topic Level Payload) and answers
% True to consume or False to leave the host printer and later hooks active.
% The event is quoted at the call boundary to preserve its held payload;
% Atom-typed parameters retain that written quote by normal argument rules.
% Only the first verdict is used. Missing/non-Bool answers and exceptions raise.
% Earlier host hooks retain precedence. Disabled topics never apply Handler.
'log-to!'(Handler, Topic, Level, Payload, []) :-
    current_metta_module(Module),
    log_message(handler(Module,Handler), Topic, Level, Payload).

log_message(Handler, Topic, Level, Payload) :-
    log_arguments(Topic, Level),
    'log-enabled'(Topic, Enabled),
    (   Enabled == true
    ->  ( Level == debug -> Kind = debug(metta_log(Topic)) ; Kind = Level ),
        print_message(Kind, metta_library_log(Handler,['log-event',Topic,Level,Payload]))
    ;   true
    ).

%! 'log-format'(+Topic:string, +Level:atom, +Payload:'Atom', -Text:string) is det.
%
% The message's diagnostic text, whether or not its topic is enabled. It uses
% the engine's display syntax for the held payload, not a serialization format.
'log-format'(Topic, Level, Payload, Text) :-
    log_arguments(Topic, Level),
    message_to_string(metta_library_log(default,['log-event',Topic,Level,Payload]), Text).

log_arguments(Topic, Level) :-
    must_be(string, Topic),
    (   atom(Level), log_level(Level)
    ->  true
    ;   'log-levels'(Levels),
        throw(error(domain_error(log_level,Level),
                    context('log!',choose_one_of(Levels))))
    ).

prolog:message(metta_library_log(_,['log-event',Topic,Level,Payload])) -->
    { sdisplay(Payload, Text) }, ['~s [~w] ~s'-[Topic,Level,Text]].

user:message_hook(metta_library_log(handler(Module,Handler),Event), _, _) :-
    (   once(eval_metta_in_module(Module,[Handler,[quote,Event]],Verdict))
    ->  (   Verdict == true -> true
        ;   Verdict == false -> fail
        ;   throw(error(domain_error(log_handler_verdict,Verdict),
                        context('log-to!','the handler must answer True or False')))
        )
    ;   throw(error(existence_error(log_handler_answer,Handler),
                    context('log-to!','the handler must answer True or False')))
    ).

:- det('log-topic!'/3).
:- det('log-enabled'/2).
:- det('log-topics'/1).
:- det('log-levels'/1).
:- det('log!'/4).
:- det('log-to!'/5).
:- det('log-format'/4).
