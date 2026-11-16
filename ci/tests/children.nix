# `childrenOf` and `children` (lib/children.nix): a node's children as structured references, and the
# named include value over them. Ids are asserted by their RELATIONS, never by a literal: a bundle's id
# carries the source position of its `name` (identity design §2).
#
# Each cell carries the arm that discriminates it: the `RED` comment names the edit that turns it.
{
  aspects,
  mkSchemaEval,
  ...
}:
let
  inherit (aspects) guard pred children childrenOf;
  ks.couching.category = "class";
  marked = n: { couching.stitches = [ n ]; };
  try =
    v:
    let
      r = builtins.tryEval (builtins.deepSeq v v);
    in
    if r.success then r.value else "REFUSED";
  first = l: if builtins.isList l && l != [ ] then builtins.head l else "<none>";
  isBundle = n: builtins.match "@/includes/.*" n != null;

  treeAt =
    prefix: mods:
    (mkSchemaEval {
      keySemantics = ks;
      providerPrefix = prefix;
      modules = mods;
    }).config.aspects;
  cnfAt = prefix: {
    keySemantics = ks;
    providerPrefix = prefix;
  };
  cnf = cnfAt [ ];

  loom = {
    couching.stitches = [ "loom" ];
    warp = marked "warp";
    weft = marked "weft";
    gate = guard (pred.has "rope") (marked "gate");
  };
  # The bundle written inside the tree it enumerates.
  main =
    extra:
    treeAt [ ] [
      (
        { config, ... }:
        let
          ch = children cnf config.aspects;
        in
        {
          aspects = {
            inherit loom;
            bolt.skein = marked "skein";
            bare = marked "bare";
            p.includes = [ (ch [ "loom" ]) ];
            q.includes = [ (ch [ "loom" ]) ];
            r.includes = [ (ch [ "bolt" ]) ];
            e.includes = [ (ch [ "bare" ]) ];
          }
          // extra;
        }
      )
    ];
  factsOf = as: aspects.graphFacts cnf as;
  f = factsOf (main { });
  pB = first f.includesOf.p;

  far = treeAt [ "far" ] [ { aspects.loom = marked "far-loom" // { warp = marked "far-warp"; }; } ];
  sib = treeAt [ ] [ { aspects.loom = marked "sib-loom" // { warp = marked "warp"; }; } ];
  ghost = treeAt [ ] [ { aspects.loom = marked "g" // { ghost = marked "ghost"; }; } ];
  ab = treeAt [ "a" "b" ] [ { aspects.c = marked "c"; } ];
  a1 = treeAt [ "a" ] [ { aspects.b.c = marked "c"; } ];
  env = factsOf (main {
    s.includes = [ (children (cnfAt [ "far" ]) far [ "loom" ]) ];
    sb.includes = [ (children cnf sib [ "loom" ]) ];
  });
  inj = factsOf (main {
    i1.includes = [ (children (cnfAt [ "a" "b" ]) ab [ "c" ]) ];
    i2.includes = [ (children (cnfAt [ "a" ]) a1 [ "b" "c" ]) ];
  });
  spell = factsOf (main {
    sp.includes = [
      {
        name = builtins.toJSON {
          origin = [ ];
          path = [ "loom" ];
        };
        includes = [
          "loom/gate"
          "loom/warp"
          "loom/weft"
        ];
      }
    ];
  });
  # loom's children written in a second module, in the reverse of their attribute order
  flipped = factsOf (
    treeAt [ ] [
      (
        { config, ... }:
        {
          aspects.loom = {
            couching.stitches = [ "loom" ];
            gate = guard (pred.has "rope") (marked "gate");
          };
          aspects.p.includes = [ (children cnf config.aspects [ "loom" ]) ];
        }
      )
      {
        aspects.loom.weft = marked "weft";
        aspects.loom.warp = marked "warp";
      }
    ]
  );
  lazy = factsOf (main {
    loom = loom // {
      trap.couching.stitches = throw "an unread child's content";
    };
  });
in
{
  # RED: drop `name` from `children` (an anonymous bundle is a node per site, 0cmbt Q1): p and q differ.
  flake.tests.children.test-one-node-wherever-included = {
    expr = {
      same = pB == first f.includesOf.q;
      bundle = isBundle pB;
      members = f.includesOf.${pB} or "<none>";
      root = f.parentOf.${pB} or "<none>";
    };
    expected = {
      same = true;
      bundle = true;
      members = [
        "loom/gate"
        "loom/warp"
        "loom/weft"
      ];
      root = null;
    };
  };
  # RED: the same edit: no bundle is a node, so no two are told apart.
  flake.tests.children.test-another-parent-is-another-node = {
    expr = {
      parent = first f.includesOf.r != pB && isBundle (first f.includesOf.r);
      empty = first f.includesOf.e != pB && first f.includesOf.e != first f.includesOf.r && isBundle (first f.includesOf.e);
      emptyMembers = f.includesOf.${first f.includesOf.e} or "<none>";
    };
    expected = {
      parent = true;
      empty = true;
      emptyMembers = [ ];
    };
  };
  # RED: emit local strings instead of structured references: the far bundle's edge reads LOCAL `loom/warp`.
  flake.tests.children.test-another-origin-is-another-node-and-foreign = {
    expr = {
      distinct = first env.includesOf.s != first env.includesOf.p;
      foreign = env.foreignIncludesOf.${first env.includesOf.s} or "<none>";
      local = env.includesOf.${first env.includesOf.s} or "<none>";
    };
    expected = {
      distinct = true;
      foreign = [
        {
          key = "loom/warp";
          origin = [ "far" ];
          path = [
            "loom"
            "warp"
          ];
        }
      ];
      local = [ ];
    };
  };
  # Same origin and parent path, another tree: another class at one §2 key. RED: compare names only.
  flake.tests.children.test-another-tree-is-another-node = {
    expr = {
      distinct = first env.includesOf.sb != first env.includesOf.p;
      members = env.includesOf.${first env.includesOf.sb} or "<none>";
    };
    expected = {
      distinct = true;
      members = [ "loom/warp" ];
    };
  };
  # RED: name the bundle `render (origin ++ path)`: [a b]+[c] and [a]+[b c] become one node.
  flake.tests.children.test-name-is-injective-over-origin-and-path = {
    expr = first inj.includesOf.i1 != first inj.includesOf.i2 && isBundle (first inj.includesOf.i1);
    expected = true;
  };
  # One spelling at another `name` position is another node: identity is not the spelling.
  flake.tests.children.test-spelling-is-not-identity = {
    expr = first spell.includesOf.sp != first spell.includesOf.p;
    expected = true;
  };
  # RED: `isChild = isNestedAspect` drops the guard leaf; `isChild = isAttrs` adds `couching`, which
  # then refuses as a dangling reference.
  flake.tests.children.test-members-are-the-walks-children = {
    expr = map (r: r.key) (childrenOf cnf (main { }) [ "loom" ]);
    expected = [
      "loom/gate"
      "loom/warp"
      "loom/weft"
    ];
  };
  # RED: reverse the member list: the declared order is attribute order, whatever the module order.
  flake.tests.children.test-order-is-attribute-order = {
    expr = flipped.includesOf.${first flipped.includesOf.p} or "<none>";
    expected = [
      "loom/gate"
      "loom/warp"
      "loom/weft"
    ];
  };
  # RED: answer `[ ]` for an absent parent. The control is loom itself.
  flake.tests.children.test-absent-guard-and-class-parents-refuse = {
    expr = {
      absent = try (childrenOf cnf (main { }) [ "nope" ]);
      guardLeaf = try (childrenOf cnf (main { }) [ "loom" "gate" ]);
      classKey = try (childrenOf cnf (main { }) [ "loom" "couching" ]);
      container = try (childrenOf cnf (main { }) [ ]);
      control = builtins.length (try (childrenOf cnf (main { }) [ "loom" ]));
    };
    expected = {
      absent = "REFUSED";
      guardLeaf = "REFUSED";
      classKey = "REFUSED";
      container = "REFUSED";
      control = 3;
    };
  };
  # A child the including tree lacks is a dangling reference, refused where it is included.
  flake.tests.children.test-a-missing-child-refuses-where-included = {
    expr = {
      ghost = try (
        let
          g = factsOf (main { gh.includes = [ (children cnf ghost [ "loom" ]) ]; });
        in
        g.includesOf.${first g.includesOf.gh}
      );
      control = env.includesOf.${first env.includesOf.sb} or "<none>";
    };
    expected = {
      ghost = "REFUSED";
      control = [ "loom/warp" ];
    };
  };
  # RED: deepSeq the children in `childrenOf`: the facts then read `trap`'s throwing content.
  flake.tests.children.test-a-childs-content-stays-unread = {
    expr = try (lazy.includesOf.${first lazy.includesOf.p} or "<none>");
    expected = [
      "loom/gate"
      "loom/trap"
      "loom/warp"
      "loom/weft"
    ];
  };
}
