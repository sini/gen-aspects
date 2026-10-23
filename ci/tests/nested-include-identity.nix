# A NESTED INCLUDE ELEMENT IS KEYED UNDER ITS ENCLOSING ELEMENT'S DECLARED POSITION (ADR-0034's rider:
# identity is the declaring position, never the merged one; identity design §1 item 4).
#
# Every include element's tree is evaluated at its declared site (`includeEntryCoercedAt`, gen-merge
# `nests.locOf`), so everything read below it — a named child's `<owner>`, a freeform child's
# `prefix`, a guard carrier's or guard record's `meta.loc`, a declared aspect-typed option's key, and
# an unnamed element's default `name` — names the declaration, never the `[definition N-entry M]`
# list position the merge gave it, which moves with module order.
#
# The fixture is keyed modules, so an unnamed ancestor's address is its module key and never a list
# index, read over four orders and an empty `owner.includes` definition first (`q2empty`, which
# shifts every merge position by one). Each cell's `RED` comment names an edit that turns it.
#
# Not a member here: a guard record written DIRECTLY as an include element is dispatched with no
# declaration address, so it still keys at its merge position (den-hoag-guard-include-identity-xhxky).
{
  aspects,
  mkSchemaEval,
  genMerge,
  typesInternals,
  ...
}:
let
  id = aspects.aspectId [ ];
  cnf.keySemantics = {
    classOne.category = "class";
    classTwo.category = "class";
  };
  gv = aspects.mkGuardVocab cnf;
  fire = gv.applyGuard { thimble.name = "x"; };
  # An aspect-typed declared option (a facet), so a named element below an include element's
  # declared option is read too.
  fac = {
    category = "facet";
    option = genMerge.mkOption {
      type = genMerge.types.nullOr (aspects.aspectType { keySemantics.classOne.category = "class"; });
      default = null;
    };
  };
  eval =
    mods:
    (mkSchemaEval {
      keySemantics = { inherit fac; };
      modules = mods;
    }).config.aspects;
  keyed = k: v: {
    key = "m-${k}";
    config.aspects = v;
  };
  carrier =
    extra:
    genMerge.mkMerge [
      (gv.vocab.always { description = "b"; })
      extra
    ];
  tc = {
    name = "tc";
    description = "tc";
  };
  tci = {
    name = "tci";
    description = "tci";
  };
  mods = {
    F = keyed "F" { owner.includes = [ { description = "F"; } ]; };
    X = keyed "X" {
      owner.includes = [
        {
          description = "outerU";
          includes = [
            {
              name = "toolX";
              description = "X";
            }
          ];
        }
      ];
    };
    Y = keyed "Y" {
      owner.includes = [
        {
          name = "outerN";
          description = "outerN";
          includes = [
            {
              name = "toolY";
              description = "Y";
            }
          ];
        }
      ];
    };
    Z = keyed "Z" {
      owner.includes = [
        {
          name = "top";
          description = "Z";
        }
      ];
    };
    W = keyed "W" {
      owner.includes = [
        {
          description = "outerW";
          includes = [ { description = "W"; } ];
        }
      ];
    };
    D = keyed "D" {
      owner.includes = [
        {
          description = "outerD";
          includes = [
            {
              name = "midN";
              description = "midN";
              includes = [
                {
                  name = "toolD";
                  description = "D";
                }
              ];
            }
          ];
        }
      ];
    };
    K = keyed "K" {
      owner.includes = [
        {
          description = "outerK";
          sub = {
            description = "K";
            includes = [
              {
                name = "toolK";
                description = "KN";
              }
            ];
          };
        }
      ];
    };
    # a guard carrier at a freeform key below an include element, with a named element in its includes
    C = keyed "C" {
      owner.includes = [
        {
          description = "outerC";
          sub = carrier {
            includes = [
              {
                name = "tcc";
                description = "tcc";
              }
            ];
          };
        }
      ];
    };
    # a single guard record at a freeform key below an include element
    GR = keyed "GR" {
      owner.includes = [
        {
          description = "outerG";
          gsub = gv.vocab.always { description = "gr"; };
        }
      ];
    };
    # a declared aspect-typed option below an include element, with a named element in its includes
    FO = keyed "FO" {
      owner.includes = [
        {
          description = "outerF";
          fac = {
            description = "facv";
            includes = [
              {
                name = "tf";
                description = "tf";
              }
            ];
          };
        }
      ];
    };
    # a guard carrier at a TREE position: a named element in its includes and in a nested position
    B = keyed "B" {
      dup = carrier {
        includes = [ tc ];
        inner.includes = [ tci ];
      };
    };
    Uempty = keyed "U" { owner.includes = [ ]; };
  };
  all = [
    "F"
    "X"
    "Y"
    "Z"
    "W"
    "D"
    "K"
    "C"
    "GR"
    "FO"
    "B"
  ];
  orders = {
    p1 = all;
    p2 = [
      "X"
      "Y"
      "Z"
      "W"
      "F"
      "D"
      "K"
      "B"
      "FO"
      "GR"
      "C"
    ];
    p3 = [
      "C"
      "K"
      "W"
      "D"
      "Z"
      "GR"
      "Y"
      "X"
      "FO"
      "F"
      "B"
    ];
    p4 = [
      "Y"
      "F"
      "FO"
      "K"
      "B"
      "X"
      "C"
      "W"
      "Z"
      "GR"
      "D"
    ];
    q2empty = [ "Uempty" ] ++ all;
  };
  byDesc = d: es: builtins.head (builtins.filter (e: (e.description or null) == d) es);
  # Every member of the class, its enclosing element, and the controls, by name.
  members =
    o:
    let
      inc = o.owner.includes;
      outer = d: byDesc d inc;
      midN = builtins.head (outer "outerD").includes;
      K = (outer "outerK").sub;
      C-sub = (outer "outerC").sub;
      fo = (outer "outerF").fac;
      dupF = fire o.dup;
    in
    {
      X = builtins.head (outer "outerU").includes;
      Y = builtins.head (outer "outerN").includes;
      inherit midN K C-sub;
      D = builtins.head midN.includes;
      KN = builtins.head K.includes;
      C-tcc = builtins.head (fire C-sub).includes;
      GR = (outer "outerG").gsub;
      FO = fo;
      FO-tf = builtins.head fo.includes;
      B-tc = builtins.head dupF.includes;
      B-tci = builtins.head dupF.inner.includes;
      # controls: depth-1 elements, named and unnamed, and an unnamed element's own child
      Z = outer "Z";
      F = outer "F";
      outerN = outer "outerN";
      outerU = outer "outerU";
      outerD = outer "outerD";
      outerK = outer "outerK";
      W = builtins.head (outer "outerW").includes;
    };
  runs = builtins.mapAttrs (_: order: members (eval (map (m: mods.${m}) order))) orders;
  perms = map (p: runs.${p}) [
    "p1"
    "p2"
    "p3"
    "p4"
  ];
  # distinct values over the four orders, and whether the empty definition first moves it
  stability =
    f:
    builtins.mapAttrs (n: _: {
      distinct = builtins.length (uniq (map (r: f r.${n}) perms));
      moves = f runs.q2empty.${n} != f runs.p2.${n};
    }) runs.p1;
  uniq = builtins.foldl' (acc: x: if builtins.elem x acc then acc else acc ++ [ x ]) [ ];
  stable = builtins.mapAttrs (_: _: {
    distinct = 1;
    moves = false;
  }) runs.p1;
  # the in-cell expectation for a named element's segment: `<name>@<line>:<column>:<file>`
  seg =
    v:
    let
      p = builtins.unsafeGetAttrPos "name" v;
    in
    builtins.replaceStrings [ "/" ] [ "%2F" ]
      "${v.name}@${toString p.line}:${toString p.column}:${p.file}";
  facts = mods: aspects.graphFacts { } (eval mods);
  # a node's class content is a module; its marks sit under its `imports`
  marksIn =
    v:
    if builtins.isAttrs v then
      (v.marks or [ ]) ++ builtins.concatMap marksIn (v.imports or [ ])
    else if builtins.isList v then
      builtins.concatMap marksIn v
    else
      [ ];
  tryValue =
    v:
    let
      r = builtins.tryEval (builtins.deepSeq v v);
    in
    if r.success then r.value else "REFUSED";
