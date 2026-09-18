<!-- Purpose: pin the CSV grammar and explain its local adaptations. -->
# CSV grammar source

`csv_codec.pl` adapts the record, field, doubled-quote and emitter grammar
from SWI-Prolog's `library/csv.pl` at
[`fc7ef84b949378b729052c3ade79c90ce5416abb`](https://github.com/SWI-Prolog/swipl-devel/blob/fc7ef84b949378b729052c3ade79c90ce5416abb/library/csv.pl).
The original file has SHA-256
`763446315884b5e6220ac91552f50def47bb712eea031722dabc4d2303aca205`.
Its copyright, redistribution terms and disclaimer remain in the source.

The adaptation parses one record from a lazy byte-list remainder. It decodes
and validates each field as UTF-8, preserves quoted CR/LF characters, and
parameterizes the delimiter and doubled quote by Unicode scalar. It omits
numeric conversion, case conversion and whitespace stripping. Blank records
have zero fields; a singleton empty field is quoted on output. An empty quote
setting refuses output that needs escaping. The owner supplies row-width
checks, file ownership, errors and dialect validation.

`tests/prolog/suites/libraries/lib_csv_surface.plt` checks the adapter and
its public callers. Python tests compare generated records against `csv`.
