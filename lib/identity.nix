# Aspect identity: path-based key for dedup.
{ prelude }:
let
  # The rendering of a record's OWN fields. It is the key only of a record with no declared path
  # (`meta.loc`: an include element, a hand-built record); a placed declaration keys by `meta.loc`.
  aspectPath = a: (a.meta.aspect-chain or [ ]) ++ [ (a.name or "<anon>") ];

  inherit (import ./path.nix) render parse;
  pathKey = render;

  # keyRef — an origin-qualified reference to a node that may live OUTSIDE the local fixpoint
  # (cross-source direct-use, gen-link federation, decision 6). Accepts a structured `{ origin; path }`
  # (origin/path each a list, or a "/"-joined string) OR a bare "origin/seg/seg" string. Marked
  # `__keyRef` so the includes element type recognizes it BEFORE aspectType's accept-all merge absorbs
  # it as a nested aspect. Carries `.key` (= pathKey path) so a reference's target key is inspectable
  # uniformly with an aspect's own `.key`. `builtins.split "/"` is a single-literal-char regex (no `.*`
  # backtracking — safe on short key strings, cf. the whole-file hasInfix stack overflow split fixes).
  splitSlash = parse;

  # keyRef's refusal (ADR-0025 item 1). It names the TYPE and never interpolates the value, because
  # interpolating a non-string is itself the coercion abort the refusal replaces, and `typeOf` is
  # total. Both segment fields are checked, not just `path`'s presence: a `path = 3` or a
  # `path = [ { … } ]` otherwise aborts inside `pathKey`, and a bad `origin` is admitted here and
  # aborts downstream in gen-link. The checks are forced ahead of the result, so the refusal fires
  # where the reference is written.
  keyRefRefusal =
    got:
    "gen-aspects.keyRef: got ${got}, expected a reference: an origin-qualified string "
    + "(\"<origin>/<path>\") or { path; origin ? [ ]; }, each a \"/\"-joined string or a list of strings";
  keyRefSegments =
    field: v:
    if builtins.isString v then
      splitSlash v
    else if builtins.isList v && builtins.all builtins.isString v then
      v
    else
      throw (
        keyRefRefusal (
          "${field} = ${builtins.typeOf v}" + (if builtins.isList v then " holding a non-string" else "")
        )
      );
  keyRef =
    ref:
    let
      r =
        if builtins.isString ref then
          (
            let
              parts = splitSlash ref;
            in
            # "" or all separators leaves no origin segment, and `head []` is an uncatchable abort.
            if parts == [ ] then
              throw (keyRefRefusal "the string \"${ref}\", which has no non-empty segment")
            else
              {
                origin = [ (builtins.head parts) ];
                path = builtins.tail parts;
              }
          )
        else if builtins.isAttrs ref && ref ? path then
          ref
        else
          throw (
            keyRefRefusal (if builtins.isAttrs ref then "a set with no 'path' field" else builtins.typeOf ref)
          );
      originList = keyRefSegments "origin" (r.origin or [ ]);
      pathList = keyRefSegments "path" r.path;
    in
    builtins.seq originList (
      builtins.seq pathList {
        __keyRef = true;
        origin = originList;
        path = pathList;
        key = pathKey pathList;
      }
    );

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

  # guardChainMaxDepth / guardChainDepthRefusal: bodyKey's nested-guard arm dispatches straight back
  # into guardKey, so a guard record whose body eventually recurses back to a guard already on the
  # chain — most directly, one whose body IS itself — cycles guardKey -> bodyKey -> guardKey WITHOUT
  # EVER REACHING hasFn, and so never spends from hasFn's budget. It is the unguarded-walk class one
  # level up from hasFn's own: same remedy, a depth budget over the guard/body HOPS (not value
  # nesting), exhausted by a NAMED throw so a catcher can take the opaque-body branch instead of
  # riding the recursion into an uncatchable stack overflow.
  #
  # Unlike hasFn's single-function `go`, this walk is mutually recursive across two functions
  # (bodyKey's guard arm below), and the throw is left UNCAUGHT all the way through both. Catching it
  # PER HOP would convert only the innermost frame to the opaque answer and let every frame above
  # re-wrap that answer as ordinary content — for a true self-loop (`g.body == g`) that mints a
  # content hash instead of ever reaching the position fallback, because "guard-loc:…" is just
  # another string once it comes back up. The ONE catch, at `guardKey` below, is what makes the
  # WHOLE chain opaque rather than just its last hop.
  guardChainMaxDepth = 256;

  guardChainDepthRefusal =
    "gen-aspects: identity: the guard/body chase exceeded its depth budget of "
    + "${toString guardChainMaxDepth} hops while resolving a guard's body key. A chain nested that "
    + "deeply is almost always CYCLIC — a guard record whose body recurses back to a guard already on "
    + "the chain, most directly one whose body IS itself — and an unbounded chase over one aborts the "
    + "evaluator UNCATCHABLY, so it refuses by name here instead. The guard is treated as opaque: it "
    + "keys by source position (`guard-loc:…`) rather than by content. Keep guard nesting finite if the "
    + "guard needs a content-addressed key.";

  guardLocFallback = g: "guard-loc:" + pathKey (g.meta.loc or [ (g.name or "<anon>") ]);

  mintGuardKey =
    g: bk:
    "guard:${g.pred.p}:"
    + builtins.hashString "sha256" (
      builtins.toJSON {
        inherit (g) pred;
        body = bk;
      }
    );

  # bodyKey: nested guard -> its key (depth-budgeted chase, see above); first-order body -> content
  # hash (discriminating + site-independent); opaque body -> null (caller falls back to source
  # position). The first-order probe reads BOTH of hasFn's ways of declining a body and treats them
  # alike, which is why hasFn's OWN depth refusal needed no new branch here: `probe.value == false` is
  # "a function is in there", and `probe.success == false` is "the scan refused to answer" — under
  # either the body is not one this library will content-address, and the source-position fallback is
  # already that answer.
  bodyKey =
    let
      go =
        d: b:
        if builtins.isAttrs b && (b.__guard or false) then
          if d >= guardChainMaxDepth then
            throw guardChainDepthRefusal
          else
            let
              bk = go (d + 1) b.body;
            in
            if bk == null then guardLocFallback b else mintGuardKey b bk
        else
          let
            probe = builtins.tryEval (!hasFn b);
          in
          if probe.success && probe.value then
            "h:" + builtins.hashString "sha256" (builtins.toJSON b)
          else
            null;
    in
    go 0;

  # guardKey: pred is ALWAYS structural (pure data). First-order body -> fully structural key
  # (site-independent -> dedup). For an OPAQUE body (bodyKey null OR the guard-chain budget above
  # exhausted), fall back to SOURCE POSITION. Once meta.loc is present (attached by types.nix, Task 2)
  # this is SOUND: two different opaque bodies at different sites never collide. Until then, opaque
  # guards lacking meta.loc share the "<anon>" fallback; guardKey has no live dedup consumer yet, so
  # that collapse is latent, not a live bug.
  # Reynolds "Elimination of Higher-Order Functions": the constructor tag (pred.p) is the
  # principled kind identity, replacing source position for the first-order case.
  #
  # THE ONE CATCH POINT for the guard-chain depth budget: bodyKey's nested-guard arm never catches its
  # own throw, so a cyclic chain propagates it, uncaught, all the way back here — where it is caught
  # ONCE and answered with THIS guard's own position, exactly the answer bodyKey already gives any
  # body it cannot content-address.
  # Multi-def guard carrier identity (den-hoag-sezf Arm B). A carrier of RECORD/unconditional
  # fragments is inert first-order structure, so it mints structurally over its ordered fragment
  # list, exactly as a single guard record mints over its body (ADR-0034/ADR-0016 ruling 5: one
  # mint, and what the mint cannot take gets no identity at all — a total tagged field and a
  # named refusal when identity is demanded). A carrier holding ANY function-bodied fragment — or
  # any fragment whose body itself fails `bodyKey` — is a sealed site: the same `guardLocFallback`
  # a single opaque-bodied guard already falls back to, now for the whole carrier rather than one
  # fragment, because a partial mint is not a mint (R-2, the fragment-order-in-preimage question,
  # is carried separately and NOT settled by this — see the spec's §4).
  fragmentToken =
    f:
    if f.kind == "fn" then
      null
    else if f.kind == "record" then
      { guard = termGuardId f; }
    else
      let
        probe = builtins.tryEval (bodyKey f.body);
      in
      if !(probe.success && probe.value != null) then null else { body = probe.value; };

  carrierKey =
    g:
    let
      toks = map fragmentToken g.fragments;
    in
    if builtins.any (t: t == null) toks then
      guardLocFallback g
    else
      "guard:carrier:" + builtins.hashString "sha256" (builtins.toJSON { fragments = toks; });

  # A first-order guard's identity is its mint over (condition, body), attached where it was checked
  # against its `cnf` (lib/guard-term.nix): defined for a checked guard only, and refused by name when
  # the mint cannot take it (ADR-0034, REFUSED). No source-position fallback.
  termGuardId =
    g:
    if !(g ? __mint) then
      throw "gen-aspects: identity: a first-order guard has an identity once it is checked against its cnf (placed at an aspect position, or fired through a vocabulary); this one is unchecked."
    else
      g.__mint.minted or (throw g.__mint.unmintable);

  guardKey =
    g:
    if g ? condition then
      termGuardId g
    else if g ? fragments then
      carrierKey g
    else
      let
        probe = builtins.tryEval (bodyKey g.body);
      in
      if probe.success && probe.value != null then mintGuardKey g probe.value else guardLocFallback g;
  # The declared path's shape (ADR-0025 item 1: malformed caller input refuses by name, catchably).
  # `meta` is freeform, so `meta.loc` takes any value, and a non-list or a non-string segment
  # otherwise aborts the evaluator inside `pathKey`/`init`, where `tryEval` cannot see it. The
  # refusal names the type and never interpolates the value, as `keyRefRefusal` does.
  declaredPathRefusal =
    got:
    "gen-aspects: identity: meta.loc is ${got}, expected the declared path: a non-empty list of strings. "
    + "meta.loc is stamped by the aspect type from the position the aspect is declared at; remove the definition.";
  declaredPath =
    a:
    let
      loc = a.meta.loc;
    in
    if !(builtins.isList loc) then
      throw (declaredPathRefusal "a ${builtins.typeOf loc}")
    else if loc == [ ] then
      throw (declaredPathRefusal "an empty list")
    else if !(builtins.all builtins.isString loc) then
      throw (declaredPathRefusal "a list holding a non-string")
    else
      loc;
  # A record is a DECLARATION when the type stamped its declared path (`meta.loc`, null when unstamped).
  isDeclared = a: builtins.isAttrs (a.meta or null) && (a.meta.loc or null) != null;
  # Renders a caller-set chain for the refusal below without coercing it: interpolating a
  # non-string is itself an uncatchable abort.
  renderChain =
    chain:
    if builtins.isList chain && builtins.all builtins.isString chain then
      "[ ${prelude.concatStringsSep " " chain} ]"
    else
      "a ${builtins.typeOf chain}";
  # A static declaration's key. Its chain is a rendering of the declared path (`init loc`), so a
  # chain that says otherwise is refused by name rather than honoured or ignored (identity design Q4).
  checkedPath =
    a:
    let
      loc = declaredPath a;
      chain = a.meta.aspect-chain or null;
    in
    if a.__guard or false then
      loc
    else if chain != null && chain != prelude.init loc then
      throw (
        "gen-aspects: identity: `${pathKey loc}` sets meta.aspect-chain = ${renderChain chain}, "
        + "which contradicts its declared path [ ${prelude.concatStringsSep " " loc} ]. meta.aspect-chain "
        + "is a rendering of the declared path and never an identity input; remove the definition."
      )
    else
      loc;
  rawKeyOf =
    a:
    if isDeclared a then
      pathKey (checkedPath a)
    else if a.__guard or false then
      guardKey a
    else
      pathKey (aspectPath a);
