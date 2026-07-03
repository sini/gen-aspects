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

  # multi-def limitation (documented, not fixed — feedback_no_deferral): a guard record defined
  # TWICE under one key takes the merge `length != 1` path, which folds the two attrs guard
  # records into an aspect submodule rather than passing either through. ACTUAL observed behavior
  # (2026-07-02): it does NOT throw, but `__guard` is folded as a freeform bool key and becomes a
  # `genMerge.mkMerge [ true true ]` wrapper ({ _type = "merge"; ... }) — NOT the clean `true` a real
  # guard record carries. So the result is not a usable guard record. Single-def is the real usage.
  # TODO(guard): multi-def guard records not supported (single-def only) — see lib/types.nix branch.
  flake.tests.guard.test-guard-multidef-limitation =
    let
      gv = aspects.mkGuardVocab { };
      eval = mkSchemaEval {
        modules = [
          { config.aspects.dup = gv.vocab.whenHost "cortex" { classOne.setting = "x"; }; }
          { config.aspects.dup = gv.vocab.whenHost "blade" { classOne.setting = "y"; }; }
        ];
      };
      guardField = eval.config.aspects.dup.__guard or false;
    in
    {
      # single-def would give `true`; multi-def folds into the submodule -> a mkMerge attrset,
      # so the guard-record shape is lost (guardField == true is FALSE).
      expr = guardField == true;
      expected = false;
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
}
