# The aspect-tree WALK: the node-membership predicate and the descent, held ONCE.
#
# Membership is gen-aspects' own domain knowledge — a nested aspect or a guard leaf is a node,
# class content is not, and a leaf is never recursed into. Two readers need it: `flatten.nix`
# renders the walk as a path-keyed registry, and `facts.nix` reads the same walk for the node
# set and the node values. Held here so the predicate has ONE definition rather than one copy
# per reader (ADR-0013 forbids exactly that duplication).
#
# Detection is structural — no hardcoded key lists:
# - Nested aspects have `name` (from aspectSubmodule), class content and primitives don't
# - Guard leaves — wrapped guard functions (__isWrappedFn) AND defunctionalized guard
#   records (__guard, guard.nix) — are included as leaf entries but never recursed into
#
# Each entry carries its walk position as a SEGMENT LIST, not a joined string. Joining is a
# rendering, and a rendering belongs to the reader that wants it: `flatten` joins with "/",
# `facts` joins an origin-qualified id. Handing readers the joined string is what makes a
# consumer split it again to recover the position.
#
# Collects entries as a list (O(n) via concatMap); the reader does a single listToAttrs,
# avoiding the O(n²) cost of accumulating with foldl'+//.
# Dep-free (builtins only) → a bare value (gen convention: no `{ }:` when argument-less).
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
        path = prefix ++ [ k ];
      in
      if isNestedAspect v then
        [
          {
            inherit path;
            value = v;
          }
        ]
        ++ collectEntries path v
      else if isGuardLeaf v then
        [
          {
            inherit path;
            value = v;
          }
        ]
      else
        [ ]
    ) (builtins.attrNames aspect);
in
{
  inherit isGuardLeaf isNestedAspect;
  # `walk aspects` → [ { path = [ seg … ]; value = <the aspect value>; } … ], parent before children.
  walk = collectEntries [ ];
}
