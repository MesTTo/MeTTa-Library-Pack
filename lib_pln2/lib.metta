; Purpose: an isolated, assumption-explicit truth-value library for Beta and
; moment formulas that are independently checked rather than inherited from
; legacy lib_pln policy.
; Assumes: (stv STRENGTH CONFIDENCE), (beta ALPHA BETA),
; (moments MEAN VARIANCE), and (supported MOMENTS SUPPORT-IDS) are transparent
; data; support IDs are caller-stable evidence identities.
; Guarantees: every formula that assumes independence either accepts explicit
; disjoint support sets or refuses overlap [tested:
; test_supported_total_probability_matches_the_formula;
; commit=afc4024cef7d4b7bcdd194bb030a112187b676d0].
; Fails when: a probability, variance, Beta shape, confidence, evidence scale,
; or support identity violates its declared domain; the error names a remedy.
; Decides: the evidence scale is an explicit argument and no fixed constant,
; clipping, ratio inversion, or negative-branch heuristic is library policy.

(= (package backing) (prolog "lib_pln2.pl"
  (pln2-confidence-count
   pln2-count-confidence
   pln2-stv-moments
   pln2-moments-stv
   pln2-beta-moments
   pln2-beta-update
   pln2-require-independent-supports
   pln2-product-independent
   pln2-total-probability-independent)))
