;PCRE2 regular expressions over strings, the engine's own library(pcre)
;underneath: patterns compile once into its cache, matching is
;thread-safe, and flags ride the pattern inline in PCRE2's own style,
;(?i) for caseless, because flag terms are Prolog spelling.
;
;(re-match $pattern $text) answers True or False, so it guards queries.
;(re-find $pattern $text) answers every match nondeterministically.
;(re-captures $pattern $text) answers the first match's groups as
;((key value) ...) pairs, the whole match under 0, named groups under
;their names, and a _I name suffix answers an integer, PCRE's own typed
;captures. (re-split $pattern $text) alternates skipped and matched
;parts. (re-replace $pattern $with $text) replaces the first match,
;(re-replace-all ...) every match; $with references groups as $name.

!(import! &self (library lib_import))
!(import_prolog_functions_from_file (library lib_regex.pl)
  (regex_match regex_find regex_captures regex_split regex_replace regex_replace_all))

(= (re-match $pattern $text) (regex_match $pattern $text))
(= (re-find $pattern $text) (regex_find $pattern $text))
(= (re-captures $pattern $text) (regex_captures $pattern $text))
(= (re-split $pattern $text) (regex_split $pattern $text))
(= (re-replace $pattern $with $text) (regex_replace $pattern $with $text))
(= (re-replace-all $pattern $with $text) (regex_replace_all $pattern $with $text))
