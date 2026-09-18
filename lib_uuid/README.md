# UUID

```metta
!(import! &self (library lib_uuid))
!(uuid-name 5 dns "example.com") ; "cfbff0d1-9375-5685-968c-48ce8b15ae17"
!(uuid-namespaces) ; (dns url oid x500)
!(uuid-version (uuid-random!)) ; 4
!(uuid-of-bytes (uuid-bytes (uuid-nil))) ; "00000000-0000-0000-0000-000000000000"
```

Use version 3 or 5 with a predefined namespace Symbol or any UUID String. Names
are complete UTF8 text, including empty strings and embedded NULs. Version 3
uses MD5 and version 5 uses SHA1; these are identifiers, not authentication.
The name recipe composes Encoding and Crypto with the
[RFC construction used by CPython](https://github.com/python/cpython/blob/v3.14.0/Lib/uuid.py#L763-L790).

Namespaces form an ordinary pair relation. Name hashing, nil, byte conversion,
version and variant inspection are MeTTa equations. One field-layout value drives
both strict validation and canonical formatting. Every 128-bit value survives,
including nil and reserved version/variant patterns. Validation requires a String
with literal hyphens and ASCII hex fields; `uuid-is` answers a Bool. Consumers
name their supplying boundary or shape assertion when input is malformed.

The host supplies random/time generation, validation and version 1 timestamps.
`uuid-time!` requires the host OSSP provider and may expose a MAC address. Other
versions have no timestamp answer. Use Crypto's random bytes for secrets.

```metta
!(let $recipe
   (match &self (= (uuid-version $id) $body) (quote (|-> ($id) $body)))
   (let $inspect (eval $recipe)
     ($inspect "ffffffff-ffff-ffff-ffff-ffffffffffff"))) ; 15
```

```python
from metta import G, MeTTa, S, lib

with MeTTa() as engine:
    m = engine.self
    m += lib.uuid
    assert m.fn.uuid_name(5, S.dns, G("example.com")).one() == "cfbff0d1-9375-5685-968c-48ce8b15ae17"
```

Byte formulas can cost more than native field inspection; their equations can
be reconstructed and specialized. Shape assertions make recording replay
conservative. The executable reference is
[`33-uuid_lib.metta`](../../examples/ch08-data/08-03-the-shipped-libraries/33-uuid_lib.metta).
