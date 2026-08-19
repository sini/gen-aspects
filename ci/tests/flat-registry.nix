# Test: flat registry walks recursive aspect tree into path-keyed attrset.
#
# PARENTHOOD IS READ FROM THE PUBLISHED RELATION, NEVER SPLIT OUT OF THE KEY. This suite used to
# carry its own `parentOf` helper that split a key on "/" — the derivation ADR-0012 rules out and
# `graphFacts` replaces. A suite that re-derives the edge cannot notice that the derivation is
# wrong for a guard leaf, which is exactly the defect the published relation retires.
{
  lib,
  mkSchemaEval,
  aspects,
  ...
}:
let
  inherit (aspects) flatten graphFacts;

  eval = mkSchemaEval {
    fixtureKeySemantics = {
      nixos = {
        category = "class";
      };
    };
    modules = [
      {
        config.aspects.networking = {
          nixos.networking.hostName = "test";
          firewall = {
            nixos.networking.firewall.enable = true;
          };
        };
        config.aspects.desktop = {
          nixos.environment.systemPackages = [ ];
        };
      }
    ];
  };

  flat = flatten eval.config.aspects;
  facts = graphFacts { } eval.config.aspects;

  # Test with guard function
  guardEval = mkSchemaEval {
    fixtureKeySemantics = {
      nixos = {
        category = "class";
      };
    };
    modules = [
      {
        config.aspects.conditional =
          { host }:
          {
            nixos.networking.hostName = host.name;
          };
      }
    ];
  };

  guardFlat = flatten guardEval.config.aspects;

  # Test deep nesting
  deepEval = mkSchemaEval {
    fixtureKeySemantics = {
      nixos = {
        category = "class";
      };
    };
    modules = [
      {
        config.aspects.infra.networking.dns = {
          nixos.networking.nameservers = [ "1.1.1.1" ];
        };
      }
    ];
  };

  deepFlat = flatten deepEval.config.aspects;
  deepFacts = graphFacts { } deepEval.config.aspects;

  # THE MIXED FIXTURE: all three node shapes under a NON-EMPTY ORIGIN. Every element of it is
  # load-bearing. The origin is what makes the id-vs-`.key` comparison a real comparison instead of
  # one over an empty qualifier; the guard record and the wrapped fn are the shapes the retired
  # `? key` domain filter silently dropped, so they are here to be WITNESSED rather than assumed.
  origin = [ "acme" ];
  mixedEval = mkSchemaEval {
    providerPrefix = origin;
    fixtureKeySemantics = {
      nixos = {
        category = "class";
      };
    };
    modules = [
      {
        config.aspects.infra = {
          nixos.networking.domain = "example";
          networking.dns.nixos.networking.nameservers = [ "1.1.1.1" ];
          g = (aspects.mkGuardVocab { }).vocab.whenHost "cortex" { nixos.networking.hostName = "c"; };
          w =
            { host }:
            {
              nixos.networking.hostName = host.name;
            };
        };
      }
    ];
  };
  mixedFlat = flatten mixedEval.config.aspects;
  mixedFacts = graphFacts { providerPrefix = origin; } mixedEval.config.aspects;
  mixedData = mixedFacts.nodeData;
  stripOrigin = lib.removePrefix "acme/";

  # The two shapes the walk-key ≡ `.key` claim is scoped AWAY from, named rather than filtered out
  # by a `? key` test that happens to exclude them.
  isGuardRecord = id: mixedData.${id}.__guard or false;
  isWrappedFn = id: mixedData.${id}.__isWrappedFn or false;
  comparable = builtins.filter (id: !(isGuardRecord id || isWrappedFn id)) mixedFacts.nodes;

  sorted = lib.sort (a: b: a < b);
