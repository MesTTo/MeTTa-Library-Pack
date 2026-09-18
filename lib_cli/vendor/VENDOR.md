<!-- Purpose: pin the private option parser and record its local corrections. -->
# Option parser source

lib_cli_optparse.pl comes from SWI-Prolog optparse.pl at
[fc7ef84b949378b729052c3ade79c90ce5416abb](https://github.com/SWI-Prolog/swipl-devel/blob/fc7ef84b949378b729052c3ade79c90ce5416abb/library/optparse.pl).
The original SHA256 is
`b6e20f2d28352b058c8c9abeecec1e0b97bc1eedbd74fa1ad2db559ec6738d36`.
The copied file retains the upstream BSD-2-Clause license.

The literal dashed-name scanner and direct Boolean negation adapt Logtalk's
[command_line_options.lgt at 9d0906cf4a4344e01d26c6bf2b3d7844fe9856ac](https://github.com/LogtalkDotOrg/logtalk3/blob/9d0906cf4a4344e01d26c6bf2b3d7844fe9856ac/library/command_line_options/command_line_options.lgt).
Those portions carry the same BSD-2-Clause terms and retain their copyright
notice beside the scanner. Logtalk is not a runtime dependency.

The module is private and uses explicit imports. Its scanner distinguishes
missing values from empty tokens, consumes the option terminator, recognizes
literal declared names, separates short/long namespaces and emits negated
Booleans once. Errors carry the original flag and cause instead of printing
their context to stdout. Declaration uniqueness is checked by the adapter,
including identical rows that the original comparison misses.

Explicit defaults use default_value/1 and raw custom inputs use raw_value/1.
The module-local parse_type/3 hook retains a printable type label while the
adapter holds the actual function in its call-local declaration map. A private
format_default/2 hook renders defaults with the MeTTa writer. Missing defaults
have no printed equals suffix. Native conversion, default insertion, repeat
selection and help layout remain in this provider. remove_duplicates/3 is
exported privately so custom conversions precede repeat selection too.

The native defects have tracked reproductions and entries in
[the host workaround ledger](../../../docs/host-workarounds.md). The design
and measurements are in the CLI section of
[the journal](../../../docs/journal/2026-09-11-a-standard-library-for-a-language.md).
