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
}
