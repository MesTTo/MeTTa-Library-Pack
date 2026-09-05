; Purpose: construct a queryable CSV space through the native provider seam.
; csv-space validates the path; each query reopens it and streams (row ...)
; atoms. Every field is a String, so leading zeros and empty fields survive.
; The first record is data, including headers. Use parse-number from lib_string
; when a column represents a number. Quotes, commas, and embedded newlines
; follow SWI library(csv); inconsistent row widths and broken quotes raise.
; A descriptor owns no handle. Each query closes its stream on completion,
; error, or early termination. Later queries see later file contents.
;
; csv-snapshot! is the other door. It reads the file ONCE into an ordinary
; space of (row Number Field...) atoms, so repeated queries pay one parse
; between them where csv-space reparses per query, and the rows stay as they
; were read where csv-space follows the file. The record number comes with the
; snapshot because a space is unordered: without it a space of rows can neither
; say which record came first nor skip a header, and a number is an identity
; only once the rows are fixed. Fields, quoting, widths and refusals are
; csv-space's, and the space is an ordinary one, so it takes writes.

!(import! &self (library lib_import))
!(import_prolog_functions_from_file (library lib_csv.pl) (csv-space csv-snapshot!))

(@doc csv-space
      (@desc "A read-only CSV row space; each query streams the file anew, every cell is a String, and the first record is data")
      (@params ((@param "a readable UTF-8 CSV file path")))
      (@return "Space"))
(@doc csv-snapshot!
      (@desc "Read a CSV file ONCE into an ordinary space of (row Number Field...) atoms; the record number is 1-based, the rows do not change under the program, and repeated queries pay one parse between them")
      (@params ((@param "a readable UTF-8 CSV file path")))
      (@return "Space"))
