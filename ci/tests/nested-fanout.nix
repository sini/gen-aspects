# Nested fan-out over the bound entities' descendants (lib/instance.nix `instancesFor`; den-hoag-8g2rn,
# rulings 7 and 13, and the 8g2rn rulings S3c, T1 and K-c amended to SHADOW). Descendants are derived
# from the one-step `containment`; a nested parametric include fans out at the MEET of its vertex's
# tuple and the reading node's, through a level only when the aspect takes that level's coordinate;
# argument bindings inherit down containment, and a re-declared one shadows. The door texts are
# `instance-relation-doors` in ci/tests-error.nix; what `project` delivers is gen-delivery's.
#
# Containment: a ⊃ u1 ⊃ d1, a ⊃ u2 ⊃ d2. Nodes: n (host a), m (a, u1), mu2 (a, u2), mu1only (u1).
# The REDs named per cell were driven against den-hoag-8g2rn spec v1.1's prototype ("v1.1") and the
# arms in reports/den-hoag-8g2rn-spec-gate-v1.probes (den-ag-design).
{
  aspects,
  genIdentity,
  mkSchemaEval,
  ...
}:
let
  inherit (aspects) guard pred;
  has = pred.has;
  src = n: genIdentity.hashIdentity "entity" [ "name" ] (_: n);
  names = [
    "a"
    "u1"
    "u2"
    "d1"
    "d2"
    "s0"
    "kf"
    "kf2"
    "kx"
  ];
  nameOf = builtins.listToAttrs (
    map (x: {
      name = src x;
      value = x;
    }) names
  );
  marked = n: { classOne.marks = [ n ]; };
  g =
    c: n: extra:
    guard c (marked n // extra);
  defs = {
    innerN = g (has "user") "innerN" { };
    innerH = g (has "host") "innerH" { };
    innerD = g (has "dot") "innerD" { };
    outerN = g (has "host") "outerN" { includes = [ "innerN" ]; };
    outerNb = g (has "host") "outerNb" { includes = [ "innerNb" ]; };
    innerNb = g (has "user") "innerNb" { };
    outerNc = g (has "host") "outerNc" { includes = [ "innerNc" ]; };
    innerNc = g (has "user") "innerNc" { };
    outerNd = g (has "host") "outerNd" { includes = [ "innerNd" ]; };
    innerNd = g (has "user") "innerNd" { };
    midU = g (has "user") "midU" { includes = [ "innerD" ]; };
    outer2 = g (has "host") "outer2" { includes = [ "midU" ]; };
    outerD = g (has "host") "outerD" { includes = [ "innerD" ]; };
    outerU = g (has "user") "outerU" { includes = [ "innerD" ]; };
    outerUH = g (has "user") "outerUH" { includes = [ "innerH" ]; };
    outerHU = guard (pred.all [
      (has "host")
      (has "user")
    ]) (marked "outerHU" // { includes = [ "innerD" ]; });
    innerHU = guard (pred.all [
      (has "host")
      (has "user")
    ]) (marked "innerHU");
    outerHU2 = g (has "host") "outerHU2" { includes = [ "innerHU" ]; };
    innerUD = guard (pred.all [
      (has "user")
      (has "dot")
    ]) (marked "innerUD");
    outerUD = g (has "host") "outerUD" { includes = [ "innerUD" ]; };
    innerUF = guard (pred.all [
      (has "user")
      (has "flavor")
    ]) (marked "innerUF");
    outerUFn = g (has "host") "outerUFn" { includes = [ "innerUF" ]; };
    innerDF = guard (pred.all [
      (has "dot")
      (has "flavor")
    ]) (marked "innerDF");
  };
  cnfOf =
    declared:
    {
      keySemantics.classOne.category = "class";
    }
    // (
      if declared then
        {
          entityKinds = {
            site = true;
            host = true;
            user = true;
            dot = true;
            flavor = false;
          };
        }
      else
        { }
    );
  treeOf = cnf: (mkSchemaEval (cnf // { modules = [ { config.aspects = defs; } ]; })).config.aspects;
  suppliers =
    builtins.listToAttrs (
      map
        (x: {
          name = src x.n;
          value.${x.key} = "v-${x.n}";
        })
        [
          {
            n = "a";
            key = "host";
          }
          {
            n = "u1";
            key = "user";
          }
          {
            n = "u2";
            key = "user";
          }
          {
            n = "d1";
            key = "dot";
          }
          {
            n = "d2";
            key = "dot";
          }
          {
            n = "s0";
            key = "site";
          }
          {
            n = "kx";
            key = "user";
          }
        ]
    )
    // {
      ${src "kf"}.flavor = "vanilla";
      ${src "kf2"}.flavor = "chocolate";
    };
  rec0 = parent: key: x: {
    inherit parent key;
    identity = src x;
    marked = false;
    bindings = { };
  };
  containment = {
    a = rec0 null "host" "a";
    u1 = rec0 "a" "user" "u1";
    u2 = rec0 "a" "user" "u2";
    d1 = rec0 "u1" "dot" "d1";
    d2 = rec0 "u2" "dot" "d2";
  };
  nodes = {
    n.host = src "a";
    m = {
      host = src "a";
      user = src "u1";
    };
    mu2 = {
      host = src "a";
      user = src "u2";
    };
    mu1only.user = src "u1";
    nk = {
      host = src "a";
      user = src "kx";
    };
    nf = {
      host = src "a";
      flavor = src "kf";
    };
    nfu = {
      host = src "a";
      user = src "u1";
      flavor = src "kf2";
    };
  };
  # the relation over `at` (node names), each reading `members`, under `cEdit` of the containment
  relOf =
    {
      members,
      at ? [ "n" ],
      declared ? true,
      cEdit ? (c: c),
    }:
    let
      cnf = cnfOf declared;
    in
    aspects.instancesFor cnf (treeOf cnf)
      {
        inherit suppliers;
        containment = cEdit containment;
      }
      (
        builtins.listToAttrs (
          map (nd: {
            name = nd;
            value = {
              inherit members;
              sources = nodes.${nd};
            };
          }) at
        )
      );
  # a vertex's label: its aspect, @, its formals' entity names in key order
  labelIn =
    r: i:
    "${builtins.head r.instantiates.${i}}@${
      builtins.concatStringsSep "," (
        map (k: nameOf.${r.vertices.${i}.formals.${k}}) (builtins.attrNames r.vertices.${i}.formals)
      )
    }";
  vertices = r: builtins.sort builtins.lessThan (map (labelIn r) (builtins.attrNames r.vertices));
  # node nd's nested edges of the vertex labelled `v`, by aspect, labelled
  nestedOf =
    r: nd: v:
    let
      i = builtins.head (builtins.filter (i: labelIn r i == v) (builtins.attrNames r.vertices));
    in
    builtins.mapAttrs (_: map (labelIn r)) r.nestedAt.${nd}.${i};
  declinedOf =
    r: nd: v:
    let
      i = builtins.head (builtins.filter (i: labelIn r i == v) (builtins.attrNames r.vertices));
    in
    r.declined.nestedAt.${nd}.${i};
  refused = x: !(builtins.tryEval (builtins.deepSeq x x)).success;
  withBindings = bs: c: builtins.mapAttrs (x: e: e // { bindings = bs.${x} or { }; }) c;
  shadowB = withBindings {
    a.flavor = src "kf";
    u1.flavor = src "kf2";
  };
  plainB = withBindings { a.flavor = src "kf"; };
  # siblings of outer's nested inner at n: entity names, and whether the instance ids ascend
  siblings =
    outer: cEdit:
    let
      r = relOf {
        members = [ outer ];
        inherit cEdit;
      };
      ids = builtins.head (builtins.attrValues r.nestedAt.n.${builtins.head r.reaches.n.${outer}});
    in
    {
      users = map (i: nameOf.${r.vertices.${i}.formals.user}) ids;
      idsAscending = ids == builtins.sort builtins.lessThan ids;
    };
  # renames an identifier, its identity fixed
  rename =
    from: to: c:
    let
      c' = builtins.mapAttrs (_: e: if e.parent == from then e // { parent = to; } else e) c;
    in
    removeAttrs c' [ from ] // { ${to} = c'.${from}; };
in
{
  flake.tests.nested-fanout = {
    # M1 (ruling 7). A {host} vertex at host a fans its {user} include over a's users, at the meet.
    # RED (base: a nested instance minted at the vertex's own tuple only): `["outerN@a"]`.
    test-direct-fans-out-at-the-host = {
      expr = vertices (relOf {
        members = [ "outerN" ];
      });
      expected = [
        "innerN@u1"
        "innerN@u2"
        "outerN@a"
      ];
    };
    # S3c. At a user's node the same vertex fans only that user: what the node binds is bound before
    # any fan-out is tried. RED (S1, fan-out at the vertex alone): m reaches innerN@u1 and innerN@u2.
    test-user-node-fans-its-own-user = {
      expr = nestedOf (relOf {
        members = [ "outerN" ];
        at = [ "m" ];
      }) "m" "outerN@a";
      expected.innerN = [ "innerN@u1" ];
    };
    # T1, TWO. {host} ⊃ {user} ⊃ {dot} at the host: the dots are below the user level, which the
    # {dot} aspect does not take, so each midU vertex declines innerD there (declared world), and lists
    # it in neither set under the open world (`project` refuses). RED (`seed-own`): innerD@d1, innerD@d2
    # are vertices at n.
    test-two-levels-host-declines-dots = {
      expr = {
        vertices = vertices (relOf {
          members = [ "outer2" ];
        });
        declared = declinedOf (relOf { members = [ "outer2" ]; }) "n" "midU@u1";
        open = declinedOf (relOf {
          members = [ "outer2" ];
          declared = false;
        }) "n" "midU@u1";
        atUser = vertices (relOf {
          members = [ "outer2" ];
          at = [ "m" ];
        });
      };
      expected = {
        vertices = [
          "midU@u1"
          "midU@u2"
          "outer2@a"
        ];
        declared = [ "innerD" ];
        open = [ ];
        atUser = [
          "innerD@d1"
          "midU@u1"
          "outer2@a"
        ];
      };
    };
    # T1, SKIP. {host} ⊃ {dot} at the host: declined, no dots; at a user's node, that user's dot.
    # RED (`seed-own`): d1, d2 at the host. RED (S1): d1, d2 at m.
    test-skip-a-level = {
      expr = {
        host = declinedOf (relOf { members = [ "outerD" ]; }) "n" "outerD@a";
        m = nestedOf (relOf {
          members = [ "outerD" ];
          at = [ "m" ];
        }) "m" "outerD@a";
      };
      expected = {
        host = [ "innerD" ];
        m.innerD = [ "innerD@d1" ];
      };
    };
    # T1, UD. A co-destructured {user, dot} aspect takes the user level, so it fans over the pairs.
    test-co-destructured-fans-over-pairs = {
      expr = nestedOf (relOf { members = [ "outerUD" ]; }) "n" "outerUD@a";
      expected.innerUD = [
        "innerUD@d1,u1"
        "innerUD@d2,u2"
      ];
    };
    # T1, rule (b) (gate C1): only levels BELOW the reading node's entities are crossed. A site above
    # host a, and the host level above a user-only node, cross nothing. RED (v1.1, every level on the
    # chain): the host node fans no user (`[]`), and mu1only declines innerD.
    test-levels-above-the-node-are-not-crossed = {
      expr = {
        site = nestedOf (relOf {
          members = [ "outerN" ];
          cEdit =
            c:
            c
            // {
              s0 = rec0 null "site" "s0";
              a = c.a // {
                parent = "s0";
              };
            };
        }) "n" "outerN@a";
        userOnly = vertices (relOf {
          members = [ "outerU" ];
          at = [ "mu1only" ];
        });
        userOnlyDot = vertices (relOf {
          members = [ "innerD" ];
          at = [ "mu1only" ];
        });
      };
      expected = {
        site.innerN = [
          "innerN@u1"
          "innerN@u2"
        ];
        userOnly = [
          "innerD@d1"
          "outerU@u1"
        ];
        userOnlyDot = [ "innerD@d1" ];
      };
    };
    # MULTI: {host, user} at (a, u1) ⊃ {dot}. RED (base): `["outerHU@a,u1"]` only.
    test-multi-entity-vertex = {
      expr = vertices (relOf {
        members = [ "outerHU" ];
        at = [ "m" ];
      });
      expected = [
        "innerD@d1"
        "outerHU@a,u1"
      ];
    };
    # MARK (ADR-0026): a marked u2 is no descendant of a. Control: unmarked, both users.
    test-mark-narrows = {
      expr = {
        marked = vertices (relOf {
          members = [ "outerN" ];
          cEdit =
            c:
            c
            // {
              u2 = c.u2 // {
                marked = true;
              };
            };
        });
        control = vertices (relOf {
          members = [ "outerN" ];
        });
      };
      expected = {
        marked = [
          "innerN@u1"
          "outerN@a"
        ];
        control = [
          "innerN@u1"
          "innerN@u2"
          "outerN@a"
        ];
      };
    };
    # MARKIN: at a marked u2's own node, its dot by both routes. RED (`seed-isect`): declined by both.
    test-marked-entity-own-node = {
      expr =
        let
          cEdit =
            c:
            c
            // {
              u2 = c.u2 // {
                marked = true;
              };
            };
        in
        {
          node = vertices (relOf {
            members = [ "innerD" ];
            at = [ "mu2" ];
            inherit cEdit;
          });
          vertex = vertices (relOf {
            members = [ "outerU" ];
            at = [ "mu2" ];
            inherit cEdit;
          });
        };
      expected = {
        node = [ "innerD@d2" ];
        vertex = [
          "innerD@d2"
          "outerU@u2"
        ];
      };
    };
    # DEEP: a descendant's tuple is its whole coordinate. RED (`seed-alpha`): `["outerHU2@a"]`.
    test-descendant-tuple-is-its-coordinate = {
      expr = vertices (relOf {
        members = [ "outerHU2" ];
      });
      expected = [
        "innerHU@a,u1"
        "innerHU@a,u2"
        "outerHU2@a"
      ];
    };
    # UPWARD-u: {user} ⊃ {host} at a user-only node is minted from the vertex's own tuple, never from
    # a descendant's chain. RED (`seed-beta`): innerH@a.
    test-no-upward-fan-out = {
      expr = vertices (relOf {
        members = [ "outerUH" ];
        at = [ "mu1only" ];
      });
      expected = [ "outerUH@u1" ];
    };
    # ORDER (ruling 13): siblings in identifier order, never the ids'. Renaming u1 to z1 (identity
    # fixed) moves it last; renaming d1 to zd1 interleaves deeper identifiers and moves nothing; other
    # aspect names move the ids, ascending under some and descending under others, and never the
    # siblings. RED (`seed-idorder`, siblings by identity): `ren` unmoved; (`seed-iid`, by instance id):
    # `users` differs under some name.
    test-siblings-in-identifier-order = {
      expr = {
        users = map (o: (siblings o (c: c)).users) [
          "outerN"
          "outerNb"
          "outerNc"
          "outerNd"
        ];
        idsAscending = map (o: (siblings o (c: c)).idsAscending) [
          "outerN"
          "outerNb"
          "outerNc"
          "outerNd"
        ];
        ren = (siblings "outerN" (rename "u1" "z1")).users;
        deep = (siblings "outerN" (rename "d1" "zd1")).users;
      };
      expected = {
        users = builtins.genList (_: [
          "u1"
          "u2"
        ]) 4;
        # outerNd's ids descend: an id-ordered list reads [ u2 u1 ] there
        idsAscending = [
          true
          true
          true
          false
        ];
        ren = [
          "u2"
          "u1"
        ];
        deep = [
          "u1"
          "u2"
        ];
      };
    };
    # SHARE (ruling 7's property): a nested instance minted from a descendant's coordinate is the
    # direct one, one id. RED (an own-binding tuple): two ids.
    test-nested-and-direct-share-an-id = {
      expr =
        let
          r = relOf {
            members = [
              "outerN"
              "innerN"
            ];
            at = [
              "n"
              "m"
            ];
          };
        in
        builtins.head (builtins.attrValues r.nestedAt.m.${builtins.head r.reaches.m.outerN})
        == [ (builtins.head r.reaches.m.innerN) ];
      expected = true;
    };
    # K-c, KARG: the binding a declares inherits to its users. RED (`seed-ka`, entity-only): `[]`.
    test-binding-inherits-down-containment = {
      expr = vertices (relOf {
        members = [ "innerUF" ];
        at = [ "nf" ];
        cEdit = plainB;
      });
      expected = [
        "innerUF@kf,u1"
        "innerUF@kf,u2"
      ];
    };
    # K-c amended to SHADOW (owner, 2026-10-05): u1 re-declares a's `flavor`, which shadows it for u1
    # and its descendants as a new binding id; u2 keeps a's, and its instance id is unchanged. Read at
    # the host node binding a's kf, directly (users), through a {host} vertex at the meet (nested), at
    # the user nodes binding no flavor (dots), and at a node binding u1's shadowing kf2. RED
    # (`seed-override`, the ancestor winning): u1 silently keeps kf, ids unchanged; RED (v1.1, refused):
    # the relation refuses; RED (the fold flipped alone, the rebind door over every key): users and
    # nested refuse at nf.
    test-a-re-declared-binding-shadows =
      let
        plain = relOf {
          members = [ "innerUF" ];
          at = [ "nf" ];
          cEdit = plainB;
        };
        shadow = relOf {
          members = [ "innerUF" ];
          at = [ "nf" ];
          cEdit = shadowB;
        };
        idOf = r: v: builtins.head (builtins.filter (i: labelIn r i == v) (builtins.attrNames r.vertices));
      in
      {
        expr = {
          users = vertices shadow;
          nested = nestedOf (relOf {
            members = [ "outerUFn" ];
            at = [ "nf" ];
            cEdit = shadowB;
          }) "nf" "outerUFn@a";
          dots = vertices (relOf {
            members = [ "innerDF" ];
            at = [
              "m"
              "mu2"
            ];
            cEdit = shadowB;
          });
          nodeU1 = vertices (relOf {
            members = [
              "innerD"
              "innerUF"
            ];
            at = [ "nfu" ];
            cEdit = shadowB;
          });
          u2IdUnchanged = idOf shadow "innerUF@kf,u2" == idOf plain "innerUF@kf,u2";
          u1IdNew = idOf shadow "innerUF@kf2,u1" != idOf plain "innerUF@kf,u1";
        };
        expected = {
          users = [
            "innerUF@kf,u2"
            "innerUF@kf2,u1"
          ];
          nested.innerUF = [
            "innerUF@kf2,u1"
            "innerUF@kf,u2"
          ];
          dots = [
            "innerDF@d1,kf2"
            "innerDF@d2,kf"
          ];
          nodeU1 = [
            "innerD@d1"
            "innerUF@kf2,u1"
          ];
          u2IdUnchanged = true;
          u1IdNew = true;
        };
      };
    # The node door (gate C3) and the rebind door refuse at every call, whatever the members: a node
    # overriding an inherited binding (nfu over a's kf) and a node whose descendant rebinds its user
    # (nk), each read with a member that fans out and one that does not. The shadowed coordinate is the
    # DEEPER entity's whatever the keys' names: with a re-keyed `zone`, which sorts after `user`, a node
    # binding u1's kf2 is admitted. RED (v1.1, no node door): `overrideNoFan` and `rebindNoFan` admit.
    # RED (the node's coordinates folded in key-name order): `deeperWins` refuses.
    test-node-doors-refuse-whatever-the-members = {
      expr = {
        overrideFan =
          refused
            (relOf {
              members = [ "innerD" ];
              at = [ "nfu" ];
              cEdit = plainB;
            }).reaches;
        overrideNoFan =
          refused
            (relOf {
              members = [ "innerUF" ];
              at = [ "nfu" ];
              cEdit = plainB;
            }).reaches;
        rebindFan =
          refused
            (relOf {
              members = [ "innerD" ];
              at = [ "nk" ];
            }).reaches;
        rebindNoFan =
          refused
            (relOf {
              members = [ "innerN" ];
              at = [ "nk" ];
            }).reaches;
        deeperWins =
          let
            zoned =
              c:
              shadowB (
                c
                // {
                  a = c.a // {
                    key = "zone";
                  };
                }
              );
          in
          vertices (
            aspects.instancesFor (cnfOf true) (treeOf (cnfOf true))
              {
                suppliers = suppliers // {
                  ${src "a"} = {
                    host = "v-a";
                    zone = "v-az";
                  };
                };
                containment = zoned containment;
              }
              {
                nz = {
                  members = [ "innerUF" ];
                  sources = {
                    zone = src "a";
                    user = src "u1";
                    flavor = src "kf2";
                  };
                };
              }
          );
      };
      expected = {
        overrideFan = true;
        overrideNoFan = true;
        rebindFan = true;
        rebindNoFan = true;
        deeperWins = [ "innerUF@kf2,u1" ];
      };
    };
  };
}