in
{
  inherit
    aspectPath
    pathKey
    ;
  parsePath = parse;
  inherit
    isMeaningfulName
    guardKey
    keyRef
    isDeclared
    checkedPath
    ;

  # Exported for the CI's guard cells and their message assertion, NOT re-exported from
  # `lib/default.nix`: a consumer asks this library for a KEY, never for the scan behind one, and
  # never renders its refusal. The budget travels with them so the cells that straddle it read the
  # number from here instead of restating it — a restated bound is one that drifts silently past the
  # thing it is supposed to be testing. `bodyKey` rides along too: it is the ONE path in this file
  # that lets the guard-chain depth throw escape uncaught, which is what a cell needs to assert
  # catchability on the real path rather than through `guardKey`'s own graceful fallback.
  inherit
    hasFn
    hasFnMaxDepth
    hasFnDepthRefusal
    bodyKey
    guardChainMaxDepth
    guardChainDepthRefusal
    ;
  # A DECLARATION's key: origin + declared path (identity design §1), the origin entering at `aspectId`.
  # The declared path is `meta.loc`, which the type stamps on every placed declaration: a guard leaf
  # (placement, types.nix: the single record and the carrier alike) and a static aspect alike. Never
  # `name` or `meta.aspect-chain`, which are renderings a caller can set; a static's chain that contradicts
  # its declared path refuses by name (identity design Q4). A guard's `guardKey` is the TERM's identity and
  # never the declaration's: the class payload is outside the term's mint (ADR-0034 a0gc), so keying the
  # declaration by it gave two declarations with one condition and one non-class body one key, and one
  # instance. Only a record with no declared path (an unplaced guard, a hand-built record, the container
  # root) keys by its own fields.
  # A typed aspect's checked `key` option is forced first, so a declared path forced past the type
  # (an mkForce'd `meta.loc`) refuses at every reader, not only at the option.
  key = a: builtins.seq (a.key or null) (rawKeyOf a);
  rawKey = rawKeyOf;
}
