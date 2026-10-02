# The four types a gen evaluation folds a nested aspect tree through are gen-NATIVE (den-hoag-n6dh7
# item 5, cells U2-p and U2-m). `aspectType`, `aspectsRoot`, `gatedFreeformKey` and `includesElem` are
# built through gen-merge's `defineType`, so each carries its fold's threaded sibling, states what it
# carries (a union's members, a container's element), and still answers the sub-option protocol as it
# did. The two raw-closure applicators merge through the interim door and keep their value.
{
  lib,
  aspects,
  genMerge,
  ...
}:
let
  t = genMerge.types;
  cnf = {
    keySemantics.classOne.category = "class";
  };
  closed = cnf // {
    closedKeys = true;
    freeformKeys = [ "ns" ];
  };
  sub = aspects.aspectSubmodule cnf;
  # The two types this library does not export, reached through the published protocol of the
  # submodule that uses them: its freeform element and its `includes` element.
  freeformOf =
    c:
    ((builtins.head (aspects.aspectSubmodule c).getSubModules) {
      name = "x";
      config = { };
      prefix = [ ];
    }).freeformType.nestedTypes.elemType;
  ported = {
    aspectType = aspects.aspectType cnf;
    aspectsRoot = aspects.aspectsRoot cnf;
    gatedFreeformKey = freeformOf closed;
    includesElem = (sub.getSubOptions [ ]).includes.type.nestedTypes.elemType;
  };
  # gen-merge's `isNesting`, as its record states it.
  isNesting = ty: builtins.isAttrs ty && ty ? nests && ty ? mergeDefs.threaded;
  # gen-merge's `canNest`, read through the door that asks it: a stock foreign `attrsOf` over `ty` is
  # re-homed as gen's own container exactly when `ty` may nest, and gen's container carries a split.
  canNest = ty: (genMerge.mkOptionType (lib.types.attrsOf ty)) ? split;
  def = v: [
    {
      file = "<t>";
      value = v;
    }
  ];
  guardFn =
    { host, ... }:
    {
      description = "from-guard";
    };
