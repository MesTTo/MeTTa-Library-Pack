# Encoding

```metta
!(import! &self (library lib_encoding))
!(hex-encode (utf8-encode "hé")) ; "68c3a9"
!(utf8-decode (hex-decode "68C3A9")) ; "hé"
!(base64-encode url (0 255)) ; "AP8"
```

Bytes are expressions of integers from 0 to 255. UTF8 and base64 use the shared
host codecs. Base64 takes `standard` for padded output or `url` for unpadded
output. Decoder acceptance follows the host policy; its URL decoder also reads
classic `+` and `/` digits. Malformed input raises a named error. Cancellation,
resource exhaustion and unrelated provider exceptions propagate unchanged.

Hex is an ordinary MeTTa recipe over one ASCII alphabet, arithmetic, String
characters and segment traversal. It writes lowercase, reads either case and
rejects odd lengths, whitespace and nonhex characters. The strict byte boundary
does not execute literal expressions to manufacture integers. Length and digit
refusals are named MeTTa assertions; incompatible literal types remain `Error`
values. Assertions make recording replay conservative.

The equation is data that you can inspect, return and apply:

```metta
!(let $recipe
   (match &self (= (hex-encode $bytes) $body) (quote (|-> ($bytes) $body)))
   (let $format (eval $recipe) ($format (0 255)))) ; "00ff"
```

```python
from metta import G, MeTTa, lib

with MeTTa() as engine:
    m = engine.self
    m += lib.encoding
    assert m.fn.hex_encode((0, 255)).one() == "00ff"
    assert list(m.fn.hex_decode(G("00FF")).one()) == [0, 255]
```

The shared byte and text boundaries stay native. Hex composition can cost more
than a native codec; its representation is available to MeTTa rewriting.
The executable reference is
[`30-encoding_lib.metta`](../../examples/ch08-data/08-03-the-shipped-libraries/30-encoding_lib.metta).
