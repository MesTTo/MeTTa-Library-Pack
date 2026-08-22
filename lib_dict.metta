;The dict story, and it is the SPACE.
;
;A dict is a space of (key value) atoms. That is MeTTa HE's own decision,
;taken for JSON objects and called "the mettafied one" in lib_json's header,
;and the reason to keep it for dicts generally is that it costs no new type:
;a lookup is a match, a dict is queryable with every operation any other
;space has, and the answer set is the language's own reading of "all of
;them". lib_json ships dict-space, get-keys and get-value; what a dict needs
;beyond a decoded document is written here, in MeTTa, over those.
;
;THE ROUTES NOT TAKEN, each measured rather than argued
;[source: ai-python-first-revamp-discussion.md, "DICTS MOVED OUT of this
;category"]:
;  - an OPAQUE HANDLE over the Python dict, which the shipped auto_image
;    policy already decides per value. It is one crossing per lookup and it
;    answers no query the Python dict cannot; reverse lookup by value is a
;    scan in Python and impossible on a handle.
;  - a LIVE VIEW, a foreign provider over the Python dict: registering costs
;    69.3us and is size-independent where materialising 2,000 entries costs
;    54,844us and 1.15M inferences, mutation stays visible, and reverse
;    lookup is an ordinary pattern. That is the right route for a dict the
;    Python side keeps mutating, and it is the seam's, not the stdlib's.
;  - a NATIVE DICT TYPE, SWI's `_{a:1}` or library(assoc)'s AVL trees. The
;    space is already an indexed store with the same asymptotics, so a native
;    type would add a representation to learn and a second set of operations
;    to keep in step for no measured gain.
;The space image is a SNAPSHOT of a mutable value and says so; live currency
;wants the view or the state cell.
;
;THE ARBITER IS SILENT. LeaTTa's stdlib.md carries no dict entry and its
;semantics corpus has no dict program, so nothing here is a divergence from a
;ruling: it is vocabulary in the space the arbiter leaves open, the way the
;kernel's performance builtins are. The question filed for it is whether a
;dict's KEY ORDER is observable; this library answers get-keys in the space's
;own order, which is insertion order here, and states that rather than
;promising it.

!(import! &self (library lib_json))

;A key holds ONE value, which is the only thing that makes this a dict rather
;than a relation: putting a key that is already there replaces it. Written as
;a remove and an add because that is what the space offers, and the remove of
;an absent key is an ordinary answer rather than a failure.
(: dict-put (-> SpaceType %Undefined% %Undefined% SpaceType))
(= (dict-put $d $k $v)
   (let $dropped (dict-remove $d $k)
        (let $added (add-atom $dropped ($k $v)) $dropped)))

;remove-atom is EXACT, not a pattern removal, and its atom argument is HELD,
;so the pair has to arrive as a VALUE: it is matched first, bound to a
;variable, and the variable substituted into the held position. That is also
;what makes the put above a replacement, since the key's old pair is found and
;removed before the new one is added. The collapse makes the whole thing
;deterministic, so removing a key that is not there answers the dict once
;rather than not at all.
(: dict-remove (-> SpaceType %Undefined% SpaceType))
(= (dict-remove $d $k)
   (let $gone (collapse (dict-remove-pair $d $k)) $d))

(: dict-remove-pair (-> SpaceType %Undefined% %Undefined%))
(= (dict-remove-pair $d $k)
   (let $pair (superpose (collapse (match $d ($k $v) ($k $v))))
        (remove-atom $d $pair)))

(: dict-has (-> SpaceType %Undefined% Bool))
(= (dict-has $d $k)
   (if (== (collapse (match $d ($k $v) $v)) ()) False True))

(: dict-size (-> SpaceType Number))
(= (dict-size $d) (space-atom-count $d))

;The inverse of dict-space, and the shape a comprehension builds: an
;expression of (key value) pairs, which dict-space reads back.
(: dict-pairs (-> SpaceType Expression))
(= (dict-pairs $d) (collapse (get-atoms $d)))

(: dict-values (-> SpaceType %Undefined%))
(= (dict-values $d) (match $d ($k $v) $v))
