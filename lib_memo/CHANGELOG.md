# Changelog

## Unreleased

- Document that `memoize-exact` and `@space.cache` use counted answer tables,
  while `cache force` selects the ordinary cache. The recursive coefficient
  differential now explicitly exercises the exact path and retains duplicate
  answers on cold calls and replay.
