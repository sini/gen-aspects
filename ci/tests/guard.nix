# Test: guard-predicate vocabulary — predicates are first-order data, one applyGuard dispatches.
# Theory: Reynolds "Elimination of Higher-Order Functions" (defunctionalize the guard space)
# as formalized by Danvy & Nielsen 2001 (O1-O7).
{
  genMerge,
  genAlgebra,
  genIdentity,
  lib,
  aspects,
  mkSchemaEval,
  ...
}:
let
  v = aspects.mkGuardVocab { };
  # A guard placed at aspect `name`, where it meets its cnf and is checked.
  placed =
    name: g: (mkSchemaEval { modules = [ { config.aspects.${name} = g; } ]; }).config.aspects.${name};
  ctxCortex = {
    thimble.name = "cortex";
    class = "nixos";
    spool.name = "sini";
    tags = {
      role = "db";
    };
  };
in
{
  flake.tests.guard.test-applyguard-fires = {
    expr = v.applyGuard ctxCortex (v.vocab.whenEq [ "thimble" "name" ] "cortex" { ok = true; });
    expected = {
      ok = true;
    };
  };
  # A guard record is open beyond `condition` and `body` (R5's stated price: an extra field on a
  # data record is never reported), so a `pred` key beside a present `condition` is admitted and
  # not read: the condition decides. Pinned as a SUCCESS, so that a later closure is visible.
  flake.tests.guard.test-an-extra-key-beside-condition-is-admitted-and-not-read = {
    expr = v.applyGuard ctxCortex {
      __guard = true;
      condition = aspects.pred.class "nixos";
      pred = aspects.pred.class "darwin";
      body.ok = true;
    };
    expected = {
      ok = true;
    };
  };
  flake.tests.guard.test-applyguard-not-fires = {
    expr = v.applyGuard ctxCortex (v.vocab.whenEq [ "thimble" "name" ] "blade" { ok = true; });
    expected = null;
  };
  flake.tests.guard.test-all-recurses = {
    expr = v.applyGuard ctxCortex (
      v.vocab.whenAll [
        (v.pred.eq [ "thimble" "name" ] "cortex")
        (v.pred.class "nixos")
      ] { ok = true; }
    );
    expected = {
      ok = true;
    };
  };
  flake.tests.guard.test-any-recurses = {
    expr = v.applyGuard ctxCortex (
      v.vocab.whenAny [
        (v.pred.eq [ "thimble" "name" ] "blade")
        (v.pred.class "nixos")
      ] { ok = true; }
    );
    expected = {
      ok = true;
    };
  };
  flake.tests.guard.test-eq-path = {
    expr = v.applyGuard ctxCortex (v.vocab.whenEq [ "tags" "role" ] "db" { ok = true; });
    expected = {
      ok = true;
    };
  };
  # I1: per-form coverage (fires + not-fires) for whenEq on a second kind / whenTagEq / whenClass / always / all / any.
  flake.tests.guard.test-wheneq-second-kind-fires = {
    expr = v.applyGuard ctxCortex (v.vocab.whenEq [ "spool" "name" ] "sini" { ok = true; });
    expected = {
      ok = true;
    };
  };
  flake.tests.guard.test-wheneq-second-kind-not-fires = {
    expr = v.applyGuard ctxCortex (v.vocab.whenEq [ "spool" "name" ] "vic" { ok = true; });
    expected = null;
  };
  flake.tests.guard.test-whentageq-fires = {
    expr = v.applyGuard ctxCortex (v.vocab.whenTagEq "role" "db" { ok = true; });
    expected = {
      ok = true;
    };
  };
  flake.tests.guard.test-whentageq-not-fires = {
    expr = v.applyGuard ctxCortex (v.vocab.whenTagEq "role" "web" { ok = true; });
    expected = null;
  };
  flake.tests.guard.test-whenclass-fires = {
    expr = v.applyGuard ctxCortex (v.vocab.whenClass "nixos" { ok = true; });
    expected = {
      ok = true;
    };
  };
  flake.tests.guard.test-whenclass-not-fires = {
    expr = v.applyGuard ctxCortex (v.vocab.whenClass "darwin" { ok = true; });
    expected = null;
  };
  flake.tests.guard.test-always-fires = {
    expr = v.applyGuard ctxCortex (v.vocab.always { ok = true; });
    expected = {
      ok = true;
    };
  };
  flake.tests.guard.test-all-not-fires = {
    expr = v.applyGuard ctxCortex (
      v.vocab.whenAll [
        (v.pred.eq [ "thimble" "name" ] "cortex")
        (v.pred.class "darwin")
      ] { ok = true; }
    );
    expected = null;
  };
  flake.tests.guard.test-any-not-fires = {
    expr = v.applyGuard ctxCortex (
      v.vocab.whenAny [
        (v.pred.eq [ "thimble" "name" ] "blade")
        (v.pred.class "darwin")
      ] { ok = true; }
    );
    expected = null;
  };

  # ADR-0035: the published predicate surface names no domain entity. A context path is the
  # caller's (`eq`), and a framework's named entity predicate is the framework's own declaration.
  # These two cells pin the surface EXACTLY, so re-adding an entity-named constructor or its
  # `when…` sugar reds them. `custom` is the retired form's refused-by-name alias (den-hoag-lwbb1).
  flake.tests.guard.test-pred-surface-names-no-entity = {
    expr = builtins.attrNames aspects.pred;
    expected = [
      "all"
      "always"
      "any"
      "class"
      "custom"
      "eq"
      "has"
      "not"
      "tagEq"
    ];
  };
  flake.tests.guard.test-vocab-surface-names-no-entity = {
    expr = builtins.attrNames v.vocab;
    expected = [
      "always"
      "whenAll"
      "whenAny"
      "whenClass"
      "whenEq"
      "whenTagEq"
    ];
  };

  # A guard's identity is the mint over (condition, body), defined once the guard is checked against
  # its cnf: here, placed at an aspect position (den-hoag-lwbb1, lib/guard-term.nix `checkGuard`).
  # site-independence: same condition + first-order body at two "sites" -> equal key
  flake.tests.guard.test-guardkey-site-independent =
    let
      g1 = aspects.guard (aspects.pred.eq [ "thimble" "name" ] "cortex") { a = 1; };
      g2 = aspects.guard (aspects.pred.eq [ "thimble" "name" ] "cortex") { a = 1; };
    in
    {
      expr = aspects.guardKey (placed "aaa" g1) == aspects.guardKey (placed "bbb" g2);
      expected = true;
    };

  # the mint discriminates differing first-order bodies
  flake.tests.guard.test-guardkey-body-discriminates =
    let
      g1 = aspects.guard (aspects.pred.eq [ "thimble" "name" ] "cortex") { a = 1; };
      g2 = aspects.guard (aspects.pred.eq [ "thimble" "name" ] "cortex") { a = 2; };
    in
    {
      expr = aspects.guardKey (placed "g" g1) == aspects.guardKey (placed "g" g2);
      expected = false;
    };

  # a guard nested as the body stays a guard, and its identity enters the outer's ("guard:…")
  flake.tests.guard.test-guardkey-nested-body-structural =
    let
      mk =
        a:
        aspects.guard (aspects.pred.eq [ "thimble" "name" ] "cortex") (
          aspects.guard (aspects.pred.class "nixos") { inherit a; }
        );
    in
    {
      expr = {
        siteIndep = aspects.guardKey (placed "aaa" (mk 1)) == aspects.guardKey (placed "bbb" (mk 1));
        discriminates = aspects.guardKey (placed "g" (mk 1)) == aspects.guardKey (placed "g" (mk 2));
        structural = lib.hasPrefix "guard:" (aspects.guardKey (placed "g" (mk 1)));
      };
      expected = {
        siteIndep = true;
        discriminates = false;
        structural = true;
      };
    };

  # a module function as the whole body is a declared module slot: keyed by its position, never its
  # payload, so the key is a mint, site-independent (no source-position fallback).
  flake.tests.guard.test-guardkey-nested-no-throw =
    let
      g =
        body:
        aspects.guard (aspects.pred.all [
          (aspects.pred.eq [ "thimble" "name" ] "cortex")
          (aspects.pred.class "nixos")
        ]) body;
    in
    {
      expr = {
        minted = lib.hasPrefix "guard:" (aspects.guardKey (placed "g" (g ({ config, ... }: { }))));
        payloadOutside =
          aspects.guardKey (placed "aaa" (g ({ config, ... }: { })))
          == aspects.guardKey (placed "bbb" (g ({ pkgs, ... }: { a = 1; })));
      };
      expected = {
        minted = true;
        payloadOutside = true;
      };
    };

  # a first-order body CONTAINING a nested guard whose body is a module function mints: the inner
  # guard is its own clause, its module function a slot.
  flake.tests.guard.test-guardkey-nested-guard-fn-body =
    let
      g = aspects.guard (aspects.pred.eq [ "thimble" "name" ] "cortex") {
        sub = aspects.guard (aspects.pred.class "nixos") ({ config, ... }: { });
      };
    in
    {
      expr = lib.hasPrefix "guard:" (aspects.guardKey (placed "g" g));
      expected = true;
    };

  # end-to-end: a guard record survives merge as inert data
  flake.tests.guard.test-guard-record-passes-through =
    let
      gv = aspects.mkGuardVocab { };
      eval = mkSchemaEval {
        modules = [
          { config.aspects.db = gv.vocab.whenEq [ "thimble" "name" ] "cortex" { classOne.setting = "x"; }; }
        ];
      };
    in
    {
      expr = eval.config.aspects.db.__guard or false;
      expected = true;
    };

  # end-to-end site-independence: same guard (first-order body) at two sites -> equal TERM key
  # (`guardKey`), and two declarations, each keyed by its declared path (identity design §1)
  flake.tests.guard.test-guard-record-key-site-independent =
    let
      gv = aspects.mkGuardVocab { };
      mk =
        name:
        (mkSchemaEval {
          modules = [
            {
              config.aspects.${name} = gv.vocab.whenEq [ "thimble" "name" ] "cortex" { classOne.setting = "x"; };
            }
          ];
        }).config.aspects.${name};
    in
    {
      expr = {
        termSiteIndependent = aspects.guardKey (mk "aaa") == aspects.guardKey (mk "bbb");
        declarations = [
          (aspects.key (mk "aaa"))
          (aspects.key (mk "bbb"))
        ];
      };
      expected = {
        termSiteIndependent = true;
        declarations = [
          "aaa"
          "bbb"
        ];
      };
    };

  # end-to-end: a guard whose body is a module function is a declared module slot, its TERM keyed by
  # the mint over (condition, slot position) with no source-position fallback (den-hoag-lwbb1): the
  # same guard at two sites is ONE term key, and a differing condition is another. Its declaration
  # key is its declared path.
  flake.tests.guard.test-guard-slot-body-keyed-by-mint =
    let
      gv = aspects.mkGuardVocab { };
      mk =
        name: v:
        (mkSchemaEval {
          modules = [
            { config.aspects.${name} = gv.vocab.whenEq [ "thimble" "name" ] v ({ config, ... }: { }); }
          ];
        }).config.aspects.${name};
    in
    {
      expr = {
        siteIndependent = aspects.guardKey (mk "aaa" "cortex") == aspects.guardKey (mk "bbb" "cortex");
        conditionDiscriminates =
          aspects.guardKey (mk "aaa" "cortex") == aspects.guardKey (mk "aaa" "blade");
        declarations = [
          (aspects.key (mk "aaa" "cortex"))
          (aspects.key (mk "bbb" "cortex"))
        ];
      };
      expected = {
        siteIndependent = true;
        conditionDiscriminates = false;
        declarations = [
          "aaa"
          "bbb"
        ];
      };
    };

  # O8 (den-hoag-sezf): the above "multi-def limitation" fixture RETIRES here — it asserted the
  # shape LOSS as correct behaviour, and that loss is exactly what Arm B's fragment carrier fixes.
  # Replaced by the carrier cells below (test-guard-multidef-carrier-*), not deleted silently: the
  # limitation retires by becoming expressible, per spec §3 O8. `dup` still resolves, still holds
  # `__guard == true` (never lost), and now carries BOTH fragments rather than one shredded blend.

  # den-hoag-sezf Arm B (O4/O12): a guard record defined twice under one key merges to a fragment
  # carrier rather than folding through `(aspectSubmodule cnf).merge` — witness 2's fix. RED
  # (measured this session by execution, gen-aspects f0d9d14c, pre-fix): `aspects.flatten
  # eval.config.aspects` aborted `expected a Boolean but found a set` at `lib/walk.nix:25`, and
  # `builtins.tryEval` wrapped around `builtins.deepSeq` did NOT catch it — the whole eval died,
  # unpiped exit 1. That RED is out-of-suite only (an uncatchable abort kills the runner before it
  # can report a ❌) — captured as a probe transcript in the build report, not as an in-suite cell.
  # GREEN, in-suite, three parts:
  flake.tests.guard.test-guard-multidef-carrier-flattens-as-single-leaf =
    let
      gv = aspects.mkGuardVocab { };
      eval = mkSchemaEval {
        modules = [
          { config.aspects.dup = gv.vocab.whenEq [ "thimble" "name" ] "cortex" { classOne.setting = "x"; }; }
          { config.aspects.dup = gv.vocab.whenEq [ "thimble" "name" ] "blade" { classOne.setting = "y"; }; }
        ];
      };
      flat = aspects.flatten eval.config.aspects;
    in
    {
      # (i) flatten succeeds, one leaf — not a shredded subtree.
      expr = builtins.attrNames flat;
      expected = [ "dup" ];
    };

  flake.tests.guard.test-guard-multidef-carrier-both-fragments-recoverable =
    let
      gv = aspects.mkGuardVocab { };
      eval = mkSchemaEval {
        modules = [
          { config.aspects.dup = gv.vocab.whenEq [ "thimble" "name" ] "cortex" { classOne.setting = "x"; }; }
          { config.aspects.dup = gv.vocab.whenEq [ "thimble" "name" ] "blade" { classOne.setting = "y"; }; }
        ];
      };
      carrier = eval.config.aspects.dup;
    in
    {
      # (ii) both fragments recoverable, predicates distinguishable, neither body merged into
      # the other. Order is gen-merge's declared reverse-flattened-module-order invariant
      # (measured live this session, same as O1a's list/string-concat cells) — NOT authored
      # order; an oracle asserting authored order would be wrong per spec §3.
      expr = {
        isGuard = carrier.__guard or false;
        fragmentCount = builtins.length carrier.fragments;
        preds = map (f: f.condition.value) carrier.fragments;
        bodies = map (f: f.body.attrs.classOne.setting) carrier.fragments;
      };
      expected = {
        isGuard = true;
        fragmentCount = 2;
        preds = [
          "blade"
          "cortex"
        ];
        bodies = [
          "y"
          "x"
        ];
      };
    };

  flake.tests.guard.test-guard-multidef-carrier-discharges-firing-fragment =
    let
      gv = aspects.mkGuardVocab { };
      eval = mkSchemaEval {
        modules = [
          { config.aspects.dup = gv.vocab.whenEq [ "thimble" "name" ] "cortex" { classOne.setting = "x"; }; }
          { config.aspects.dup = gv.vocab.whenEq [ "thimble" "name" ] "blade" { classOne.setting = "y"; }; }
        ];
      };
      carrier = eval.config.aspects.dup;
    in
    {
      # (iii) discharge at a context where exactly one guard fires yields that fragment's body
      # alone.
      expr = gv.applyGuard { thimble.name = "cortex"; } carrier;
      expected = {
        classOne.setting = "x";
      };
    };

  flake.tests.guard.test-guard-multidef-carrier-discharges-to-null-when-none-fire =
    let
      gv = aspects.mkGuardVocab { };
      eval = mkSchemaEval {
        modules = [
          { config.aspects.dup = gv.vocab.whenEq [ "thimble" "name" ] "cortex" { classOne.setting = "x"; }; }
          { config.aspects.dup = gv.vocab.whenEq [ "thimble" "name" ] "blade" { classOne.setting = "y"; }; }
        ];
      };
      carrier = eval.config.aspects.dup;
    in
    {
      # (iii, continued) where neither fires, null.
      expr = gv.applyGuard { thimble.name = "vault"; } carrier;
      expected = null;
    };

  # O12: two guards at one key, BOTH firing at the same context, with directly conflicting INT
  # bodies — proves discharge routes survivors through Arm A's own refusal law (a catchable named
  # `throw`), not a pick-one shortcut. The bodies must be the bare ints themselves, not ints
  # NESTED inside an attrset key (`classOne.count = 1` vs `= 2`): measured live this session, an
  # attrset-nested collision never reaches Arm A's scalar arm at all — `mergeDefaultOption` sees
  # two ATTRSETS at the top level and takes the ADR-0031 shallow-`//`-fold arm instead (silent
  # last-wins, no refusal; already scoped away, den-hoag-z5rvp), which would have made this cell
  # pass for the wrong reason. The key must be an int specifically: differing strings/bools
  # concatenate or `or` rather than refusing (O1a/O1b), and would red against a correct build.
  flake.tests.guard.test-guard-multidef-discharge-routes-int-collision-through-arm-a-refusal =
    let
      gv = aspects.mkGuardVocab { };
      eval = mkSchemaEval {
        modules = [
          { config.aspects.dup = gv.vocab.whenEq [ "thimble" "name" ] "cortex" 1; }
          { config.aspects.dup = gv.vocab.whenEq [ "thimble" "name" ] "cortex" 2; }
        ];
      };
      carrier = eval.config.aspects.dup;
    in
    {
      expr =
        !(builtins.tryEval (builtins.deepSeq (gv.applyGuard { thimble.name = "cortex"; } carrier) true))
        .success;
      expected = true;
    };

  # O5: guard control, byte-identical — single-def dispatch is untouched by either arm.
  flake.tests.guard.test-guard-singledef-control-byte-identical =
    let
      gv = aspects.mkGuardVocab { };
      eval = mkSchemaEval {
        modules = [
          { config.aspects.solo = gv.vocab.whenEq [ "thimble" "name" ] "cortex" { classOne.setting = "x"; }; }
        ];
      };
    in
    {
      expr = {
        isGuard = eval.config.aspects.solo.__guard or false;
        pred = eval.config.aspects.solo.condition.value;
        body = eval.config.aspects.solo.body.attrs;
        flatKeys = builtins.attrNames (aspects.flatten eval.config.aspects);
      };
      expected = {
        isGuard = true;
        pred = "cortex";
        body = {
          classOne.setting = "x";
        };
        flatKeys = [ "solo" ];
      };
    };

  # O6: no shredding, non-enumeratively. `A` is derived LIVE from a third, plain-attrset fixture
  # that legitimately routes to `aspectSubmodule.merge` (two attrset defs at one key, the same
  # shape `multi-def.nix`'s `test-attrset-multi-def-preserves-both-keys` exercises) — never an
  # enumerated literal name list (a prior enumerated form omitted a name and would have passed an
  # implementation that left it behind).
  flake.tests.guard.test-guard-multidef-carrier-no-shredding =
    let
      gv = aspects.mkGuardVocab { };
      carrierEval = mkSchemaEval {
        modules = [
          { config.aspects.dup = gv.vocab.whenEq [ "thimble" "name" ] "cortex" { classOne.setting = "x"; }; }
          { config.aspects.dup = gv.vocab.whenEq [ "thimble" "name" ] "blade" { classOne.setting = "y"; }; }
        ];
      };
      carrier = carrierEval.config.aspects.dup;
      singleDefEval = mkSchemaEval {
        modules = [
          { config.aspects.solo = gv.vocab.whenEq [ "thimble" "name" ] "cortex" { classOne.setting = "x"; }; }
        ];
      };
      singleDefNames = builtins.attrNames singleDefEval.config.aspects.solo;
      thirdEval = mkSchemaEval {
        modules = [
          { config.aspects.plain.x = "from-a"; }
          { config.aspects.plain.y = "from-b"; }
        ];
      };
      a = builtins.attrNames thirdEval.config.aspects.plain;
      carrierNames = builtins.attrNames carrier;
      shredded = builtins.filter (n: builtins.elem n a && !(builtins.elem n singleDefNames)) carrierNames;
    in
    {
      expr = shredded;
      expected = [ ];
    };

  # O9: the silent heterogeneous case — a guard record plus a plain attrset def at one key.
  # Nothing in O1-O8/O12 sees this shape. RED (measured this session by execution, pre-fix):
  # `flatten` SUCCEEDS today, byte-identical at the registry surface (`["mixed"]`, one leaf) to
  # the correct single-def case — the fully silent form. The difference is invisible at `flatten`;
  # it surfaces only on the node itself, which picked up `aspectSubmodule`'s own structural option
  # names (`description`, `id_hash`, `includes`, `key`) alongside the plain attrset's content —
  # never assert on `flatten` merely succeeding. GREEN: the plain attrset becomes an unconditional
  # fragment (condition ≡ true) riding beside the guarded one; O6's no-shredding predicate holds;
  # discharge where the guard does not fire yields the unconditional body alone.
  flake.tests.guard.test-guard-heterogeneous-multidef-flattens-as-single-leaf =
    let
      gv = aspects.mkGuardVocab { };
      eval = mkSchemaEval {
        modules = [
          {
            config.aspects.mixed = gv.vocab.whenEq [ "thimble" "name" ] "cortex" { classOne.setting = "x"; };
          }
          { config.aspects.mixed.classTwo.other = "y"; }
        ];
      };
    in
    {
      expr = builtins.attrNames (aspects.flatten eval.config.aspects);
      expected = [ "mixed" ];
    };

  flake.tests.guard.test-guard-heterogeneous-multidef-no-shredding =
    let
      gv = aspects.mkGuardVocab { };
      eval = mkSchemaEval {
        modules = [
          {
            config.aspects.mixed = gv.vocab.whenEq [ "thimble" "name" ] "cortex" { classOne.setting = "x"; };
          }
          { config.aspects.mixed.classTwo.other = "y"; }
        ];
      };
      singleDefEval = mkSchemaEval {
        modules = [
          { config.aspects.solo = gv.vocab.whenEq [ "thimble" "name" ] "cortex" { classOne.setting = "x"; }; }
        ];
      };
    in
    {
      expr = {
        # the aspectSubmodule structural names a shredded merge would have added, absent here
        noSubmoduleContamination =
          !(builtins.any (
            n:
            builtins.elem n [
              "description"
              "id_hash"
              "includes"
              "key"
            ]
          ) (builtins.attrNames eval.config.aspects.mixed));
        # the plain attrset's own content survived as a fragment, not shredded away
        hasClassTwoFragment = builtins.any (
          f: f.kind == "unconditional" && (f.body.classTwo.other or null) == "y"
        ) eval.config.aspects.mixed.fragments;
      };
      expected = {
        noSubmoduleContamination = true;
        hasClassTwoFragment = true;
      };
    };

  flake.tests.guard.test-guard-heterogeneous-multidef-discharge-when-guard-does-not-fire =
    let
      gv = aspects.mkGuardVocab { };
      eval = mkSchemaEval {
        modules = [
          {
            config.aspects.mixed = gv.vocab.whenEq [ "thimble" "name" ] "cortex" { classOne.setting = "x"; };
          }
          { config.aspects.mixed.classTwo.other = "y"; }
        ];
      };
      carrier = eval.config.aspects.mixed;
    in
    {
      # guard does not fire ("vault" != "cortex") -> the unconditional fragment's body alone.
      expr = gv.applyGuard { thimble.name = "vault"; } carrier;
      expected = {
        classTwo.other = "y";
      };
    };

  flake.tests.guard.test-guard-multidef-module-functions-still-coerce-to-includes =
    let
      eval = mkSchemaEval {
        modules = [
          {
            config.aspects.modfn =
              { aspect, ... }:
              {
                classOne.a = "1";
              };
          }
          {
            config.aspects.modfn =
              { aspect, ... }:
              {
                classOne.b = "2";
              };
          }
        ];
      };
    in
    {
      expr = builtins.length eval.config.aspects.modfn.includes;
      expected = 2;
    };

  # a defunctionalized guard record flattens as a LEAF, never recursed
  flake.tests.guard.test-guard-record-flattens-as-leaf =
    let
      gv = aspects.mkGuardVocab { };
      eval = mkSchemaEval {
        modules = [
          { config.aspects.db = gv.vocab.whenEq [ "thimble" "name" ] "cortex" { classOne.setting = "x"; }; }
        ];
      };
      flat = aspects.flatten eval.config.aspects;
    in
    {
      expr = {
        hasDb = flat ? "db";
        dbIsGuard = flat.db.__guard or false;
        noChildren = !(builtins.any (lib.hasPrefix "db/") (builtins.attrNames flat));
      };
      expected = {
        hasDb = true;
        dbIsGuard = true;
        noChildren = true;
      };
    };

  # THE REGISTRY IS A PROJECTION OF THE PUBLISHED FACTS, identical modulo the origin qualifier —
  # asserted over a GUARD-RECORD fixture, the node shape the projection is least able to describe
  # from a key alone. A guard leaf carries no `meta.aspect-chain`, so the published parent for it is
  # a dispatch result rather than a chain read, and it is asserted here alongside the projection.
  flake.tests.guard.test-registry-projects-from-published-facts =
    let
      gv = aspects.mkGuardVocab { };
      eval = mkSchemaEval {
        modules = [
          {
            config.aspects.top.db = gv.vocab.whenEq [ "thimble" "name" ] "cortex" { classOne.setting = "x"; };
            config.aspects.top.plain.classOne.setting = "y";
          }
        ];
      };
      flat = aspects.flatten eval.config.aspects;
      facts = aspects.graphFacts { providerPrefix = [ "acme" ]; } eval.config.aspects;
      sorted = lib.sort (a: b: a < b);
    in
    {
      expr = {
        strippedKeysMatch =
          sorted (map (lib.removePrefix "acme/") facts.nodes) == sorted (builtins.attrNames flat);
        differBeforeStripping = sorted facts.nodes != sorted (builtins.attrNames flat);
        # The guard leaf IS a node, and its parent is the container it sits in — not the root the
        # bare `meta.aspect-chain or [ ]` reader would report for it.
        guardLeafIsANode = builtins.elem "acme/top/db" facts.nodes;
        guardLeafParent = facts.parentOf."acme/top/db";
        # CONTROL: the plain sibling in the same fixture answers the same way, so the assertion is
        # not simply reporting whatever the walk position happened to be.
        plainSiblingParent = facts.parentOf."acme/top/plain";
      };
      expected = {
        strippedKeysMatch = true;
        differBeforeStripping = true;
        guardLeafIsANode = true;
        guardLeafParent = "acme/top";
        plainSiblingParent = "acme/top";
      };
    };

  # FIRING A GUARD GROWS THE TREE BY EXACTLY ONE LEVEL. A guard nested in a fired body stays a guard
  # (it fires at its own firing), so depth is exactly the caller's firing count. The self-reference is
  # the reference former (design Section 3's migration of `selfw`): firing hands back the reference,
  # never its expansion. A FINITE two-level chain is the fixture that sees k = 2; `leafw` bottoms out
  # and is the control that the predicate can say no.
  flake.tests.guard.test-application-is-one-level-per-application =
    let
      t = (genAlgebra.term genIdentity.hashIdentity).term;
      ctx = {
        host = "h1";
      };
      g = aspects.guard (aspects.pred.has "host");
      leafw = g { includes = [ { description = "leaf"; } ]; };
      chainw = g { includes = [ leafw ]; };
      selfw = g { includes = [ (t.ref "selfw") ]; };
      fire = name: x: v.applyGuard ctx (placed name x);
      nextOf = r: builtins.head (r.includes or [ ]);
      isGuard = x: builtins.isAttrs x && (x.__guard or false);
    in
    {
      expr = {
        appliedOnce = !(isGuard (fire "chainw" chainw));
        chainNextIsGuard = isGuard (nextOf (fire "chainw" chainw));
        controlNextIsGuard = isGuard (nextOf (fire "leafw" leafw));
        nextFiresAtItsOwnFiring = (nextOf (v.applyGuard ctx (nextOf (fire "chainw" chainw)))).description;
        selfIsTheReference = nextOf (fire "selfw" selfw);
      };
      expected = {
        appliedOnce = true;
        chainNextIsGuard = true;
        controlNextIsGuard = false;
        nextFiresAtItsOwnFiring = "leaf";
        selfIsTheReference = "selfw";
      };
    };

  # den-hoag-ywlww (ADR-0025 item 1): the carrier's discharge merges the surviving fragments by the
  # module system's law for untyped content (`types.anything`), as nixpkgs does: lists concatenate,
  # attrsets merge per key, a conflicting scalar is refused by name. RED (measured at gen-aspects
  # 9827a96): `mergeDefaultOption` folded with `//`, so two firing definitions with different
  # `description` read one value at rc 0 and `includes = [ "p" ]` / `[ "q" ]` read `[ "p" ]`.
  flake.tests.guard.test-guard-multidef-carrier-discharge-merges-by-module-law =
    let
      gv = aspects.mkGuardVocab { };
      fire =
        a: b:
        gv.applyGuard { thimble.name = "cortex"; }
          (mkSchemaEval {
            modules = [
              { config.aspects.dup = a; }
              { config.aspects.dup = b; }
            ];
          }).config.aspects.dup;
      always = gv.vocab.always;
      ok = v: (builtins.tryEval (builtins.deepSeq v true)).success;
    in
    {
      expr = {
        conflictRefuses = ok (
          fire (always { description = "a"; }) (always {
            description = "b";
          })
        );
        conflictWithUnconditionalRefuses = ok (
          fire { description = "u"; } (always {
            description = "g";
          })
        );
        includes = lib.sort (x: y: x < y) (
          (fire (always { includes = [ "p" ]; }) (always {
            includes = [ "q" ];
          })).includes
        );
        disjointKeysBothLand = builtins.attrNames (
          fire (always { description = "a"; }) (always {
            classOne.x = [ "k" ];
          })
        );
        # controls: equal scalars agree; a definition whose guard does not fire does not conflict.
        equalScalars =
          (fire (always { description = "s"; }) (always {
            description = "s";
          })).description;
        nonFiringDoesNotConflict =
          (fire (always { description = "a"; }) (
            gv.vocab.whenEq [ "thimble" "name" ] "blade" { description = "b"; }
          )).description;
      };
      expected = {
        conflictRefuses = false;
        conflictWithUnconditionalRefuses = false;
        includes = [
          "p"
          "q"
        ];
        disjointKeysBothLand = [
          "classOne"
          "description"
        ];
        equalScalars = "s";
        nonFiringDoesNotConflict = "a";
      };
    };

  # den-hoag-cgobz: a module function written beside a guard record at one key is applied once, in
  # this evaluation, as `coerced` applies it beside a plain second definition (the T4 shape): its
  # fragment is UNCONDITIONAL, marked `coerced`, and holds the applied `includes` element in place of
  # the function. RED (measured at gen-aspects 6c9ea4e): the fragment held the raw function, so no
  # fragment was `coerced` (GA1 read `[ ]`) and firing the carrier handed the function onward.
  flake.tests.guard.test-guard-multidef-module-function-is-one-applied-element =
    let
      gv = aspects.mkGuardVocab { };
      # gen-aspects' `isTypedAspect` is not exported; the predicate is stated here.
      isApplied = v: builtins.isAttrs v && v ? id_hash && v ? key && !(v.__guard or false);
      carrier =
        (mkSchemaEval {
          modules = [
            { config.aspects.main = gv.vocab.always { description = "G"; }; }
            {
              config.aspects.main =
                { config, ... }:
                {
                  description = "Y";
                  includes = [ { description = "T"; } ];
                };
            }
          ];
        }).config.aspects.main;
    in
    {
      expr = map (f: builtins.length f.body.includes == 1 && builtins.all isApplied f.body.includes) (
        builtins.filter (f: f.coerced or false) carrier.fragments
      );
      expected = [ true ];
    };

  # GA2 and GA3 (den-hoag-cgobz): the carrier's applied element equals the element the T4 shape (the
  # same function beside a plain definition, no carrier) produces, read as its description and its own
  # includes' descriptions. A framework aspect module writing `includes` at `main` reaches no carrier
  # (F4(a): a carrier is not an aspect submodule) and applies INSIDE each element, as in T4; so the
  # elements stay the functions' own, in definition order, under `mkIf`, `mkBefore` and `mkAfter`.
  # RED for the `mkIf` and `mkBefore` rows: a carrier position evaluated as a whole aspect submodule,
  # whose `includes` the aspect module also writes, indexes COMMON as the function's element.
  flake.tests.guard.test-guard-multidef-module-function-element-equals-t4 =
    let
      gv = aspects.mkGuardVocab { };
      y = d: {
        config.aspects.main =
          { config, ... }:
          {
            description = d;
            includes = [ { description = "T-${d}"; } ];
          };
      };
      x.config.aspects.main = gv.vocab.always { description = "G"; };
      p.config.aspects.main.description = "P";
      common = wrap: { name, ... }: {
        includes = genMerge.mkIf (name == "main") (wrap [ { description = "COMMON"; } ]);
      };
      eval =
        extra: modules:
        (mkSchemaEval {
          inherit modules;
          aspectModules = extra;
        }).config.aspects.main;
      view = e: [ e.description ] ++ map (i: i.description) e.includes;
      carrierEls =
        a:
        map view (builtins.concatMap (f: if f.coerced or false then f.body.includes else [ ]) a.fragments);
      t4Els =
        a:
        map view (
          builtins.filter (
            e:
            builtins.elem e.description [
              "Y"
              "Y2"
            ]
          ) a.includes
        );
      row = extra: {
        carrier = carrierEls (
          eval extra [
            x
            (y "Y")
          ]
        );
        t4 = t4Els (
          eval extra [
            p
            (y "Y")
          ]
        );
      };
      fired = gv.applyGuard { } (eval [ ] [ x (y "Y") ]);
    in
    {
      expr = {
        # GA2: firing the carrier hands the applied element onward, beside the record's body
        firedDescription = fired.description;
        fired = map view fired.includes;
        firedT4 = t4Els (eval [ ] [ p (y "Y") ]);
        # GA3
        mkIf = row [ (common (l: l)) ];
        mkBefore = row [ (common genMerge.mkBefore) ];
        mkAfter = row [ (common genMerge.mkAfter) ];
        twoFunctions = {
          carrier = carrierEls (eval [ (common (l: l)) ] [ x (y "Y") (y "Y2") ]);
          t4 = t4Els (eval [ (common (l: l)) ] [ p (y "Y") (y "Y2") ]);
        };
      };
      expected =
        let
          one = [
            [
              "Y"
              "T-Y"
            ]
          ];
          both = {
            carrier = one;
            t4 = one;
          };
        in
        {
          firedDescription = "G";
          fired = one;
          firedT4 = one;
          mkIf = both;
          mkBefore = both;
          mkAfter = both;
          twoFunctions = {
            carrier = one ++ [
              [
                "Y2"
                "T-Y2"
              ]
            ];
            t4 = one ++ [
              [
                "Y2"
                "T-Y2"
              ]
            ];
          };
        };
    };

  # den-hoag-3849t (route (a)): of a plain definition beside a guard record, only its `includes` lists
  # are typed, at every aspect position, and a module function at a nested key is coerced into one, as
  # F4(b) coerces it beside a second definition. GA4: a plain fragment mints over its definition as
  # written, so a function-free carrier keeps its structural key; the typed fragment of plain
  # definitions alone is skipped by identity. GA5: the typed fragment's nested position is not an
  # aspect (no typed default reaches the content law), and its `includes` holds the applied element.
  # RED for GA5 (gen-aspects 36b3879): no fragment was typed, `[ ]`.
  flake.tests.guard.test-guard-multidef-plain-positions-typed =
    let
      gv = aspects.mkGuardVocab { };
      isApplied = v: builtins.isAttrs v && v ? id_hash && v ? key && !(v.__guard or false);
      x.config.aspects.main = gv.vocab.always { description = "G"; };
      eval = modules: (mkSchemaEval { inherit modules; }).config.aspects.main;
      carrierQ = eval [
        x
        { config.aspects.main.includes = [ { description = "Q"; } ]; }
      ];
      carrierSub = eval [
        x
        {
          config.aspects.main.sub =
            { config, ... }:
            {
              includes = [ { description = "T"; } ];
            };
        }
      ];
    in
    {
      expr = {
        # GA4
        qIncKey = lib.hasPrefix "guard:carrier:" (aspects.guardKey carrierQ);
        qIncFired = map (i: i.description) (gv.applyGuard { } carrierQ).includes;
        # GA5
        nestedFn = map (f: {
          subIsAspect = (f.body.sub or { }) ? id_hash;
          elems = map isApplied (f.body.sub.includes or [ ]);
        }) (builtins.filter (f: f.coerced or false) carrierSub.fragments);
      };
      expected = {
        qIncKey = true;
        qIncFired = [ "Q" ];
        nestedFn = [
          {
            subIsAspect = false;
            elems = [ true ];
          }
        ];
      };
    };

  # GA6 (den-hoag-dmdou): a carrier carried by value to another aspect position passes through,
  # re-stamped with the position it is placed at, so its key is that position's. RED (gen-aspects
  # 36b3879): the carrier reached the guard-record arm, which read `condition`, and aborted uncatchably.
  flake.tests.guard.test-guard-carrier-carried-by-value-is-restamped =
    let
      gv = aspects.mkGuardVocab { };
      r =
        (mkSchemaEval {
          modules = [
            { config.aspects.other = gv.vocab.always { description = "G"; }; }
            {
              config.aspects.other =
                { config, ... }:
                {
                  includes = [ { description = "Y"; } ];
                };
            }
            ({ config, ... }: { config.aspects.main = config.aspects.other; })
          ];
        }).config.aspects;
    in
    {
      expr = {
        key = aspects.guardKey r.main;
        name = r.main.name;
        fired = (gv.applyGuard { } r.main).description;
      };
      expected = {
        key = "guard-loc:main";
        name = "main";
        fired = "G";
      };
    };
}
