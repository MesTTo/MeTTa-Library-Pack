# Persistent syntax

`database-atoms` returns an expression. Select its elements with ordinary
MeTTa segment patterns, sharing variables between the pattern and its result:

```metta
!(import! &self (library lib_database))
!(with-database "catalog" close
   (|-> ($store)
     (let $added (database-add! $store (item apple 3))
       (collapse
         (let ((:seg $before) (item $name $price) (:seg $after))
              (database-atoms $store)
           (quote ($name $price)))))))
; ((apple 3)) on a newly created catalog
```

Each snapshot preserves insertion order and duplicate occurrences. A second
pattern over the same snapshot joins another relation through shared variables.
The [executable example](../../examples/ch08-data/08-03-the-shipped-libraries/42-database_lib.metta)
joins edges that refer to other edges and reconstructs persisted equations.

Stored expressions are passive data. For example, `(+ 1 2)` remains that
expression, and storing `(= (twice $x) (+ $x $x))` does not install an equation
in the calling space. Match its parameter and body, construct a lambda, then
explicitly evaluate that lambda when you want a callable function. Keep syntax
under `quote` while composing it. `superpose` evaluates its alternatives;
segment patterns enumerate passive data.

Variables are fresh for each occurrence and snapshot. Sharing within an
occurrence survives closing and reopening. Binding a snapshot cannot mutate
the stored value. Removal takes one alpha-identical occurrence: variable names
may change, but their sharing and every scalar's native kind must agree.
An unbound variable removes a stored variable, not an arbitrary row.

The directory contains a journal and a permanent lock file. Keep its contents
under this API's ownership while it is open. `with-database` closes on every
exit; explicit handles need `database-close!`. Sync modes control buffering,
not transactions or durable `fsync`. A write or sync error closes the owner;
malformed journals refuse before replay and remain available for repair.

Use `database-atoms` with core matching in place of the former `database-query`.
Existing ground journals retain their representation. Journals containing
variables use a canonical private encoding and require the current reader.
Cycles, attributed variables and foreign resources cannot be persisted.
