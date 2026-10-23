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
  entry = extra: value: builtins.attrNames (entryOf extra value);
  entryOf =
    extra: value:
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
  doorIn =
    cnf: scope: output:
    cnf
    // {
      ref = _: {
        right = {
          inherit output scope;
        };
      };
    };
  doorWith = doorIn closed;
  door = doorWith { };
  doorGuard = g (t.ref rid);
  # A door output holding a guard of its own at `includes.0`, which the scope names.
  nestedId =
    (T.refId {
      nested = {
        outer = rid;
        sources.host = src "h1";
        position = [
          "includes"
          0
        ];
        reads = [ "host" ];
      };
    }).right;
  # A guard nested at a position of a body, judged as the aspect type judges that position: `chan` is a
  # declared channel, whose value is raw, so a guard there gets no aspect-body judgement. The verdict is
  # the evaluated aspect forced whole (`graphFacts` does not force an `includes` element's gated key).
  chanKs.keySemantics = {
    nixos.category = "class";
    chan.category = "channel";
  };
  forced = extra: value: ok (placed (chanKs // extra) value).x;
  twins = extra: mk: inner: {
    nested = forced extra (g (mk (g inner)));
    static = forced extra (mk inner);
  };
  served = {
    nested = true;
    static = true;
  };
  nestedNsId =
    (T.refId {
      nested = {
        outer = rid;
        sources.host = src "h1";
        position = [
          "ns"
          "chan"
        ];
        reads = [ "host" ];
      };
    }).right;
  # `sub` is a listed undeclared key: the aspect type opens an ungated subtree below it.
  listed = {
    closedKeys = true;
    freeformKeys = [ "sub" ];
  };
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
    # A guard nested below a listed key is judged as the aspect type judges that position: ungated, so
    # an undeclared namespace reaching a class key is served, as its static twin, the same guard placed
    # at the key, and the same namespace in a plain body are.
    test-nested-guard-below-a-listed-key-is-ungated = {
      expr = {
        nestedGuard = ok (
          facts listed (g {
            sub = g { foo.nixos.x = 1; };
          })
        );
        staticTwin = ok (facts listed { sub.foo.nixos.x = 1; });
        guardAtKey = ok (facts listed { sub = g { foo.nixos.x = 1; }; });
        plainBody = ok (
          facts listed (g {
            sub.foo.nixos.x = 1;
          })
        );
      };
      expected = {
        nestedGuard = true;
        staticTwin = true;
        guardAtKey = true;
        plainBody = true;
      };
    };
    # Below an undeclared key a guard body's first-level scalar is already an orphan leaf, as its static
    # twin's is: placed at the listed key, and nested below it.
    test-guard-below-a-listed-key-orphan-leaf = {
      expr = {
        guardAtKey = ok (facts listed { sub = g { foo = 1; }; });
        nestedGuard = ok (
          facts listed (g {
            sub = g { foo = 1; };
          })
        );
        staticTwin = ok (facts listed { sub.foo = 1; });
      };
      expected = {
        guardAtKey = false;
        nestedGuard = false;
        staticTwin = false;
      };
    };
    # A nested guard is judged under the vocabulary of the aspect it sits in, so a schema extension the
    # type declares is declared there too: in an authored body, and in a door's output.
    test-nested-guard-holds-an-extension-key = {
      expr = ok (
        entry listed (g {
          sub = g { ext = "v"; };
        })
      );
      expected = true;
    };
    test-door-output-nested-guard-holds-an-extension-key = {
      expr =
        (builtins.head
          (entryOf (doorWith { ${nestedId} = null; } { includes = [ (g { ext = "v"; }) ]; }) doorGuard)
          .includes
        ).ext;
      expected = "v";
    };
    # Below an undeclared key, then a declared channel: the channel's value is raw.
    test-nested-guard-in-a-channel-below-an-undeclared-key = {
      expr = twins open (i: { ns.chan = i; }) { foo = 1; };
      expected = served;
    };
    test-nested-guard-in-a-channel = {
      expr = twins listed (i: { chan = i; }) { foo = 1; };
      expected = served;
    };
    # A list that is not `includes` is no aspect position, under a channel or an undeclared key.
    test-nested-guard-in-a-channel-list = {
      expr = twins open (i: { chan = [ i ]; }) { foo.bar = 1; };
      expected = served;
    };
    test-nested-guard-in-an-undeclared-list = {
      expr = twins open (i: { ns = [ i ]; }) { foo.bar = 1; };
      expected = served;
    };
    # An `includes` element is a declared aspect position under the gate in force there: ungated below a
    # listed key, gated at a declared aspect, open in the open mode.
    test-nested-guard-in-includes-below-a-listed-key = {
      expr = twins listed (i: { sub.includes = [ i ]; }) { bar = 1; };
      expected = served;
    };
    test-nested-guard-in-includes-gated = {
      expr = twins listed (i: { includes = [ i ]; }) { foo = 1; };
      expected = {
        nested = false;
        static = false;
      };
    };
    test-nested-guard-in-includes-open = {
      expr = twins open (i: { includes = [ i ]; }) { foo = 1; };
      expected = served;
    };
    # The same position in a door's output.
    test-door-output-nested-guard-in-a-channel-below-an-undeclared-key = {
      expr =
        (entryOf (doorIn chanKs { ${nestedNsId} = null; } { ns.chan = g { foo = 1; }; }) doorGuard).ns.chan;
      expected.foo = 1;
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
