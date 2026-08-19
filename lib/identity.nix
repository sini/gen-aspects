# Aspect identity: path-based key for dedup.
{ prelude }:
let
  aspectPath = a: (a.meta.aspect-chain or [ ]) ++ [ (a.name or "<anon>") ];

  pathKey = path: prelude.concatStringsSep "/" path;

  # keyRef — an origin-qualified reference to a node that may live OUTSIDE the local fixpoint
  # (cross-source direct-use, gen-link federation, decision 6). Accepts a structured `{ origin; path }`
  # (origin/path each a list, or a "/"-joined string) OR a bare "origin/seg/seg" string. Marked
  # `__keyRef` so the includes element type recognizes it BEFORE aspectType's accept-all merge absorbs
  # it as a nested aspect. Carries `.key` (= pathKey path) so a reference's target key is inspectable
  # uniformly with an aspect's own `.key`. `builtins.split "/"` is a single-literal-char regex (no `.*`
  # backtracking — safe on short key strings, cf. the whole-file hasInfix stack overflow split fixes).
  splitSlash = s: builtins.filter (seg: builtins.isString seg && seg != "") (builtins.split "/" s);
  keyRef =
    ref:
    let
      r =
        if builtins.isString ref then
          (
            let
              parts = splitSlash ref;
            in
            {
              origin = [ (builtins.head parts) ];
              path = builtins.tail parts;
            }
          )
        else
          ref;
      originRaw = r.origin or [ ];
      originList = if builtins.isString originRaw then splitSlash originRaw else originRaw;
      pathList = if builtins.isString r.path then splitSlash r.path else r.path;
    in
    {
      __keyRef = true;
      origin = originList;
      path = pathList;
      key = pathKey pathList;
    };

  isMeaningfulName =
    name: name != "<anon>" && name != "<function body>" && !(prelude.hasPrefix "[definition " name);

  # hasFn: does the value (recursively) contain a function anywhere? Forces structure.
  # REQUIRED because builtins.toJSON on a function is an UNCATCHABLE error (verified:
  # `tryEval (toJSON { x = _: _; })` does NOT rescue it) — detect functions STRUCTURALLY
  # *before* ever calling toJSON. NO __guard exclusion: a nested guard whose body is a function must
  # still flip hasFn (else that function reaches toJSON and crashes); a nested FIRST-ORDER guard is
  # still toJSON-able and content-hashes fine.
  #
  # ★ THE WALK IS OVER CALLER-SUPPLIED VALUES, SO IT CANNOT BE A PLAIN STRUCTURAL RECURSION. Unguarded
  # it diverges on ordinary Nix values, measured on the shipped definition with each arm its own eval:
  # a cyclic attrset and a list containing itself both `stack overflow; max-call-depth exceeded`, and
  # a derivation value the same way — its `out` attribute is self-referential (`drv.out.out.out…`) —
  # while a deep finite payload mints its key and a lambda-carrying one is detected. An abort is NOT a
  # `tryEval`-catchable failure, so every one of those escapes `bodyKey`'s probe and detonates the
  # library at a position whose whole job is to return a boolean.
  #
  # Two guards, both REFUSALS rather than repairs:
  #
  #   (1) A DERIVATION ANSWERS BY TYPE TEST, BEFORE ANY DESCENT. This arm is exactness, not safety —
  #       (2) already makes the value safe. `builtins.toJSON` does not descend into a derivation
  #       either: it renders the `outPath` string alone. So no function reachable only inside one can
  #       ever reach the builtin this predicate exists to protect, and `false` is the honest answer to
  #       the question actually being asked. Without this arm every derivation-valued body would
  #       instead exhaust (2)'s budget and lose its content key to the source-position fallback.
  #
  #   (2) EVERY DESCENT SPENDS FROM A DEPTH BUDGET, and exhaustion THROWS BY NAME. Depth rather than a
  #       node count because a cycle IS unbounded depth by construction, whereas a node cap would also
  #       refuse large FINITE payloads — false refusals for values the walk terminates on perfectly
  #       well. The throw is `tryEval`-catchable where the abort it replaces is not, so `bodyKey`'s
  #       existing probe simply sees a failed probe and takes its opaque-body branch: a refused body
  #       keys by SOURCE POSITION instead of aborting.
  #
  # ★ WHAT THIS CANNOT GUARD, stated rather than left silent: a value whose own thunk is a black hole
  # (`l = [ 1 ] ++ l`) aborts when it is FORCED, and the shallowest possible observation — a bare
  # `builtins.isList l`, no walk at all — aborts identically. No predicate can admit such a value,
  # here or anywhere. It is not this walk's to refuse.
  #
  # The budget is chosen against both ends: no guard body written as configuration data nests anywhere
  # near it, and it is well below the evaluator's own max-call-depth, so the named throw always fires
  # BEFORE the abort it exists to pre-empt.
  hasFnMaxDepth = 256;

  # The refusal renders from a NAMED binding rather than being spelled at its `throw`. Nix cannot
  # recover a thrown message through `tryEval`, so the CI asserts catchability on the real path and
  # message CONTENT on this renderer — the same split `cnf.nix` and `facts.nix` use. A message that
  # exists only inside a `throw` is one nothing can hold to naming its subject.
  hasFnDepthRefusal =
    "gen-aspects: identity: the structural function-scan exceeded its depth budget of "
    + "${toString hasFnMaxDepth} while walking a guard body. A value nested that deeply is almost "
    + "always CYCLIC — a self-referential attrset, or a list containing itself — and an unbounded walk "
    + "over one aborts the evaluator UNCATCHABLY, so the scan refuses by name here instead. The body "
    + "is treated as opaque from this point: its guard keys by source position (`guard-loc:…`) rather "
    + "than by content. Pass a finite, acyclic body if the guard needs a content-addressed key.";

  hasFn =
    let
      go =
        d: v:
        if builtins.isFunction v then
          true
        else if builtins.isAttrs v && (v.type or null) == "derivation" then
          false
        else if !(builtins.isAttrs v || builtins.isList v) then
          false
        else if d >= hasFnMaxDepth then
          throw hasFnDepthRefusal
        else
          builtins.any (go (d + 1)) (if builtins.isList v then v else builtins.attrValues v);
    in
    go 0;

  # bodyKey: nested guard -> its key; first-order body -> content hash (discriminating +
  # site-independent); opaque body -> null (caller falls back to source position).
  # The probe reads BOTH of hasFn's ways of declining a body and treats them alike, which is why the
  # depth refusal needed no new branch here: `probe.value == false` is "a function is in there", and
  # `probe.success == false` is "the scan refused to answer" — under either the body is not one this
  # library will content-address, and the source-position fallback is already that answer.
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
  # (site-independent -> dedup). For an OPAQUE body (bodyKey null), fall back to SOURCE POSITION.
  # Once meta.loc is present (attached by types.nix, Task 2) this is SOUND: two different opaque
  # bodies at different sites never collide. Until then, opaque guards lacking meta.loc share the
  # "<anon>" fallback; guardKey has no live dedup consumer yet, so that collapse is latent, not a
  # live bug.
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
    keyRef
    ;

  # Exported for the CI's guard cells and their message assertion, NOT re-exported from
  # `lib/default.nix`: a consumer asks this library for a KEY, never for the scan behind one, and
  # never renders its refusal. The budget travels with them so the cells that straddle it read the
  # number from here instead of restating it — a restated bound is one that drifts silently past the
  # thing it is supposed to be testing.
  inherit hasFn hasFnMaxDepth hasFnDepthRefusal;
  key =
    a:
    if a.__guard or false then
      guardKey a
    else if a.__isWrappedFn or false then
      pathKey (a.meta.loc or [ (a.name or "<anon>") ])
    else
      pathKey (aspectPath a);
}
