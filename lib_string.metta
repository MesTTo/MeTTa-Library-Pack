;Text, the way C reaches for string.h: import it when you need it.
;
;(string-length $s) counts characters. (string-slice $s $from $to) is
;half-open, From included and To not, and clamps rather than erroring, so
;(string-slice "hello" 3 999) is "lo". (string-split $sep $s) splits on every
;character of $sep and (string-join $sep $parts) puts them back.
;(string-trim $s), (string-upper $s) and (string-lower $s) do the obvious.
;
;(string-starts-with $s $prefix), (string-ends-with $s $suffix) and
;(string-contains $s $sub) answer True or False, so they guard a query.
;(string-index-of $s $sub) answers where, or -1 when it is not there, rather
;than failing, because a caller asking "where" wants an answer either way.
;(string-replace $s $from $to) replaces EVERY occurrence.
;
;(string-chars $s) gives one-character STRINGS, not char symbols, so the
;pieces feed straight back into these operations; (string-from-chars $list)
;is its inverse. (string-repeat $s $n), (string-pad-left $s $width $pad) and
;(string-pad-right ...) round it out.
;
;(format-args $template $args) is MeTTa HE's spelling and fills {} in order:
;(format-args "Probability of {} is {}%" (head 50)) gives
;"Probability of head is 50%". (sort-strings $list) is HE's too.
;(parse-number $s) answers a Number, or nothing when the text is not one, so
;you test it with a match rather than a catch. (number-to-string $n) inverts.
;
;Every operation accepts a String, a Symbol or a Number wherever text is
;wanted, because a symbol arriving where a string was meant is ordinary in
;MeTTa, and every operation ANSWERS a String, so results compose.

!(import! &self (library lib_import))
!(import_prolog_functions_from_file (library lib_string.pl)
  (string-length string-slice string-split string-join
   string-trim string-upper string-lower
   string-starts-with string-ends-with string-contains string-index-of
   string-replace string-chars string-from-chars string-repeat
   string-pad-left string-pad-right
   format-args sort-strings parse-number number-to-string))
