; Purpose: compose collection transformations and held control forms in MeTTa.
; Assumes: collections are finite expressions; callers quote runnable values.
; Guarantees: callback alternatives, literal data, input order and variable
; identity survive the compositions [tested: lib_functional; commit=6fa571d1b7059b610f73e9feed657711414251e5].
; Fails when: a collection or step result has the wrong shape, or a slicing
; count is outside its domain. Core assertions report those refusals.
; Decides: derive the operations from map, fold, choice and application.
; Growing accumulators and indexed slices may take quadratic work.

!(import! &self (library lib_combinatorics))

; The three control forms hold their body and their condition, which is what
; `(: while (-> Atom Atom %Undefined%))` says: a loop that evaluated its body
; before running would run it once and loop over the answer. `eval` is how a
; held form is run, once per round, the way lib_thread's `after` and `with-lock`
; run theirs. They are ordinary equations rather than translator rules, because
; a rule rewrites the written form and a RECURSIVE rule would rewrite itself
; forever at translation time; the held parameter already stops the body being
; evaluated too early, so the rule buys nothing.

; `while` evaluates its body for as long as the condition answers True, and
; answers each body result. The condition is asked again after every body, which
; is what makes it a while and not an if; a condition that never changes never
; stops, which is the caller's own contract.
(: while (-> Atom Atom %Undefined%))
(= (while $condition $body)
   (if (eval $condition)
       (superpose ((eval $body) (while $condition $body)))
       (empty)))

; `repeat` evaluates its body a fixed number of times and answers each result.
; A count of zero or less answers nothing, which is what makes it total.
(: repeat (-> Number Atom %Undefined%))
(= (repeat $times $body)
   (let $iteration (range 0 $times) (eval $body)))

; `unless` is `if` with one arm and the condition read the other way round: the
; body runs when the condition answers False and nothing runs when it answers
; True.
(: unless (-> Atom Atom %Undefined%))
(= (unless $condition $body)
   (if (eval $condition) (empty) (eval $body)))

(@doc while
  (@desc "Evaluate the held body while the held condition answers True, answering each body result. The condition is asked again after every body, so a condition that never changes never stops.")
  (@params ((@param "the held condition") (@param "the held body")))
  (@return "each body result"))
(@doc repeat
  (@desc "Evaluate the held body that many times, answering each result. A count of zero or less answers nothing.")
  (@params ((@param "how many times") (@param "the held body")))
  (@return "each body result"))
(@doc unless
  (@desc "Evaluate the held body when the held condition answers False, and answer nothing when it answers True: if with one arm, read the other way round.")
  (@params ((@param "the held condition") (@param "the held body")))
  (@return "the body's answers, or none"))

(: zip (-> Expression Expression Expression))
(= (zip $left $right)
   (let* (($ln (collections-size $left)) ($rn (collections-size $right)))
     (unfold (|-> ($sides)
               (let (($l (:seg $ls)) ($r (:seg $rs))) (quote $sides)
                 (quote (($l $r) ($ls $rs)))))
             (quote ($left $right)))))
(@doc zip
  (@desc "The pairs of corresponding elements, truncating at the shorter collection, so zipping a long one with a short one answers the short one's length. unzip inverts it.")
  (@params ((@param "Left") (@param "Right")))
  (@return "Pairs"))

(: unzip (-> Expression Expression))
(= (unzip $pairs)
   (let* (($size (collections-size $pairs))
          ($checked (forall (index-atom $pairs (range 0 $size))
                     (|-> ($pair) (assertEqualMsg (collections-size $pair) 2 (quote $pair)))))
          ($left (map-atom $pairs $pair (index-atom $pair 0)))
          ($right (map-atom $pairs $pair (index-atom $pair 1))))
     (quote ($left $right))))
(@doc unzip
  (@desc "The two collections a zip was made from, as (Lefts Rights). Every element must be a two-element expression; anything else raises.")
  (@params ((@param "Pairs")))
  (@return "Sides"))

