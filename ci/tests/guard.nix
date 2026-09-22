# Test: guard-predicate vocabulary — predicates are first-order data, one applyGuard dispatches.
# Theory: Reynolds "Elimination of Higher-Order Functions" (defunctionalize the guard space)
# as formalized by Danvy & Nielsen 2001 (O1-O7).
{
  genMerge,
  lib,
  aspects,
  mkSchemaEval,
  ...
}:
let
  v = aspects.mkGuardVocab { };
  ctxCortex = {
    host.name = "cortex";
    class = "nixos";
    user.name = "sini";
    tags = {
      role = "db";
    };
  };
in
{
  flake.tests.guard.test-toargdata-type-tags = {
    expr = aspects.toArgData {
      host = "cortex";
      n = 5;
    };
    expected = {
      host = {
        __t = "string";
        v = "cortex";
      };
      n = {
        __t = "int";
        v = 5;
      };
    };
  };
  # toArgData is LAZY (mapAttrs) — deepSeq to force the throw so tryEval can catch it.
  flake.tests.guard.test-toargdata-throws-on-function = {
    expr = (builtins.tryEval (builtins.deepSeq (aspects.toArgData { f = x: x; }) true)).success;
    expected = false;
  };
  flake.tests.guard.test-applyguard-fires = {
    expr = v.applyGuard ctxCortex (v.vocab.whenHost "cortex" { ok = true; });
    expected = {
      ok = true;
    };
  };
  flake.tests.guard.test-applyguard-not-fires = {
    expr = v.applyGuard ctxCortex (v.vocab.whenHost "blade" { ok = true; });
    expected = null;
  };
  flake.tests.guard.test-all-recurses = {
    expr = v.applyGuard ctxCortex (
      v.vocab.whenAll [ (v.pred.host "cortex") (v.pred.class "nixos") ] { ok = true; }
    );
    expected = {
      ok = true;
    };
  };
  flake.tests.guard.test-any-recurses = {
    expr = v.applyGuard ctxCortex (
      v.vocab.whenAny [ (v.pred.host "blade") (v.pred.class "nixos") ] { ok = true; }
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
  flake.tests.guard.test-escape-hatch = {
    expr = v.applyGuard ctxCortex (
      { host, ... }:
      {
        hn = host.name;
      }
    );
    expected = {
      hn = "cortex";
    };
  };

  # I1: per-form coverage (fires + not-fires) for whenUser / whenTagEq / whenClass / always / all / any.
  flake.tests.guard.test-whenuser-fires = {
    expr = v.applyGuard ctxCortex (v.vocab.whenUser "sini" { ok = true; });
    expected = {
      ok = true;
    };
  };
  flake.tests.guard.test-whenuser-not-fires = {
    expr = v.applyGuard ctxCortex (v.vocab.whenUser "vic" { ok = true; });
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
      v.vocab.whenAll [ (v.pred.host "cortex") (v.pred.class "darwin") ] { ok = true; }
    );
    expected = null;
  };
  flake.tests.guard.test-any-not-fires = {
    expr = v.applyGuard ctxCortex (
      v.vocab.whenAny [ (v.pred.host "blade") (v.pred.class "darwin") ] { ok = true; }
    );
    expected = null;
  };

  # M4: type tags keep "5" (string) and 5 (int) distinct — spec 5f.
  flake.tests.guard.test-toargdata-all-types = {
    expr = aspects.toArgData {
      s = "5";
      i = 5;
      b = true;
      l = [ "a" ];
    };
    expected = {
      s = {
        __t = "string";
        v = "5";
      };
      i = {
        __t = "int";
        v = 5;
      };
      b = {
        __t = "bool";
        v = true;
      };
      l = {
        __t = "list";
        v = [
          {
            __t = "string";
            v = "a";
          }
        ];
      };
    };
  };
  flake.tests.guard.test-toargdata-no-collision = {
    expr = (aspects.toArgData { x = "5"; }).x == (aspects.toArgData { x = 5; }).x;
    expected = false;
  };

  # I2: custom cnf.guardForms seam — dispatches by form name; may not shadow a core form.
  flake.tests.guard.test-custom-form =
    let
      gv = aspects.mkGuardVocab {
        guardForms = {
          region = {
            eval = ctx: a: (ctx.region or null) == a.region.v;
            reads = [ [ "region" ] ];
          };
        };
      };
      g = gv.guard (aspects.pred.custom "region" { region = "us"; }) { ok = true; };
    in
    {
      expr = gv.applyGuard { region = "us"; } g;
      expected = {
        ok = true;
      };
    };

  flake.tests.guard.test-custom-form-collision =
    let
      gv = aspects.mkGuardVocab {
        guardForms = {
          host = {
            eval = _: _: true;
            reads = [ ];
          };
        };
      };
      g = gv.guard (aspects.pred.custom "host" { host = "x"; }) { ok = true; };
    in
    {
      expr = (builtins.tryEval (gv.applyGuard { host.name = "y"; } g)).success;
      expected = false;
    };

  # den-hoag-cr72: custom-form validation is EAGER at `applyGuard`, not lazy at dispatch-by-name.
  # The cell above only reaches the refusal because it dispatches the offending form BY NAME; the
  # defect at full strength is a vocabulary whose malformed entry is NEVER named by any dispatch —
  # which refused nothing at all, so `guard.nix`'s own "MUST be { eval; reads; }" / "may NOT shadow a
  # core form" held for exactly the forms a given run happened to look up.
  #
  # BOTH POLARITIES ARE ASSERTED IN THIS ONE CELL, which is what makes it discriminate without a
  # separate harness control: a dead `ok` that always answered `true` fails the two refusal rows, and
  # one that always answered `false` fails the three total rows.
  #
  # The two `construct…StaysTotal` rows are the PERMANENT FENCE against this fix's own rejected first
  # draft. Forcing `checkedUserForms` from `mkGuardVocab`'s RETURNED RECORD instead of from
  # `applyGuard`'s body makes that return's WHNF depend on `guardForms`' full key set, and a caller
  # whose key is derived from a sibling option inside its own config fixpoint then cycles with an
  # `infinite recursion` that escapes `tryEval` entirely. Any future change that moves the check back
  # onto the return path flips these two rows to `false` first.
  flake.tests.guard.test-custom-form-eager-validation =
    let
      okForm = {
        eval = _ctx: _a: true;
        reads = [ ];
      };
      mk = forms: aspects.mkGuardVocab { guardForms = forms; };
      malformed = mk {
        brokenForm = {
          eval = _ctx: _a: true;
        }; # no `reads`
        inherit okForm;
      };
      colliding = mk {
        host = okForm; # shadows a core predicate form
        inherit okForm;
      };
      control = mk { inherit okForm; };
      # deepSeq, not WHNF: a refusal living in a lazy attribute value is invisible to a bare tryEval.
      ok = e: (builtins.tryEval (builtins.deepSeq e true)).success;
      # A dispatch through an unrelated CORE predicate — it names no declared custom form at all.
      unrelatedCore = gv: gv.applyGuard { host.name = "cortex"; } (gv.vocab.always { fired = true; });
      # A dispatch through the RAW-CLOSURE escape hatch, which evaluates no predicate whatsoever.
      rawClosure =
        gv:
        gv.applyGuard { host.name = "cortex"; } (_ctx: {
          fired = true;
        });
    in
    {
      expr = {
        unrelatedCoreRefusesMalformed = ok (unrelatedCore malformed);
        unrelatedCoreRefusesColliding = ok (unrelatedCore colliding);
        # LIVE CONTROL, same predicate, same run: a vocabulary of sound forms still dispatches
        # through that same unrelated predicate, so the refusals above are the check discriminating
        # rather than `applyGuard` refusing unconditionally on every call.
        unrelatedCoreControl = ok (unrelatedCore control);
        # THE TWO HALVES OF THE FIX ARE SEPARABLE AND BOTH ARE PINNED. `evalPred` builds its case
        # table as `{ core… } // mapAttrs … checkedUserForms`, and `//` forces its operand to WHNF —
        # so the `deepSeq` alone already answers every PREDICATE dispatch, and the row above stays
        # green if the `builtins.seq checkedUserForms` wrap on `applyGuard` is deleted (measured, all
        # three arms, one run). The raw-closure arm forces no predicate at all, so it is reached by
        # that wrap and by nothing else — delete the wrap and this row is the one that goes red.
        rawClosureRefusesMalformed = ok (rawClosure malformed);
        rawClosureControl = ok (rawClosure control);
        constructMalformedStaysTotal = ok malformed;
        constructCollidingStaysTotal = ok colliding;
      };
      expected = {
        unrelatedCoreRefusesMalformed = false;
        unrelatedCoreRefusesColliding = false;
        unrelatedCoreControl = true;
        rawClosureRefusesMalformed = false;
        rawClosureControl = true;
        constructMalformedStaysTotal = true;
        constructCollidingStaysTotal = true;
      };
    };

  # site-independence: same predicate + first-order body at two "sites" -> equal key
  flake.tests.guard.test-guardkey-site-independent =
    let
      g1 = aspects.guard (aspects.pred.host "cortex") { a = 1; };
      g2 = aspects.guard (aspects.pred.host "cortex") { a = 1; };
    in
    {
      expr = aspects.guardKey g1 == aspects.guardKey g2;
      expected = true;
    };

  # bodyKey discriminates differing first-order bodies
  flake.tests.guard.test-guardkey-body-discriminates =
    let
      g1 = aspects.guard (aspects.pred.host "cortex") { a = 1; };
      g2 = aspects.guard (aspects.pred.host "cortex") { a = 2; };
    in
    {
      expr = aspects.guardKey g1 == aspects.guardKey g2;
      expected = false;
    };

  # structural key flows THROUGH a nested first-order guard body (bodyKey -> guardKey -> "guard:…")
  flake.tests.guard.test-guardkey-nested-body-structural =
    let
      mk =
        a:
        aspects.guard (aspects.pred.host "cortex") (
          aspects.guard (aspects.pred.class "nixos") { inherit a; }
        );
    in
    {
      expr = {
        siteIndep = aspects.guardKey (mk 1) == aspects.guardKey (mk 1);
        discriminates = aspects.guardKey (mk 1) == aspects.guardKey (mk 2);
        structural = lib.hasPrefix "guard:" (aspects.guardKey (mk 1));
      };
      expected = {
        siteIndep = true;
        discriminates = false;
        structural = true;
      };
    };

  # nested all/any with a FUNCTION body must not throw when keyed (predicate/body split) AND
  # must take the source-position (opaque) branch — hasPrefix still fails if guardKey throws.
  flake.tests.guard.test-guardkey-nested-no-throw =
    let
      g = aspects.guard (aspects.pred.all [
        (aspects.pred.host "cortex")
        (aspects.pred.class "nixos")
      ]) ({ config, ... }: { });
    in
    {
      expr = lib.hasPrefix "guard-loc:" (aspects.guardKey g);
      expected = true;
    };

  # a first-order body CONTAINING a nested guard whose body is a function must go opaque
  # (no toJSON crash, source-position branch) — hasFn recurses into nested guards.
  flake.tests.guard.test-guardkey-nested-guard-fn-body =
    let
      g = aspects.guard (aspects.pred.host "cortex") {
        sub = aspects.guard (aspects.pred.class "nixos") ({ config, ... }: { });
      };
    in
    {
      expr = lib.hasPrefix "guard-loc:" (aspects.guardKey g);
      expected = true;
    };

  # end-to-end: a guard record survives merge as inert data
  flake.tests.guard.test-guard-record-passes-through =
    let
      gv = aspects.mkGuardVocab { };
      eval = mkSchemaEval {
        modules = [ { config.aspects.db = gv.vocab.whenHost "cortex" { classOne.setting = "x"; }; } ];
      };
    in
    {
      expr = eval.config.aspects.db.__guard or false;
      expected = true;
    };

  # end-to-end site-independence: same guard (first-order body) at two sites -> equal key
  flake.tests.guard.test-guard-record-key-site-independent =
    let
      gv = aspects.mkGuardVocab { };
      mk =
        name:
        (mkSchemaEval {
          modules = [ { config.aspects.${name} = gv.vocab.whenHost "cortex" { classOne.setting = "x"; }; } ];
        }).config.aspects.${name};
    in
    {
      expr = aspects.key (mk "aaa") == aspects.key (mk "bbb");
      expected = true;
    };

  # end-to-end opaque-body soundness (completes Task 1 M2): two guards with FUNCTION bodies at
  # different sites -> DIFFERENT keys, because guardKey falls back to source-position via meta.loc
  flake.tests.guard.test-guard-opaque-body-site-distinct =
    let
      gv = aspects.mkGuardVocab { };
      mk =
        name:
        (mkSchemaEval {
          modules = [ { config.aspects.${name} = gv.vocab.whenHost "cortex" ({ config, ... }: { }); } ];
        }).config.aspects.${name};
    in
    {
      expr = aspects.key (mk "aaa") == aspects.key (mk "bbb");
      expected = false;
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
          { config.aspects.dup = gv.vocab.whenHost "cortex" { classOne.setting = "x"; }; }
          { config.aspects.dup = gv.vocab.whenHost "blade" { classOne.setting = "y"; }; }
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
          { config.aspects.dup = gv.vocab.whenHost "cortex" { classOne.setting = "x"; }; }
          { config.aspects.dup = gv.vocab.whenHost "blade" { classOne.setting = "y"; }; }
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
        preds = map (f: f.pred.a.host.v) carrier.fragments;
        bodies = map (f: f.body.classOne.setting) carrier.fragments;
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
          { config.aspects.dup = gv.vocab.whenHost "cortex" { classOne.setting = "x"; }; }
          { config.aspects.dup = gv.vocab.whenHost "blade" { classOne.setting = "y"; }; }
        ];
      };
      carrier = eval.config.aspects.dup;
    in
    {
      # (iii) discharge at a context where exactly one guard fires yields that fragment's body
      # alone.
      expr = gv.applyGuard { host.name = "cortex"; } carrier;
      expected = {
        classOne.setting = "x";
      };
    };

  flake.tests.guard.test-guard-multidef-carrier-discharges-to-null-when-none-fire =
    let
      gv = aspects.mkGuardVocab { };
      eval = mkSchemaEval {
        modules = [
          { config.aspects.dup = gv.vocab.whenHost "cortex" { classOne.setting = "x"; }; }
          { config.aspects.dup = gv.vocab.whenHost "blade" { classOne.setting = "y"; }; }
        ];
      };
      carrier = eval.config.aspects.dup;
    in
    {
      # (iii, continued) where neither fires, null.
      expr = gv.applyGuard { host.name = "vault"; } carrier;
      expected = null;
    };

  # O12: two guards at one key, BOTH firing at the same host, with directly conflicting INT
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
          { config.aspects.dup = gv.vocab.whenHost "cortex" 1; }
          { config.aspects.dup = gv.vocab.whenHost "cortex" 2; }
        ];
      };
      carrier = eval.config.aspects.dup;
    in
    {
      expr =
        !(builtins.tryEval (builtins.deepSeq (gv.applyGuard { host.name = "cortex"; } carrier) true))
        .success;
      expected = true;
    };

  # O5: guard control, byte-identical — single-def dispatch is untouched by either arm.
  flake.tests.guard.test-guard-singledef-control-byte-identical =
    let
      gv = aspects.mkGuardVocab { };
      eval = mkSchemaEval {
        modules = [ { config.aspects.solo = gv.vocab.whenHost "cortex" { classOne.setting = "x"; }; } ];
      };
    in
    {
      expr = {
        isGuard = eval.config.aspects.solo.__guard or false;
        pred = eval.config.aspects.solo.pred.a.host.v;
        body = eval.config.aspects.solo.body;
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
          { config.aspects.dup = gv.vocab.whenHost "cortex" { classOne.setting = "x"; }; }
          { config.aspects.dup = gv.vocab.whenHost "blade" { classOne.setting = "y"; }; }
        ];
      };
      carrier = carrierEval.config.aspects.dup;
      singleDefEval = mkSchemaEval {
        modules = [ { config.aspects.solo = gv.vocab.whenHost "cortex" { classOne.setting = "x"; }; } ];
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
          { config.aspects.mixed = gv.vocab.whenHost "cortex" { classOne.setting = "x"; }; }
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
          { config.aspects.mixed = gv.vocab.whenHost "cortex" { classOne.setting = "x"; }; }
          { config.aspects.mixed.classTwo.other = "y"; }
        ];
      };
      singleDefEval = mkSchemaEval {
        modules = [ { config.aspects.solo = gv.vocab.whenHost "cortex" { classOne.setting = "x"; }; } ];
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
          { config.aspects.mixed = gv.vocab.whenHost "cortex" { classOne.setting = "x"; }; }
          { config.aspects.mixed.classTwo.other = "y"; }
        ];
      };
      carrier = eval.config.aspects.mixed;
    in
    {
      # guard does not fire ("vault" != "cortex") -> the unconditional fragment's body alone.
      expr = gv.applyGuard { host.name = "vault"; } carrier;
      expected = {
        classTwo.other = "y";
      };
    };

  # O10: multi-def guard FUNCTIONS. RED (measured this session by execution, pre-fix): attrNames
  # gain the six aspect-option names, `includes` length 2, `__isWrappedFn` absent — a guard
  # function collision was silently folded through `(aspectSubmodule cnf).merge` exactly as a
  # module-function collision is, losing the distinction F4(b) rules must exist. GREEN, under
  # F4(b)'s ruled arm (in): two fragments, neither wearing `includes`; arity and discharge only —
  # a fragment's contributed content stays opaque pre-discharge (ADR-0013's declared limit), so
  # this oracle does not read into one. Two controls, same run: a single-def guard function still
  # yields `__isWrappedFn`; two MODULE functions at one key still coerce to `includes` length 2.
  flake.tests.guard.test-guard-multidef-functions-carrier-not-submodule-shape =
    let
      eval = mkSchemaEval {
        modules = [
          {
            config.aspects.provider =
              { who }:
              {
                classOne.a = "hi ${who}";
              };
          }
          {
            config.aspects.provider =
              { who }:
              {
                classTwo.b = "yo ${who}";
              };
          }
        ];
      };
      node = eval.config.aspects.provider;
    in
    {
      expr = {
        isGuard = node.__guard or false;
        fragmentCount = builtins.length node.fragments;
        hasIncludes = node ? includes;
        hasIsWrappedFn = node.__isWrappedFn or false;
      };
      expected = {
        isGuard = true;
        fragmentCount = 2;
        hasIncludes = false;
        hasIsWrappedFn = false;
      };
    };

  flake.tests.guard.test-guard-multidef-functions-discharge-arity-only =
    let
      gv = aspects.mkGuardVocab { };
      eval = mkSchemaEval {
        modules = [
          {
            config.aspects.provider =
              { who }:
              {
                classOne.a = "hi ${who}";
              };
          }
          {
            config.aspects.provider =
              { who }:
              {
                classTwo.b = "yo ${who}";
              };
          }
        ];
      };
      node = eval.config.aspects.provider;
    in
    {
      # arity + discharge only — both closures apply without an arity error, both survivors reach
      # the tree (different top-level keys, so this asserts nothing about mergeDefaultOption's own
      # interim shallow-attrset fold, out of scope per ADR-0031 / den-hoag-z5rvp).
      expr = gv.applyGuard { who = "world"; } node;
      expected = {
        classOne.a = "hi world";
        classTwo.b = "yo world";
      };
    };

  flake.tests.guard.test-guard-singledef-function-control-still-wrapped =
    let
      eval = mkSchemaEval {
        modules = [
          {
            config.aspects.soloFn =
              { who }:
              {
                classOne.a = "hi ${who}";
              };
          }
        ];
      };
    in
    {
      expr = eval.config.aspects.soloFn.__isWrappedFn or false;
      expected = true;
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

  # a defunctionalized guard record flattens as a LEAF (like __isWrappedFn), never recursed
  flake.tests.guard.test-guard-record-flattens-as-leaf =
    let
      gv = aspects.mkGuardVocab { };
      eval = mkSchemaEval {
        modules = [ { config.aspects.db = gv.vocab.whenHost "cortex" { classOne.setting = "x"; }; } ];
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
            config.aspects.top.db = gv.vocab.whenHost "cortex" { classOne.setting = "x"; };
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

  # APPLYING A WRAPPED FN GROWS THE TREE BY EXACTLY ONE LEVEL. `applyGuard`'s callable arm is `g ctx`
  # with no recursion, so depth is exactly the caller's application count and the termination bound
  # belongs to whoever drives the channel — see AGENTS.md `## Not this library's job`.
  #
  # ★★ WHY THE THIRD FIXTURE: A SELF-REPRODUCING FIXTURE IS BLIND TO OFF-BY-k. `selfw` reproduces
  # forever, so its `includes` head is a wrap after ANY number of applications; `leafw` bottoms out at
  # level 1, so it reads `false` for every k >= 1. Between them they separate k=0 from k>=1 and nothing
  # else — the identical two-fixture cell under a 1-, 2- and 7-level applier reads BYTE-IDENTICAL. Only
  # a FINITE chain longer than one level can see k=2, and `chainw` is that fixture: one application
  # leaves `leafw` itself unexpanded at the head, and `chainNextIsWrapped` is the conjunct that flips
  # the moment the channel expands a second level.
  flake.tests.guard.test-application-is-one-level-per-application =
    let
      cnf = {
        keySemantics = {
          classOne = {
            category = "class";
          };
          classTwo = {
            category = "class";
          };
        };
      };
      ctx = {
        host = "h1";
      };
      selfw =
        let
          w = aspects.wrapFn cnf "selfw" (
            { host, ... }:
            {
              includes = [ w ];
            }
          );
        in
        w;
      leafw = aspects.wrapFn cnf "leafw" (
        { host, ... }:
        {
          includes = [ { description = "leaf"; } ];
        }
      );
      chainw = aspects.wrapFn cnf "chainw" (
        { host, ... }:
        {
          includes = [ leafw ];
        }
      );
      nextOf = r: builtins.head (r.includes or [ ]);
      isWrap = x: x.__isWrappedFn or false;
    in
    {
      expr = {
        # The result is a merged aspect, not a wrap: the application happened.
        appliedOnce = !(isWrap (aspects.applyGuard ctx selfw));
        # Its `includes` head is STILL a wrap — the channel stopped at one level although the next
        # level was available.
        nextIsWrapped = isWrap (nextOf (aspects.applyGuard ctx selfw));
        # CONTROL: the identical predicate over a fixture that bottoms out ⇒ `false`, which is what
        # makes `nextIsWrapped` a result rather than an artefact of a predicate that cannot say no.
        controlNextIsWrapped = isWrap (nextOf (aspects.applyGuard ctx leafw));
        # The level counter: one application of a TWO-level chain leaves `leafw` unexpanded.
        chainNextIsWrapped = isWrap (nextOf (aspects.applyGuard ctx chainw));
      };
      expected = {
        appliedOnce = true;
        nextIsWrapped = true;
        controlNextIsWrapped = false;
        chainNextIsWrapped = true;
      };
    };
}
