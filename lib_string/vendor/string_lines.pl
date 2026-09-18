/*  Part of SWI-Prolog

    Author:        Jan Wielemaker
    E-mail:        jan@swi-prolog.org
    WWW:           http://www.swi-prolog.org
    Copyright (c)  2020, SWI-Prolog Solutions b.v
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:

    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in
       the documentation and/or other materials provided with the
       distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
    COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
*/

% Adapted from SWI-Prolog 10.1.13 strings.pl; see VENDOR.md.
% Purpose: preserve SWI line and indentation semantics with length-aware splitting.
:- module(lib_string_lines, [string_lines/2, dedent_lines/3, indent_lines/3]).
:- use_module('../support/native', [split_text/4]).
:- use_module(library(apply), [foldl/4, maplist/2, maplist/3]).
:- use_module(library(error), [must_be/2]).
:- use_module(library(lists), [append/3]).
:- use_module(library(option), [option/3]).
:- meta_predicate indent_lines(1, +, +, -).

%!  string_lines(?String, ?Lines) is det.
%
%   True when String represents Lines.  This   follows  the  normal text
%   convention that a  line  is  defined   as  a  possible  empty string
%   followed by a newline character ("\n").  E.g.
%
%   ```
%   ?- string_lines("a\nb\n", L).
%   L = ["a", "b"].
%   ?- string_lines(S, ["a", "b"]).
%   S = "a\nb\n".
%   ```
%
%   This predicate is  a  true  _relation_   if  both  arguments  are in
%   canonical form, i.e. all text  is   represented  as  strings and the
%   first argument ends with  a   newline.  The implementation tolerates
%   non-canonical input: other  types  than   strings  are  accepted and
%   String does not need to end with a newline.
%
%   @see split_string/4. Using split_text(String, "\n",  "", Lines) on
%   a string that ends in a  newline   adds  an  additional empty string
%   compared to string_lines/2.

string_lines(String, Lines) :-
    (   var(String)
    ->  must_be(list, Lines),
        append(Lines, [""], Lines1),
        atomics_to_string(Lines1, "\n", String)
    ;   split_text(String, "\n", "", Lines0),
        (   append(Lines, [""], Lines0)
        ->  true
        ;   Lines = Lines0
        )
    ).

%!  dedent_lines(+In, -Out, +Options)
%
%   Remove shared indentation for all lines in a string. Lines are separated
%   by "\n" -- conversion to and from  external forms  (such as "\r\n")  are
%   typically done by the I/O predicates.
%   A final "\n" is preserved.
%
%   Options:
%
%     - tab(N)
%       Assume tabs at columns of with N.  When omitted, tabs are
%       taken literally and only exact matches are removed.
%     - chars(CodesOrString)
%       Characters to remove.  This can notably be used to remove
%       additional characters such as `*` or `|`.  Default is
%       `" \t"`.

