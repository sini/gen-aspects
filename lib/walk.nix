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
#
# ★ F-NWF / F-DEEP, an ADR-0025 item 1 declared exception (defaulted, reversible; den-hoag-vt1wn).
# `collectEntries` recurses with no depth formal, so it aborts UNCATCHABLY
# (`stack overflow; max-call-depth exceeded`, which `tryEval` does not contain) on two input
# classes:
# - F-NWF: any non-well-founded tree — a self-referential aspect declaration or an
#   `mkForce`-injected cyclic attrset, reachable through both the direct attrset surface and the
#   module route (gen-merge unfolds a cyclic module tree lazily, at nixpkgs parity, so the walk is
#   what aborts, not the merge). A non-well-founded value has no finite node list, so this is
#   outside the walk's domain, not a ceiling: no pure-Nix predicate separates it from a legitimate
#   deep tree (identity is observable only on shared heap cells, names repeat legitimately, and
#   walk paths are unique by construction), so a bounded seen-set or depth guard here would also
#   refuse well-founded input it accepts today.
# - F-DEEP: a well-founded tree past a context-dependent ceiling (about 3000-3500 levels at top
#   level and default `max-call-depth`, lower under an already-deep caller). The ceiling is real,
#   but no constant sits at it — ADR-0032 forbids a bound that refuses input which has a value in
#   some context and still fails to pre-empt the abort in another.
# The price is recorded rather than closed: peak RSS 65 MB (direct route) / 295 MB (module route),
# fast and loud. See `reports/den-hoag-diwuf-vt1wn-cyclic-spec-v0.md` and AGENTS.md, "Measured
# traps".
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
