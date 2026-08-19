# The published aspect-graph FACTS: the node set, the two edge relations, the node values.
#
# THE ORACLE THIS SUITE EXISTS FOR is that the parent relation is a DISPATCH ON NODE SHAPE and not a
# join against `meta.aspect-chain`. A lexical guard cannot establish that (ADR-0011: a token scan
# cannot observe representation), so every assertion below is behavioural, and each one carries its
# controls IN THE SAME RECORD — an assertion whose subject can go missing from the fixture without
# anything objecting is not an oracle.
{
  lib,
  mkSchemaEval,
  aspects,
  factsInternals,
  ...
}:
let
  gv = aspects.mkGuardVocab { };

  # ONE fixture, three node shapes: plain nested aspects (position under `meta.aspect-chain`), a
  # nested GUARD RECORD and a nested WRAPPED FN (position under `meta.loc`, and no `aspect-chain`
  # at all). `app` carries a by-value include so the includes relation has a subject here too.
  mkFixture =
    providerPrefix:
    mkSchemaEval {
      inherit providerPrefix;
      fixtureKeySemantics = {
        nixos = {
          category = "class";
        };
      };
      modules = [
        (
          { config, ... }:
          {
            config.aspects.infra.networking.dns.nixos.networking.nameservers = [ "1.1.1.1" ];
            config.aspects.top.g = gv.vocab.whenHost "cortex" { nixos.networking.domain = "x"; };
            config.aspects.top.w =
              { host }:
              {
                nixos.networking.hostName = host.name;
              };
            config.aspects.app.includes = [ config.aspects.infra.networking.dns ];
          }
        )
      ];
    };

  eval = mkFixture [ ];
  facts = aspects.graphFacts { } eval.config.aspects;
  flat = aspects.flatten eval.config.aspects;

  # The SAME tree under a non-empty origin. Required rather than decorative: a strip comparison
  # passes trivially on an empty qualifier, so the origin axis is only measured when one fixture
  # carries a qualifier and the run records the keys differing BEFORE the strip.
  originEval = mkFixture [ "acme" ];
  originFacts = aspects.graphFacts { providerPrefix = [ "acme" ]; } originEval.config.aspects;
  stripOrigin = id: if lib.hasPrefix "acme/" id then lib.removePrefix "acme/" id else id;

  sorted = lib.sort (a: b: a < b);

  # The naive framework-side reader this design replaces: join the registry with
  # `meta.aspect-chain or [ ]`. Kept in the suite because the DISAGREEMENT is the measurement.
  bareChainParent =
    id:
    let
      chain = (flat.${id}.meta or { }).aspect-chain or [ ];
    in
    if chain == [ ] then null else lib.concatStringsSep "/" chain;

  # A node whose held position names a container the tree does not contain. `meta.aspect-chain` is
  # stamped `mkDefault`, so a hand-set chain wins — which is exactly how a dangling parent arises.
  danglingEval = mkSchemaEval {
    fixtureKeySemantics = {
      nixos = {
        category = "class";
      };
    };
    modules = [
      {
        config.aspects.stray = {
          meta.aspect-chain = [ "ghost" ];
          nixos.networking.hostName = "s";
        };
      }
    ];
  };
  danglingFacts = aspects.graphFacts { } danglingEval.config.aspects;

  # An include element that references NO node: an inline guard record. Its `meta.loc` is the merge
  # position (`app/includes/0`), not a walk position, and the walk never descends into `includes`.
  inlineEval = mkSchemaEval {
    fixtureKeySemantics = {
      nixos = {
        category = "class";
      };
    };
    modules = [
      {
        config.aspects.app.includes = [ (gv.vocab.whenHost "cortex" { nixos.networking.domain = "x"; }) ];
      }
    ];
  };
  inlineFacts = aspects.graphFacts { } inlineEval.config.aspects;

  # A `keyRef` include — an origin-qualified reference to a node outside this fixpoint. It qualifies
  # with the REFERENT's origin, never the reading container's.
  refEval = mkSchemaEval {
    fixtureKeySemantics = {
      nixos = {
        category = "class";
      };
    };
    modules = [ { config.aspects.app.includes = [ (aspects.keyRef "acme/lib/base") ]; } ];
  };
  refFacts = aspects.graphFacts { providerPrefix = [ "local" ]; } refEval.config.aspects;

  caught = e: (builtins.tryEval e).success;

  # The refusal messages, rendered from the same bindings the throw paths call.
  danglingMsg = factsInternals.danglingParentRefusal "stray" "ghost/stray" "ghost";
  inlineMsg = factsInternals.unresolvableIncludeRefusal "app" 0;