in
{
  flake.tests.flat-registry.test-top-level-keys = {
    expr = sorted (builtins.attrNames flat);
    expected = [
      "desktop"
      "networking"
      "networking/firewall"
    ];
  };

  flake.tests.flat-registry.test-nested-parent-from-key = {
    expr = facts.parentOf."networking/firewall";
    expected = "networking";
  };

  flake.tests.flat-registry.test-top-level-parent-from-key = {
    expr = facts.parentOf."networking";
    expected = null;
  };

  flake.tests.flat-registry.test-preserves-name = {
    expr = flat."networking".name;
    expected = "networking";
  };

  flake.tests.flat-registry.test-no-parent-field-injected = {
    # flatten does NOT inject __parent — the edge is published as a relation, never as a field on
    # the value and never as something to be read back out of the key.
    expr = flat."networking/firewall" ? __parent;
    expected = false;
  };

  flake.tests.flat-registry.test-guard-function-appears = {
    expr = guardFlat ? "conditional";
    expected = true;
  };

  flake.tests.flat-registry.test-guard-function-not-recursed = {
    expr = {
      # The subject's PRESENCE is asserted in the same record as its childlessness. Held apart, the
      # empty-list expectation is satisfied by dropping the guard from the fixture altogether, and
      # the assertion goes green with nothing left for it to be about.
      guardIsAnEntry = guardFlat ? "conditional";
      notRecursedInto = builtins.filter (k: lib.hasPrefix "conditional/" k) (
        builtins.attrNames guardFlat
      );
    };
    expected = {
      guardIsAnEntry = true;
      notRecursedInto = [ ];
    };
  };

  flake.tests.flat-registry.test-deep-nesting = {
    expr = sorted (builtins.attrNames deepFlat);
    expected = [
      "infra"
      "infra/networking"
      "infra/networking/dns"
    ];
  };

  flake.tests.flat-registry.test-deep-parent-chain = {
    expr = {
      infra = deepFacts.parentOf."infra";
      networking = deepFacts.parentOf."infra/networking";
      dns = deepFacts.parentOf."infra/networking/dns";
    };
    expected = {
      infra = null;
      networking = "infra";
      dns = "infra/networking";
    };
  };

  flake.tests.flat-registry.test-class-keys-excluded = {
    expr = {
      # The subject: a declared class key is content, not a node.
      classKeyIsAnEntry = builtins.any (k: k == "networking/nixos") (builtins.attrNames flat);
      # WITNESS, in the same record: the class key IS carried by the fixture, with content on it.
      # A declared class with no content reads `null`, so this goes false the moment the fixture
      # loses the subject — which is what stops the negative above from passing on a tree that no
      # longer contains the thing it is denying.
      classContentIsInTheTree = eval.config.aspects.networking.nixos != null;
    };
    expected = {
      classKeyIsAnEntry = false;
      classContentIsInTheTree = true;
    };
  };

  # A-IDENT, RE-SCOPED ON THE AXIS THAT ACTUALLY MOVES IT. The retired claim was that the walk key
  # and `.key` are "one identity, two exactly-agreeing views" for every node. Two things falsify it
  # as stated: an origin-qualified node id takes a qualifier `identity.key` never sees, and a guard
  # record or wrapped fn carries no `key` option at all. The old assertion could observe neither —
  # its `? key` domain filter dropped those shapes before the comparison, and its fixture's origin
  # was empty — so it passed while measuring nothing, and adding a guard to its fixture produced no
  # counterexample. What replaces it compares MODULO THE ORIGIN over a domain enumerated from
  # `nodes`, names its exclusions instead of filtering them away, and answers for the excluded
  # shapes through `parentOf` rather than by staying silent about them.
  flake.tests.flat-registry.test-node-id-agrees-with-key-modulo-origin = {
    expr = {
      # (1) The comparison, modulo the qualifier.
      agreesModuloOrigin = builtins.all (id: stripOrigin id == aspects.key mixedData.${id}) comparable;
      # (1b) FIRING CAPACITY, and it is required: the RAW ids must NOT agree, or the strip is doing
      # no work and the assertion is measuring an empty qualifier.
      rawIdsDisagree = !(builtins.all (id: id == aspects.key mixedData.${id}) comparable);
      # (2) Each named exclusion is WITNESSED. An exclusion the fixture never carried is
      # indistinguishable from a scope that excludes nothing.
      guardRecordWitnessed = builtins.any isGuardRecord mixedFacts.nodes;
      wrappedFnWitnessed = builtins.any isWrappedFn mixedFacts.nodes;
      # …and the compared domain is stated exactly, so it cannot shrink to nothing unnoticed.
      comparedCount = builtins.length comparable;
      # (3) The excluded shapes' own positions, answered through the dispatch. What replaces the
      # retired claim is not silence about guards — it is the relation that does answer for them.
      guardParent = mixedFacts.parentOf."acme/infra/g";
      wrappedFnParent = mixedFacts.parentOf."acme/infra/w";
    };
    expected = {
      agreesModuloOrigin = true;
      rawIdsDisagree = true;
      guardRecordWitnessed = true;
      wrappedFnWitnessed = true;
      comparedCount = 3;
      guardParent = "acme/infra";
      wrappedFnParent = "acme/infra";
    };
  };

  # THE REGISTRY IS A PROJECTION OF THE PUBLISHED FACTS, identical modulo the origin qualifier.
  # Byte-identity is deliberately NOT the assertion: under an origin-qualified id, equality with
  # today's output is false by construction, and asserting it would pin the behaviour ruled against.
  flake.tests.flat-registry.test-registry-projects-from-published-facts = {
    expr = {
      keysMatchUnqualified = sorted facts.nodes == sorted (builtins.attrNames flat);
      valuesUntouched = builtins.all (k: facts.nodeData.${k} == flat.${k}) (builtins.attrNames flat);
      # The same projection under a NON-EMPTY origin, stripped — and recorded as differing BEFORE
      # the strip, so the equality is not the trivial one over an empty qualifier.
      qualifiedKeysStripToTheRegistry =
        sorted (map stripOrigin mixedFacts.nodes) == sorted (builtins.attrNames mixedFlat);
      qualifiedKeysDifferBeforeStripping =
        sorted mixedFacts.nodes != sorted (builtins.attrNames mixedFlat);
    };
    expected = {
      keysMatchUnqualified = true;
      valuesUntouched = true;
      qualifiedKeysStripToTheRegistry = true;
      qualifiedKeysDifferBeforeStripping = true;
    };
  };
}
