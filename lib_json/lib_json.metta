;JSON, and the dict-as-space it decodes into. The names are MeTTa HE's.
;
;HE's decision here is the mettafied one and worth stating plainly: a JSON
;object decodes into a SPACE of (key value) atoms, not into an opaque dict
;value. So looking a key up is a match, a decoded document is queryable with
;the same operations as any other space, and there is no new type to learn.
;
;(json-decode $text) turns a JSON string into MeTTa: an object becomes a
;space, an array becomes an expression, strings and numbers stay themselves,
;and true, false and null become True, False and Null.
;(json-encode $atom) is the inverse and accepts any of those back.
;
;(dict-space ((k1 v1) (k2 v2))) builds a space from pairs directly.
;(get-keys $space) answers the keys ONE PER SOLUTION, the way get-atoms does,
;so collapse it for a tuple. (get-value $space $key) answers the value, or
;nothing when the key is absent.

!(import! &self (library lib_string))
!(import_prolog_functions_from_file (library lib_json.pl)
  (json-decode json-encode dict-space get-keys get-value))
