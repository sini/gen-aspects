# Flat registry: walks the recursive aspect tree and produces a flat attrset
# keyed by path identity. Enables gen-graph/gen-select queries over aspects.
#
# Detection is structural — no hardcoded key lists:
# - Nested aspects have `name` (from aspectSubmodule), class content and primitives don't
# - Guard functions (__isWrappedFn) are included as leaf entries but not recursed
#
# Parent relationships are implicit in the path key: "a/b/c" → parent is "a/b".
_:
let
  isNestedAspect = v: builtins.isAttrs v && v ? name && !(v.__isWrappedFn or false);
  isGuardFn = v: builtins.isAttrs v && (v.__isWrappedFn or false);

  flattenWith =
    prefix: aspect:
    builtins.foldl' (
      acc: k:
      let
        v = aspect.${k};
        pathKey = if prefix == "" then k else "${prefix}/${k}";
      in
      if isNestedAspect v then
        acc // { ${pathKey} = v; } // flattenWith pathKey v
      else if isGuardFn v then
        acc // { ${pathKey} = v; }
      else
        acc
    ) { } (builtins.attrNames aspect);
in
aspects: flattenWith "" aspects