in
{
  # ── R2 · the parent edge is a DISPATCH, never a chain read ──────────────────────────────────
  # The subject and both controls sit in ONE record, so neither can pass on a fixture that lost the
  # other. Every entry is exact, so a missing subject flips it rather than satisfying it.
  flake.tests.graph-facts.test-parent-is-a-dispatch-not-a-chain = {
    expr = {
      # THE SUBJECT: a nested guard leaf, reported at its true parent.
      guardLeafDispatched = facts.parentOf."top/g";
      # POSITIVE CONTROL, same fixture, same run: the bare-chain reader answers ROOT for it. This
      # disagreement is the whole ground for publishing the relation from the library.
      guardLeafBareChain = bareChainParent "top/g";
      # A wrapped fn holds its position under `meta.loc` too, and dispatches the same way.
      wrappedFnDispatched = facts.parentOf."top/w";
      wrappedFnBareChain = bareChainParent "top/w";
      # SECOND CONTROL: a plain nested aspect AGREES under both readings, so the predicate is shown
      # to discriminate rather than to disagree with everything.
      plainDispatched = facts.parentOf."infra/networking/dns";
      plainBareChain = bareChainParent "infra/networking/dns";
      # And the collapse itself: a genuine ROOT and an absent chain are the SAME value through the
      # bare reader, which is why absence there is indistinguishable from a right answer.
      genuineRootBareChain = bareChainParent "infra";
    };
    expected = {
      guardLeafDispatched = "top";
      guardLeafBareChain = null;
      wrappedFnDispatched = "top";
      wrappedFnBareChain = null;
      plainDispatched = "infra/networking";
      plainBareChain = "infra/networking";
      genuineRootBareChain = null;
    };
  };

  # ── R1 · the node id is the ORIGIN-QUALIFIED WALK KEY, and not the minted key ────────────────
  flake.tests.graph-facts.test-node-id-is-the-walk-key-not-the-minted-key = {
    expr = {
      # The guard leaf is named by its POSITION.
      guardLeafId = builtins.elem "top/g" facts.nodes;
      # What building the id from `identity.key` would have named it instead: a content address.
      mintedGuardKeyIsContentAddressed = lib.hasPrefix "guard:" (aspects.key flat."top/g");
      # CONTROL: for a PLAIN aspect the minted key and the walk key coincide, so the prefix test
      # above is not simply true of everything.
      mintedPlainKeyIsTheWalkKey = aspects.key flat."infra/networking/dns" == "infra/networking/dns";
    };
    expected = {
      guardLeafId = true;
      mintedGuardKeyIsContentAddressed = true;
      mintedPlainKeyIsTheWalkKey = true;
    };
  };

  flake.tests.graph-facts.test-node-id-is-origin-qualified = {
    expr = {
      # Raw ids under a non-empty origin, stated exactly — an empty node set cannot satisfy this.
      raw = sorted originFacts.nodes;
      # Stripping the qualifier yields today's registry exactly.
      strippedEqualsRegistry =
        sorted (map stripOrigin originFacts.nodes) == sorted (builtins.attrNames flat);
      # REQUIRED NON-TRIVIALITY RECORD: the raw ids DIFFER from the registry before stripping, so
      # the equality above is measuring a real qualifier and not an empty one.
      differBeforeStripping = sorted originFacts.nodes != sorted (builtins.attrNames flat);
      # NEGATIVE CONTROL: with an empty origin the same comparison holds unstripped.
      emptyOriginEqualsRegistryUnstripped = sorted facts.nodes == sorted (builtins.attrNames flat);
      # The edge relations carry the qualifier on BOTH endpoints.
      qualifiedParent = originFacts.parentOf."acme/top/g";
      qualifiedInclude = originFacts.includesOf."acme/app";
    };
    expected = {
      raw = [
        "acme/app"
        "acme/infra"
        "acme/infra/networking"
        "acme/infra/networking/dns"
        "acme/top"
        "acme/top/g"
        "acme/top/w"
      ];
      strippedEqualsRegistry = true;
      differBeforeStripping = true;
      emptyOriginEqualsRegistryUnstripped = true;
      qualifiedParent = "acme/top";
      qualifiedInclude = [ "acme/infra/networking/dns" ];
    };
  };

  # ── R3 · TOTALITY — every node has an answer, and a root's answer is an explicit null ─────────
  flake.tests.graph-facts.test-relations-are-total-over-nodes = {
    expr = {
      # The node count is stated exactly, so an empty or shrunken fixture cannot satisfy the three
      # set equalities below by making both of their sides empty.
      nodeCount = builtins.length facts.nodes;
      parentDomain = sorted (builtins.attrNames facts.parentOf) == sorted facts.nodes;
      includesDomain = sorted (builtins.attrNames facts.includesOf) == sorted facts.nodes;
      nodeDataDomain = sorted (builtins.attrNames facts.nodeData) == sorted facts.nodes;
      # A ROOT is present in the relation with an explicit `null`, never absent from it.
      rootIsPresent = facts.parentOf ? "top";
      rootAnswerIsNull = facts.parentOf."top" == null;
      # And the node values are the aspect values unchanged.
      nodeDataIsTheAspectValue = facts.nodeData."infra/networking/dns" == flat."infra/networking/dns";
    };
    expected = {
      nodeCount = 7;
      parentDomain = true;
      includesDomain = true;
      nodeDataDomain = true;
      rootIsPresent = true;
      rootAnswerIsNull = true;
      nodeDataIsTheAspectValue = true;
    };
  };

  # ── R3 · the REFUSAL — a parent naming a non-node is refused HERE, by name ───────────────────
  # The ground is LOCALITY: every alternative defers the objection to a site that cannot name the
  # offending aspect. Catchability is asserted on the real path; message content on the renderer the
  # throw path calls, because Nix cannot recover a thrown message through `tryEval`.
  flake.tests.graph-facts.test-dangling-parent-refuses-by-name = {
    expr = {
      danglingRefuses = !(caught danglingFacts.parentOf."stray");
      # NEGATIVE CONTROL, same predicate, same run: a sound fixture does NOT refuse — otherwise the
      # refusal fires on everything and proves nothing.
      soundFixtureDoesNotRefuse = caught facts.parentOf."top/g";
      # The refusal is CATCHABLE, which is what lets a consumer report it rather than abort.
      refusalIsCatchable = builtins.isAttrs (builtins.tryEval danglingFacts.parentOf."stray");
      messageNamesTheNode = lib.hasInfix "'stray'" danglingMsg;
      messageNamesTheMissingParent = lib.hasInfix "'ghost'" danglingMsg;
    };
    expected = {
      danglingRefuses = true;
      soundFixtureDoesNotRefuse = true;
      refusalIsCatchable = true;
      messageNamesTheNode = true;
      messageNamesTheMissingParent = true;
    };
  };

  # ── the INCLUDES relation ────────────────────────────────────────────────────────────────────
  flake.tests.graph-facts.test-includes-resolve-to-node-ids = {
    expr = {
      # A by-value aspect element resolves through its `.key`. Measured across four multi-def
      # shapes: the demo's name→key workaround is unnecessary, `.key` reads off the element.
      byValue = facts.includesOf."app";
      # A keyRef qualifies with the REFERENT's origin (`acme`), NOT the reading container's
      # (`local`) — that is what makes it a cross-source reference rather than a local one.
      keyRefTarget = refFacts.includesOf."local/app";
      # CONTROL: a node with no includes is PRESENT in the relation with an empty list, so an
      # absent key and a declared-nothing node are not the same answer.
      emptyIsPresent = facts.includesOf ? "top";
      emptyIsEmpty = facts.includesOf."top";
    };
    expected = {
      byValue = [ "infra/networking/dns" ];
      keyRefTarget = [ "acme/lib/base" ];
      emptyIsPresent = true;
      emptyIsEmpty = [ ];
    };
  };

  flake.tests.graph-facts.test-inline-include-refuses-by-name = {
    expr = {
      # An inline guard record at the include position references no node, so no edge can land.
      # Refused rather than dropped: dropping loses a declaration the substrate holds.
      inlineRefuses = !(caught (builtins.head inlineFacts.includesOf."app"));
      # NEGATIVE CONTROL, same predicate, same run: a resolvable element does NOT refuse.
      resolvableDoesNotRefuse = caught (builtins.head facts.includesOf."app");
      messageNamesTheNode = lib.hasInfix "'app'" inlineMsg;
      messageNamesThePosition = lib.hasInfix "position 0" inlineMsg;
    };
    expected = {
      inlineRefuses = true;
      resolvableDoesNotRefuse = true;
      messageNamesTheNode = true;
      messageNamesThePosition = true;
    };
  };

  # The entry point is a `cnf` entry like every other, so an off-domain key refuses by name here
  # too rather than being silently inert.
  flake.tests.graph-facts.test-unrecognised-cnf-key-refuses = {
    expr = {
      offDomainRefuses = !(caught (aspects.graphFacts { notAKey = 1; } eval.config.aspects));
      # CONTROL: the recognised key the suite actually uses does NOT refuse, same run.
      recognisedKeyPasses = caught (
        aspects.graphFacts { providerPrefix = [ "acme" ]; } eval.config.aspects
      );
    };
    expected = {
      offDomainRefuses = true;
      recognisedKeyPasses = true;
    };
  };
}
