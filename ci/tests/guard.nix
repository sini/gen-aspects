# Test: guard-predicate vocabulary — predicates are first-order data, one applyGuard dispatches.
# Theory: Reynolds "Elimination of Higher-Order Functions" (defunctionalize the guard space)
# as formalized by Danvy & Nielsen 2001 (O1-O7).
{ lib, aspects, ... }:
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

  # nested all/any with a FUNCTION body must not throw when keyed (predicate/body split)
  flake.tests.guard.test-guardkey-nested-no-throw =
    let
      g = aspects.guard (aspects.pred.all [
        (aspects.pred.host "cortex")
        (aspects.pred.class "nixos")
      ]) ({ config, ... }: { });
    in
    {
      expr = (builtins.tryEval (builtins.stringLength (aspects.guardKey g) > 0)).success;
      expected = true;
    };

  # a first-order body CONTAINING a nested guard whose body is a function must go opaque
  # (no toJSON crash) — hasFn recurses into nested guards.
  flake.tests.guard.test-guardkey-nested-guard-fn-body =
    let
      g = aspects.guard (aspects.pred.host "cortex") {
        sub = aspects.guard (aspects.pred.class "nixos") ({ config, ... }: { });
      };
    in
    {
      expr = (builtins.tryEval (builtins.isString (aspects.guardKey g))).success;
      expected = true;
    };
}
