# The instance relation's SOURCE DOOR (lib/instance.nix `instancesFor`; den-hoag-fkkzk, owner-ruled
# 2026-10-05, arm (d)): a source is refused iff it is a node id of the relation's own graph, never by
# its kind tag (ADR-0035). A framework entity whose kind is spelled like a tag gen mints is admitted;
# gen's own node and vertex ids are refused. The two STATED DIVERGENCES (ADR-0025 item 1) are pinned
# here too: an instance id from an earlier relation is admitted, and `instanceOf` alone refuses no
# identity-shaped source. The refusals' texts are `instance-relation-doors.test-source-own-*` in
# ci/tests-error.nix.
{
  aspects,
  genIdentity,
  genAlgebra,
  mkSchemaEval,
  ...
}:
let
  t = (genAlgebra.term genIdentity.hashIdentity).term;
  cnf.entityKinds = {
    host = true;
  };
  q = aspects.guard (aspects.pred.has "host") {
    description = t.concat [
      (t.lit "q-")
      (t.readCtx "host" [ ])
    ];
  };
  tree = (mkSchemaEval (cnf // { modules = [ { config.aspects.q = q; } ]; })).config.aspects;
  entityOf = kind: genIdentity.hashIdentity kind [ "name" ] (_: "web1");
  relOf =
    scopes:
    aspects.instancesFor cnf tree {
      suppliers = builtins.mapAttrs (_: s: { host = "h-${s.sources.host}"; }) (
        builtins.listToAttrs (
          map (s: {
            name = s.sources.host;
            value = s;
          }) (builtins.attrValues scopes)
        )
      );
      containment = { };
    } scopes;
  scopeAt = src: {
    members = [ "q" ];
    sources.host = src;
  };
  admittedBy = r: (builtins.tryEval (builtins.deepSeq r.reaches true)).success;
  admitted =
    src:
    admittedBy (relOf {
      n1 = scopeAt src;
    });
  genNodeId = aspects.aspectId (cnf.providerPrefix or [ ]) (aspects.graphFacts cnf tree).nodeData.q;
  # A vertex of a relation over `entity`: an EARLIER relation's id when handed alone, this relation's
  # own vertex when handed beside the scope that mints it.
  instanceId = builtins.head (
    builtins.attrNames (relOf { n1 = scopeAt (entityOf "entity"); }).vertices
  );
  # A tree whose reached node `p` is a checked guard and whose UNREACHED node `u` is the same guard
  # unchecked (never placed at an aspect position, so it has no identity).
  rawTree = {
    p =
      (aspects.aspectType { }).merge
        [ "p" ]
        [
          {
            file = "<p>";
            value = q;
          }
        ];
    u = q;
  };
  rawRelAt =
    src:
    aspects.instancesFor { } rawTree
      {
        suppliers = {
          ${src}.host = "h1";
        };
        containment = { };
      }
      {
        n1 = {
          members = [ "p" ];
          sources.host = src;
        };
      };
  mintAdmits =
    src:
    (builtins.tryEval (
      builtins.deepSeq
        (aspects.instanceOf { } { } {
          aspect = "A";
          context = {
            host = "h1";
          };
          sources = {
            host = src;
          };
        } q).id
        true
    )).success;
in
{
  flake.tests.source-door = {
    # A framework kind spelled like a tag gen mints is a framework kind. RED (at bc295e4, the
    # retired spelling list): each refused.
    test-framework-aspect = {
      expr = admitted (entityOf "aspect");
      expected = true;
    };
    test-framework-aspect-instance = {
      expr = admitted (entityOf "aspect-instance");
      expected = true;
    };
    test-framework-include-site = {
      expr = admitted (entityOf "include-site");
      expected = true;
    };
    test-framework-named-value = {
      expr = admitted (entityOf "named-value");
      expected = true;
    };
    test-framework-guard = {
      expr = admitted (entityOf "guard");
      expected = true;
    };
    test-entity-control = {
      expr = admitted (entityOf "entity");
      expected = true;
    };
    # A node of this relation's graph. RED (the membership check removed): each admitted.
    test-own-node-id-refused = {
      expr = admitted genNodeId;
      expected = false;
    };
    test-own-vertex-id-refused = {
      expr = admittedBy (relOf {
        n1 = scopeAt (entityOf "entity");
        n2 = scopeAt instanceId;
      });
      expected = false;
    };
    # STATED DIVERGENCE 1: an instance id minted by an EARLIER relation is no node of this one, so it
    # is admitted. RED (at bc295e4): refused by its `aspect-instance` tag.
    test-divergence-earlier-instance-id-admitted = {
      expr = admitted instanceId;
      expected = true;
    };
    # STATED DIVERGENCE 2: `instanceOf` alone holds no graph, so it refuses no identity-shaped source
    # by kind, gen's own node id included. RED (at bc295e4): all but `entity` refused.
    test-divergence-mint-refuses-no-kind = {
      expr = map mintAdmits [
        genNodeId
        instanceId
        (entityOf "aspect")
        (entityOf "aspect-instance")
        (entityOf "include-site")
        (entityOf "named-value")
        (entityOf "entity")
      ];
      expected = [
        true
        true
        true
        true
        true
        true
        true
      ];
    };
    # The controls' shapes: gen's node id IS an `aspect` id and the earlier vertex an
    # `aspect-instance` id, so the refusal and the admission above are about membership, not shape.
    test-own-node-id-shape = {
      expr = builtins.substring 0 7 genNodeId;
      expected = "aspect:";
    };
    test-instance-id-shape = {
      expr = builtins.substring 0 16 instanceId;
      expected = "aspect-instance:";
    };
    # den-hoag-biefe: the door forces no unreached node for a source of a kind other than `aspect`, so
    # an UNREACHED unchecked guard stays unread and the relation mints, as at bc295e4. RED (at
    # 09cb440, which forced every node's `aspectId`): refused.
    test-biefe-unreached-unchecked-guard-admitted = {
      expr = admittedBy (rawRelAt (entityOf "entity"));
      expected = true;
    };
    # ITS BOUND (ADR-0025 item 1, stated in lib/instance.nix): a source of kind `aspect` can be shown
    # to be no node only by minting every node's id, so there the unchecked guard refuses.
    test-biefe-bound-aspect-kind-source-forces-every-node = {
      expr = admittedBy (rawRelAt (entityOf "aspect"));
      expected = false;
    };
    # Its control: the reached node alone mints, so the refusal above is `u`'s.
    test-biefe-control-reached-alone-admitted = {
      expr = admittedBy (
        aspects.instancesFor { } (removeAttrs rawTree [ "u" ])
          {
            suppliers = {
              ${entityOf "entity"}.host = "h1";
            };
            containment = { };
          }
          {
            n1 = {
              members = [ "p" ];
              sources.host = entityOf "entity";
            };
          }
      );
      expected = true;
    };
  };
}
