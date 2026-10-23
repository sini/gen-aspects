# A guard body's undeclared key is judged as a static aspect body's is (the freeform slot's
# `gatedFreeformElem` and `orphanLeaf`, one judgement in lib/types.nix `undeclaredRefusal`): at the
# declaration check for a plain-data body, and at the firing for a body whose keys exist only once
# fired (a context read, a door's output). Each refusal row is its own cell, so a mutant that drops one
# arm reddens that arm's row alone; the controls beside them keep a judgement that refused everything
# from passing. The message each refusal SAYS is pinned on the error plane
# (`ci/tests-error.nix`, `guard-undeclared-key`); these cells pin that it is CATCHABLE.
{
  aspects,
  mkSchemaEval,
  genMerge,
  genAlgebra,
  genIdentity,
  ...
}:
let
  a = aspects;
  T = genAlgebra.term genIdentity.hashIdentity;
  t = T.term;
  ok = v: (builtins.tryEval (builtins.deepSeq v true)).success;
  src = n: "entity:" + builtins.hashString "sha256" n;

  # `ext` is a schema extension: declared by the aspect type, though not in keySemantics.
  extMod.config.schema.aspect.options.ext = genMerge.mkOption {
    type = genMerge.types.str;
    default = "";
  };
  cnfOf = extra: { keySemantics.nixos.category = "class"; } // extra;
  placed =
    extra: value:
    (mkSchemaEval (
      cnfOf extra
      // {
        fixtureKeySemantics = { };
        modules = [
          extMod
          { config.aspects.x = value; }
        ];
      }
    )).config.aspects;
  facts =
    extra: value:
    let
      f = a.graphFacts (cnfOf extra) (placed extra value);
    in
    {
      inherit (f) nodes deadNested deliversOf;
    };
  entry =
    extra: value:
    builtins.attrNames
      (a.instanceOf (cnfOf extra) { } {
        aspect = "x";
        context = {
          host = "h1";
          payload.hm.home.username = "u";
        };
        sources = {
          host = src "h1";
          payload = src "p1";
        };
      } (placed extra value).x).entry;

  open = { };
  closed.closedKeys = true;
  g = a.guard (a.pred.has "host");
  # A body whose keys exist only once fired: the context's value.
  fromCtx = a.guard (a.pred.all [
    (a.pred.has "host")
    (a.pred.has "payload")
  ]) (t.readCtx "payload" [ ]);
  # A door body (`cnf.ref`), whose output is the fired value.
  rid =
    (T.refId {
      declared = {
        site = "out";
        reads = [ "host" ];
      };
    }).right;
  door = output: {
    closedKeys = true;
    ref = _: {
      right = {
        inherit output;
        scope = { };
      };
    };
  };
  doorGuard = g (t.ref rid);
in
{
  flake.tests.guard-undeclared-key = {
    # Open: a scalar below an undeclared key is an orphan leaf, refused where the check is forced.
    test-orphan-leaf-at-the-check = {
      expr = ok (
        facts open (g {
          hm.home.username = "u";
        })
      );
      expected = false;
    };
    test-orphan-leaf-at-the-instance = {
      expr = ok (
        entry open (g {
          hm.home.username = "u";
        })
      );
      expected = false;
    };
    # Closed: an undeclared first-level key is refused by name.
    test-closed-gate-at-the-check = {
      expr = ok (
        facts closed (g {
          hm = "u";
        })
      );
      expected = false;
    };
    test-closed-gate-at-the-instance = {
      expr = ok (
        entry closed (g {
          hm = "u";
        })
      );
      expected = false;
    };
    # The declared set is the aspect type's options, extensions included: `ext` is declared, `sub`
    # above it is not.
    test-closed-gate-above-an-extension = {
      expr = ok (
        facts closed (g {
          sub.inner.ext = "deep";
        })
      );
      expected = false;
    };
    # Fire time: the keys exist only once the context is read.
    test-fired-context-read = {
      expr = ok (entry closed fromCtx);
      expected = false;
    };
    # Fire time: the keys exist only in the door's output.
    test-fired-door-output = {
      expr = ok (entry (door { hm = "u"; }) doorGuard);
      expected = false;
    };
    # Controls: a class key, an extension key and an open first-level datum are served as written, and
    # so is a door output holding a class key.
    test-controls-served = {
      expr = {
        classClosed = entry closed (g {
          nixos.x = 1;
        });
        extensionClosed = entry closed (g {
          ext = "v";
        });
        firstLevelOpen = entry open (g {
          hm = "u";
        });
        doorClass = entry (door { nixos.x = 1; }) doorGuard;
      };
      expected = {
        classClosed = [ "nixos" ];
        extensionClosed = [ "ext" ];
        firstLevelOpen = [ "hm" ];
        doorClass = [ "nixos" ];
      };
    };
  };
}
