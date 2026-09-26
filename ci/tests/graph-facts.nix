# The published aspect-graph FACTS: the node set, the edge relations, the node values.
#
# THE ORACLE THIS SUITE EXISTS FOR is that the published parent is the node's OWN WALK POSITION and
# not a re-derivation from `meta`. Two readings must be discriminated against, not one:
#
#   * the bare `meta.aspect-chain or [ ]` join a framework would otherwise write, which answers ROOT
#     for a nested guard leaf, and
#   * the `meta`-dispatch that answer was first built as, which answers ROOT for a `wrapFn` node and
#     THROWS on a `wrapGatedFn` one.
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

  # ONE fixture, five node shapes. Three record a position under `meta` in three different ways —
  # a plain aspect under `meta.aspect-chain`, a guard record and a type-merge-wrapped bare fn under
  # `meta.loc` — and TWO record none that can be read as a position at all: `wrapFn` stamps
  # `meta.loc` from its SITING NAME, and `wrapGatedFn` defaults `meta` to `{ }`. Those last two are
  # the fixture's point: they are public constructors, and any construction that reads a position
  # out of `meta` gets them wrong.
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
            config.aspects.top.w =
              { host }:
              {
                nixos.networking.hostName = host.name;
              };
            config.aspects.top.wf = aspects.wrapFn { } "wf" (
              { host }:
              {
                nixos.networking.hostName = host.name;
              }
            );
            config.aspects.top.deeper.wf2 = aspects.wrapFn { } "wf2" (
              { host }:
              {
                nixos.networking.hostName = host.name;
              }
            );
            config.aspects.top.gf =
              aspects.wrapGatedFn
                {
                  functionArgs = {
                    host = false;
                  };
                }
                (
                  { host }:
                  {
                    nixos.networking.hostName = host.name;
                  }
                );
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
  metaDispatchParent =
    id:
    let
      v = flat.${id};
      isLeaf = (v.__guard or false) || (v.__isWrappedFn or false);
      position =
        if isLeaf then (v.meta or { }).loc or null else ((v.meta or { }).aspect-chain or [ ]) ++ [ v.name ];
    in
    if position == null then
      "<THREW: no position recorded>"
    else if builtins.length position <= 1 then
      null
    else
      lib.concatStringsSep "/" (lib.init position);

  # A node whose HELD chain contradicts its walk position. `meta.aspect-chain` is `mkDefault`, so a
  # hand-set chain wins in the substrate — and an earlier construction honoured it, producing a node
  # whose parent contradicted its own id.
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
      }
    ];
  };
  handSetFacts = aspects.graphFacts { } handSetEval.config.aspects;

  # Include-element fixtures. Every shape below is one the library SHIPS and TESTS.
  mkIncludes =
    {
      providerPrefix ? [ ],
      deferIncludeResolution ? false,
      ...
    }@args:
    mkSchemaEval (
      (removeAttrs args [ "elems" ])
      // {
        inherit providerPrefix deferIncludeResolution;
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
    deferIncludeResolution = true;
    elems = _: [
      (
        { host, ... }:
        {
          nixos.networking.hostName = host.name;
        }
      ) # raw closure
      {
        batteryFn =
          { host, ... }:
          {
            nixos.networking.hostName = host.name;
          };
        name = "batt";
      }
      {
        __isPolicy = true;
        name = "pol";
        fn = { host, ... }: [ ];
      }
      { nixos.networking.domain = "inline"; } # inline aspect literal
      (gv.vocab.whenEq [ "thimble" "name" ] "cortex" { nixos.networking.domain = "g"; }) # inline guard record
    ];
  };
  inlineFacts = aspects.graphFacts { } inlineEval.config.aspects;

  # The DEFAULT path: a bare closure with the opt-in OFF is wrapped as `__isWrappedFn` by the type.
  wrappedIncludeEval = mkIncludes {
    elems = _: [
      (
        { host, ... }:
        {
          nixos.networking.hostName = host.name;
        }
      )
    ];
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
  declarationMsg = factsInternals.danglingDeclarationRefusal "app" 1 "elsewhere/thing";

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
      deferIncludeResolution ? false,
    }:
    modules:
    mkSchemaEval {
      inherit providerPrefix deferIncludeResolution modules;
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
      deferIncludeResolution ? false,
    }:
    modules:
    let
      ev = declEval { inherit providerPrefix deferIncludeResolution; } modules;
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
      { host, ... }:
      {
        nixos.networking.hostName = host.name;
      }
    )
    {
      batteryFn =
        { host, ... }:
        {
          nixos.networking.hostName = host.name;
        };
      name = "batt";
    }
    (lit "inline")
  ];
  shapesB = [
    {
      __isPolicy = true;
      name = "pol";
      fn = { host, ... }: [ ];
    }
    (lit "inline2")
    (gv.vocab.whenEq [ "thimble" "name" ] "cortex" (lit "g"))
  ];

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
  # is substituted for the construction. The `wrapFn` and `wrapGatedFn` entries are what make the
  # `meta` dispatch distinguishable at all: under it, `top/wf` reads ROOT and `top/gf` throws.
  flake.tests.graph-facts.test-parent-is-the-walk-not-a-meta-read = {
    expr = {
      # SUBJECTS — public constructors whose `meta` cannot be read as a position.
      wrapFnParent = facts.parentOf."top/wf";
      wrapFnNestedParent = facts.parentOf."top/deeper/wf2";
      wrapGatedFnParent = facts.parentOf."top/gf";
      # …and what the `meta` dispatch answers for the same three, same fixture, same run.
      wrapFnUnderMetaDispatch = metaDispatchParent "top/wf";
      wrapFnNestedUnderMetaDispatch = metaDispatchParent "top/deeper/wf2";
      wrapGatedFnUnderMetaDispatch = metaDispatchParent "top/gf";
      # CONTROL: a type-merge-wrapped bare fn DOES carry a real `meta.loc`, so the dispatch agrees
      # with the walk on it. The predicate discriminates rather than disagreeing with everything.
      typeMergedFnParent = facts.parentOf."top/w";
      typeMergedFnUnderMetaDispatch = metaDispatchParent "top/w";
      # …and the guard leaf, where the BARE-CHAIN reader is the one that goes wrong.
      guardLeafParent = facts.parentOf."top/g";
      guardLeafUnderBareChain = bareChainParent "top/g";
      # SECOND CONTROL: a plain nested aspect agrees under all three readings.
      plainParent = facts.parentOf."infra/networking/dns";
      plainUnderBareChain = bareChainParent "infra/networking/dns";
      plainUnderMetaDispatch = metaDispatchParent "infra/networking/dns";
    };
    expected = {
      wrapFnParent = "top";
      wrapFnNestedParent = "top/deeper";
      wrapGatedFnParent = "top";
      wrapFnUnderMetaDispatch = null;
      wrapFnNestedUnderMetaDispatch = null;
      wrapGatedFnUnderMetaDispatch = "<THREW: no position recorded>";
      typeMergedFnParent = "top";
      typeMergedFnUnderMetaDispatch = "top";
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

  # A hand-set `meta.aspect-chain` no longer moves the edge. It is `mkDefault`, so the substrate
  # lets a user set it — but the id is the walk key, so honouring a divergent chain publishes an
  # edge between ids that do not relate. One source for both ends, or the disagreement is
  # expressible and silent.
  flake.tests.graph-facts.test-hand-set-chain-does-not-move-the-edge = {
    expr = {
      parentIsTheWalkPosition = handSetFacts.parentOf."top/deep";
      # WITNESS, same record: the chain really is set, and to a real node — so this is the case
      # where honouring it would have gone silently wrong rather than refused.
      chainIsSetToSomethingElse = handSetEval.config.aspects.top.deep.meta.aspect-chain;
      targetOfThatChainIsANode = builtins.elem "real" handSetFacts.nodes;
    };
    expected = {
      parentIsTheWalkPosition = "top";
      chainIsSetToSomethingElse = [ "real" ];
      targetOfThatChainIsANode = true;
    };
  };

  # ── the node id ──────────────────────────────────────────────────────────────────────────────
  flake.tests.graph-facts.test-node-id-is-the-walk-key-not-the-minted-key = {
    expr = {
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
      # A same-tree member whose `name` moves its key off its walk id is REFUSED: its key names no
      # node. A resolver that checks membership on the canonical entry (den-hoag-7gp66) makes it an
      # edge, and this row is the one that flips.
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
      messageNamesTheNode = lib.hasInfix "'app'" declarationMsg;
      messageNamesTheKey = lib.hasInfix "'elsewhere/thing'" declarationMsg;
      messageNamesThePosition = lib.hasInfix "position 1" declarationMsg;
      # Content never reaches this branch, so the repair must not tell the caller to write it.
      messageDoesNotAdviseInline = !(lib.hasInfix "inline" declarationMsg);
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
        u = "REFUSED";
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
      messageNamesTheNode = true;
      messageNamesTheKey = true;
      messageNamesThePosition = true;
      messageDoesNotAdviseInline = true;
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
      shapesTwoDefs = declRead { deferIncludeResolution = true; } [
        (one shapesA)
        (one shapesB)
      ];
      shapesTwoDefsNested =
        declRead
          {
            id = "top/deeper";
            deferIncludeResolution = true;
          }
          [
            (at [ "top" "deeper" ] shapesA)
            (at [ "top" "deeper" ] shapesB)
          ];
      twoDefsUnderOrigin = declRead { providerPrefix = [ "acme" ]; } [
        (one [ (lit "a") ])
        (one [ (lit "b") ])
      ];
      # A hand key INSIDE the include-position space claims to be content, and is: nothing can be a
      # node there, so the forger gains nothing.
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
        u = [ 0 ];
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
      # path) and a message assertion (on the renderer).
      covered = [
        "danglingDeclarationRefusal"
        "danglingIncludeRefusal"
      ];
    };
    expected = {
      renderers = [
        "danglingDeclarationRefusal"
        "danglingIncludeRefusal"
      ];
      covered = [
        "danglingDeclarationRefusal"
        "danglingIncludeRefusal"
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
}
