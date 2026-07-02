# Aspect identity: path-based key for dedup.
{ lib }:
let
  aspectPath = a: (a.meta.aspect-chain or [ ]) ++ [ (a.name or "<anon>") ];

  pathKey = path: lib.concatStringsSep "/" path;

  isMeaningfulName =
    name: name != "<anon>" && name != "<function body>" && !(lib.hasPrefix "[definition " name);

  # hasFn: does the value (recursively) contain a function anywhere? Forces structure.
  # REQUIRED because builtins.toJSON on a function is an UNCATCHABLE error (verified:
  # `tryEval (toJSON { x = _: _; })` does NOT rescue it) — detect functions STRUCTURALLY
  # *before* ever calling toJSON. Plain recursion, NO __guard exclusion: a nested guard
  # whose body is a function must still flip hasFn (else that function reaches toJSON and
  # crashes); a nested FIRST-ORDER guard is still toJSON-able and content-hashes fine.
  hasFn =
    v:
    builtins.isFunction v
    || (builtins.isList v && builtins.any hasFn v)
    || (builtins.isAttrs v && builtins.any hasFn (builtins.attrValues v));

  # bodyKey: nested guard -> its key; first-order body -> content hash (discriminating +
  # site-independent); opaque body -> null (caller falls back to source position).
  bodyKey =
    b:
    if builtins.isAttrs b && (b.__guard or false) then
      guardKey b
    else
      let
        probe = builtins.tryEval (!hasFn b);
      in
      if probe.success && probe.value then
        "h:" + builtins.hashString "sha256" (builtins.toJSON b)
      else
        null;

  # guardKey: pred is ALWAYS structural (pure data). First-order body -> fully structural key
  # (site-independent -> dedup). OPAQUE body (bodyKey null) -> SOURCE POSITION so two different
  # opaque bodies never collide = SOUND (no false merge). meta.loc attached by types.nix (Task 2).
  # Reynolds "Elimination of Higher-Order Functions": the constructor tag (pred.p) is the
  # principled kind identity, replacing source position for the first-order case.
  guardKey =
    g:
    let
      bk = bodyKey g.body;
    in
    if bk == null then
      "guard-loc:" + pathKey (g.meta.loc or [ (g.name or "<anon>") ])
    else
      "guard:${g.pred.p}:"
      + builtins.hashString "sha256" (
        builtins.toJSON {
          inherit (g) pred;
          body = bk;
        }
      );
in
{
  inherit
    aspectPath
    pathKey
    isMeaningfulName
    guardKey
    bodyKey
    ;
  key =
    a:
    if a.__guard or false then
      guardKey a
    else if a.__isWrappedFn or false then
      pathKey (a.meta.loc or [ (a.name or "<anon>") ])
    else
      pathKey (aspectPath a);
}