dedent_lines(In, Out, Options) :-
    option(tab(Tab), Options, 0),
    option(chars(Chars), Options, "\s\t"),
    string_codes(Sep, Chars),
    How = s(Tab,Sep),
    split_text(In, "\n", "", Lines),
    foldl(common_indent(How), Lines, _, Indent0),
    (   prepare_delete(Indent0, Indent)
    ->  maplist(dedent_line(Tab, Sep, Indent), Lines, Dedented),
        atomics_to_string(Dedented, "\n", Out)
    ;   length(Lines, NLines),
        NewLines is NLines - 1,
        length(Codes, NewLines),
        maplist(=(0'\n), Codes),
        string_codes(Out, Codes)
    ).

prepare_delete(Var, _) :-               % All blank lines
    var(Var),
    !,
    fail.
prepare_delete(Width, Width) :-
    integer(Width),
    !.
prepare_delete(Codes, String) :-
    string_codes(String, Codes).

common_indent(s(0,Sep), Line, Indent0, Indent) :-
    !,
    line_indent(Line, Indent1, Sep),
    join_indent(Indent0, Indent1, Indent).
common_indent(s(Tab,Sep), Line, Indent0, Indent) :-
    !,
    line_indent_width(Line, Indent1, Tab, Sep),
    join_indent_width(Indent0, Indent1, Indent).

%!  line_indent(+Line, -Indent, +Sep) is det.
%
%   Determine the indentation as a list of character codes.  If the
%   line only holds white space Indent is left unbound.

line_indent(Line, Indent, Sep) :-
    string_codes(Line, Codes),
    code_indent(Codes, Indent0, Sep),
    (   is_list(Indent0)
    ->  Indent = Indent0
    ;   true
    ).

code_indent([H|T0], [H|T], Sep) :-
    string_code(_, Sep, H),
    !,
    code_indent(T0, T, Sep).
code_indent([], _, _) :-
    !.
code_indent(_, [], _).

join_indent(Var, Indent, Indent) :-
    var(Var),
    !.
join_indent(Indent, Var, Indent) :-
    var(Var),
    !.
join_indent(Indent1, Indent2, Indent) :-
    shared_prefix(Indent1, Indent2, Indent).

shared_prefix(Var, Prefix, Prefix) :-
    var(Var),
    !.
shared_prefix(Prefix, Var, Prefix) :-
    var(Var),
    !.
shared_prefix([H|T0], [H|T1], [H|T]) :-
    !,
    shared_prefix(T0, T1, T).
shared_prefix(_, _, []).

%!  line_indent_width(+Line, -Indent, +Tab, +Sep) is det.
%
%   Determine the indentation as a  column,   compensating  for  the Tab
%   width.  This is used if the tab(Width) option is provided.

line_indent_width(Line, Indent, Tab, Sep) :-
    string_codes(Line, Codes),
    code_indent_width(Codes, 0, Indent, Tab, Sep).

code_indent_width([H|T], Indent0, Indent, Tab, Sep) :-
    string_code(_, Sep, H),
    !,
    update_pos(H, Indent0, Indent1, Tab),
    code_indent_width(T, Indent1, Indent, Tab, Sep).
code_indent_width([], _, _, _, _) :-
    !.
code_indent_width(_, Indent, Indent, _, _).

join_indent_width(Var, Indent, Indent) :-
    var(Var),
    !.
join_indent_width(Indent, Var, Indent) :-
    var(Var),
    !.
join_indent_width(Indent0, Indent1, Indent) :-
    Indent is min(Indent0, Indent1).

%!  dedent_line(+Tab, +Sep, +Indent, +String, -Dedented)
%
%   Dedent a single line according to Tab   and Indent. Indent is either
%   an integer, deleting the  first  Indent   characters  or  a  string,
%   deleting the string literally.

% Blank lines normalize independently of the shared prefix's length.
dedent_line(_Tab, Sep, _Indent, String, "") :-
    split_text(String, "", Sep, [""]),
    !.
dedent_line(_Tab, _Sep, Indent, String, Dedented) :-
    string(Indent),
    !,
    (   string_concat(Indent, Dedented, String)
    ->  true
    ;   Dedented = ""               % or ""?
    ).
dedent_line(Tab, _Sep, Indent, String, Dedented) :-
    string_codes(String, Codes),
    delete_width(0, Indent, Codes, Codes1, Tab),
    string_codes(Dedented, Codes1).

delete_width(Here, Indent, Codes, Codes, _) :-
    Here =:= Indent,
    !.
delete_width(Here, Indent, Codes0, Codes, _) :-
    Here > Indent,
    !,
    NSpaces is Here-Indent,
    length(Spaces, NSpaces),
    maplist(=(0'\s), Spaces),
    append(Spaces, Codes0, Codes).
delete_width(Here, Indent, [H|T0], T, Tab) :-
    !,
    update_pos(H, Here, Here1, Tab),
    delete_width(Here1, Indent, T0, T, Tab).
delete_width(_, _, [], [], _).

update_pos(0'\t, Here0, Here, Tab) :-
    !,
    Here is ((Here0+Tab)//Tab)*Tab.
update_pos(_, Here0, Here, _) :-
    Here is Here0 + 1.

%!  indent_lines(+Prefix, +In, -Out) is det.
%
%   Add Prefix to the beginning of lines   in In. Lines are separated by
%   "\n" -- conversion to and from external   forms (such as "\r\n") are
%   typically done by the I/O predicates. Lines that consist entirely of
%   whitespace are left as-is.

indent_lines(Prefix, In, Out) :-
    indent_lines(ignore_whitespace_line, Prefix, In, Out).

%!  indent_lines(:Filter, +Prefix, +In, -Out) is det.
%
%   Similar to indent_lines/3, but only adds   Prefix to lines for which
%   call(Filter, Line) succeeds.

indent_lines(Pred, Prefix, In, Out) :-
    % Use split_string/4 rather than string_lines/2, to preserve final "\n".
    split_text(In, "\n", "", Lines0),
    (   append(Lines, [""], Lines0)
    ->  maplist(concat_to_string(Pred, Prefix), Lines, IndentedLines0),
        append(IndentedLines0, [""], IndentedLines),
        atomics_to_string(IndentedLines, "\n", Out)
    ;   Lines = Lines0,
        maplist(concat_to_string(Pred, Prefix), Lines, IndentedLines),
        atomics_to_string(IndentedLines, "\n", Out)
    ).

ignore_whitespace_line(Str) :-
    \+ split_text(Str, "", " \t", [""]).

:- meta_predicate concat_to_string(:, +, +, -).

concat_to_string(Pred, Prefix, Line, Out) :-
    (   call(Pred, Line)
    ->  atomics_to_string([Prefix, Line], Out)
    ;   Out = Line
    ).