in
{
  # U2-p: each port carries the sibling and may nest. A port through `mkOptionType` erases the
  # sibling (the checked fold is a bare lambda), and one stating no `carries` reads as a leaf.
  flake.tests.nesting-port.test-each-port-carries-the-sibling-and-may-nest = {
    expr = builtins.mapAttrs (_: ty: {
      threaded = ty ? mergeDefs.threaded;
      canNest = canNest ty;
      carries = builtins.attrNames (ty.carries or { });
      recarry = ty ? recarry;
      substructure = builtins.attrNames (ty.substructure or { });
    }) ported;
    expected =
      let
        union = {
          threaded = true;
          canNest = true;
          carries = [ "alternatives" ];
          recarry = true;
          substructure = [
            "declares"
            "modules"
            "rebuild"
          ];
        };
      in
      {
        aspectType = union;
        aspectsRoot = union // {
          carries = [ "element" ];
        };
        gatedFreeformKey = union;
        includesElem = union;
      };
  };

  # The predicate reads what a type states: a leaf may not nest, a gen submodule may.
  flake.tests.nesting-port.test-control-the-nesting-read-discriminates = {
    expr = {
      leaf = canNest t.str;
      submodule = canNest sub;
    };
    expected = {
      leaf = false;
      submodule = true;
    };
  };

  # Item 2: a union states its member choice once. `aspectType` picks the plain submodule for one
  # attrset, the coercing member for several, and no member for a guard fn; `gatedFreeformKey` picks
  # by the key (`loc`), so one definition gives a member at a listed key and none elsewhere;
  # `includesElem` reads a bare module through its own member and passes a keyRef through.
  flake.tests.nesting-port.test-each-union-chooses-its-member = {
    expr =
      let
        at = ported.aspectType;
        gated = ported.gatedFreeformKey;
        inc = ported.includesElem;
        member =
          m:
          if m == null then
            null
          else
            {
              inherit (m) name;
              nesting = isNesting m;
            };
      in
      {
        atSingle = member (at.choose [ "a" ] (def { }));
        atMulti = member (
          at.choose [ "a" ] (
            def { }
            ++ def (
              { config, ... }:
              { }
            )
          )
        );
        # The coercing member reads a function among several as `{ includes = [ f ]; }` in its
        # tree's entry, where the plain member reads it as a module.
        atMultiEntry =
          let
            f =
              { config, ... }:
              { };
            m = at.choose [ "a" ] (def { } ++ def f);
          in
          {
            coercing = builtins.attrNames ((m.nests.entry (builtins.head (def f))).config or { });
            plain = builtins.attrNames ((sub.nests.entry (builtins.head (def f))).config or { });
          };
        atGuardFn = member (at.choose [ "a" ] (def guardFn));
        gatedListed = member (gated.choose [ "ns" ] (def { }));
        gatedOther = member (gated.choose [ "other" ] (def { }));
        incBare = member (
          inc.choose [ "i" ] (def {
            imports = [ { } ];
          })
        );
        incKeyRef = member (
          inc.choose [ "i" ] (def {
            __keyRef = true;
          })
        );
        incAspect = member (inc.choose [ "i" ] (def { }));
      };
    expected = {
      atSingle = {
        name = "submodule";
        nesting = true;
      };
      atMulti = {
        name = "submodule";
        nesting = true;
      };
      atMultiEntry = {
        coercing = [ "includes" ];
        plain = [ ];
      };
      atGuardFn = null;
      gatedListed = {
        name = "aspect";
        nesting = false;
      };
      gatedOther = null;
      incBare = {
        name = "submodule";
        nesting = true;
      };
      incKeyRef = null;
      incAspect = {
        name = "either";
        nesting = false;
      };
    };
  };

  # The container states one position per key, re-rooted at `[ k ]`, over its element.
  flake.tests.nesting-port.test-the-root-splits-by-key = {
    expr =
      map
        (e: {
          inherit (e) step loc;
          type = e.type.name;
        })
        (
          ported.aspectsRoot.split [ "aspects" ] (def {
            foo = { };
          })
        );
    expected = [
      {
        step = [ "foo" ];
        loc = [ "foo" ];
        type = "aspect";
      }
    ];
  };

  # The sub-option protocol reads as it did before the port: no module set, and the option names of
  # the aspect submodule where the type answers with it, with gen-merge's `_freeformOptions` beside
  # them, nixpkgs' answer for a freeform submodule.
  flake.tests.nesting-port.test-the-sub-option-protocol-reads-as-before = {
    expr = builtins.mapAttrs (_: ty: {
      modules = ty.getSubModules;
      options = builtins.attrNames (ty.getSubOptions [ ]);
    }) ported;
    expected =
      let
        aspectOptions = [
          "_freeformOptions"
          "classOne"
          "description"
          "id_hash"
          "includes"
          "key"
          "meta"
          "name"
        ];
      in
      {
        aspectType = {
          modules = null;
          options = aspectOptions;
        };
        aspectsRoot = {
          modules = null;
          options = aspectOptions;
        };
        gatedFreeformKey = {
          modules = null;
          options = [ ];
        };
        includesElem = {
          modules = null;
          options = [ ];
        };
      };
  };

  # U2-m: the raw-closure applicators' value through the interim door, `name` from the door's own
  # `loc` (the `<function body>` segment), for `wrapFn` and for a type-merge-wrapped guard fn.
  flake.tests.nesting-port.test-the-interim-door-keeps-the-value = {
    expr =
      let
        fn = ctx: { description = "d-${ctx.d}"; };
        read = a: { inherit (a) description name; };
        viaType = ported.aspectType.mergeDefs [ "n" ] (def ({ d, ... }: fn { inherit d; }));
      in
      {
        wrapFn = read ((aspects.wrapFn cnf "n" fn) { d = "x"; });
        typeMerge = read (viaType {
          d = "x";
        });
      };
    expected = {
      wrapFn = {
        description = "d-x";
        name = "<function body>";
      };
      typeMerge = {
        description = "d-x";
        name = "<function body>";
      };
    };
  };
}
