;Documentation, MeTTa HE's vocabulary. The design is HE's and it is the
;mettafied one: documentation is ATOMS IN A SPACE, so help! is a query rather
;than a separate mechanism, docs are data a program can reason about, and
;nothing here needs the engine's help.
;
;This whole library is MeTTa. There is no .pl beside it, because the doc forms
;are data constructors: an unapplied symbol stays as itself, so writing
;
;    (@doc greet (@desc "Greets somebody by name"))
;
;in a file is already an atom in the space. Retrieval is a match over that
;atom, which is all get-doc and help! are.
;
;The constructors, all HE's:
;  (@doc $name $desc)                       documentation for a name
;  (@doc $name $desc $params)               with its parameters
;  (@doc $name $desc $params $return)       and its return value
;  (@desc "text")                           a description
;  (@param "text")                          one parameter
;  (@params ((@param "a") (@param "b")))     all of them
;  (@return "text")                         the return value
;  (@type Type)                             a type, for the formal form
;  (@item name)                             a name, for the formal form
;  (@kind function) / (@kind atom)          which sort of thing is documented
;
;  (get-doc $name)   the documentation atom, or nothing when there is none
;  (help! $name)     prints it
;  (documented)      every documented name, one per solution
;  (undocumented-in $space) every function in $space with no documentation

!(import! &self (library lib_import))

;One clause per arity rather than one variadic clause, because @doc carries
;two, three or four parts depending on how much was written, and matching each
;shape is how a MeTTa program asks "whichever of these exists".
(= (get-doc $name) (match &self (@doc $name $desc) (@doc $name $desc)))
(= (get-doc $name)
   (match &self (@doc $name $desc $params) (@doc $name $desc $params)))
(= (get-doc $name)
   (match &self (@doc $name $desc $params $return)
                (@doc $name $desc $params $return)))

(= (help! $name) (println! (get-doc $name)))

;Every documented name, one per solution, so collapse it for a tuple.
(= (documented) (match &self (@doc $name $_) $name))
(= (documented) (match &self (@doc $name $_ $__) $name))
(= (documented) (match &self (@doc $name $_ $__ $___) $name))

;Every function name defined in this space, whatever its arity, once each.
;Matching (= $head $_) catches every equation, car-atom takes the name out of
;the head, and unique-atom removes the repeat a multi-clause function would
;otherwise produce.
(= (defined-name)
   (let $all (collapse (let $head (match &self (= $head $_) $head)
                         (car-atom $head)))
     (let $once (unique-atom $all)
       (superpose $once))))

;The gap worth closing in a real codebase: what is defined and has no docs.
;This library documents itself below, so it does not report its own names.
(= (undocumented)
   (let $name (defined-name)
     (if (== (collapse (get-doc $name)) ()) $name (empty))))

;A library that reports undocumented names and has none of its own would be
;telling other people to do what it does not.
(@doc get-doc
      (@desc "The documentation atom for a name, or nothing when there is none")
      (@params ((@param "the name to look up")))
      (@return "the (@doc ...) atom"))
(@doc help!
      (@desc "Prints the documentation for a name")
      (@params ((@param "the name to look up")))
      (@return "unit"))
(@doc documented
      (@desc "Every documented name, one per solution")
      (@params ())
      (@return "a name"))
(@doc defined-name
      (@desc "Every function name defined in this space, once each")
      (@params ())
      (@return "a name"))
(@doc undocumented
      (@desc "Every defined name that has no documentation")
      (@params ())
      (@return "a name"))
