# First-order guards over the one term algebra (den-hoag-lwbb1 unit 2;
# specs/2026-10-02-gen-aspects-first-order-guards-spec.md). A guard is a condition term and a body
# term (design Section 3). This file is gen-aspects' INSTANCE of gen-algebra's core: its declared set,
# its module slots, its admitted formers, the check that runs where a guard meets its `cnf`, and the
# resolver whose read environment carries the framework's door (`cnf.ref`) and, inside one firing, the
# scope the door returns. It stores no closure and applies none: the door and its scope are runtime
# parameters (design G5 scope ruling).
{
  T,
  hashIdentity,
  keyCategory,
  mkIsModuleFn,
}:
let
  inherit (import ./cnf.nix) declaredOf;
  tm = T.term;
  isLeft = r: builtins.isAttrs r && builtins.attrNames r == [ "left" ];
  unique =
    xs:
    builtins.attrNames (
      builtins.listToAttrs (
        map (x: {
          name = x;
          value = null;
        }) xs
      )
    );

  # THE IDENTIFIERS A `ref` CARRIES. A door registration identifier is `toJSON` of a one-key
  # `declared`/`nested` record (unifying spec §2.8); a NESTED-GUARD identifier is `toJSON` of a one-key
  # `guard` record, built by `lift` alone (below); anything else is an aspect, by its local key.
  # The prefix is compared by `substring`, never by a regex: a `.*` match over an id of 100000
  # characters overflows the C++ stack uncatchably on nix and Determinate, and the length bound below
  # has not run yet at this point.
  hasPrefix = ps: id: builtins.any (p: builtins.substring 0 (builtins.stringLength p) id == p) ps;
  isDoorId = hasPrefix [
    "{\"declared\":"
    "{\"nested\":"
  ];
  isGuardId = hasPrefix [
    "{\"guard\":"
    "{\"slot\":"
  ];

  # A door id is DECODED only once it matches refId's output grammar, because `builtins.fromJSON`
  # aborts uncatchably on malformed input on all three evaluators. The grammar match itself overflows
  # the C++ stack on long input (a 64002-character string on nix and Determinate; 32002 passes on all
  # three), so the length is bounded first, a quarter of the measured ceiling. At refId's measured
  # growth this admits nesting depth 7 (den v1's measured maximum is 3). The grammar admits only what
  # `toJSON` emits where `fromJSON` decodes it back: no raw control character, a `\u` escape only for
  # U+0001..U+001F (no NUL, no surrogate), an integer of at most 18 digits with no leading zero (a
  # longer one decodes to a float). A string holding bytes that are not UTF-8 is the residue.
  maxIdLength = 8192;
  ctl = builtins.fromJSON "\"\\u0001-\\u001f\"";
  jstr = "\"([^\\\\\"${ctl}]|\\\\([\"\\\\/bfnrt]|u00(0[1-9a-fA-F]|1[0-9a-fA-F])))*\"";
  jseg = "(${jstr}|-?(0|[1-9][0-9]{0,17}))";
  jstrs = "(${jstr}(,${jstr})*)?";
  jreads = "(null|\\[${jstrs}])";
  rxDeclared = "[{]\"declared\":[{]\"reads\":${jreads},\"site\":${jstr}[}][}]";
  rxNested = "[{]\"nested\":[{]\"outer\":${jstr},\"position\":\\[(${jseg}(,${jseg})*)?],\"reads\":${jreads},\"sources\":[{](${jstr}:${jstr}(,${jstr}:${jstr})*)?[}][}][}]";
  decodeDoorId =
    id:
    if
      builtins.isString id
      && builtins.stringLength id <= maxIdLength
      && (builtins.match rxDeclared id != null || builtins.match rxNested id != null)
    then
      builtins.fromJSON id
    else
      null;
  shortId = id: if builtins.stringLength id > 120 then builtins.substring 0 120 id + "…" else id;

  # D as gen-aspects' instance reads it: the framework's set, widened by this library's own context
  # fields (unifying spec OQ5). One value, passed to both the check and the resolver (P3).
  declaredFor =
    cnf:
    let
      d = declaredOf cnf;
    in
    if d == null then
      null
    else
      d
      ++ [
        "class"
        "tags"
      ];

  instanceFor = cnf: {
    vocabulary = builtins.filter (f: f != "ReadFrom") T.knownFormers;
    declared = declaredFor cnf;
    slots = {
      isKey = k: keyCategory cnf k == "class";
      admits =
        v: builtins.isAttrs v || builtins.isPath v || (builtins.isFunction v && mkIsModuleFn cnf v);
    };
  };

  # First-order data into its term, by the algebra's own images of Nix data, with the nested guards it
  # meets. A class key's value is left as written (the instance's module slot), so is a function (refused
  # by name by the check); a derivation is handed to `lit`, which refuses it by name.
  #
  # A GUARD NESTED IN A BODY STAYS A GUARD. It is checked as its own clause, under the same cnf, and the
  # body holds `ref <id>` in its place, where `<id>` names its position and its identity; the checked
  # inner record rides beside the body (`__nested`), and the outer's firing resolves the `ref` to it
  # unchanged, so it fires at ITS OWN firing, never at the outer's (as base served it). Its reads are
  # not the outer's, and its identity enters the outer's preimage through the id.
  #
  # EVERY DESCENT SPENDS FROM ONE DEPTH BUDGET, and exhaustion refuses by name: a cyclic body (a guard
  # whose body holds itself, a self-referential attrset) is unbounded depth by construction, and an
  # unbounded walk over one overflows the stack uncatchably. 256 is base's own pair of budgets
  # (`hasFnMaxDepth`, `guardChainMaxDepth`), so every chain base keyed still keys: a 248-guard chain
  # and a 250-level body were measured to check, key and fire on nix, Determinate and Lix.
  maxLiftDepth = 256;
  # The aspect a nested guard sits in, without the trail of the guards above it (a refusal at depth 256
  # names the aspect and its own depth, never 256 repeated segments).
  rootAt = at: builtins.head (builtins.split ", the guard nested " at);
  showPos = pos: if pos == [ ] then "the body" else builtins.concatStringsSep "." (map toString pos);
  depthRefusal =
    at: pos:
    "gen-aspects.guard: ${at}: guard-depth: the guard body nests deeper than ${toString maxLiftDepth} levels at `${showPos pos}`; a body that deep is almost always CYCLIC (a guard whose body holds itself, or an attrset containing itself). Pass a finite, acyclic body.";
  none = { };
  liftAt =
    cnf: at: depth: pos: v:
    if depth > maxLiftDepth then
      throw (depthRefusal at pos)
    else if builtins.isFunction v && mkIsModuleFn cnf v then
      # A MODULE FUNCTION AT AN ASPECT POSITION OF THE BODY (the whole body, an `includes` element) is a
      # declared module slot, as one at a class key is (design Section 5: "Module functions, the form
      # nixpkgs serves, are declared module slots: carried opaque in guard bodies and never applied by
      # the algebra"). The core admits a slot only as an attrset child at a slot key, so the body holds
      # `ref <id>` at its position and the function rides beside it, as a nested guard does: its
      # POSITION enters the identity, its payload does not (unifying §2.4).
      let
        id = builtins.toJSON { slot.at = pos; };
      in
      {
        term = tm.ref id;
        nested.${id} = v;
      }
    else if T.isTerm v || isLeft v || builtins.isFunction v then
      {
        term = v;
        nested = none;
      }
    else if builtins.isAttrs v && (v.__guard or false) then
      let
        inner =
          checkGuardAt cnf "${rootAt at}, the guard nested ${toString (depth + 1)} deep at `${showPos pos}`"
            (depth + 1)
            v;
        id = builtins.toJSON {
          guard = {
            at = pos;
            id = inner.__mint.minted or null;
          };
        };
      in
      {
        term = tm.ref id;
        nested.${id} = inner;
      }
    else if builtins.isAttrs v && (v.type or null) == "derivation" then
      {
        term = tm.lit v;
        nested = none;
      }
    else if builtins.isAttrs v then
      let
        kids = builtins.mapAttrs (
          k: c:
          if keyCategory cnf k == "class" then
            {
              term = c;
              nested = none;
            }
          else
            liftAt cnf at (depth + 1) (pos ++ [ k ]) c
        ) v;
      in
      {
        term = tm.attrs (builtins.mapAttrs (_: x: x.term) kids);
        nested = builtins.foldl' (acc: x: acc // x.nested) none (builtins.attrValues kids);
      }
    else if builtins.isList v then
      let
        kids = builtins.genList (i: liftAt cnf at (depth + 1) (pos ++ [ i ]) (builtins.elemAt v i)) (
          builtins.length v
        );
      in
      {
        term = tm.list (map (x: x.term) kids);
        nested = builtins.foldl' (acc: x: acc // x.nested) none kids;
      }
    else
      {
        term = tm.lit v;
        nested = none;
      };
  lift = cnf: v: (liftAt cnf "guard" 0 [ ] v).term;

  nodes = t: [ t ] ++ builtins.concatMap nodes (T.children t);
  refsIn = t: builtins.filter (n: n.__bodyTerm == "Ref") (nodes t);
  # UC1: a door-registration `ref` is admitted only as the whole body.
  misplacedDoorRef =
    body:
    builtins.filter (n: n.__bodyTerm == "Ref" && isDoorId n.id) (
      builtins.concatMap nodes (T.children body)
    );
  isDoorBody = body: body.__bodyTerm == "Ref" && isDoorId body.id;
  malformedDoorRef =
    body: builtins.filter (n: isDoorId n.id && decodeDoorId n.id == null) (refsIn body);

  render =
    at: l:
    "gen-aspects.guard: ${at}: ${l.code}: ${
      l.witness.message or (builtins.toJSON (removeAttrs l.witness [ "message" ]))
    }"
    + (
      if l.code == "term-function" then
        ". A guard body is data: module content belongs under a class key. A context closure crosses the gen-rules door: declare the aspect through the framework's surface, or write the body as a guard term (`guard (pred.has <coordinate>) <body>`)."
      else
        ""
    );

  # The declaration check, where a guard meets its `cnf`: the clause (gen-algebra `checkClause`), then
  # the door reference's position and its identifier's domain. Returns the checked record; identity is
  # defined for it only.
  checkGuardAt =
    cnf: at: depth: g:
    if g ? pred then
      throw "gen-aspects.guard: ${at}: a guard record built by the retired predicate vocabulary (`pred`); build its condition with `pred.*`, which now emit terms (den-hoag-lwbb1)."
    else if g.__checked or false then
      g
    else
      let
        lifted = liftAt cnf at depth [ ] g.body;
        body = lifted.term;
        r = T.checkClause (instanceFor cnf) {
          inherit (g) condition;
          inherit body;
        };
        bad = misplacedDoorRef body;
        malformed = malformedDoorRef body;
        cm = g.condition.__mint;
        bm = body.__mint;
        innerUnmintable = builtins.filter (i: builtins.isAttrs i && !(i.__mint ? minted)) (
          builtins.attrValues lifted.nested
        );
      in
      if isLeft r then
        throw (render at r.left)
      else if malformed != [ ] then
        throw "gen-aspects.guard: ${at}: ref-id-domain: a door registration reference's identifier is outside refId's grammar (or longer than ${toString maxIdLength} characters), so it cannot be read back: ${shortId (builtins.head malformed).id}; build it with gen-algebra's `refId`."
      else if bad != [ ] then
        throw "gen-aspects.guard: ${at}: ref-position: a door registration reference is admitted only as the whole body of a door node; found below the root: ${shortId (builtins.head bad).id}"
      else
        g
        // {
          __checked = true;
          # The D this guard was checked under; the resolver must read the same one (P3).
          __declared = declaredFor cnf;
          __nested = lifted.nested;
          inherit body;
          __mint =
            if cm ? minted && bm ? minted && innerUnmintable == [ ] then
              {
                minted = hashIdentity "guard" [ "condition" "body" ] (
                  l:
                  {
                    condition = cm.minted;
                    body = bm.minted;
                  }
                  .${l}
                );
              }
            else
              {
                unmintable = "gen-aspects.guard: ${at}: the guard has no identity: ${
                  cm.unmintable or bm.unmintable or (builtins.head innerUnmintable).__mint.unmintable
                }";
              };
        };
  checkGuard = cnf: at: checkGuardAt cnf at 0;

  # The coordinates a checked guard reads (ADR-0008 :150): its terms' heads, and a door reference's
  # declared reads, decoded from its identifier (unifying spec §2.7), `null` meaning D.
  refReads =
    cnf: context: id:
    let
      d = declaredOf cnf;
      all = if d == null then builtins.attrNames context else d;
      or' = rs: if rs == null then all else rs;
      r = decodeDoorId id;
    in
    if r == null then
      [ ]
    else if r ? declared then
      or' r.declared.reads
    else
      builtins.attrNames r.nested.sources ++ or' r.nested.reads;
  derivedReads =
    cnf: context: g:
    unique (
      T.readCtxHeads g.condition
      ++ T.readCtxHeads g.body
      ++ builtins.concatMap (n: refReads cnf context n.id) (refsIn g.body)
    );

  # Each position of `ps` in `v` replaced by what `fireAt` makes of it, in ONE pass: the positions are
  # grouped by their first segment, so a list is rebuilt once however many of its elements are patched
  # (one write per position rebuilds it once per position, quadratic in the fan-out). A position below
  # another is patched first, and the guard above it fires over the patched value.
  patchAt =
    fireAt: ps: v:
    let
      deeper = builtins.filter (p: p != [ ]) ps;
      groups = builtins.groupBy (p: builtins.toJSON (builtins.head p)) deeper;
      sub = g: x: patchAt fireAt (map builtins.tail g) x;
      patched =
        if deeper == [ ] then
          v
        else if builtins.isList v then
          builtins.genList (
            i:
            let
              x = builtins.elemAt v i;
            in
            if groups ? ${toString i} then sub groups.${toString i} x else x
          ) (builtins.length v)
        else
          v
          // builtins.listToAttrs (
            map (
              g:
              let
                s = builtins.head (builtins.head g);
              in
              {
                name = s;
                value = sub g v.${s};
              }
            ) (builtins.attrValues groups)
          );
    in
    if builtins.elem [ ] ps then fireAt patched else patched;

  # The read environment of one firing. `sources` is `null` where the caller holds none (`applyGuard`),
  # and a door node then refuses by name: the door keys its output on them.
  envOf =
    cnf:
    {
      context,
      sources,
      scope,
      nested ? { },
    }:
    {
      inherit context;
      declared = declaredFor cnf;
      ref =
        id:
        if isGuardId id then
          (
            if nested ? ${id} then
              { right = nested.${id}; }
            else
              {
                left = {
                  code = "ref-unresolved";
                  witness.message = "no guard is nested in this body under ${shortId id}";
                };
              }
          )
        else if !(isDoorId id) then
          { right = id; }
        else if cnf.ref == null then
          {
            left = {
              code = "ref-unresolved";
              witness.message = "no door is supplied (`cnf.ref` is null) to resolve ${id}";
            };
          }
        else if sources == null then
          throw "gen-aspects.guard: a door node fires with the sources of its context (the door keys its output on them); fire it through `instanceOf` or `instancesFor`, which carry them."
        else
          cnf.ref {
            inherit id context sources;
            captured = scope.${id} or null;
          };
    };

  # Fire a checked guard at a context: `null` when its condition is FALSE, else its body's value. A door
  # node's value is the door's output, whose nested door nodes fire HERE, at the same context, under the
  # scope extended by the one the door returned (design G5): the lexically nested path. A nested node
  # whose condition is FALSE stays in the output as a node, and a later firing of it is the fallback.
  fire =
    cnf: at: args: g:
    if g.__declared != declaredFor cnf then
      throw "gen-aspects.guard: ${at}: one-declared-set: this guard was checked under the declared set ${builtins.toJSON g.__declared} and is fired under ${builtins.toJSON (declaredFor cnf)}; a guard is checked and resolved under ONE set, the framework's (fire it through the vocabulary of the cnf that placed it)."
    else
      let
        env = envOf cnf (args // { nested = g.__nested or { }; });
        c = T.resolveTerm env g.condition;
        b = T.resolveTerm env g.body;
      in
      if isLeft c then
        throw (render at c.left)
      else if !c.right then
        null
      else if isLeft b then
        throw (render at b.left)
      else if isDoorBody g.body then
        let
          res = b.right;
          shape =
            msg:
            throw "gen-aspects.guard: ${at}: door-result-shape: the door (`cnf.ref`) answered ${shortId g.body.id} with ${msg}; a door answers `{ right = { output; scope; }; }`, its scope keyed by nested registration identifiers (gen-algebra `refId`) each naming the position of a guard in `output`.";
          isRec = builtins.isAttrs res && res ? output && res ? scope && builtins.isAttrs res.scope;
          ids = builtins.attrNames res.scope;
          # The position a scope key names, checked to hold a guard in `output`, or the reason it does not.
          decoded = map (id: {
            inherit id;
            r = decodeDoorId id;
          }) ids;
          located =
            { id, r }:
            let
              p = r.nested.position;
              reach = builtins.foldl' (
                acc: s:
                if acc == null then
                  null
                else if builtins.isInt s then
                  (if builtins.isList acc && s >= 0 && s < builtins.length acc then builtins.elemAt acc s else null)
                else if builtins.isAttrs acc && acc ? ${s} then
                  acc.${s}
                else
                  null
              ) res.output p;
            in
            if r == null || !(r ? nested) then
              "a scope key that is not a nested registration identifier: ${shortId id}"
            else if reach == null then
              "a scope position ${builtins.toJSON p} that `output` does not hold"
            else if !(builtins.isAttrs reach && (reach.__guard or false)) then
              "a scope position ${builtins.toJSON p} that holds a ${builtins.typeOf reach}, not a guard"
            else
              null;
          problems = builtins.filter (x: x != null) (map located decoded);
          scope = args.scope // res.scope;
          fireAt =
            x:
            let
              v = fire cnf at (args // { inherit scope; }) (checkGuard cnf at x);
            in
            if v == null then x else v;
        in
        if !isRec then
          shape "a `right` that is not { output; scope; } (got ${builtins.typeOf res}${
            if builtins.isAttrs res then " with fields " + builtins.toJSON (builtins.attrNames res) else ""
          })"
        else if problems != [ ] then
          shape (builtins.head problems)
        else
          patchAt fireAt (map (d: d.r.nested.position) decoded) res.output
      else
        b.right;

  # Whether a checked guard's condition holds at a context, absence under the open world reading as
  # FALSE (an instance relation's pre-filter, as a missing required formal is today).
  holds =
    cnf: context: g:
    let
      c = T.resolveTerm (envOf cnf {
        inherit context;
        sources = null;
        scope = { };
      }) g.condition;
    in
    if isLeft c then
      (if c.left.code == "absent-coordinate" then false else throw (render "condition" c.left))
    else
      c.right;
in
{
  inherit
    instanceFor
    declaredFor
    lift
    checkGuard
    derivedReads
    fire
    holds
    isDoorId
    maxLiftDepth
    maxIdLength
    ;
}
