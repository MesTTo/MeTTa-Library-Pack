; Purpose: construct a queryable CSV space through the native provider seam.
; csv-space validates the path; each query reopens it and streams (row ...)
; atoms. Every field is a String, so leading zeros and empty fields survive.
; The first record is data, including headers. Use parse-number from lib_string
; when a column represents a number. Quotes, commas, and embedded newlines
; follow SWI library(csv); inconsistent row widths and broken quotes raise.
; A descriptor owns no handle. Each query closes its stream on completion,
; error, or early termination. Later queries see later file contents.

!(import! &self (library lib_import))
!(import_prolog_functions_from_file (library lib_csv.pl) (csv-space))

(@doc csv-space
      (@desc "A read-only CSV row space; each query streams the file anew, every cell is a String, and the first record is data")
      (@params ((@param "a readable UTF-8 CSV file path")))
      (@return "Space"))
