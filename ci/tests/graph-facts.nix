# The published aspect-graph FACTS: the node set, the edge relations, the node values.
#
# THE ORACLE THIS SUITE EXISTS FOR is that the published parent is the node's OWN WALK POSITION and
# not a re-derivation from `meta`. Two readings must be discriminated against, not one:
#
#   * the bare `meta.aspect-chain or [ ]` join a framework would otherwise write, which answers ROOT
#     for a nested guard leaf, and
#   * the `meta`-dispatch that answer was first built as, which THROWS on a guard leaf no aspect type
#     stamped (built by the public `guard` in a raw tree) and answers the WRONG parent for a guard
#     carried by value from another tree (its `meta.loc` is where it was placed there).
#
# The second is the one an earlier revision of this suite could not see: every assertion in it passed
# under BOTH the dispatch and the walk, so the oracle that "decides the design" did not decide
# between the shipped construction and the one that has neither defect.
# `test-parent-is-the-walk-not-a-meta-read` closes that — it fails under the dispatch and under the
# bare-chain reader alike.
#
# A lexical guard cannot establish any of this (ADR-0011: a token scan cannot observe
# representation), so every assertion below is behavioural, and each carries its controls IN THE SAME
# RECORD — an assertion whose subject can go missing from the fixture without anything objecting is
# not an oracle.
{
  lib,
  mkSchemaEval,
  aspects,
  factsInternals,
  genMerge,
  ...
}:
let
  gv = aspects.mkGuardVocab { };
  hostGuard = aspects.guard (aspects.pred.has "host") { nixos.networking.hostName = "h"; };

  # ONE placed fixture: a plain aspect under `meta.aspect-chain` and guard records under `meta.loc`,
  # each stamped by the aspect type with its own position. The shapes whose `meta` CANNOT be read as
  # a position live in the raw fixture (`rawFacts`, below): a guard no aspect type stamped, and a
  # guard carried by value from another tree.
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
            config.aspects.top.g = gv.vocab.whenEq [ "thimble" "name" ] "cortex" {
              nixos.networking.domain = "x";
            };
            config.aspects.top.w = hostGuard;
            config.aspects.top.wf = hostGuard;
            config.aspects.top.deeper.wf2 = hostGuard;
            config.aspects.top.gf = hostGuard;
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

  # The two readings this design is discriminated AGAINST, both written out so the disagreement is
  # measured in the same run rather than asserted in prose.
  #
  # (1) the naive framework-side join.
  bareChainParent =
    id:
    let
      chain = (flat.${id}.meta or { }).aspect-chain or [ ];
    in
    if chain == [ ] then null else lib.concatStringsSep "/" chain;
  # (2) the `meta`-shape dispatch this construction replaced: `meta.loc` for a leaf shape, the
  # chain for a plain aspect. Reproduced faithfully, including its `parent = init position` step.
  metaDispatchParentIn =
    fl: id:
    let
      v = fl.${id};
      isLeaf = v.__guard or false;
      position =
        if isLeaf then (v.meta or { }).loc or null else ((v.meta or { }).aspect-chain or [ ]) ++ [ v.name ];
    in
    if position == null then
      "<THREW: no position recorded>"
    else if builtins.length position <= 1 then
      null
    else
      lib.concatStringsSep "/" (lib.init position);
  metaDispatchParent = metaDispatchParentIn flat;

  # A tree handed to `graphFacts` as a value, not through the aspect type: nothing stamps `meta`, so a
  # guard built by the public constructor records no position, and a guard carried in by value from
  # another tree records THAT tree's position. These are the shapes on which a `meta` read is wrong.
  carriedEval = mkSchemaEval {
    fixtureKeySemantics.nixos.category = "class";
    modules = [ { config.aspects.elsewhere.deep.g = hostGuard; } ];
  };
  rawTree = {
    top = {
      name = "top";
      g = hostGuard;
      carried = carriedEval.config.aspects.elsewhere.deep.g;
      deeper = {
        name = "deeper";
        g2 = hostGuard;
      };
    };
  };
  rawFacts = aspects.graphFacts { } rawTree;
  rawFlat = aspects.flatten rawTree;

  # A node whose HELD chain contradicts its walk position. An earlier construction honoured such a
  # chain, producing a node whose parent contradicted its own id; the chain is now a rendering of the
  # declared path, and one that contradicts it refuses by name (identity design Q4). `top.ctl` is a
  # clean sibling.
  handSetEval = mkSchemaEval {
    fixtureKeySemantics = {
      nixos = {
        category = "class";
      };
    };
    modules = [
      {
        config.aspects.real.nixos.networking.domain = "r";
        config.aspects.top.deep = {
          meta.aspect-chain = [ "real" ];
          nixos.networking.hostName = "s";
        };
        config.aspects.top.ctl.nixos.networking.hostName = "c";
      }
    ];
  };
  handSetFacts = aspects.graphFacts { } handSetEval.config.aspects;

  # Include-element fixtures. Every shape below is one the library SHIPS and TESTS.
  mkIncludes =
    {
      providerPrefix ? [ ],
      ...
    }@args:
    mkSchemaEval (
      (removeAttrs args [ "elems" ])
      // {
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
              config.aspects.lib.base.nixos.networking.domain = "b";
              config.aspects.app.includes = args.elems config;
            }
          )
        ];
      }
    );

  # The deferred shapes (a raw closure, a policy record), two inline aspect literals (one carrying a
  # closure-valued field) and a guard record, all in one tree.
  inlineEval = mkIncludes {
    elems = _: [
      (
        { config, ... }:
        {
          nixos.networking.hostName = "m";
        }
      ) # module function
      {
        name = "batt";
        nixos.networking.hostName = "b";
      }
      hostGuard
      { nixos.networking.domain = "inline"; } # inline aspect literal
      (gv.vocab.whenEq [ "thimble" "name" ] "cortex" { nixos.networking.domain = "g"; }) # inline guard record
    ];
  };
  inlineFacts = aspects.graphFacts { } inlineEval.config.aspects;

  # A parametric include: a first-order guard at the include position (inline content, no edge).
  wrappedIncludeEval = mkIncludes {
    elems = _: [ hostGuard ];
  };
  wrappedIncludeFacts = aspects.graphFacts { } wrappedIncludeEval.config.aspects;

  # A by-value REFERENCE — the shape that IS an edge.
  refEval = mkIncludes { elems = config: [ config.aspects.lib.base ]; };
  refFacts = aspects.graphFacts { } refEval.config.aspects;

  # keyRefs: one FOREIGN (uncheckable here, unrefused), one LOCAL and dangling (refused by name),
  # one LOCAL and sound (the control that the refusal does not fire on everything).
  foreignEval = mkIncludes {
    providerPrefix = [ "acme" ];
    elems = _: [
      (aspects.keyRef {
        origin = [ "other" ];
        path = [
          "lib"
          "base"
        ];
      })
    ];
  };
  foreignFacts = aspects.graphFacts { providerPrefix = [ "acme" ]; } foreignEval.config.aspects;

  localBadEval = mkIncludes {
    providerPrefix = [ "acme" ];
    elems = _: [
      (aspects.keyRef {
        origin = [ "acme" ];
        path = [
          "lib"
          "bsae"
        ];
      })
    ];
  };
  localBadFacts = aspects.graphFacts { providerPrefix = [ "acme" ]; } localBadEval.config.aspects;

  localGoodEval = mkIncludes {
    providerPrefix = [ "acme" ];
    elems = _: [
      (aspects.keyRef {
        origin = [ "acme" ];
        path = [
          "lib"
          "base"
        ];
      })
    ];
  };
  localGoodFacts = aspects.graphFacts { providerPrefix = [ "acme" ]; } localGoodEval.config.aspects;

  # A BARE STRING, the same edge shape as by-value (den-hoag-zxgan): dangling, sound, and the
  # by-value control it must agree with.
  localBadStringEval = mkIncludes {
    providerPrefix = [ "acme" ];
    elems = _: [ "lib/bsae" ];
  };
  localBadStringFacts = aspects.graphFacts {
    providerPrefix = [ "acme" ];
  } localBadStringEval.config.aspects;

  localGoodStringEval = mkIncludes {
    providerPrefix = [ "acme" ];
    elems = _: [ "lib/base" ];
  };
  localGoodStringFacts = aspects.graphFacts {
    providerPrefix = [ "acme" ];
  } localGoodStringEval.config.aspects;

  localGoodValueEval = mkIncludes {
    providerPrefix = [ "acme" ];
    elems = config: [ config.aspects.lib.base ];
  };
  localGoodValueFacts = aspects.graphFacts {
    providerPrefix = [ "acme" ];
  } localGoodValueEval.config.aspects;

  # THE TWO keyRef FORMS OVER THE SAME TARGET, under the default empty provider prefix. `lib/base`
  # IS a node here, so the two forms differ in nothing a consumer can see unless the relation says so.
  sugarSelfFacts =
    let
      eval = mkIncludes { elems = _: [ (aspects.keyRef "lib/base") ]; };
    in
    aspects.graphFacts { } eval.config.aspects;
  structSelfFacts =
    let
      eval = mkIncludes {
        elems = _: [
          (aspects.keyRef {
            origin = [ ];
            path = [
              "lib"
              "base"
            ];
          })
        ];
      };
    in
    aspects.graphFacts { } eval.config.aspects;

  # The prefix lengths at which the STRING sugar cannot name a local node at all: its origin is
  # always exactly one segment (`identity.nix`'s `keyRef` takes `head parts`), so the locality
  # comparison can only succeed at `length providerPrefix == 1`.
  twoSegPrefix = [
    "acme"
    "sub"
  ];
  twoSegFacts =
    let
      eval = mkIncludes {
        providerPrefix = twoSegPrefix;
        elems = _: [ (aspects.keyRef "acme/sub/nope") ];
      };
    in
    aspects.graphFacts { providerPrefix = twoSegPrefix; } eval.config.aspects;
  bareSegFacts =
    let
      eval = mkIncludes { elems = _: [ (aspects.keyRef "nope") ]; };
    in
    aspects.graphFacts { } eval.config.aspects;

  caught = e: (builtins.tryEval e).success;

  # The refusal message, rendered from the same binding the throw path calls.
  danglingMsg = factsInternals.danglingIncludeRefusal "acme/app" 0 "acme/lib/bsae";

  # ── REFERENCES RESOLVE BY IDENTITY (den-hoag-7gp66 P1, §v1.3 arm (d)) ──
  # ykt9t's key-field pair. `collisionOther` is ANOTHER tree at the same (default) origin holding a
  # node with the same key and different content; `rekeyed` is a member of THIS tree whose key was
  # edited to spell another member.
  collisionOtherEval = mkSchemaEval {
    fixtureKeySemantics.nixos.category = "class";
    modules = [ { config.aspects.lib.base.nixos.networking.domain = "FOREIGN"; } ];
  };
  refRead =
    {
      providerPrefix ? [ ],
    }:
    elems:
    let
      f = aspects.graphFacts {
        inherit providerPrefix;
      } (mkIncludes { inherit providerPrefix elems; }).config.aspects;
      id = lib.concatStringsSep "/" (providerPrefix ++ [ "app" ]);
    in
    tryValue f.includesOf.${id};

  # ── DECLARATION vs CONTENT fixtures ──
  # Raw module lists, so one aspect's `includes` can take SEVERAL definitions: an element's merge
  # position is numbered per definition, and a construction that compares it to the merged index is
  # wrong exactly there. Each reading states the declared length beside the published positions,
  # so no reading can pass by its fixture having gone empty.
  lit = d: { nixos.networking.domain = d; };
  at =
    p: x:
    lib.setAttrByPath (
      [
        "config"
        "aspects"
      ]
      ++ p
      ++ [ "includes" ]
    ) x;
  one = at [ "app" ];
  baseMod = {
    config.aspects.lib.base.nixos.networking.domain = "b";
  };
  declEval =
    {
      providerPrefix ? [ ],
    }:
    modules:
    mkSchemaEval {
      inherit providerPrefix modules;
      fixtureKeySemantics = {
        nixos = {
          category = "class";
        };
      };
    };
  tryValue =
    v:
    let
      r = builtins.tryEval (builtins.deepSeq v v);
    in
    if r.success then r.value else "REFUSED";
  declRead =
    {
      id ? "app",
      providerPrefix ? [ ],
    }:
    modules:
    let
      ev = declEval { inherit providerPrefix; } modules;
      f = aspects.graphFacts { inherit providerPrefix; } ev.config.aspects;
    in
    {
      u = tryValue f.unresolvedIncludesOf.${lib.concatStringsSep "/" (providerPrefix ++ [ id ])};
      n =
        builtins.length
          (builtins.foldl' (a: k: a.${k}) ev.config.aspects (lib.splitString "/" id)).includes;
    };

  # ANOTHER TREE, whose values are carried into this one by value. Its `renamed` node is NAMED
  # `includes`, so its `.key` is `elsewhere/includes` while its walk id is `elsewhere/renamed`.
  otherEval = declEval { } [
    {
      config.aspects.elsewhere.thing.nixos.networking.domain = "o";
      config.aspects.elsewhere.box.includes = [ (lit "o-inline") ];
      config.aspects.elsewhere.renamed = {
        name = "includes";
        nixos.networking.domain = "r";
      };
    }
  ];
  oa = otherEval.config.aspects;

  # The suite's inline shapes, split over two definitions.
  shapesA = [
    (
      { config, ... }:
      {
        nixos.networking.hostName = "m";
      }
    )
    {
      name = "batt";
      nixos.networking.hostName = "b";
    }
    (lit "inline")
  ];
  shapesB = [
    hostGuard
    (lit "inline2")
    (gv.vocab.whenEq [ "thimble" "name" ] "cortex" (lit "g"))
  ];

  # The include-sites fixtures: bare modules over the class-keyed schema.
  sitesEval =
    mods:
    (mkSchemaEval {
      fixtureKeySemantics = {
        nixos = {
          category = "class";
        };
      };
      modules = mods;
    }).config.aspects;
  hostFn = aspects.guard (aspects.pred.has "host") { nixos.marks = [ "h" ]; };

  # x7: inline content in one definition, another tree's node in a second.
  otherSecondDefFacts =
    aspects.graphFacts { }
      (declEval { } [
        baseMod
        (one [ (lit "a") ])
        (one [ oa.elsewhere.thing ])
      ]).config.aspects;
in
{
  # ── THE DECIDING ORACLE · the parent is the WALK, not any read of `meta` ─────────────────────────
  # Subject and both counterfactual readings in ONE record, so the assertion fails if either reading
  # is substituted for the construction. The raw-tree and carried guards are what make the `meta`
  # dispatch distinguishable at all: under it, `top/g` and `top/deeper/g2` throw and `top/carried`
  # reads the parent of the tree it was placed in.
  flake.tests.graph-facts.test-parent-is-the-walk-not-a-meta-read = {
    expr = {
      # SUBJECTS — guard leaves whose `meta` cannot be read as a position: built by the public
      # constructor in a tree no aspect type stamped, and carried by value from another tree.
      rawGuardParent = rawFacts.parentOf."top/g";
      rawGuardNestedParent = rawFacts.parentOf."top/deeper/g2";
      carriedGuardParent = rawFacts.parentOf."top/carried";
      # …and what the `meta` dispatch answers for the same three, same run.
      rawGuardUnderMetaDispatch = metaDispatchParentIn rawFlat "top/g";
      rawGuardNestedUnderMetaDispatch = metaDispatchParentIn rawFlat "top/deeper/g2";
      carriedGuardUnderMetaDispatch = metaDispatchParentIn rawFlat "top/carried";
      # CONTROL: a guard placed through the aspect type carries its real `meta.loc`, so the dispatch
      # agrees with the walk on it. The predicate discriminates rather than disagreeing with everything.
      typeMergedGuardParent = facts.parentOf."top/deeper/wf2";
      typeMergedGuardUnderMetaDispatch = metaDispatchParent "top/deeper/wf2";
      # …and the guard leaf, where the BARE-CHAIN reader is the one that goes wrong.
      guardLeafParent = facts.parentOf."top/g";
      guardLeafUnderBareChain = bareChainParent "top/g";
      # SECOND CONTROL: a plain nested aspect agrees under all three readings.
      plainParent = facts.parentOf."infra/networking/dns";
      plainUnderBareChain = bareChainParent "infra/networking/dns";
      plainUnderMetaDispatch = metaDispatchParent "infra/networking/dns";
    };
    expected = {
      rawGuardParent = "top";
      rawGuardNestedParent = "top/deeper";
      carriedGuardParent = "top";
      rawGuardUnderMetaDispatch = "<THREW: no position recorded>";
      rawGuardNestedUnderMetaDispatch = "<THREW: no position recorded>";
      carriedGuardUnderMetaDispatch = "elsewhere/deep";
      typeMergedGuardParent = "top/deeper";
      typeMergedGuardUnderMetaDispatch = "top/deeper";
      guardLeafParent = "top";
      guardLeafUnderBareChain = null;
      plainParent = "infra/networking";
      plainUnderBareChain = "infra/networking";
      plainUnderMetaDispatch = "infra/networking";
    };
  };

  # `null` means ROOT and nothing else. Under any `meta` read this was false — `top/wf` was a
  # non-root node reported as a root — so the claim is asserted rather than left to the docs.
  flake.tests.graph-facts.test-null-parent-means-root-and-only-root = {
    expr = {
      roots = sorted (builtins.attrNames (lib.filterAttrs (_: p: p == null) facts.parentOf));
      # WITNESS: the fixture does contain non-root nodes, so the list above is a real partition and
      # not the whole node set.
      nonRootCount = builtins.length (
        builtins.attrNames (lib.filterAttrs (_: p: p != null) facts.parentOf)
      );
    };
    expected = {
      roots = [
        "app"
        "infra"
        "top"
      ];
      nonRootCount = 8;
    };
  };

  # THE PROPERTY THE RETIRED PARENT-REFUSAL USED TO GUARD, now pinned as a construction. `walk.nix`
  # descends only into values it also emits, so a non-root node's parent is necessarily a node. A
  # refusal for a case that cannot arise is dead code; a pin on the property that makes it
  # unreachable is not, and it fires if the walk ever stops emitting what it descends into.
  flake.tests.graph-facts.test-parent-closure-is-a-construction = {
    expr = {
      everyNonRootParentIsANode = builtins.all (
        id:
        let
          p = facts.parentOf.${id};
        in
        p == null || builtins.elem p facts.nodes
      ) facts.nodes;
      # Stated exactly, so the `all` above cannot be satisfied by an empty node set.
      nodeCount = builtins.length facts.nodes;
      # …and the same property under a non-empty origin, where both endpoints carry the qualifier.
      everyNonRootParentIsANodeQualified = builtins.all (
        id:
        let
          p = originFacts.parentOf.${id};
        in
        p == null || builtins.elem p originFacts.nodes
      ) originFacts.nodes;
    };
    expected = {
      everyNonRootParentIsANode = true;
      nodeCount = 11;
      everyNonRootParentIsANodeQualified = true;
    };
  };

  # A hand-set `meta.aspect-chain` never moves the edge: it refuses by name rather than publish an
  # edge between ids that do not relate. The refusal reaches the whole tree's facts, since they force
  # every node's key (spec OQ6), while the declaration's own fields and a clean sibling's key still
  # read. Before, the chain was honoured nowhere and silently, and `parentOf."top/deep"` read `"top"`.
  flake.tests.graph-facts.test-hand-set-chain-refuses-and-does-not-move-the-edge =
    let
      ok = x: (builtins.tryEval (builtins.deepSeq x x)).success;
    in
    {
      expr = {
        parentRefuses = !(ok handSetFacts.parentOf."top/deep");
        nodesRefuse = !(ok handSetFacts.nodes);
        siblingParentRefuses = !(ok handSetFacts.parentOf."top/ctl");
        # WITNESS, same record: the chain really is set, and to a real node, so honouring it would
        # have gone silently wrong.
        chainIsSetToSomethingElse = handSetEval.config.aspects.top.deep.meta.aspect-chain;
        # CONTROL: the refusal is the facts', not the tree's; a clean sibling still keys.
        siblingKey = aspects.key handSetEval.config.aspects.top.ctl;
      };
      expected = {
        parentRefuses = true;
        nodesRefuse = true;
        siblingParentRefuses = true;
        chainIsSetToSomethingElse = [ "real" ];
        siblingKey = "top/ctl";
      };
    };

  # ── the node id ──────────────────────────────────────────────────────────────────────────────
  flake.tests.graph-facts.test-node-id-is-the-walk-key-not-the-minted-key = {
    expr = {
      guardLeafId = builtins.elem "top/g" facts.nodes;
      # The guard's TERM key is a content address, so it can never name the node.
      termGuardKeyIsContentAddressed = lib.hasPrefix "guard:" (aspects.guardKey flat."top/g");
      # Its declaration key is its declared path, which renders as the walk key does.
      declaredGuardKeyIsTheWalkKey = aspects.key flat."top/g" == "top/g";
      # CONTROL: for a PLAIN aspect the declaration key and the walk key coincide too.
      mintedPlainKeyIsTheWalkKey = aspects.key flat."infra/networking/dns" == "infra/networking/dns";
    };
    expected = {
      guardLeafId = true;
      termGuardKeyIsContentAddressed = true;
      declaredGuardKeyIsTheWalkKey = true;
      mintedPlainKeyIsTheWalkKey = true;
    };
  };

  flake.tests.graph-facts.test-node-id-is-origin-qualified = {
    expr = {
      raw = sorted originFacts.nodes;
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
        "acme/top/deeper"
        "acme/top/deeper/wf2"
        "acme/top/g"
        "acme/top/gf"
        "acme/top/w"
        "acme/top/wf"
      ];
      strippedEqualsRegistry = true;
      differBeforeStripping = true;
      emptyOriginEqualsRegistryUnstripped = true;
      qualifiedParent = "acme/top";
      qualifiedInclude = [ "acme/infra/networking/dns" ];
    };
  };

  # ── TOTALITY — every node has an answer in every relation ────────────────────────────────────
  flake.tests.graph-facts.test-relations-are-total-over-nodes = {
    expr = {
      # The node count is stated exactly, so the set equalities below cannot pass by both of their
      # sides going empty.
      nodeCount = builtins.length facts.nodes;
      parentDomain = sorted (builtins.attrNames facts.parentOf) == sorted facts.nodes;
      includesDomain = sorted (builtins.attrNames facts.includesOf) == sorted facts.nodes;
      foreignDomain = sorted (builtins.attrNames facts.foreignIncludesOf) == sorted facts.nodes;
      unresolvedDomain = sorted (builtins.attrNames facts.unresolvedIncludesOf) == sorted facts.nodes;
      sitesDomain = sorted (builtins.attrNames facts.includeSitesOf) == sorted facts.nodes;
      # `nodeIdOf` is keyed by LOCAL key, so under the empty origin its values are the node set.
      nodeIdOfRange = sorted (builtins.attrValues facts.nodeIdOf) == sorted facts.nodes;
      nodeDataDomain = sorted (builtins.attrNames facts.nodeData) == sorted facts.nodes;
      # A ROOT is present in the relation with an explicit `null`, never absent from it.
      rootIsPresent = facts.parentOf ? "top";
      rootAnswerIsNull = facts.parentOf."top" == null;
      # And the node values are the aspect values unchanged.
      nodeDataIsTheAspectValue = facts.nodeData."infra/networking/dns" == flat."infra/networking/dns";
    };
    expected = {
      nodeCount = 11;
      parentDomain = true;
      includesDomain = true;
      foreignDomain = true;
      unresolvedDomain = true;
      sitesDomain = true;
      nodeIdOfRange = true;
      nodeDataDomain = true;
      rootIsPresent = true;
      rootAnswerIsNull = true;
      nodeDataIsTheAspectValue = true;
    };
  };

  # ── the INCLUDES relation ────────────────────────────────────────────────────────────────────
  # An `includes` list holds REFERENCES and INLINE CONTENT. Only a reference is an edge; inline
  # content has no node to reach, because the walk never descends into `includes`.
  flake.tests.graph-facts.test-includes-resolve-references-to-node-ids = {
    expr = {
      byValue = refFacts.includesOf."app";
      # A by-value reference produces an edge and nothing unresolved, in the same record.
      byValueUnresolved = refFacts.unresolvedIncludesOf."app";
      # A FOREIGN keyRef qualifies with the REFERENT's origin, not the reading container's — that
      # is what makes it a cross-source reference — and is not checkable here, so not refused. It is
      # therefore NOT an edge of this graph: `includesOf` carries what this library checked, and the
      # reference itself is published beside it.
      foreignKeyRef = foreignFacts.includesOf."acme/app";
      foreignKeyRefIsPublished = foreignFacts.foreignIncludesOf."acme/app";
      # CARDINALITY, so neither side can pass by having gone empty: the foreign fixture declares
      # exactly one include, and it is accounted for exactly once across the two relations.
      foreignDeclaredCount =
        builtins.length foreignFacts.includesOf."acme/app"
        + builtins.length foreignFacts.foreignIncludesOf."acme/app"
        + builtins.length foreignFacts.unresolvedIncludesOf."acme/app";
      # A LOCAL, sound keyRef resolves. This is the control for the refusal below.
      localKeyRef = localGoodFacts.includesOf."acme/app";
      # CONTROL: a node with no includes is PRESENT in both relations with empty lists, so an
      # absent key and a declared-nothing node are not the same answer.
      emptyIsPresent = refFacts.includesOf ? "lib/base";
      emptyIsEmpty = refFacts.includesOf."lib/base";
    };
    expected = {
      byValue = [ "lib/base" ];
      byValueUnresolved = [ ];
      foreignKeyRef = [ ];
      foreignKeyRefIsPublished = [
        {
          origin = [ "other" ];
          path = [
            "lib"
            "base"
          ];
          key = "lib/base";
        }
      ];
      foreignDeclaredCount = 1;
      localKeyRef = [ "acme/lib/base" ];
      emptyIsPresent = true;
      emptyIsEmpty = [ ];
    };
  };

  # ★ THE SHIPPED INLINE SHAPES ARE PUBLISHED, NOT REFUSED AND NOT DROPPED. Each of these five is a
  # shape the library ships and tests; a refusal on any of them would be a refusal whose repair
  # advice is "undo a feature you were invited to use".
  flake.tests.graph-facts.test-inline-include-content-is-published-not-refused = {
    expr = {
      # Deferred shapes, aspect literals and a guard record, none of them an edge…
      edges = inlineFacts.includesOf."app";
      # …and every one of their positions is stated rather than lost.
      unresolvedPositions = inlineFacts.unresolvedIncludesOf."app";
      # The whole relation EVALUATES — the reading that used to throw.
      relationEvaluates = caught (builtins.deepSeq inlineFacts.includesOf true);
      # The DEFAULT path too: a bare closure with the opt-in OFF is wrapped by the type, and is
      # still inline content rather than an edge.
      defaultWrappedEdges = wrappedIncludeFacts.includesOf."app";
      defaultWrappedUnresolved = wrappedIncludeFacts.unresolvedIncludesOf."app";
      # WITNESS: the elements really are there to be indexed back to, so "unresolved" names
      # something present rather than covering for an empty list.
      declaredCount = builtins.length inlineEval.config.aspects.app.includes;
    };
    expected = {
      edges = [ ];
      unresolvedPositions = [
        0
        1
        2
        3
        4
      ];
      relationEvaluates = true;
      defaultWrappedEdges = [ ];
      defaultWrappedUnresolved = [ 0 ];
      declaredCount = 5;
    };
  };

  # ★ NO INCLUDE EDGE TARGET IS OUTSIDE `nodes` — UNIVERSALLY, with no local-origin hedge. The claim
  # was once scoped to local-origin fixtures because a FOREIGN keyRef put its uncheckable target into
  # `includesOf` and the property was simply false for it. That target is now published as a
  # REFERENCE in `foreignIncludesOf` — `foreignKeyRef` above asserts `includesOf` holds `[ ]` for it —
  # so this relation carries only what the library checked and the property is total over it.
  #
  # The fabrication this repairs, in its general form: an inline aspect literal carries a `.key`, but
  # that key is its MERGE position under `includes` (`app/includes/0`), so taking the `? key` branch
  # on shape alone minted an id for a node that does not exist. Left standing it does not merely
  # mislead — `gen-graph.mkGraph` unions edge targets into its node set, so the fabricated id would
  # have been ADMITTED as a node.
  flake.tests.graph-facts.test-no-include-edge-names-a-non-node = {
    expr = {
      # Across EVERY fixture in this suite, foreign ones included. The scope used to be "every
      # LOCAL-origin fixture" because a foreign keyRef put a non-node into `includesOf` and the
      # property was simply false for it; the relation now carries only what this library checked,
      # so the claim is universal and the fixtures that used to be excluded are the ones that
      # discriminate.
      inlineTargetsAreNodes = builtins.all (t: builtins.elem t inlineFacts.nodes) (
        lib.concatLists (builtins.attrValues inlineFacts.includesOf)
      );
      refTargetsAreNodes = builtins.all (t: builtins.elem t refFacts.nodes) (
        lib.concatLists (builtins.attrValues refFacts.includesOf)
      );
      wrappedTargetsAreNodes = builtins.all (t: builtins.elem t wrappedIncludeFacts.nodes) (
        lib.concatLists (builtins.attrValues wrappedIncludeFacts.includesOf)
      );
      # The specific id that used to be fabricated, named so this cannot pass by the relation
      # having gone empty everywhere.
      fabricatedIdIsAbsent =
        !(builtins.elem "app/includes/3" (lib.concatLists (builtins.attrValues inlineFacts.includesOf)));
      foreignTargetsAreNodes = builtins.all (t: builtins.elem t foreignFacts.nodes) (
        lib.concatLists (builtins.attrValues foreignFacts.includesOf)
      );
      sugarTargetsAreNodes = builtins.all (t: builtins.elem t sugarSelfFacts.nodes) (
        lib.concatLists (builtins.attrValues sugarSelfFacts.includesOf)
      );
      twoSegTargetsAreNodes = builtins.all (t: builtins.elem t twoSegFacts.nodes) (
        lib.concatLists (builtins.attrValues twoSegFacts.includesOf)
      );
      # WITNESS: a real edge IS emitted somewhere in the suite, so "all targets are nodes" is not
      # vacuously true over an empty relation.
      aRealEdgeExists = refFacts.includesOf."app" == [ "lib/base" ];
      # CARDINALITY, read off the relation that exists either side of the change: each of the three
      # fixtures the widening added contributes ZERO checked edges. Paired with `aRealEdgeExists`
      # above — which is non-zero — this says the universal claim holds over a relation that is not
      # empty everywhere, and says exactly where the foreign ones went from.
      foreignEdgeCounts = map (f: builtins.length (lib.concatLists (builtins.attrValues f.includesOf))) [
        foreignFacts
        sugarSelfFacts
        twoSegFacts
      ];
    };
    expected = {
      inlineTargetsAreNodes = true;
      refTargetsAreNodes = true;
      wrappedTargetsAreNodes = true;
      fabricatedIdIsAbsent = true;
      foreignTargetsAreNodes = true;
      sugarTargetsAreNodes = true;
      twoSegTargetsAreNodes = true;
      aRealEdgeExists = true;
      foreignEdgeCounts = [
        0
        0
        0
      ];
    };
  };

  # ── the ONE refusal that survives ────────────────────────────────────────────────────────────
  # A keyRef is a REFERENCE by construction, so a bad one is an error rather than an ambiguity — and
  # a keyRef carrying THIS tree's origin is checkable. Left unrefused it does not merely vanish:
  # `gen-graph.mkGraph` unions edge targets into its node set, so the typo would be ADMITTED as a
  # node, widening the graph past the membership predicate.
  flake.tests.graph-facts.test-dangling-local-keyref-refuses-by-name = {
    expr = {
      localDanglingRefuses = !(caught (builtins.head localBadFacts.includesOf."acme/app"));
      # NEGATIVE CONTROL, same predicate, same run: the sound local keyRef does NOT refuse.
      localSoundDoesNotRefuse = caught (builtins.head localGoodFacts.includesOf."acme/app");
      # SECOND CONTROL: a FOREIGN keyRef to an equally absent target does not refuse either, so the
      # refusal is keyed on locality and not merely on absence. It is read through
      # `foreignIncludesOf`, which is where such a reference is published — forcing it runs `resolve`
      # on the element exactly as forcing `includesOf` did, so this is the same code path under a
      # different relation and not a weaker check.
      foreignAbsentDoesNotRefuse = caught (builtins.head foreignFacts.foreignIncludesOf."acme/app");
      messageNamesTheNode = lib.hasInfix "'acme/app'" danglingMsg;
      messageNamesTheTarget = lib.hasInfix "'acme/lib/bsae'" danglingMsg;
      messageNamesThePosition = lib.hasInfix "position 0" danglingMsg;
    };
    expected = {
      localDanglingRefuses = true;
      localSoundDoesNotRefuse = true;
      foreignAbsentDoesNotRefuse = true;
      messageNamesTheNode = true;
      messageNamesTheTarget = true;
      messageNamesThePosition = true;
    };
  };

  # ── the DECLARATION refusal ─────────────────────────────────────────────────────────────────
  # A KEYED by-value element that names no node of this tree and was not written at an include
  # position is a declaration whose target is missing. Published as a position it would read
  # exactly like inline content, and neither consumer — one looking for broken references, one
  # looking for content — could tell which it got.
  flake.tests.graph-facts.test-dangling-declaration-refuses-by-name = {
    expr = {
      # G1: another tree's node, alone; then after inline content in a first definition, at a
      # nested aspect, and through `mkMerge`.
      otherTreeNode = declRead { } [ (one [ oa.elsewhere.thing ]) ];
      otherTreeSecondDef = declRead { } [
        baseMod
        (one [ (lit "a") ])
        (one [ oa.elsewhere.thing ])
      ];
      otherTreeNested = declRead { id = "top/deeper"; } [
        (at [ "top" "deeper" ] [ (lit "a") ])
        (at [ "top" "deeper" ] [ oa.elsewhere.thing ])
      ];
      otherTreeMkMerge = declRead { } [
        (one (
          genMerge.mkMerge [
            [ (lit "a") ]
            [ oa.elsewhere.thing ]
          ]
        ))
      ];
      # d2: another tree's node NAMED `includes`. Its key alone renders an include position; its
      # chain does not, and the chain is what decides.
      otherTreeNodeNamedIncludes = declRead { } [ (one [ oa.elsewhere.renamed ]) ];
      # G2: a key set by hand outside the include-position space, alone, after content, and with
      # `includes` only as its FIRST segment (where a root aspect named `includes` would sit).
      handKey = declRead { } [
        (one [
          {
            key = "no/such";
            nixos.networking.domain = "k";
          }
        ])
      ];
      handKeySecondDef = declRead { } [
        (one [ (lit "a") ])
        (one [
          {
            key = "no/such";
            nixos.networking.domain = "k";
          }
        ])
      ];
      handKeyRootIncludesSegment = declRead { } [
        (one [
          {
            key = "includes/zz";
            nixos.networking.domain = "z";
          }
        ])
      ];
      # A same-tree member whose `name` moves its key off its walk id is NOT refused: its key names
      # no node by walk key, but `prelude.resolve` locates it by the key field and its stamp and key
      # are the canonical entry's (den-hoag-7gp66), so it is an edge (`includesOf.app` = `[ "base" ]`,
      # pinned in `test-references-resolve-by-identity`).
      renamedMember = declRead { } [
        {
          config.aspects.base = {
            name = "Base";
            nixos.networking.domain = "b";
          };
        }
        ({ config, ... }: one [ config.aspects.base ])
      ];
      # G4: the refusal reaches every include relation of the node, and nothing else.
      includesOfRefuses = tryValue otherSecondDefFacts.includesOf.app;
      foreignIncludesOfRefuses = tryValue otherSecondDefFacts.foreignIncludesOf.app;
      parentOfStillReads = tryValue otherSecondDefFacts.parentOf.app;
      nodesStillRead = sorted (tryValue otherSecondDefFacts.nodes);
      # CONTROL: the planted value IS a node of its own tree, so "names no node of THIS tree" is the
      # fact refused rather than a value that names nothing anywhere.
      otherTreeNodes = sorted (aspects.graphFacts { } oa).nodes;
    };
    expected = {
      otherTreeNode = {
        u = "REFUSED";
        n = 1;
      };
      otherTreeSecondDef = {
        u = "REFUSED";
        n = 2;
      };
      otherTreeNested = {
        u = "REFUSED";
        n = 2;
      };
      otherTreeMkMerge = {
        u = "REFUSED";
        n = 2;
      };
      otherTreeNodeNamedIncludes = {
        u = "REFUSED";
        n = 1;
      };
      handKey = {
        u = "REFUSED";
        n = 1;
      };
      handKeySecondDef = {
        u = "REFUSED";
        n = 2;
      };
      handKeyRootIncludesSegment = {
        u = "REFUSED";
        n = 1;
      };
      renamedMember = {
        u = [ ];
        n = 1;
      };
      includesOfRefuses = "REFUSED";
      foreignIncludesOfRefuses = "REFUSED";
      parentOfStillReads = null;
      nodesStillRead = [
        "app"
        "lib"
        "lib/base"
      ];
      otherTreeNodes = [
        "elsewhere"
        "elsewhere/box"
        "elsewhere/renamed"
        "elsewhere/thing"
      ];
    };
  };

  # ── the REFERENCE refusal (den-hoag-zxgan) ──────────────────────────────────────────────────
  # A bare string is unconditionally a reference (den-hoag-2zjg1 TERM ruling), so a local-key
  # mismatch is always a refusal — the same shape as the by-value branch, never a fall-through to
  # inline content (a bare string has no `isIncludeContent` escape hatch to begin with).
  flake.tests.graph-facts.test-dangling-reference-refuses-by-name = {
    expr = {
      localDanglingRefuses = !(caught (builtins.head localBadStringFacts.includesOf."acme/app"));
      # NEGATIVE CONTROL, same predicate, same run: the sound local bare string does NOT refuse.
      localSoundDoesNotRefuse = caught (builtins.head localGoodStringFacts.includesOf."acme/app");
      # A bare string and the by-value form over the same target publish the SAME edge.
      stringAndByValueAgree =
        localGoodStringFacts.includesOf."acme/app" == localGoodValueFacts.includesOf."acme/app";
    };
    expected = {
      localDanglingRefuses = true;
      localSoundDoesNotRefuse = true;
      stringAndByValueAgree = true;
    };
  };

  # ── REFERENCES RESOLVE BY IDENTITY (den-hoag-7gp66 P1) ─────────────────────────────────────────
  # A by-value element and a bare identifier both resolve through `prelude.resolve` with this
  # library's `isCanonical` (stamp `id_hash` and key equal): membership is decided on the canonical
  # entry, never on the editable `.key` alone. Each refusal is caught here; its message is pinned on
  # the real path in `ci/tests-error.nix` (`includes-resolve`).
  flake.tests.graph-facts.test-references-resolve-by-identity = {
    expr = {
      # CONTROL: the instrument can read a refusal at all.
      controlThrowIsRefused = tryValue (throw "control");
      memberById = refRead { } (_: [ "lib/base" ]);
      memberByDeclaration = refRead { } (config: [ config.aspects.lib.base ]);
      memberByIdOrigin = refRead { providerPrefix = [ "acme" ]; } (_: [ "lib/base" ]);
      memberByDeclarationOrigin = refRead { providerPrefix = [ "acme" ]; } (config: [
        config.aspects.lib.base
      ]);
      # A member whose `name` moved its key off its walk key is still that member: located by the
      # key field through the index, verdict on the canonical entry.
      renamedMember =
        let
          ev = declEval { } [
            {
              config.aspects.base = {
                name = "Base";
                nixos.networking.domain = "b";
              };
            }
            ({ config, ... }: one [ config.aspects.base ])
          ];
        in
        tryValue (aspects.graphFacts { } ev.config.aspects).includesOf.app;
      # 6-c: a member re-keyed to spell another member. The key names a node (`app`) and the stamp
      # is base's, so it is refused; the key-only verdict made it a self-edge `[ "app" ]`.
      rekeyedMember = refRead { } (config: [ (config.aspects.lib.base // { key = "app"; }) ]);
      # gate C1: a stampless value naming a REAL member is "not this member", refused by name —
      # never an abort on the missing stamp. Handed to `graphFacts` directly: declared through the
      # module system, the include element's type re-mints `id_hash` from the value's own identity.
      stamplessRealMember =
        let
          a = (mkIncludes { elems = _: [ ]; }).config.aspects;
        in
        tryValue
          (aspects.graphFacts { } (
            a
            // {
              app = a.app // {
                includes = [ (removeAttrs a.lib.base [ "id_hash" ]) ];
              };
            }
          )).includesOf.app;
      # CONTROL, same construction: the stamped member handed over the same way resolves.
      stampedRealMemberDirect =
        let
          a = (mkIncludes { elems = _: [ ]; }).config.aspects;
        in
        tryValue
          (aspects.graphFacts { } (
            a
            // {
              app = a.app // {
                includes = [ a.lib.base ];
              };
            }
          )).includesOf.app;
      # A bare string naming nothing is refused, as it was before the move.
      bareNamingNothing = refRead { } (_: [ "lib/bsae" ]);
      # 6-d, B1 (i): another tree's value with the same origin and key carries the same stamp, so it
      # resolves to the LOCAL node — see the README's "References resolve by identity".
      otherTreeSameKey = refRead { } (_: [ collisionOtherEval.config.aspects.lib.base ]);
      # ...and the value served for that node is the LOCAL one: the foreign content is dropped.
      otherTreeSameKeyServes =
        let
          ev = mkIncludes { elems = _: [ collisionOtherEval.config.aspects.lib.base ]; };
          served = (aspects.graphFacts { } ev.config.aspects).nodeData."lib/base";
        in
        {
          local = served == ev.config.aspects.lib.base;
          foreign = served == collisionOtherEval.config.aspects.lib.base;
        };
      # CONTROL for 6-d: the foreign value shares the local node's stamp (and so its key).
      otherTreeSameStamp =
        collisionOtherEval.config.aspects.lib.base.id_hash == (mkIncludes { elems = _: [ ]; })
        .config.aspects.lib.base.id_hash;
    };
    expected = {
      controlThrowIsRefused = "REFUSED";
      memberById = [ "lib/base" ];
      memberByDeclaration = [ "lib/base" ];
      memberByIdOrigin = [ "acme/lib/base" ];
      memberByDeclarationOrigin = [ "acme/lib/base" ];
      renamedMember = [ "base" ];
      rekeyedMember = "REFUSED";
      stamplessRealMember = "REFUSED";
      stampedRealMemberDirect = [ "lib/base" ];
      bareNamingNothing = "REFUSED";
      otherTreeSameKey = [ "lib/base" ];
      otherTreeSameKeyServes = {
        local = true;
        foreign = false;
      };
      otherTreeSameStamp = true;
    };
  };

  # ★ CONTENT IS STILL CONTENT, however it was merged or copied. The same record is the control for
  # the refusal above: every row here carries a key, reaches the new branch, and must publish its
  # positions. Multi-definition lists, `mkMerge`, `mkBefore`, an `mkIf`-false drop and `name` all
  # move an element's merge position off its merged index; copied lists keep the key and chain of
  # where they were written.
  flake.tests.graph-facts.test-inline-content-is-content-across-definitions-and-copies = {
    expr = {
      single = declRead { } [ (one [ (lit "a") ]) ];
      twoDefs = declRead { } [
        (one [ (lit "a") ])
        (one [ (lit "b") ])
      ];
      mkMerge = declRead { } [
        (one (
          genMerge.mkMerge [
            [ (lit "a") ]
            [ (lit "b") ]
          ]
        ))
      ];
      mkIfDrop = declRead { } [
        (one [
          (genMerge.mkIf false (lit "x"))
          (lit "y")
        ])
      ];
      mkBefore = declRead { } [
        (one [ (lit "a") ])
        (one (genMerge.mkBefore [ (lit "b") ]))
      ];
      named = declRead { } [
        (one [
          {
            name = "firewall";
            nixos.networking.domain = "n";
          }
        ])
      ];
      described = declRead { } [
        (one [
          {
            description = "firewall";
            nixos.networking.domain = "n";
          }
        ])
      ];
      copiedSibling = declRead { } [
        (
          { config, ... }:
          {
            config.aspects.base.includes = [ (lit "s") ];
            config.aspects.app.includes = config.aspects.base.includes;
          }
        )
      ];
      copiedOtherTree = declRead { } [ (one oa.elsewhere.box.includes) ];
      nestedLiteral = declRead { } [ (one [ { includes = [ (lit "inner") ]; } ]) ];
      guardDefault = declRead { } [ (one [ (gv.vocab.whenEq [ "thimble" "name" ] "cortex" (lit "g")) ]) ];
      shapesTwoDefs = declRead { } [
        (one shapesA)
        (one shapesB)
      ];
      shapesTwoDefsNested =
        declRead
          {
            id = "top/deeper";
          }
          [
            (at [ "top" "deeper" ] shapesA)
            (at [ "top" "deeper" ] shapesB)
          ];
      twoDefsUnderOrigin = declRead { providerPrefix = [ "acme" ]; } [
        (one [ (lit "a") ])
        (one [ (lit "b") ])
      ];
      # A hand key INSIDE the include-position space is a caller write of an identity input, and the
      # aspect type, its one writer, refuses it (den-hoag-gywcg).
      forgedOwnPosition = declRead { } [
        (one [
          {
            key = "app/includes/zz";
            nixos.networking.domain = "f";
          }
        ])
      ];
    };
    expected = {
      single = {
        u = [ 0 ];
        n = 1;
      };
      twoDefs = {
        u = [
          0
          1
        ];
        n = 2;
      };
      mkMerge = {
        u = [
          0
          1
        ];
        n = 2;
      };
      mkIfDrop = {
        u = [ 0 ];
        n = 1;
      };
      mkBefore = {
        u = [
          0
          1
        ];
        n = 2;
      };
      named = {
        u = [ 0 ];
        n = 1;
      };
      described = {
        u = [ 0 ];
        n = 1;
      };
      copiedSibling = {
        u = [ 0 ];
        n = 1;
      };
      copiedOtherTree = {
        u = [ 0 ];
        n = 1;
      };
      nestedLiteral = {
        u = [ 0 ];
        n = 1;
      };
      guardDefault = {
        u = [ 0 ];
        n = 1;
      };
      shapesTwoDefs = {
        u = [
          0
          1
          2
          3
          4
          5
        ];
        n = 6;
      };
      shapesTwoDefsNested = {
        u = [
          0
          1
          2
          3
          4
          5
        ];
        n = 6;
      };
      twoDefsUnderOrigin = {
        u = [
          0
          1
        ];
        n = 2;
      };
      forgedOwnPosition = {
        u = "REFUSED";
        n = 1;
      };
    };
  };

  # References by value still resolve beside content: a member after content in another definition,
  # and a ROOT aspect named `includes`, whose key has that segment at index 0 only.
  flake.tests.graph-facts.test-member-declarations-resolve-beside-content = {
    expr =
      let
        facts =
          mods:
          let
            f = aspects.graphFacts { } (declEval { } mods).config.aspects;
          in
          {
            edges = f.includesOf.app;
            unresolved = f.unresolvedIncludesOf.app;
          };
      in
      {
        memberSecondDef = facts [
          baseMod
          (one [ (lit "a") ])
          ({ config, ... }: one [ config.aspects.lib.base ])
        ];
        rootNamedIncludes = facts [
          { config.aspects.includes.nixos.networking.domain = "i"; }
          ({ config, ... }: one [ config.aspects.includes ])
        ];
      };
    expected = {
      memberSecondDef = {
        edges = [ "lib/base" ];
        unresolved = [ 0 ];
      };
      rootNamedIncludes = {
        edges = [ "includes" ];
        unresolved = [ ];
      };
    };
  };

  # The references did not VANISH when they left `includesOf` — they are in the relation that names
  # them, one per fixture. Separate from the cell above on purpose: that one must fail with a legible
  # diff against a library without `foreignIncludesOf`, and a row reading a missing attribute aborts
  # the whole cell instead (`tryEval` cannot catch it), burying the claim it was written to make.
  flake.tests.graph-facts.test-foreign-references-are-published-not-dropped = {
    expr = {
      foreignRefCounts =
        map (f: builtins.length (lib.concatLists (builtins.attrValues f.foreignIncludesOf)))
          [
            foreignFacts
            sugarSelfFacts
            twoSegFacts
          ];
      # CONTROL: a fixture with no foreign reference publishes an empty relation, not a missing one.
      localOnlyRefCount = builtins.length (
        lib.concatLists (builtins.attrValues localGoodFacts.foreignIncludesOf)
      );
      localOnlyRelationIsPresent = localGoodFacts.foreignIncludesOf ? "acme/app";
    };
    expected = {
      foreignRefCounts = [
        1
        1
        1
      ];
      localOnlyRefCount = 0;
      localOnlyRelationIsPresent = true;
    };
  };

  # ★ THE TWO keyRef FORMS MUST NOT BE INDISTINGUISHABLE. Under the default empty provider prefix
  # the string sugar's origin (`[ "lib" ]`, its first segment) never equals the corpus's (`[ ]`), so
  # the sugar takes the FOREIGN arm and is never checked, while the structured form with an explicit
  # empty origin takes the LOCAL arm and is. Both used to render the same target string into the same
  # relation, so a consumer could not tell a checked edge from an unchecked one — this cell is the
  # discriminator, and it reads only relations that exist either side of the change so it fails with
  # a legible diff rather than an abort.
  flake.tests.graph-facts.test-the-two-keyref-forms-are-distinguishable = {
    expr = {
      viaSugar = sugarSelfFacts.includesOf."app";
      # CONTROL, same target, same fixture shape: the checked arm still emits its edge.
      viaStructured = structSelfFacts.includesOf."app";
      indistinguishable = sugarSelfFacts.includesOf."app" == structSelfFacts.includesOf."app";
      # CARDINALITY: the fixtures are the same size, so the difference is the arm and nothing else.
      sugarNodeCount = builtins.length sugarSelfFacts.nodes;
      structuredNodeCount = builtins.length structSelfFacts.nodes;
    };
    expected = {
      viaSugar = [ ];
      viaStructured = [ "lib/base" ];
      indistinguishable = false;
      sugarNodeCount = 3;
      structuredNodeCount = 3;
    };
  };

  # The same split at the prefix lengths the string sugar can never match. `keyRef`'s string arm
  # takes `head parts` as the origin, so the origin is ALWAYS one segment: at length 0 and at
  # length >= 2 the locality comparison is unconditionally false and the local refusal is
  # unreachable through the sugar. Both are read here, with the reference each publishes.
  flake.tests.graph-facts.test-string-sugar-is-foreign-at-every-prefix-length-but-one = {
    expr = {
      twoSegEdges = twoSegFacts.includesOf."acme/sub/app";
      twoSegRefs = twoSegFacts.foreignIncludesOf."acme/sub/app";
      # A single-segment sugar ref carries an EMPTY path, so its rendered target is a bare name in
      # the same string space as an unqualified node id.
      bareSegEdges = bareSegFacts.includesOf."app";
      bareSegRefs = bareSegFacts.foreignIncludesOf."app";
      # CONTROL: at length 1 the sugar DOES name a local node and the edge is checked and emitted.
      oneSegEdges = localGoodFacts.includesOf."acme/app";
      oneSegRefs = localGoodFacts.foreignIncludesOf."acme/app";
    };
    expected = {
      twoSegEdges = [ ];
      twoSegRefs = [
        {
          origin = [ "acme" ];
          path = [
            "sub"
            "nope"
          ];
          key = "sub/nope";
        }
      ];
      bareSegEdges = [ ];
      bareSegRefs = [
        {
          origin = [ "nope" ];
          path = [ ];
          key = "";
        }
      ];
      oneSegEdges = [ "acme/lib/base" ];
      oneSegRefs = [ ];
    };
  };

  # EVERY refusal renderer `lib/facts.nix` EXPORTS has both a catchability and a message assertion.
  # The reach is the exports, and stating it wider would overstate what this roster measures: it reads
  # `attrNames factsInternals`, so a renderer defined in this file's `let` but not exported, or one in
  # another library file, is outside it. `lib/cnf.nix`'s `cnfRefusal` is the library's only other
  # renderer and carries both assertion kinds in `ci/tests/cnf-refusal.nix`.
  # Stated as an assertion rather than left to review, because the gap this closes was exactly a
  # refusal that had neither: the check is that the set of renderers equals the set covered.
  flake.tests.graph-facts.test-every-refusal-renderer-is-covered = {
    expr = {
      renderers = sorted (
        builtins.filter (n: lib.hasSuffix "Refusal" n) (builtins.attrNames factsInternals)
      );
      # Each name below is exercised in this suite by BOTH a catchability assertion (on the real
      # path) and a message assertion (on the renderer); `declarationMemberRefusal`'s are in
      # ci/tests/instantiation-edge.nix, beside the relation they gate.
      covered = [
        "danglingIncludeRefusal"
        "declarationMemberRefusal"
        "includeSitesDepthRefusal"
        "memberKeyRefusal"
      ];
    };
    expected = {
      renderers = [
        "danglingIncludeRefusal"
        "declarationMemberRefusal"
        "includeSitesDepthRefusal"
        "memberKeyRefusal"
      ];
      covered = [
        "danglingIncludeRefusal"
        "declarationMemberRefusal"
        "includeSitesDepthRefusal"
        "memberKeyRefusal"
      ];
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

  # ── A MEMBER WITH NO `includes` READS AS THE TYPE'S DECLARED DEFAULT (den-hoag-fxrmd) ──
  # A directly-supplied registry bypasses the aspect type, so a hand-built member can lack the key
  # the type always supplies. `graphFacts` applies the type's own declared default (`includesDefault`)
  # rather than aborting uncatchably on `attribute 'includes' missing`.
  flake.tests.graph-facts.test-missing-includes-reads-declared-default =
    let
      bare = aspects.graphFacts { } {
        x = {
          name = "x";
        };
      };
      explicit = aspects.graphFacts { } {
        x = {
          name = "x";
          includes = [ ];
        };
      };
    in
    {
      expr = {
        # catchable and total: no include edges for x, and x is a node.
        missing = caught (builtins.deepSeq bare.includesOf null);
        nodes = bare.nodes;
        includesOf = bare.includesOf;
        foreignIncludesOf = bare.foreignIncludesOf;
        unresolvedIncludesOf = bare.unresolvedIncludesOf;
        # CONTROL: the explicit `[ ]` gives the same facts over the same member.
        sameAsExplicit =
          {
            inherit (bare)
              nodes
              parentOf
              includesOf
              foreignIncludesOf
              unresolvedIncludesOf
              ;
          } == {
            inherit (explicit)
              nodes
              parentOf
              includesOf
              foreignIncludesOf
              unresolvedIncludesOf
              ;
          };
        explicitNodes = explicit.nodes;
      };
      expected = {
        missing = true;
        nodes = [ "x" ];
        includesOf.x = [ ];
        foreignIncludesOf.x = [ ];
        unresolvedIncludesOf.x = [ ];
        sameAsExplicit = true;
        explicitNodes = [ "x" ];
      };
    };

  # ── A MEMBER KEY OF THE WRONG TYPE REFUSES BY NAME (den-hoag-rc4mb) ──
  # Every key `graphFacts` reads from a directly-supplied member with an assumed type: the aspect's own
  # `includes`, and an include element's `key`, `meta.aspect-chain` and (inline content) `includes`.
  # Each aborted past `tryEval` in a builtin before; each now refuses catchably. The message is
  # asserted on the real path in `ci/tests-error.nix` (`member-key-type`).
  flake.tests.graph-facts.test-member-key-of-wrong-type-refuses =
    let
      f =
        m:
        aspects.graphFacts { } {
          x = {
            name = "x";
          }
          // m;
        };
      content = {
        key = "x/includes/0";
        meta.aspect-chain = [
          "x"
          "includes"
        ];
      };
      refused = r: !(caught (builtins.deepSeq r.includeSitesOf null));
      msg = factsInternals.memberKeyRefusal "gen-aspects.includes (aspect 'x')" "includes" "a list" "s";
    in
    {
      expr = {
        includesString = refused (f {
          includes = "notalist";
        });
        includesSet = refused (f {
          includes.y = 1;
        });
        contentIncludes = refused (f {
          includes = [ (content // { includes = "notalist"; }) ];
        });
        keyInt = refused (f {
          includes = [ { key = 5; } ];
        });
        chainString = refused (f {
          includes = [ (content // { meta.aspect-chain = "x/includes"; }) ];
        });
        # The node set does not read `includes`, so it still answers.
        nodesAnswer = (f { includes = "notalist"; }).nodes;
        # CONTROLS, same predicate: well-formed inline content, `[ ]` and a missing `includes` pass.
        contentOk = refused (f {
          includes = [ (content // { includes = [ ]; }) ];
        });
        empty = refused (f {
          includes = [ ];
        });
        missing = refused (f { });
        messageNamesTheAspect = lib.hasInfix "(aspect 'x')" msg;
        messageNamesTheKey = lib.hasInfix "'includes' must be a list, not a string" msg;
      };
      expected = {
        includesString = true;
        includesSet = true;
        contentIncludes = true;
        keyInt = true;
        chainString = true;
        nodesAnswer = [ "x" ];
        contentOk = false;
        empty = false;
        missing = false;
        messageNamesTheAspect = true;
        messageNamesTheKey = true;
      };
    };

  # ── THE INCLUDE SITES: one ordered, classified relation over include positions ───────────────
  # `includeSitesOf.<id>` is every include position of a node, in declared order, classified local /
  # foreign / content (recursing into the element's own `includes`) / sealed. A consumer that
  # delivers inline content walks it, so it must never have to re-run the resolver.
  flake.tests.graph-facts.test-include-sites-classify-every-position-in-order =
    let
      mixed = aspects.graphFacts { } (sitesEval [
        {
          aspects.a.includes = [
            "b"
            (aspects.keyRef {
              origin = [ "acme" ];
              path = [ "ssh" ];
            })
            {
              nixos.marks = [ "i" ];
              includes = [
                "b"
                { nixos.marks = [ "deep" ]; }
              ];
            }
            hostFn
          ];
          aspects.b.nixos.marks = [ "b" ];
        }
      ]);
    in
    {
      expr = {
        a = mixed.includeSitesOf.a;
        # CONTROL: a node with no includes is present with an empty list.
        b = mixed.includeSitesOf.b;
      };
      expected = {
        a = [
          {
            kind = "local";
            target = "b";
          }
          {
            kind = "foreign";
            ref = {
              origin = [ "acme" ];
              path = [ "ssh" ];
              key = "ssh";
            };
          }
          {
            kind = "content";
            sites = [
              {
                kind = "local";
                target = "b";
              }
              {
                kind = "content";
                sites = [ ];
              }
            ];
          }
          { kind = "sealed"; }
        ];
        b = [ ];
      };
    };

  # ★ A SPLIT ASPECT'S COERCED PART IS CONTENT. `aspectType` turns a function definition that is one
  # of several definitions of an aspect into `{ includes = [ f ]; }`; that element is static content
  # and its own includes resolve. A `{ host, ... }:` element is SEALED. A split whose second
  # definition is `{ host, ... }:` makes the node itself a guard leaf, with no include sites.
  flake.tests.graph-facts.test-include-sites-split-aspect-shapes =
    let
      sites = mods: (aspects.graphFacts { } (sitesEval mods)).includeSitesOf.p;
      data = mods: (aspects.graphFacts { } (sitesEval mods)).nodeData.p;
      attr = {
        aspects.p.nixos.marks = [ "attr" ];
      };
      ssh = {
        aspects.ssh.nixos.marks = [ "ssh" ];
      };
    in
    {
      expr = {
        splitConfigFn = sites [
          attr
          ssh
          {
            aspects.p =
              { config, ... }:
              {
                nixos.marks = [ "fn" ];
                includes = [ "ssh" ];
              };
          }
        ];
        # CONTROL: the same function as the ONLY definition has no inline site; its include is the
        # node's own.
        singleConfigFn = sites [
          ssh
          {
            aspects.p =
              { config, ... }:
              {
                nixos.marks = [ "fn" ];
                includes = [ "ssh" ];
              };
          }
        ];
        sealedAtPosition = sites [ { aspects.p.includes = [ hostFn ]; } ];
        splitHostIsGuardLeaf = aspects.isGuardLeaf (data [
          attr
          { aspects.p = hostFn; }
        ]);
        splitHostSites = sites [
          attr
          { aspects.p = hostFn; }
        ];
        singleHostIsGuardLeaf = aspects.isGuardLeaf (data [ { aspects.p = hostFn; } ]);
        # CONTROL: a plain aspect is not a guard leaf.
        plainIsGuardLeaf = aspects.isGuardLeaf (data [ attr ]);
      };
      expected = {
        splitConfigFn = [
          {
            kind = "content";
            sites = [
              {
                kind = "local";
                target = "ssh";
              }
            ];
          }
        ];
        singleConfigFn = [
          {
            kind = "local";
            target = "ssh";
          }
        ];
        sealedAtPosition = [ { kind = "sealed"; } ];
        splitHostIsGuardLeaf = true;
        splitHostSites = [ ];
        singleHostIsGuardLeaf = true;
        plainIsGuardLeaf = false;
      };
    };

  # A DANGLING REFERENCE INSIDE INLINE CONTENT refuses only for a reader that descends into it. The
  # top-level relations of the same node, and the content site itself, still evaluate.
  flake.tests.graph-facts.test-include-sites-nested-dangling-refuses-only-when-read =
    let
      f = aspects.graphFacts { } (sitesEval [
        {
          aspects.a.includes = [
            {
              nixos.marks = [ "i" ];
              includes = [ "nope" ];
            }
          ];
        }
      ]);
      site = builtins.head f.includeSitesOf.a;
    in
    {
      expr = {
        nestedRefuses = !(caught (builtins.deepSeq site.sites null));
        kindEvaluates = caught (builtins.deepSeq site.kind null);
        topLevelRelationsEvaluate = caught (
          builtins.deepSeq [ f.includesOf f.foreignIncludesOf f.unresolvedIncludesOf ] null
        );
        unresolved = f.unresolvedIncludesOf.a;
      };
      expected = {
        nestedRefuses = true;
        kindEvaluates = true;
        topLevelRelationsEvaluate = true;
        unresolved = [ 0 ];
      };
    };

  # ★ SELF-REFERENTIAL INLINE CONTENT REFUSES BY NAME. `let s = { includes = [ s ]; }` has positions
  # without end; the recursion spends from `includeSitesMaxDepth` and throws catchably past it,
  # where a reader following the sites would otherwise run until memory is exhausted.
  flake.tests.graph-facts.test-include-sites-cyclic-content-refuses-by-name =
    let
      s = {
        nixos.marks = [ "s" ];
        includes = [ s ];
      };
      depthOf = sites: if sites == [ ] then 0 else 1 + depthOf (builtins.head sites).sites;
      cyclic = aspects.graphFacts { } (sitesEval [ { aspects.a.includes = [ s ]; } ]);
      # CONTROL, same predicate: content nested to depth 3 walks to the bottom.
      finite = aspects.graphFacts { } (sitesEval [
        {
          aspects.a.includes = [
            {
              includes = [
                {
                  includes = [ { nixos.marks = [ "deep" ]; } ];
                }
              ];
            }
          ];
        }
      ]);
      msg = factsInternals.includeSitesDepthRefusal "a" "0.0.0";
    in
    {
      expr = {
        cyclicRefuses = !(caught (depthOf cyclic.includeSitesOf.a));
        finiteDepth = depthOf finite.includeSitesOf.a;
        # The node's top-level relations do not descend, so they still answer.
        cyclicUnresolved = cyclic.unresolvedIncludesOf.a;
        budget = factsInternals.includeSitesMaxDepth;
        messageNamesTheNode = lib.hasInfix "'a'" msg;
        messageNamesThePosition = lib.hasInfix "position 0.0.0" msg;
        messageNamesTheBudget = lib.hasInfix "256" msg;
      };
      expected = {
        cyclicRefuses = true;
        finiteDepth = 3;
        cyclicUnresolved = [ 0 ];
        budget = 256;
        messageNamesTheNode = true;
        messageNamesThePosition = true;
        messageNamesTheBudget = true;
      };
    };

  # THE KEY → ID RELATION: a member named by its local key resolves to its origin-qualified id.
  flake.tests.graph-facts.test-node-id-of-qualifies-local-keys =
    let
      f = aspects.graphFacts { providerPrefix = [ "acme" ]; } (sitesEval [
        {
          aspects.a.inner.nixos.marks = [ "x" ];
        }
      ]);
    in
    {
      expr = {
        inherit (f) nodeIdOf;
        rangeIsNodes = sorted (builtins.attrValues f.nodeIdOf) == sorted f.nodes;
      };
      expected = {
        nodeIdOf = {
          a = "acme/a";
          "a/inner" = "acme/a/inner";
        };
        rangeIsNodes = true;
      };
    };

  # ★★ THE THREE RELATIONS ARE PROJECTIONS OF `includeSitesOf`, NOT A SECOND PASS BESIDE IT. Both
  # constructions give the same values, so no behavioural cell can separate them; this one reads the
  # construction. `resolve` is APPLIED at exactly one site (inside `sitesOf`), and the classification
  # pass the relations used to run on their own (`indexed` / `resolved` / `ofKind`) is gone. The
  # counter is shown live on a text with two applications, in the same record.
  flake.tests.graph-facts.test-relations-project-from-include-sites =
    let
      src = builtins.readFile ../../lib/facts.nix;
      code = lib.concatStringsSep "\n" (
        map (line: lib.head (lib.splitString "#" line)) (lib.splitString "\n" src)
      );
      lines = lib.splitString "\n";
      applies =
        text:
        builtins.length (
          builtins.filter (l: builtins.match ".*[^.a-zA-Z]resolve [a-z(].*" l != null) (lines text)
        );
      binds = name: builtins.any (l: builtins.match " *${name} *=.*" l != null) (lines code);
    in
    {
      expr = {
        resolveApplications = applies code;
        controlTwoApplications = applies "r = resolve id at elem;\nx // { r = resolve (idOf e.path) x.i x.elem; }";
        oldPassBindings = builtins.filter binds [
          "indexed"
          "resolved"
          "ofKind"
        ];
        # CONTROL: the predicate finds bindings that do exist.
        livePassBindings = builtins.filter binds [
          "sitesOf"
          "includeSitesOf"
        ];
      };
      expected = {
        resolveApplications = 1;
        controlTwoApplications = 2;
        oldPassBindings = [ ];
        livePassBindings = [
          "sitesOf"
          "includeSitesOf"
        ];
      };
    };
}
