# Flat registry: renders the aspect-tree walk as a flat attrset keyed by path identity.
#
# THE REGISTRY IS A PROJECTION, NEVER A SOURCE (ADR-0012). Parenthood is NOT recoverable from
# this attrset: `"a/b/c"` is a RENDERING of a parent edge, not the edge, and a nested guard leaf
# sits in the registry carrying no `meta.aspect-chain` at all — so a consumer that splits the key
# and a consumer that reads `meta.aspect-chain or [ ]` disagree, and the second answers ROOT for a
# node whose true parent is `top`. `facts.nix` publishes the edge relations the substrate holds;
# read `graphFacts`, never this key.
#
# The membership predicate and the descent live in `walk.nix` — the same walk `facts.nix` reads —
# so this file states only the rendering. Dep-free (builtins only) → a bare value (gen convention:
# no `{ }:` when argument-less).
let
  inherit (import ./walk.nix) walk;
in
aspects:
builtins.listToAttrs (
  map (e: {
    name = builtins.concatStringsSep "/" e.path;
    inherit (e) value;
  }) (walk aspects)
)