in
{
  flake.tests.nested-include-identity = {
    # G1, G8 (ii): no member's id, and no control's, moves under module order or an empty definition.
    # RED: gen-merge without `nests.locOf`; or the unnamed members without `locOf`.
    test-order-moves-no-id = {
      expr = stability id;
      expected = stable;
    };
    # G2: a nested key extends its enclosing key by its own step, in every order.
    # RED: the named member's tree at its merge position (`includeEntryCoerced` for it).
    test-a-nested-key-extends-its-enclosing-key = {
      expr = builtins.mapAttrs (
        _: r:
        map
          (
            e:
            builtins.substring 0 (builtins.stringLength (r.${e.p}.key + e.s)) r.${e.c}.key == r.${e.p}.key + e.s
          )
          [
            {
              c = "X";
              p = "outerU";
              s = "/includes/";
            }
            {
              c = "Y";
              p = "outerN";
              s = "/includes/";
            }
            {
              c = "D";
              p = "midN";
              s = "/includes/";
            }
            {
              c = "midN";
              p = "outerD";
              s = "/includes/";
            }
            {
              c = "KN";
              p = "K";
              s = "/includes/";
            }
            {
              c = "K";
              p = "outerK";
              s = "/sub";
            }
          ]
      ) runs;
      expected = builtins.mapAttrs (_: _: [
        true
        true
        true
        true
        true
        true
      ]) runs;
    };
    # G5: the relations hold across orders; `includesOf` lists follow definition order, so as sets.
    # RED: `unnamedSite` answering the merge position.
    test-relations-are-order-invariant = {
      expr =
        let
          rel =
            order:
            let
              gf = facts (map (m: mods.${m}) order);
            in
            {
              nodes = builtins.sort builtins.lessThan gf.nodes;
              inherit (gf) parentOf;
              includesOf = builtins.mapAttrs (_: builtins.sort builtins.lessThan) gf.includesOf;
            };
          base = rel orders.p1;
        in
        map (o: rel orders.${o} == base) [
          "p2"
          "p3"
          "p4"
          "q2empty"
        ];
      expected = [
        true
        true
        true
        true
      ];
    };
    # G5, G8 (i): a depth-1 named element, and a guard carrier's named elements at a tree position,
    # are keyed at their declaring site, built here from the position of their `name`.
    # RED: any other spelling of the site segment.
    test-declared-keys-built-in-cell = {
      expr = builtins.mapAttrs (_: r: {
        Z = r.Z.key;
        B-tc = r.B-tc.key;
        B-tci = r.B-tci.key;
      }) runs;
      expected = builtins.mapAttrs (_: _: {
        Z = "owner/includes/${seg (builtins.head mods.Z.config.aspects.owner.includes)}";
        B-tc = "dup/includes/${seg tc}";
        B-tci = "dup/inner/includes/${seg tci}";
      }) runs;
    };
    # G3: one named declaration sighted under two different parents of one owner is two elements;
    # the arm keying a nested element under its owner alone collides them.
    # RED: the named member's tree at its merge position, whose `init` is then its owner's.
    test-two-parents-keep-their-children-apart =
      let
        mk = d: {
          name = "tool";
          description = d;
        };
        o = eval [
          {
            config.aspects.c2.includes = [
              {
                name = "PA";
                description = "PA";
                includes = [ (mk "cA") ];
              }
              {
                name = "PB";
                description = "PB";
                includes = [ (mk "cB") ];
              }
            ];
          }
        ];
        ch = map (p: builtins.head p.includes) o.c2.includes;
      in
      {
        expr = {
          key = (builtins.elemAt ch 0).key == (builtins.elemAt ch 1).key;
          id = id (builtins.elemAt ch 0) == id (builtins.elemAt ch 1);
        };
        expected = {
          key = false;
          id = false;
        };
      };
    # G3 (E): two sightings sharing a §2 key under one owner share an element key, and so do their
    # children: §2 class keying one level down. `graphFacts` keeps four nodes with each one's own
    # content and edge; a distinct-name pair is apart. RED: gen-merge without `nests.locOf`.
    test-same-named-parents-share-their-childrens-key =
      let
        mkP = d: {
          name = "P";
          description = "P" + d;
          classOne.marks = [ ("P" + d) ];
          includes = [
            {
              name = "t";
              description = "t" + d;
              classOne.marks = [ ("t" + d) ];
            }
          ];
        };
        mkQ = d: {
          name = "Q" + d;
          description = "Q" + d;
          includes = [
            {
              name = "u";
              description = "u" + d;
            }
          ];
        };
        mods' = [
          {
            config.aspects.owner.includes = [
              (mkP "a")
              (mkP "b")
            ];
            config.aspects.ctl.includes = [
              (mkQ "a")
              (mkQ "b")
            ];
          }
        ];
        o = eval mods';
        gf = facts mods';
        same = es: {
          key = (builtins.elemAt es 0).key == (builtins.elemAt es 1).key;
          id = id (builtins.elemAt es 0) == id (builtins.elemAt es 1);
        };
        kids = ps: map (p: builtins.head p.includes) ps;
        content = builtins.filter (n: n != "owner" && n != "ctl") gf.nodes;
        desc = n: gf.nodeData.${n}.description or n;
      in
      {
        expr = {
          children = same (kids o.owner.includes);
          ctl = same (kids o.ctl.includes);
          childOf = builtins.listToAttrs (
            map (n: {
              name = desc n;
              value = {
                includes = map desc (gf.includesOf.${n} or [ ]);
                marks = marksIn (gf.nodeData.${n}.classOne or [ ]);
              };
            }) content
          );
        };
        expected = {
          children = {
            key = true;
            id = true;
          };
          ctl = {
            key = false;
            id = false;
          };
          childOf = {
            Pa = {
              includes = [ "ta" ];
              marks = [ "Pa" ];
            };
            Pb = {
              includes = [ "tb" ];
              marks = [ "Pb" ];
            };
            ta = {
              includes = [ ];
              marks = [ "ta" ];
            };
            tb = {
              includes = [ ];
              marks = [ "tb" ];
            };
            Qa = {
              includes = [ "ua" ];
              marks = [ ];
            };
            Qb = {
              includes = [ "ub" ];
              marks = [ ];
            };
            ua = {
              includes = [ ];
              marks = [ ];
            };
            ub = {
              includes = [ ];
              marks = [ ];
            };
          };
        };
      };
    # G10: an unnamed include element's default `name` is its declaration-address segment, the last
    # step of its declared `meta.loc`; it does not move, and it is not read as a name the author wrote.
    # RED: `isMeaningfulName` without its declaration-address test.
    test-an-unnamed-elements-name-is-its-declaration = {
      expr = builtins.mapAttrs (
        _: r:
        map
          (e: {
            loc = e.name == builtins.elemAt e.meta.loc (builtins.length e.meta.loc - 1);
            meaningful = aspects.isMeaningfulName e.name;
          })
          [
            r.F
            r.outerU
            r.W
          ]
      ) runs;
      expected = builtins.mapAttrs (_: _: [
        {
          loc = true;
          meaningful = false;
        }
        {
          loc = true;
          meaningful = false;
        }
        {
          loc = true;
          meaningful = false;
        }
      ]) runs;
    };
    # RED: gen-merge without `nests.locOf`.
    test-an-unnamed-elements-name-does-not-move = {
      expr = stability (e: e.name);
      expected = stable;
    };
    # G4: `unnamedSite` over a seed handed no declaration address refuses by name. No published route
    # reaches it (every include member states `nests.declAt`), so the cell calls the binding.
    # RED: the branch answering `prefix`.
    test-an-element-with-no-address-refuses = {
      expr = {
        refused = tryValue (
          typesInternals.unnamedSite { value = { }; } [
            "a"
            "includes"
            "[definition 1-entry 1]"
          ]
        );
        text = typesInternals.siteRefusal [
          "a"
          "includes"
          "[definition 1-entry 1]"
        ];
      };
      expected = {
        refused = "REFUSED";
        text = "gen-aspects: the include element at `a.includes.\"[definition 1-entry 1]\"' was handed no declaration address (gen-merge's `nests.declAt`), so it has no declaring position to be keyed by; evaluate it through an include position of an aspect type.";
      };
    };
  };
}
