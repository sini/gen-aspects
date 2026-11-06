# `id` on an include element is reserved and refused by name at every door the element can take
# (den-hoag-l2yba; ADR-0034: an include element is keyed by its declaring position, never by a label it
# writes; ADR-0025 item 1). The stamped members refuse at the stamp (`lib/types.nix`); data the type never
# stamped refuses where it is read (`lib/facts.nix` `resolve` for sites, `unnamedEntries` for nodes).
# Every refusal is catchable. The no-`id` twins, the served set and the depth-2 re-entries are pinned
# beside them. The messages are the error plane's (`tests-error.nix`, `structured-key-writes`).
{
  aspects,
  mkSchemaEval,
  genIdentity,
  genMerge,
  genAlgebra,
  ...
}:
let
  refused = x: !(builtins.tryEval (builtins.deepSeq x x)).success;
  inherit (aspects) guard pred;
  g = guard (pred.has "host");
  entity = n: genIdentity.hashIdentity "entity" [ "name" ] (_: n);
  ev =
    defs:
    (mkSchemaEval {
      keySemantics.T.category = "class";
      modules = [ { config.aspects = defs; } ];
    }).config.aspects;
  first = defs: builtins.head (ev defs).loom.includes;
  key =
    e:
    aspects.key (first {
      loom.includes = [ e ];
    });
  relOf =
    as: hostVals: members:
    aspects.instancesFor { } as
      {
        suppliers = builtins.listToAttrs (
          map (h: {
            name = entity h;
            value.host = hostVals.${h};
          }) (builtins.attrNames hostVals)
        );
        containment = { };
      }
      (
        builtins.mapAttrs (h: _: {
          inherit members;
          sources.host = entity h;
        }) hostVals
      );
  targets =
    as: r: iid:
    map (s: s.target or "<none>") (aspects.includeSitesOfInstance { } as r iid);
  # A guard body `a` holding `e`, fired for host `x`.
  fired =
    e:
    let
      as = ev { a = g { includes = [ e ]; }; };
      r = relOf as { x = "x"; } [ "a" ];
    in
    targets as r (builtins.head r.reaches.x.a);
  handed = e: targets (ev { }) { vertices.y.entry.includes = [ e ]; } "y";
  ctx =
    e:
    let
      as = ev {
        h = g { includes = [ ((genAlgebra.term genIdentity.hashIdentity).term.readCtx "host" [ ]) ]; };
      };
      r = relOf as { y = e; } [ "h" ];
    in
    targets as r (builtins.head r.reaches.y.h);
  raw =
    es:
    aspects.graphFacts { } {
      a = {
        name = "a";
        includes = es;
      };
    };
  named = {
    name = "t";
    T.marks = [ "t" ];
  };
  unnamed.T.marks = [ "u" ];
  withId = e: e // { id = "q"; };
  bare = {
    imports = [ { } ];
  };
  bareNamed = bare // {
    name = "t";
  };
  # The twin's value at each door, read once and compared with the planted arm. `read` is the
  # surface the door serves, forced in full on the planted arm; `twin` shows the twin is served.
  doorBy = read: twin: e: {
    twin = twin (read e);
    planted = refused (read (withId e));
  };
  door = f: doorBy f (x: x);
  # The last path segment: a named element's site key carries its file, so it is compared by its
  # tree-independent tail.
  tailSeg = s: builtins.head (builtins.match ".*/([^/]*)$" s);
  isNamedSite = s: builtins.match "loom/includes/t@[0-9]+:[0-9]+:.*" s != null;
  unnamedKey = "loom/includes/[\"a:2\",\"aspects\",\"loom\",\"includes\",0]";
  wrappedKey = rest: "loom/includes/[\"a:2\",\"aspects\",\"loom\",\"includes\",0,${rest}]";
  contentId = "aspect-content:d9111edd5e70a5619e242b9fd9ba4f5d4162736398406cf4b0f8f8bb94e57169";
