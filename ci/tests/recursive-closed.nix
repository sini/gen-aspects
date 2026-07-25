# G-b — recursive-closed admission (design §2.1). With `recursiveClosed` on (alongside `closedKeys`),
# an undeclared freeform key is admitted — recursed as a nested aspect, gate RETAINED — iff its value is
# an attrset namespace; a non-attrset undeclared leaf throws NAMED at its scope. The typo-vs-nested
# distinction falls out of the type's own recursion (no value-heuristic). Auto-vivification (the public
# ~469-site contract) is preserved: interior namespace nodes admit; the leaf must be a declared key.
# Theory: Néron/Tolmach/Visser/Wachsmuth 2015 — a name resolving to no declaration in scope is a type
# error AT that scope; the aspect container tree is a tree of nested scopes, closed recursively.
{
  lib,
  mkSchemaEval,
  ...
}:
let
  mk =
    modules:
    mkSchemaEval {
      closedKeys = true;
      recursiveClosed = true;
      inherit modules;
    };
  forced =
    eval: path: builtins.tryEval (builtins.deepSeq (lib.getAttrFromPath path eval.config.aspects) true);

  autoViv = mk [ { config.aspects.svc.base.cli.classOne = { }; } ];
  typoLeaf = mk [ { config.aspects.svc.nixxos = "x"; } ];
  deepTypo = mk [ { config.aspects.svc.nixxos.networking = "x"; } ];
  emptyBranch = mk [ { config.aspects.svc.foo = { }; } ];
  gatedBelow = mk [ { config.aspects.svc.ns.typo = "x"; } ];
in
{
  flake.tests.recursive-closed.test-autoviv-namespace-admits = {
    expr =
      (forced autoViv [
        "svc"
        "base"
        "cli"
      ]).success;
    expected = true;
  };
  flake.tests.recursive-closed.test-typo-leaf-throws = {
    expr =
      (forced typoLeaf [
        "svc"
        "nixxos"
      ]).success;
    expected = false;
  };
  flake.tests.recursive-closed.test-deep-typo-throws-at-leaf = {
    expr =
      (forced deepTypo [
        "svc"
        "nixxos"
        "networking"
      ]).success;
    expected = false;
  };
  flake.tests.recursive-closed.test-empty-branch-admits = {
    expr =
      (forced emptyBranch [
        "svc"
        "foo"
      ]).success;
    expected = true;
  };
  flake.tests.recursive-closed.test-gate-retained-below = {
    expr =
      (forced gatedBelow [
        "svc"
        "ns"
        "typo"
      ]).success;
    expected = false;
  };
}
