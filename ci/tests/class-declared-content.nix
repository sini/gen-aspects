# A DECLARED class with no content reads `null`; only declared content is a deferredModule.
#
# ADR-0028's Rider: a delivery class realizes only on DECLARED CONTENT, never on structural shape.
# The hazard this pins (den-hoag-jwm8): a `{ }` default merges to `{ imports = [ { } ]; }`, which is
# shape-indistinguishable from real content, so a consumer projecting classes by shape realizes every
# member host of a class that was only ever DECLARED. Representing absence as `null` is the
# construction in which that intermediate never forms — the consumer's shape test then excludes it
# without needing to know anything about defaults.
#
# The consumer-side statement (a projection realizes no hosts for such a class) is deliberately NOT
# reproduced here: proving a consumer-facing fix inside the library's own harness is the divergence
# den-hoag-gxe4 was closed on. It is asserted at the consumer, in gen-flake's suite.
{
  mkSchemaEval,
  aspects,
  ...
}:
let
  inherit (aspects) flatten;

  # TWO classes declared, content on ONE. `metrics` is declared and never set.
  eval = mkSchemaEval {
    fixtureKeySemantics = {
      nixos = {
        category = "class";
      };
      metrics = {
        category = "class";
      };
    };
    modules = [
      {
        config.aspects.web.nixos.networking.hostName = "set";
      }
    ];
  };
  entry = eval.config.aspects.web;
  flat = flatten eval.config.aspects;

  # Laziness: the class body is a FUNCTION module whose result throws. Inspecting the deferredModule
  # must never CALL it. The positive control lives in the same fixture — `lazyBodyReachable` below
  # proves the throw is reachable, so a clean inspection is a real absence and not a dead predicate.
  lazyEval = mkSchemaEval {
    fixtureKeySemantics = {
      nixos = {
        category = "class";
      };
    };
    modules = [ { config.aspects.web.nixos = { ... }: throw "CLASS BODY CALLED"; } ];
  };
  lazyClass = lazyEval.config.aspects.web.nixos;
  findFn =
    depth: x:
    if builtins.isFunction x then
      x
    else if depth > 6 then
      null
    else if builtins.isAttrs x && x ? imports && builtins.isList x.imports && x.imports != [ ] then
      findFn (depth + 1) (builtins.head x.imports)
    else
      null;

  # Multi-definition: two modules contributing to the SAME class of the SAME aspect still collect.
  multiEval = mkSchemaEval {
    fixtureKeySemantics = {
      nixos = {
        category = "class";
      };
    };
    modules = [
      {
        config.aspects.web.nixos =
          { ... }:
          {
            a = 1;
          };
      }
      {
        config.aspects.web.nixos =
          { ... }:
          {
            b = 2;
          };
      }
    ];
  };
in
{
  # ── the rule itself ────────────────────────────────────────────────────────
  flake.tests.class-declared-content.test-declared-without-content-is-null = {
    expr = entry.metrics;
    expected = null;
  };
  # CONTROL, must accompany the above: a class GIVEN content is a deferredModule, not null.
  flake.tests.class-declared-content.test-declared-with-content-is-deferred-module = {
    expr = {
      isNull = entry.nixos == null;
      hasImports = builtins.isAttrs entry.nixos && entry.nixos ? imports;
    };
    expected = {
      isNull = false;
      hasImports = true;
    };
  };

  # ── the same fact through `flatten`, which is the registry a consumer reads ──
  flake.tests.class-declared-content.test-flat-entry-unset-class-is-null = {
    expr = flat.web.metrics;
    expected = null;
  };
  flake.tests.class-declared-content.test-flat-entry-set-class-survives = {
    expr = builtins.isAttrs flat.web.nixos && flat.web.nixos ? imports;
    expected = true;
  };

  # ── invariants the null representation must not break ──────────────────────
  flake.tests.class-declared-content.test-inspection-does-not-force-class-body = {
    expr = {
      hasImports = lazyClass ? imports;
      len = builtins.length lazyClass.imports;
      # Positive control: the body IS reachable and DOES throw, same fixture, same run.
      lazyBodyReachable =
        let
          fn = findFn 0 lazyClass;
        in
        fn != null && !(builtins.tryEval (fn { })).success;
    };
    expected = {
      hasImports = true;
      len = 1;
      lazyBodyReachable = true;
    };
  };
  flake.tests.class-declared-content.test-multiple-definitions-still-collect = {
    expr = builtins.length multiEval.config.aspects.web.nixos.imports;
    expected = 2;
  };
}
