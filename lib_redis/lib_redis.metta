;Shared spaces over Redis, SWI's own library(redis) underneath. A platform
;without that library refuses this import by the redis capability's name
;before any part of the provider loads.
;
;(redis-attach &shared "localhost:6379") binds the space name to a
;Redis set. From then on add-atom, remove-atom, match, and get-atoms on
;that space run against Redis through the engine's foreign-space seam,
;so joins split per conjunct and unify in the engine, and every process
;attached to the same address and name reads and writes the same facts.
;Writes publish on a per-space channel: subscriptions fire in every
;attached process, remote writes arriving asynchronously, each write
;heard exactly once per process. (redis-detach &shared) releases the
;binding and leaves the stored facts in Redis for the next attach.
!(import! &self (library lib_import))
!(import_prolog_functions_from_file
  (library lib_redis.pl)
  (redis-attach redis-detach))