in
{
  # ── stamped members (`lib/types.nix`) ──────────────────────────────────────────────────────────
  flake.tests.include-element-id.test-named-literal-refuses = {
    expr = doorBy key isNamedSite named;
    expected = {
      twin = true;
      planted = true;
    };
  };
  flake.tests.include-element-id.test-unnamed-literal-refuses = {
    expr = door key unnamed;
    expected = {
      twin = unnamedKey;
      planted = true;
    };
  };
  flake.tests.include-element-id.test-wrapped-literal-refuses = {
    expr = {
      mkIf = door (e: key (genMerge.mkIf true e)) unnamed;
      mkIfNamed = doorBy (e: key (genMerge.mkIf true e)) isNamedSite named;
      mkMerge = door (e: key (genMerge.mkMerge [ e ])) unnamed;
      mkForce = door (e: key (genMerge.mkForce e)) unnamed;
    };
    expected = {
      # A wrapper's content is declared one step below the element's own address.
      mkIf = {
        twin = wrappedKey ''"content"'';
        planted = true;
      };
      mkIfNamed = {
        twin = true;
        planted = true;
      };
      mkMerge = {
        twin = wrappedKey ''"contents",0'';
        planted = true;
      };
      mkForce = {
        twin = wrappedKey ''"content"'';
        planted = true;
      };
    };
  };
  # A bare module `{ imports = [ … ]; }` is taken by its own member before the named one, so even a
  # named one keys by its declaration address.
  flake.tests.include-element-id.test-bare-module-refuses = {
    expr = {
      unnamed = door key bare;
      named = door key bareNamed;
      # The `id` is never read as a datum of the element either.
      read = refused (first { loom.includes = [ (withId bare) ]; }).id;
    };
    expected = {
      unnamed = {
        twin = unnamedKey;
        planted = true;
      };
      named = {
        twin = unnamedKey;
        planted = true;
      };
      read = true;
    };
  };
  # P3 (ruled, reversible): the whole word is reserved, so a nested aspect named `id` refuses too.
  flake.tests.include-element-id.test-nested-aspect-named-id-refuses = {
    expr = {
      planted = refused (key {
        name = "t";
        id.T.marks = [ "n" ];
      });
      # CONTROL: the same nested aspect under another name is served at its site.
      twin = isNamedSite (key {
        name = "t";
        jd.T.marks = [ "n" ];
      });
    };
    expected = {
      planted = true;
      twin = true;
    };
  };

  # ── unstamped data, refused where it is read (`lib/facts.nix`) ─────────────────────────────────
  # A guard body's literal at the declaration read: its sites are not edges, so the twin's is `[ ]`.
  flake.tests.include-element-id.test-guard-body-refuses-at-the-declaration = {
    expr = {
      named = door (
        e:
        (aspects.graphFacts { } (ev {
          a = g { includes = [ e ]; };
        })).includesOf.a
      ) named;
      unnamed = door (
        e:
        (aspects.graphFacts { } (ev {
          a = g { includes = [ e ]; };
        })).includesOf.a
      ) unnamed;
    };
    expected = {
      named = {
        twin = [ ];
        planted = true;
      };
      unnamed = {
        twin = [ ];
        planted = true;
      };
    };
  };
  flake.tests.include-element-id.test-fired-body-refuses = {
    expr = {
      named = doorBy fired (ts: map tailSeg ts) named;
      unnamed = door fired unnamed;
    };
    expected = {
      named = {
        twin = [ contentId ];
        planted = true;
      };
      unnamed = {
        twin = [
          "aspect-instance:50a11165c65157d0a9161c80d2a49eeb97857b8b801ff143832cbccb9cd37e61/includes/0"
        ];
        planted = true;
      };
    };
  };
  flake.tests.include-element-id.test-handed-body-refuses = {
    expr = {
      named = doorBy handed (ts: map tailSeg ts) named;
      unnamed = door handed unnamed;
    };
    expected = {
      named = {
        twin = [ contentId ];
        planted = true;
      };
      unnamed = {
        twin = [ "y/includes/0" ];
        planted = true;
      };
    };
  };
  flake.tests.include-element-id.test-context-route-refuses = {
    expr = doorBy ctx (ts: map tailSeg ts) named;
    expected = {
      twin = [ contentId ];
      planted = true;
    };
  };
  # A raw tree (a registry never typed): its sites refuse at `resolve`, and its position-keyed node
  # refuses where its data is read (`unnamedEntries`). The node id is still listed: it keys nothing.
  flake.tests.include-element-id.test-raw-tree-refuses-at-sites-and-nodes = {
    expr = {
      sites = doorBy (e: (raw [ e ]).includeSitesOf.a) (map (s: s.kind)) unnamed;
      nodeData = doorBy (e: (raw [ e ]).nodeData) builtins.attrNames unnamed;
      nodes = (raw [ (withId unnamed) ]).nodes;
    };
    expected = {
      sites = {
        twin = [ "content" ];
        planted = true;
      };
      nodeData = {
        twin = [
          "a"
          "a/includes/0"
        ];
        planted = true;
      };
      nodes = [
        "a"
        "a/includes/0"
      ];
    };
  };

  # ── depth 2: an element's own `includes` re-enters the same doors ──────────────────────────────
  flake.tests.include-element-id.test-depth-two-refuses = {
    expr = {
      # A named element inside a named element's `includes` (the nested `includesElemType`).
      stamped = doorBy (
        e:
        aspects.key (
          builtins.head (first { loom.includes = [ (named // { includes = [ e ]; }) ]; }).includes
        )
      ) (k: builtins.match "loom/includes/t@.*/includes/t@.*" k != null) named;
      # A handed vertex whose content element holds the element (`sitesOf`'s recursion).
      handed = doorBy (
        e:
        aspects.includeSitesOfInstance { } (ev { }) {
          vertices.y.entry.includes = [ (unnamed // { includes = [ e ]; }) ];
        } "y"
      ) (ss: map (s: map (c: c.target) s.sites) ss) unnamed;
      # The raw tree's node surface one level down.
      rawNodes = doorBy (
        e: (raw [ (unnamed // { includes = [ e ]; }) ]).nodeData
      ) builtins.attrNames unnamed;
    };
    expected = {
      stamped = {
        twin = true;
        planted = true;
      };
      handed = {
        twin = [ [ "y/includes/0/includes/0" ] ];
        planted = true;
      };
      rawNodes = {
        twin = [
          "a"
          "a/includes/0"
          "a/includes/0/includes/0"
        ];
        planted = true;
      };
    };
  };

  # ── what stays served ──────────────────────────────────────────────────────────────────────────
  # A literal module's `config.id` (its content can be wrapped, so a syntactic refusal would be
  # partial), a reference to a node carrying an `id` datum, a keyRef, a typed copy of a served source,
  # and a guard element's body (judged by the undeclared-key judgement, open here).
  flake.tests.include-element-id.test-served-set-is-unchanged =
    let
      cfgSrc = {
        config.id = "q";
        config.T.marks = [ "c" ];
      };
      srcTree = ev { src.includes = [ cfgSrc ]; };
      # The typed D4 element at the node surface: `unnamedEntries` refuses only a KEY-LESS element
      # writing `id`, so a keyed (typed) one's node data is served with its `config.id`.
      d4Facts = aspects.graphFacts { } (ev {
        loom.includes = [ { config = withId unnamed; } ];
      });
    in
    {
      expr = {
        configModule = key { config = withId unnamed; };
        configModuleNode = d4Facts.nodeData.${unnamedKey}.id;
        reference = map aspects.key (
          (mkSchemaEval {
            keySemantics.T.category = "class";
            modules = [
              (
                { config, ... }:
                {
                  config.aspects.foo = {
                    id = "q";
                    T.marks = [ "f" ];
                  };
                  config.aspects.loom.includes = [ config.aspects.foo ];
                }
              )
            ];
          }).config.aspects.loom.includes
        );
        keyRef =
          (first {
            other = { };
            loom.includes = [ ((aspects.keyRef "other") // { id = "q"; }) ];
          }).id;
        copyId =
          (builtins.head
            (ev {
              src.includes = [ cfgSrc ];
              loom.includes = [ (builtins.head srcTree.src.includes) ];
            }).loom.includes
          ).id;
        guardElement = refused (key (g (withId unnamed)));
        # The sibling refusal is unchanged.
        siblingKey = refused (key (named // { key = "q"; }));
      };
      expected = {
        configModule = unnamedKey;
        configModuleNode = "q";
        reference = [ "foo" ];
        keyRef = "q";
        copyId = "q";
        guardElement = false;
        siblingKey = true;
      };
    };

}
