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
# den-hoag-gxe4 was closed on. It is asserted at the consumer: the live cells are gen-delivery's
# ci/tests/declared-content.nix, re-derived at the surface that realizes; gen-flake's suite still
# carries the original assertion, but that repo is orphaned as reference (ADR-0031 F3).
{
  lib,
  mkSchemaEval,
  aspects,
  ...
}:
let
  inherit (aspects) flatten graphFacts hasClassContent;

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
  # The same tree under a NON-EMPTY ORIGIN, so the projection assertion below is measured against a
  # real qualifier rather than an empty one.
  originFacts = graphFacts { providerPrefix = [ "acme" ]; } eval.config.aspects;

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

  # THE FABRICATED EMPTY deferredModule, hand-built because this library never renders one — the
  # `null` default above is precisely the construction in which it never forms. The predicate is
  # EXPORTED, so it answers for values this library did not build: a registry handed to a consumer
  # directly, or another framework's spelling of emptiness. Same fixture shape gen-delivery's
  # ci/tests/realization-predicate.nix hand-builds, for the same reason.
  fabricatedEmpty = {
    imports = [ ];
  };

  # The BOUNDARY fixture: a key declared NOWHERE in keySemantics. `fixtureKeySemantics` replaces the
  # harness default rather than extending it, so `loose` below is undeclared by construction and
  # takes gen-aspects' freeform fallback — becoming a nested ASPECT, a different node kind that never
  # reaches a class predicate's domain at all. Kept as its own eval: adding a nested aspect to the
  # fixture above would add a node and move the projection cell's key set.
  boundaryCnf = {
    keySemantics = {
      nixos = {
        category = "class";
      };
    };
  };
  boundaryEval = mkSchemaEval {
    fixtureKeySemantics = boundaryCnf.keySemantics;
    modules = [
      {
        config.aspects.web = {
          nixos.networking.hostName = "set";
          loose.child.setting = "freeform";
        };
      }
    ];
  };
  boundaryEntry = boundaryEval.config.aspects.web;

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

  # ── the fact NAMED: `aspects.hasClassContent` ───────────────────────────────
  # The cells above pin the REPRESENTATION (declared-without-content reads `null`). These pin the
  # exported PREDICATE over it — the name a consumer composes with instead of privately re-deriving
  # the fact (ADR-0012 clause 2). Asserted on the same fixture the representation cells use, so the
  # predicate is measured against this library's real merge output and not a restatement of itself.
  flake.tests.class-declared-content.test-has-class-content-separates-declared-fixtures = {
    expr = {
      declaredWithContent = hasClassContent entry.nixos;
      declaredWithoutContent = hasClassContent entry.metrics;
      # The check destructured nothing: the value is still the deferredModule it was.
      valueSurvivesTheCheck = entry.nixos ? imports;
      # LAZINESS, on the fixture whose class body THROWS when called. The predicate reads `true`
      # without calling it. Its positive control is next door in this same file and this same run:
      # `test-inspection-does-not-force-class-body`'s `lazyBodyReachable` proves the throw IS
      # reachable, so a clean read here is laziness rather than an unreachable body.
      lazyBodyNotForced = hasClassContent lazyClass;
    };
    expected = {
      declaredWithContent = true;
      declaredWithoutContent = false;
      valueSurvivesTheCheck = true;
      lazyBodyNotForced = true;
    };
  };

  # BOTH CLAUSES, and the second one is why this cell exists. `v != null` alone admits the fabricated
  # empty deferredModule, which is the state ADR-0028's Rider hazard turns on — a delivery class
  # realizing on the mere DECLARATION. The arming arm is in the same expectation: it asserts the first
  # clause alone WOULD admit the fixture, so dropping the second clause reds this cell instead of
  # quietly widening every consumer of the export.
  flake.tests.class-declared-content.test-has-class-content-excludes-the-fabricated-empty-module = {
    expr = {
      fabricatedEmptyIsNotContent = hasClassContent fabricatedEmpty;
      firstClauseAloneWouldAdmitIt = fabricatedEmpty != null;
      # And the exclusion is SHAPE-EXACT, not a blanket refusal of attrsets or of empty `imports`:
      # the test is on the whole key set, so a definition sitting beside an empty `imports` counts.
      definitionBesideEmptyImportsIsContent = hasClassContent {
        imports = [ ];
        setting = "real";
      };
      nonEmptyImportsIsContent = hasClassContent { imports = [ { } ]; };
    };
    expected = {
      fabricatedEmptyIsNotContent = false;
      firstClauseAloneWouldAdmitIt = true;
      definitionBesideEmptyImportsIsContent = true;
      nonEmptyImportsIsContent = true;
    };
  };

  # THE DOMAIN, stated so the predicate is not read as discriminating a case it never sees. An
  # undeclared key is not a contentless class — it is a nested ASPECT, and `keyCategory` says so.
  # This is the companion boundary to the pair above: the two primitives compose as
  # `keyCategory cnf k == "class" && hasClassContent entry.${k}`, and this cell pins what the first
  # of them keeps out of the second's way.
  flake.tests.class-declared-content.test-has-class-content-domain-is-declared-class-values = {
    expr = {
      undeclaredKeyIsNestedAspect = boundaryEntry.loose ? name;
      undeclaredKeyHasNoCategory = aspects.keyCategory boundaryCnf "loose" == null;
      declaredClassIsNotAnAspect = !(boundaryEntry.nixos ? name);
      declaredClassHasTheCategory = aspects.keyCategory boundaryCnf "nixos" == "class";
    };
    expected = {
      undeclaredKeyIsNestedAspect = true;
      undeclaredKeyHasNoCategory = true;
      declaredClassIsNotAnAspect = true;
      declaredClassHasTheCategory = true;
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

  # THE REGISTRY IS A PROJECTION OF THE PUBLISHED FACTS, identical modulo the origin qualifier —
  # asserted here because this fixture is the one carrying a DECLARED-BUT-UNSET class, the value
  # shape a projection is most likely to normalise away.
  flake.tests.class-declared-content.test-registry-projects-from-published-facts = {
    expr = {
      strippedKeysMatch =
        lib.sort (a: b: a < b) (map (lib.removePrefix "acme/") originFacts.nodes)
        == lib.sort (a: b: a < b) (builtins.attrNames flat);
      differBeforeStripping =
        lib.sort (a: b: a < b) originFacts.nodes != lib.sort (a: b: a < b) (builtins.attrNames flat);
      # The unset class still reads `null` through the published node value, not `{ }` and not a
      # missing attribute — the whole point of the representation this suite pins.
      unsetClassIsNullThroughFacts = originFacts.nodeData."acme/web".metrics == null;
      setClassSurvives = builtins.isAttrs originFacts.nodeData."acme/web".nixos;
    };
    expected = {
      strippedKeysMatch = true;
      differBeforeStripping = true;
      unsetClassIsNullThroughFacts = true;
      setClassSurvives = true;
    };
  };
}
