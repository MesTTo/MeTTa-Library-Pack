; Purpose: share validated hexadecimal recipes across Encoding and UUID.
; Assumes: encoding-hex-text receives bytes checked by encoding-bytes.
; [source: lib/lib_encoding/lib_encoding.metta:hex-encode, lib/lib_uuid/lib_uuid.metta:uuid-of-bytes; commit=8fe20f1bdcde1af8b3e1753c545924f978246dba].
; Guarantees: the alphabet is ASCII, two digits encode each byte, and decoding
; preserves every byte value. Literal nonbytes never become executable elements.
; [tested: lib_encoding, test_encoding_python_oracles; commit=8fe20f1bdcde1af8b3e1753c545924f978246dba].

!(import_prolog_functions_from_file (library "lib_encoding/lib_encoding.pl")
  (encoding-bytes encoding-text))
(: encoding-bytes (-> Atom Atom Expression))
(@doc encoding-bytes
  (@desc "Validate a finite expression of byte integers and return the same value. Head names the caller in a refusal. Private codec boundary.")
  (@params ((@param "Head") (@param "Bytes"))) (@return "Checked"))
(: encoding-text (-> Atom Atom %Undefined%))
(@doc encoding-text
  (@desc "Validate text without String's numeric coercions and return the same value. Head names the caller in a refusal. Private codec boundary.")
  (@params ((@param "Head") (@param "Text"))) (@return "Checked"))

(: encoding-hex-alphabet (-> String))
(= (encoding-hex-alphabet) "0123456789abcdefABCDEF")
(@doc encoding-hex-alphabet
  (@desc "One alphabet for lowercase output and case-insensitive ASCII input. Private hex recipe.")
  (@params ()) (@return "Alphabet"))

(: encoding-hex-text (-> Expression String))
(= (encoding-hex-text $bytes)
   (let $digits (string-chars (encoding-hex-alphabet))
     (string-join ""
       (flatten-once
         (map-atom (quote $bytes) $byte
           (let* (($high (index-atom $digits (floor-div $byte 16)))
                  ($low (index-atom $digits (% $byte 16))))
             (quote ($high $low))))))))
(@doc encoding-hex-text
  (@desc "Format previously validated bytes as lowercase hex. Private recipe shared by Encoding and UUID.")
  (@params ((@param "Bytes"))) (@return "Text"))

(: encoding-hex-value (-> String Number))
(= (encoding-hex-value $digit)
   (let* (($index (string-index-of (encoding-hex-alphabet) $digit))
          ($valid (assertEqualMsg (>= $index 0) True
                     (quote (hex-decode "use a hexadecimal digit" $digit)))))
     (if (< $index 16) $index (- $index 6))))
(@doc encoding-hex-value
  (@desc "Look up one ASCII hex digit and assert membership. Private decoder recipe.")
  (@params ((@param "Digit"))) (@return "Value"))

(: encoding-hex-bytes (-> Expression Expression))
(= (encoding-hex-bytes ()) ())
(= (encoding-hex-bytes ($high $low (:seg $rest)))
   (cons-atom (+ (* 16 (encoding-hex-value $high)) (encoding-hex-value $low))
              (encoding-hex-bytes (quote $rest))))
(@doc encoding-hex-bytes
  (@desc "Decode a previously checked even-length character expression, two digits per byte. Private decoder recipe.")
  (@params ((@param "Characters"))) (@return "Bytes"))