(: drop (-> Expression Number Expression))
(= (drop $items $count)
   (let* (($size (collections-size $items))
          ($checked (assertEqualMsg (and (collections-integer? $count) (>= $count 0)) True
                                   (quote (drop $items $count))))
          ($prefix (takeK $count (quote $items))))
     (let ((:seg $prefix) (:seg $rest)) (quote $items) (quote $rest))))
(@doc drop
  (@desc "The collection without its first Count elements, and empty when there are fewer than that. Dropping a negative count raises; the PREFIX is takeK, which lib_combinatorics already publishes.")
  (@params ((@param "Items") (@param "Count")))
  (@return "Rest"))

(: chunk (-> Expression Number Expression))
(= (chunk $items $width)
   (let* (($size (collections-size $items))
          ($checked (assertEqualMsg (and (collections-integer? $width) (> $width 0)) True
                                   (quote (chunk $items $width)))))
     (unfold (|-> ($rest)
               (if (== $rest ()) (empty)
                 (let* (($piece (takeK $width (quote $rest)))
                        ($tail (drop (quote $rest) $width)))
                   (quote ($piece $tail)))))
             (quote $items))))
(@doc chunk
  (@desc "The collection cut into pieces of that size, in order, with a shorter last piece when the size does not divide the length. A size of zero or less raises, because it would never finish; an empty collection has no chunks.")
  (@params ((@param "Items") (@param "Size")))
  (@return "Chunks"))

(: window (-> Expression Number Expression))
(= (window $items $width)
   (let* (($size (collections-size $items))
          ($checked (assertEqualMsg (and (collections-integer? $width) (> $width 0)) True
                                   (quote (window $items $width)))))
     (unfold (|-> ($rest)
               (if (< (size-atom $rest) $width) (empty)
                 (let* (($piece (takeK $width (quote $rest)))
                        ($tail (drop (quote $rest) 1)))
                   (quote ($piece $tail)))))
             (quote $items))))
(@doc window
  (@desc "Every run of that many consecutive elements, overlapping by all but one: the sliding window a moving average or a bigram is written over. A collection shorter than the window has none. A size of zero or less raises.")
  (@params ((@param "Items") (@param "Size")))
  (@return "Windows"))

(: flatten-once (-> Expression Expression))
(= (flatten-once $items)
   (let $size (collections-size $items)
     (foldl-atom $items () $rest $item
       (if (== (get-metatype $item) Expression)
         (union-atom $rest $item) (union-atom $rest (quote ($item)))))))
(@doc flatten-once
  (@desc "One level of nesting removed: the elements of every element that is itself a collection, in order, with anything else kept as it is. flatten-deep removes every level, and the bare name flatten is the host's own every-level one, which is why neither of these is spelled that way.")
  (@params ((@param "Items")))
  (@return "Flat"))

(: flatten-deep (-> Expression Expression))
(= (flatten-deep $items)
   (let $size (collections-size $items)
     (flatten-once
       (map-atom $items $item
         (if (== (get-metatype $item) Expression)
           (flatten-deep (quote $item)) (quote ($item)))))))
(@doc flatten-deep
  (@desc "Every level of nesting removed, so the answer holds only the leaves, in order. An empty collection nested anywhere contributes nothing; flatten-once removes exactly one.")
  (@params ((@param "Items")))
  (@return "Flat"))

(: partition (-> %Undefined% Expression Expression))
(= (partition $test $items)
   (let $size (collections-size $items)
     (foldl-atom $items (() ()) $sides $item
       (let ($yes $no) (quote $sides)
         (if (forall ($test (quote $item)) (|-> ($verdict) (!= $verdict True)))
           (let $next (union-atom $no (quote ($item))) (quote ($yes $next)))
           (let $next (union-atom $yes (quote ($item))) (quote ($next $no))))))))
(@doc partition
  (@desc "Split Items into (Yes No), preserving input order. The predicate runs in input order; an item belongs to Yes when some answer is True, and otherwise to No. Predicate search bindings remain local to that question.")
  (@params ((@param "Test") (@param "Items")))
  (@return "Sides"))

