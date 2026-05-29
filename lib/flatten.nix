# Flat registry: walks the recursive aspect tree and produces a flat attrset
# keyed by path identity. Enables gen-graph/gen-select queries over aspects.
#
# Detection is structural — no hardcoded key lists:
# - Nested aspects have `name` (from aspectSubmodule), class content and primitives don't
# - Guard functions (__isWrappedFn) are included as leaf entries but not recursed
#
# Parent relationships are implicit in the path key: "a/b/c" → parent is "a/b".
#
# Collects entries as a list (O(n) via concatMap) then single listToAttrs at the
# end, avoiding the O(n²) cost of accumulating with foldl'+//.
_:
let
  isNestedAspect = v: builtins.isAttrs v && v ? name && !(v.__isWrappedFn or false);
  isGuardFn = v: builtins.isAttrs v && (v.__isWrappedFn or false);

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
      else if isGuardFn v then
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
