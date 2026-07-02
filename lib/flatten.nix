# Flat registry: walks the recursive aspect tree and produces a flat attrset
# keyed by path identity. Enables gen-graph/gen-select queries over aspects.
#
# Detection is structural — no hardcoded key lists:
# - Nested aspects have `name` (from aspectSubmodule), class content and primitives don't
# - Guard leaves — wrapped guard functions (__isWrappedFn) AND defunctionalized guard
#   records (__guard, guard.nix) — are included as leaf entries but never recursed into
#
# Parent relationships are implicit in the path key: "a/b/c" → parent is "a/b".
#
# Collects entries as a list (O(n) via concatMap) then single listToAttrs at the
# end, avoiding the O(n²) cost of accumulating with foldl'+//.
_:
let
  # A guard leaf: a wrapped guard function (__isWrappedFn) OR a defunctionalized guard
  # record (__guard, guard.nix). Both are included as leaf entries, never recursed into.
  isGuardLeaf = v: builtins.isAttrs v && ((v.__isWrappedFn or false) || (v.__guard or false));
  isNestedAspect = v: builtins.isAttrs v && v ? name && !(isGuardLeaf v);

  collectEntries =
    prefix: aspect:
    builtins.concatMap (
      k:
      let
        v = aspect.${k};
        pathKey = if prefix == "" then k else "${prefix}/${k}";
      in
      if isNestedAspect v then
        [
          {
            name = pathKey;
            value = v;
          }
        ]
        ++ collectEntries pathKey v
      else if isGuardLeaf v then
        [
          {
            name = pathKey;
            value = v;
          }
        ]
      else
        [ ]
    ) (builtins.attrNames aspect);
in
aspects: builtins.listToAttrs (collectEntries "" aspects)