(: unfold (-> %Undefined% %Undefined% Expression))
(= (unfold $step $seed)
   (case ($step (quote $seed))
     ((Empty ())
      ($pair
       (let $checked (unzip (quote ($pair)))
         (let ($value $next) (quote $pair)
           (cons-atom $value (unfold $step (quote $next)))))))))
(@doc unfold
  (@desc "Grow a collection from a seed. Each step answer must be (Value NextSeed); no answer ends that path. Multiple step answers produce multiple collections. Malformed results raise. A step that never stops never completes its collection.")
  (@params ((@param "Step") (@param "Seed")))
  (@return "Items"))

(: group-by (-> %Undefined% Expression Expression))
(= (group-by $key $items)
   (let* (($size (collections-size $items))
          ($keyed (map-atom $items $item
                    (let $value ($key (quote $item)) (quote ($value $item))))))
     (unfold
       (|-> ($remaining)
         (if (== $remaining ()) (empty)
           (let* (($first (index-atom (index-atom $remaining 0) 0))
                  ($sides (partition
                            (|-> ($pair) (== (index-atom $pair 0) $first))
                            (quote $remaining)))
                  ($matches (index-atom $sides 0))
                  ($rest (index-atom $sides 1))
                  ($members (map-atom $matches $pair (index-atom $pair 1))))
             (quote (($first $members) $rest)))))
       (quote $keyed))))
(@doc group-by
  (@desc "Gather items into (Key Members) groups in first-appearance order. Compute keys in input order and preserve each function answer as an alternative grouping. Members retain their order and variable identity.")
  (@params ((@param "Key") (@param "Items")))
  (@return "Groups"))

(: sort-by (-> %Undefined% Expression Expression))
(= (sort-by $key $items)
   (let $groups (group-by $key (quote $items))
     (flatten-once (map-atom (sort-atom $groups) $group
                   (index-atom $group 1)))))
(@doc sort-by
  (@desc "Compute a key for each item, sort the groups by term order and concatenate their members. Equal keys retain input order and duplicates. Alternative key answers give alternative stable sorts.")
  (@params ((@param "Key") (@param "Items")))
  (@return "Sorted"))

(: scan (-> %Undefined% %Undefined% Expression Expression))
(= (scan $fn $seed $items)
   (let $size (collections-size $items)
     (foldl-atom $items (quote ($seed)) $running $item
       (let ((:seg $previous) $acc) (quote $running)
         (let $next ($fn (quote $acc) (quote $item))
           (union-atom $running (quote ($next))))))))
(@doc scan
  (@desc "Every running fold result, beginning with Start. Each callback answer extends a history, so a branching function produces alternative histories and a function with no answer ends that history.")
  (@params ((@param "Function") (@param "Start") (@param "Items")))
  (@return "Running"))

(: pipe (-> Atom %Undefined% %Undefined%))
(= (pipe $functions $seed)
   (let $size (collections-size $functions)
     (foldl-atom (quote $functions) $seed $acc $fn
       (let $function (eval $fn) ($function (quote $acc))))))
(@doc pipe
  (@desc "Pass Value through a held collection of functions from left to right. Evaluate each function entry, then apply the resulting function to the current literal value. Preserve zero or many answers from every application.")
  (@params ((@param "Functions") (@param "Value")))
  (@return "Result"))

(: apply-to (-> %Undefined% Expression %Undefined%))
(= (apply-to $fn $arguments)
   (let* (($size (collections-size $arguments))
          ($quoted (map-atom $arguments $arg (quote (quote $arg))))
          ($call (cons-atom $fn $quoted)))
     (eval $call)))
(@doc apply-to
  (@desc "Apply Function to the literal arguments held by an expression. A computed head, lambda or other function value uses ordinary application, preserving all answers and variable sharing.")
  (@params ((@param "Function") (@param "Arguments")))
  (@return "Result"))
