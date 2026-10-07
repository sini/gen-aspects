# An aspect's identity is its declaring position as a structured value, and the type is its one
# writer (den-hoag-gywcg; identity design §1, §2; ADR-0034, ADR-0016 r5).
#
# - One injective rendering (`lib/path.nix`): a segment holding `/` or `%` is escaped, so `"f/x"`
#   beside `f.x` are two declarations at every reader, and the mint takes the path LIST.
# - A named include element is keyed by its declaring site, `<owner>/includes/<name>@<line>:<col>:<file>`,
#   never by its name alone and never by its merge position.
# - A caller write of `key`, `id_hash` or `meta.loc` refuses where it is read. A write EQUAL to the
#   type's own value is accepted: it mints nothing.
# The messages are the error plane's (`tests-error.nix`, `structured-key-writes`).
{
  lib,
  aspects,
  mkSchemaEval,
  genIdentity,
  genMerge,
  ...
}:
let
  id = aspects.aspectId [ ];
  ok = x: (builtins.tryEval (builtins.deepSeq x x)).success;
  distinct = xs: builtins.length xs == builtins.length (lib.unique xs);
  entity = n: genIdentity.hashIdentity "entity" [ "name" ] (_: n);
  gCnf = {
    keySemantics.classOne.category = "class";
    entityKinds.host = true;
  };
  tree = body: (mkSchemaEval (gCnf // { modules = [ { config.aspects = body; } ]; })).config.aspects;
  marked = m: aspects.guard (aspects.pred.has "host") { classOne.marks = [ m ]; };

  # `u` beside `f.x`: the separator pair (`u` = [ "f/x" ]) or its control (`u` = [ "f" "y" ]).
  sites =
    body: pu:
    let
      a = tree body;
      u = aspects.pathKey pu;
      v = aspects.pathKey [
        "f"
        "x"
      ];
      g = aspects.graphFacts gCnf a;
      U = lib.getAttrFromPath pu a;
      V = a.f.x;
    in
    {
      key = distinct [
        (aspects.key U)
        (aspects.key V)
      ];
      aspectId = distinct [
        (id U)
        (id V)
      ];
      factsNodes = distinct g.nodes;
      nodeData = builtins.length (builtins.attrNames g.nodeData);
      nodeIdOf = distinct [
        (g.nodeIdOf.${u} or "absent-u")
        (g.nodeIdOf.${v} or "absent-v")
      ];
      flatten = builtins.length (builtins.attrNames (aspects.flatten a));
      instanceVertices = builtins.length (
        builtins.attrNames
          (aspects.instancesFor gCnf a
            {
              suppliers = {
                ${entity "h1"}.host = "h1";
              };
              containment = { };
            }
            {
              n = {
                members = [
                  u
                  v
                ];
                sources.host = entity "h1";
              };
            }
          ).vertices
      );
    };
  apart = {
    key = true;
    aspectId = true;
    factsNodes = true;
    nodeData = 3;
    nodeIdOf = true;
    flatten = 3;
    instanceVertices = 2;
  };

  # Named include elements: `body` is one module's `owner.includes`.
  elemsOf =
    mods:
    map (e: {
      d = e.description;
      k = e.key;
      i = id e;
    }) (mkSchemaEval { modules = mods; }).config.aspects.owner.includes;
  byDescription = es: builtins.listToAttrs (map (e: lib.nameValuePair e.d e.i) es);
  mA.config.aspects.owner.includes = [
    {
      name = "tool";
      description = "A";
    }
  ];
  mB.config.aspects.owner.includes = [
    {
      name = "tool";
      description = "B";
    }
  ];

  # Caller writes on `selvage`, beside `bobbin`.
  w =
    write:
    tree {
      selvage = write;
      bobbin.classOne.marks = [ "b" ];
    };
  bobbinId = (w { }).bobbin.id_hash;
  # One named include element carrying `write`.
  el =
    write:
    builtins.head
      (tree {
        loom.includes = [
          (
            {
              name = "t";
              classOne.marks = [ "t" ];
            }
            // write
          )
        ];
      }).loom.includes;
in
{
  # ── one injective rendering ───────────────────────────────────────────────────────────────────
  flake.tests.structured-key.test-render-escapes-the-separator-and-parse-inverts-it = {
    expr = {
      slash = aspects.pathKey [ "f/x" ];
      nested = aspects.pathKey [
        "f"
        "x"
      ];
      percent = aspects.pathKey [ "a%2Fb" ];
      roundTrip = aspects.parsePath (
        aspects.pathKey [
          "a%2Fb"
          "c/d"
          "e"
        ]
      );
      # CONTROL: an ordinary path renders byte-identically to the raw join.
      plain = aspects.pathKey [
        "hardware"
        "cpu"
        "intel"
      ];
    };
    expected = {
      slash = "f%2Fx";
      nested = "f/x";
      percent = "a%252Fb";
      roundTrip = [
        "a%2Fb"
        "c/d"
        "e"
      ];
      plain = "hardware/cpu/intel";
    };
  };

  # `aspects."f/x"` beside `aspects.f.x` are two declarations at every reader that names a node:
  # before, they shared one key and one id, `nodeData` and `flatten` held 2 entries for 3 walk nodes,
  # and two guards minted ONE instance vertex.
  flake.tests.structured-key.test-a-separator-segment-is-its-own-declaration = {
    expr = {
      statics = sites {
        "f/x".classOne.marks = [ "slash" ];
        f.x.classOne.marks = [ "nested" ];
      } [ "f/x" ];
      guards = sites {
        "f/x" = marked "slash";
        f.x = marked "nested";
      } [ "f/x" ];
      # CONTROLS: two plainly distinct paths.
      staticsCtl =
        sites
          {
            f.y.classOne.marks = [ "y" ];
            f.x.classOne.marks = [ "x" ];
          }
          [
            "f"
            "y"
          ];
      guardsCtl =
        sites
          {
            f.y = marked "y";
            f.x = marked "x";
          }
          [
            "f"
            "y"
          ];
    };
    expected = {
      statics = apart // {
        instanceVertices = 0;
      };
      guards = apart;
      staticsCtl = apart // {
        instanceVertices = 0;
      };
      guardsCtl = apart;
    };
  };

  # keyRef's structured form names a segment holding `/`; its string sugar parses the escape back.
  flake.tests.structured-key.test-keyref-renders-through-the-one-rendering = {
    expr = {
      apart = distinct [
        (aspects.keyRef { path = [ "f/x" ]; }).key
        (aspects.keyRef {
          path = [
            "f"
            "x"
          ];
        }).key
      ];
      sugarSegment = (aspects.keyRef { path = "f%2Fx"; }).path;
      # CONTROL
      ctl = distinct [
        (aspects.keyRef {
          path = [
            "f"
            "y"
          ];
        }).key
        (aspects.keyRef {
          path = [
            "f"
            "x"
          ];
        }).key
      ];
    };
    expected = {
      apart = true;
      sugarSegment = [ "f/x" ];
      ctl = true;
    };
  };

  # ── a named include element is keyed by its declaring site ────────────────────────────────────
  # Two elements named `tool` in one list, and one each from two modules: two declarations, apart,
  # and swapping the modules moves neither id (ADR-0034's rider: the declaring position, never the
  # merged one). Before, both keyed `owner/includes/tool`, one identity.
  flake.tests.structured-key.test-same-named-include-elements-are-apart-by-site =
    let
      oneList = elemsOf [
        {
          config.aspects.owner.includes = [
            {
              name = "tool";
              description = "A";
            }
            {
              name = "tool";
              description = "B";
            }
          ];
        }
      ];
      ab = elemsOf [
        mA
        mB
      ];
      ba = elemsOf [
        mB
        mA
      ];
      ctl = elemsOf [
        {
          config.aspects.owner.includes = [
            {
              name = "toolA";
              description = "A";
            }
            {
              name = "toolB";
              description = "B";
            }
          ];
        }
      ];
    in
    {
      expr = {
        oneListApart = distinct (map (e: e.i) oneList) && distinct (map (e: e.k) oneList);
        twoModulesApart = distinct (map (e: e.i) ab);
        orderInvariant = byDescription ab == byDescription ba;
        keyedBySite = builtins.all (e: lib.hasPrefix "owner/includes/tool@" e.k) (oneList ++ ab);
        ctlApart = distinct (map (e: e.i) ctl);
      };
      expected = {
        oneListApart = true;
        twoModulesApart = true;
        orderInvariant = true;
        keyedBySite = true;
        ctlApart = true;
      };
    };

  # ── the type is the one writer of the identity inputs ─────────────────────────────────────────
  # One write each of `meta.loc`, `key`, `id_hash`, plain or at `mkForce`, refuses at every reader:
  # the option, `aspects.key` and `aspects.aspectId`. Before, `meta.loc = [ "bobbin" ]` gave `selvage`
  # bobbin's key and id. A write EQUAL to the type's own value mints nothing and is accepted.
  flake.tests.structured-key.test-a-caller-write-of-an-identity-input-refuses =
    let
      reads = a: {
        option = ok a.selvage.key;
        key = ok (aspects.key a.selvage);
        id = ok (id a.selvage);
      };
      none = {
        option = false;
        key = false;
        id = false;
      };
    in
    {
      expr = {
        loc = reads (w {
          meta.loc = [ "bobbin" ];
        });
        locForce = reads (w {
          meta.loc = genMerge.mkForce [ "bobbin" ];
        });
        key = reads (w {
          key = "bobbin";
        });
        keyForce = reads (w {
          key = genMerge.mkForce "bobbin";
        });
        idHash = ok (w { id_hash = bobbinId; }).selvage.id_hash;
        idHashForce = ok (w { id_hash = genMerge.mkForce bobbinId; }).selvage.id_hash;
        equalWrite = (w { key = "selvage"; }).selvage.key;
        # CONTROL
        bobbin = aspects.key (w { }).bobbin;
      };
      expected = {
        loc = none;
        locForce = none;
        key = none;
        keyForce = none;
        idHash = false;
        idHashForce = false;
        equalWrite = "selvage";
        bobbin = "bobbin";
      };
    };

  # A NAMED include element is read as a module that imports the authored value, so its own `key`
  # would be the module key: dropped silently, or (spelt like another module's key) deduplicating the
  # element's content away. It refuses by name before the wrap instead.
  flake.tests.structured-key.test-a-named-include-element-write-refuses-by-name = {
    expr = {
      key = ok (el { key = "q"; }).key;
      idHash = ok (el { id_hash = "aspect:0"; }).id_hash;
      loc = ok (
        aspects.key (el {
          meta.loc = [ "q" ];
        })
      );
      # CONTROL: the unwritten element keeps its content and its site key.
      ctlMarks = (el { }).classOne != null;
      ctlKeyedBySite = lib.hasPrefix "loom/includes/t@" (el { }).key;
    };
    expected = {
      key = false;
      idHash = false;
      loc = false;
      ctlMarks = true;
      ctlKeyedBySite = true;
    };
  };
}
