# `cnf` refuses an off-domain key BY NAME (lib/cnf.nix).
#
# Before this construction a `cnf` was an ordinary attrset read with `or` defaults, so an
# unrecognised key was not reinterpreted — it was INERT, and whatever it meant to declare stayed
# undeclared and fell through the aspect submodule's freeform fallback into a nested aspect tree.
# The former `classes` spelling is the measured instance: `mkAspectSchema { classes = { nixos = { }; }; }`
# computed exactly `mkAspectSchema { }`, and an aspect's `nixos` content then acquired a nested
# aspect's `description = "Aspect nixos"`.
#
# ★ THE THROW MUST BE REACHABLE AT WHNF OF THE CONSTRUCTOR'S RESULT, not only by evaluating a
# configuration through it. Forcing a returned option DECLARATION does not force validation buried
# inside its type — a check placed there fires at whatever unrelated read first happens to build the
# submodule — so every refusal cell below forces with `builtins.seq` on the entry point's own result
# and none of them routes through a configuration.
#
# ★ WHAT THESE CELLS CANNOT SEE, stated rather than left silent. (1) Nix cannot recover a thrown
# message through `tryEval`, so catchability is asserted here and the message is pinned byte for byte
# on the error plane (`ci/tests-error.nix`, `cnf-door`): since den-hoag-7gp66 P2 L5 every `cnf` step
# is a `prelude.door` and the refusal is the shared check's unknown-option text, `classes` included
# (den-hoag-c54n4). (2) None of these cells can catch a key declared
# in `cnfDefaults` that nothing in `lib/` reads: they all assert that a declared key CONSTRUCTS, and
# a vestigial key constructs. That direction is pinned lexically in CI, against the read set derived
# from `lib/` itself.
{
  aspects,
  cnfInternals,
  genMerge,
  lib,
  mkSchemaEval,
  ...
}:
let
  # `cnfDefaults` is deliberately NOT public: the published surface answers whether a key is
  # recognised, and the value each key falls back to is the library's own business. The totality
  # cells need those values, so they take them through the library's internal channel.
  inherit (cnfInternals) cnfDefaults;
  inherit (aspects) cnfKeys;

  refuses = e: !(builtins.tryEval (builtins.seq e null)).success;

  # The thirteen public entry points — every export whose first argument is a `cnf` (every `cnfDoor`).
  entryPoints = {
    inherit (aspects)
      aspectType
      aspectSubmodule
      aspectsType
      aspectsRoot
      aspectOrFn
      mkIsModuleFn
      keyCategory
      mkAspectSchema
      mkGuardVocab
      graphFacts
      includeSitesOfInstance
      instanceOf
      instancesFor
      ;
  };

  # Every keySemantics entry form that declares an option of the aspect type, by the key it names:
  # each of the four generated option sets (class, channel, facet option, facet module) and the
  # malformed entry (`refusedOptions`).
  entryForms = {
    class = _: { category = "class"; };
    channel = _: { category = "channel"; };
    facetOption = _: {
      category = "facet";
      option = genMerge.mkOption {
        type = genMerge.types.raw;
        default = null;
      };
    };
    facetModule = n: {
      category = "facet";
      module.options.${n} = genMerge.mkOption {
        type = genMerge.types.raw;
        default = null;
      };
    };
    malformed = _: { category = "bogus"; };
  };
  # An aspect `a` under a cnf whose only keySemantics entry is `n` in `form`, with `modules` added.
  aspectUnder =
    n: form: modules:
    (mkSchemaEval {
      fixtureKeySemantics = { };
      keySemantics.${n} = entryForms.${form} n;
      modules = [ { config.aspects.a = { }; } ] ++ modules;
    }).config.aspects.a;

  # The two harness caller shapes R§4.0 measured in opposite directions: a caller that passes
  # `keySemantics` and no fixture must still see the fixture's classes declared, and a caller that
  # empties the fixture must see none of them. A one-knob harness drops the first and invents the
  # second.
  declaredKeysOf =
    eval: builtins.filter (k: !(lib.hasPrefix "_" k)) (builtins.attrNames eval.config.aspects.main);
  addsToFixture = mkSchemaEval {
    keySemantics = {
      firewall = {
        category = "channel";
      };
    };
    modules = [ { config.aspects.main = { }; } ];
  };
  suppressesFixture = mkSchemaEval {
    fixtureKeySemantics = { };
    modules = [ { config.aspects.main = { }; } ];
  };
  # a declared class key stays a declared key — it does NOT acquire a nested aspect's description
  recognisedSpelling = mkSchemaEval {
    fixtureKeySemantics = {
      nixos = {
        category = "class";
      };
    };
    modules = [ { config.aspects.demo.nixos.imports = [ ]; } ];
  };
in
{
  # ── the refusal itself ──────────────────────────────────────────────────────────────────────
  flake.tests.cnf-refusal.test-unrecognised-key-refuses = {
    expr = refuses (aspects.mkAspectSchema { totallyBogusKey42 = 1; });
    expected = true;
  };

  flake.tests.cnf-refusal.test-former-classes-key-refuses = {
    expr = refuses (
      aspects.mkAspectSchema {
        classes = {
          nixos = { };
        };
      }
    );
    expected = true;
  };

  # POSITIVE CONTROL for every refusal cell above: the library must still CONSTRUCT on a recognised
  # spelling. Without this, "the refusal landed" and "the library stopped constructing" are the same
  # observation.
  flake.tests.cnf-refusal.test-recognised-key-still-constructs = {
    expr = refuses (
      aspects.mkAspectSchema {
        keySemantics = {
          nixos.category = "class";
        };
      }
    );
    expected = false;
  };

  # ── R§2.4 placement: reachable at WHNF, at three independent entry points ───────────────────
  flake.tests.cnf-refusal.test-whnf-mkAspectSchema = {
    expr = refuses (aspects.mkAspectSchema { bogus = 1; });
    expected = true;
  };

  flake.tests.cnf-refusal.test-whnf-aspectsType = {
    expr = refuses (aspects.aspectsType { bogus = 1; });
    expected = true;
  };

  flake.tests.cnf-refusal.test-whnf-mkGuardVocab = {
    expr = refuses (aspects.mkGuardVocab { bogus = 1; });
    expected = true;
  };

  # A CURRIED entry point refuses on the `cnf` alone, before its second argument arrives — the
  # refusal is not deferred to a later application.
  flake.tests.cnf-refusal.test-whnf-curried-entry-point = {
    expr = refuses (aspects.keyCategory { bogus = 1; });
    expected = true;
  };

  # ── the reach: ALL thirteen entry points, and the same thirteen still accept a recognised record ──
  flake.tests.cnf-refusal.test-every-entry-point-refuses = {
    expr = builtins.mapAttrs (
      _: f:
      refuses (f {
        bogusEntryKey = 1;
      })
    ) entryPoints;
    expected = builtins.mapAttrs (_: _: true) entryPoints;
  };

  flake.tests.cnf-refusal.test-every-entry-point-accepts = {
    expr = builtins.mapAttrs (
      _: f:
      refuses (f {
        keySemantics = { };
      })
    ) entryPoints;
    expected = builtins.mapAttrs (_: _: false) entryPoints;
  };

  # ── a keySemantics name never names a structural option (den-hoag-erq8j) ─────────────────────
  # Each name became an option beside the six structural ones and, by `//`, replaced it: a channel
  # `meta` made every aspect's `key` throw blaming a write never made, a channel `key` made every
  # identity key `null`, while `keyCategory` answered "structural". Every collision, every form.
  flake.tests.cnf-refusal.test-structural-key-in-keysemantics-refuses = {
    expr = builtins.listToAttrs (
      map (n: {
        name = n;
        value = builtins.mapAttrs (
          _: form: refuses (aspects.mkAspectSchema { keySemantics.${n} = form n; })
        ) entryForms;
      }) aspects.structuralKeys
    );
    expected = builtins.listToAttrs (
      map (n: {
        name = n;
        value = builtins.mapAttrs (_: _: true) entryForms;
      }) aspects.structuralKeys
    );
  };

  flake.tests.cnf-refusal.test-structural-key-refuses-at-every-entry-point = {
    expr = builtins.mapAttrs (
      _: f:
      refuses (f {
        keySemantics.meta.category = "channel";
      })
    ) entryPoints;
    expected = builtins.mapAttrs (_: _: true) entryPoints;
  };

  # The control, in the same forms under a non-structural name: the door admits it, the key reads its
  # category (a malformed entry still refuses by name, at `checkCategory`), and every aspect keeps its
  # identity.
  flake.tests.cnf-refusal.test-non-structural-key-keeps-the-structural-options = {
    expr = builtins.mapAttrs (
      form: _:
      let
        a = aspectUnder "records" form [ ];
        category = builtins.tryEval (
          aspects.keyCategory { keySemantics.records = entryForms.${form} "records"; } "records"
        );
      in
      {
        door = refuses (aspects.mkAspectSchema { keySemantics.records = entryForms.${form} "records"; });
        category = if category.success then category.value else "refused";
        inherit (a) key name;
      }
    ) entryForms;
    expected = {
      class = {
        door = false;
        category = "class";
        key = "a";
        name = "a";
      };
      channel = {
        door = false;
        category = "channel";
        key = "a";
        name = "a";
      };
      facetOption = {
        door = false;
        category = "facet";
        key = "a";
        name = "a";
      };
      facetModule = {
        door = false;
        category = "facet";
        key = "a";
        name = "a";
      };
      malformed = {
        door = false;
        category = "refused";
        key = "a";
        name = "a";
      };
    };
  };

  flake.tests.cnf-refusal.test-non-structural-channel-reads-its-write = {
    expr =
      (aspectUnder "records" "channel" [
        {
          config.aspects.a.records = {
            x = 1;
          };
        }
      ]).records;
    expected = {
      x = 1;
    };
  };

  # The door reads keySemantics' NAMES and forces no entry (den-hoag-2ejx): an entry that throws
  # when forced still constructs.
  flake.tests.cnf-refusal.test-door-forces-no-keysemantics-entry = {
    expr = builtins.seq (aspects.keyCategory { keySemantics.records = throw "x"; }) true;
    expected = true;
  };

  # A keySemantics that is not an attrset declares no key, and was admitted as declaring none.
  flake.tests.cnf-refusal.test-non-attrset-keysemantics-refuses = {
    expr = builtins.mapAttrs (_: ks: refuses (aspects.mkAspectSchema { keySemantics = ks; })) {
      list = [ ];
      nothing = null;
      string = "meta";
    };
    expected = {
      list = true;
      nothing = true;
      string = true;
    };
  };

  # ONE binding: the structural set the door refuses is the one `keyCategory` and the submodule read.
  flake.tests.cnf-refusal.test-structural-keys-one-binding = {
    expr = {
      published = aspects.structuralKeys;
      door = cnfInternals.nativeStructuralKeys;
      definitions =
        builtins.filter
          (f: lib.hasInfix "nativeStructuralKeys = [" (builtins.readFile (../../lib + "/${f}")))
          (
            builtins.attrNames (
              lib.filterAttrs (f: t: t == "regular" && lib.hasSuffix ".nix" f) (builtins.readDir ../../lib)
            )
          );
    };
    expected = {
      published = [
        "name"
        "description"
        "key"
        "id_hash"
        "meta"
        "includes"
      ];
      door = [
        "name"
        "description"
        "key"
        "id_hash"
        "meta"
        "includes"
      ];
      definitions = [ "cnf.nix" ];
    };
  };

  # ── the vocabulary stays total ──────────────────────────────────────────────────────────────
  flake.tests.cnf-refusal.test-every-default-constructs = {
    expr = refuses (aspects.mkAspectSchema cnfDefaults);
    expected = false;
  };

  flake.tests.cnf-refusal.test-each-key-alone-constructs = {
    expr = builtins.filter (k: refuses (aspects.mkAspectSchema { ${k} = cnfDefaults.${k}; })) cnfKeys;
    expected = [ ];
  };

  # The pin's own control: without it, a construction that had stopped refusing ANYTHING would pass
  # both cells above.
  flake.tests.cnf-refusal.test-nonce-key-refuses = {
    expr = refuses (aspects.mkAspectSchema { nonceKeyForTheDriftPin = 1; });
    expected = true;
  };

  # A literal pin, so growing the vocabulary is a deliberate reviewed edit rather than accretion.
  flake.tests.cnf-refusal.test-cnfKeys-literal-pin = {
    expr = builtins.sort builtins.lessThan cnfKeys;
    expected = [
      "aspectModules"
      "closedKeys"
      "collections"
      "entityKinds"
      "freeformKeys"
      "keySemantics"
      "metaModules"
      "moduleArgs"
      "providerPrefix"
      "recursiveClosed"
      "ref"
      "rejectBareModuleInclude"
      "schemaDefs"
    ];
  };

  # ── the harness is no longer able to speak a vocabulary the library refuses ─────────────────
  #
  # Before the pass-through, a bogus harness argument was an UNCATCHABLE arity abort (`function
  # 'mkSchemaEval' called with unexpected argument`), which takes the whole evaluation down and
  # cannot be a cell at all. What changed is the refusal's KIND, so that is what this asserts.
  #
  # THE FORCING DEPTH IS NOT WHNF HERE, and the difference is worth naming: `mkSchemaEval` returns an
  # evaluated module tree, not the schema, so forcing its result to WHNF yields an attrset without
  # ever building the schema the bogus key was forwarded to. The refusal is reachable exactly where
  # a consumer meets it — on the aspect option this harness declares. The green half is the control:
  # the same forced path on a recognised key must still return.
  flake.tests.cnf-refusal.test-harness-forwards-to-a-catchable-refusal = {
    expr = {
      bogus =
        refuses
          (mkSchemaEval {
            modules = [ { config.aspects.main = { }; } ];
            bogusKey = 1;
          }).config.aspects;
      recognised =
        refuses
          (mkSchemaEval {
            modules = [ { config.aspects.main = { }; } ];
            closedKeys = false;
          }).config.aspects;
    };
    expected = {
      bogus = true;
      recognised = false;
    };
  };

  # ★ THE DISCRIMINATING CONTROLS, in opposite directions. A one-knob harness DROPS the fixture's
  # declarations for the first shape (this bead's own defect, re-created inside the suite by the
  # change that retires it) and INVENTS them for the second.
  flake.tests.cnf-refusal.test-harness-fixture-composes-with-a-caller-key = {
    expr = declaredKeysOf addsToFixture;
    expected = [
      "classOne"
      "classTwo"
      "description"
      "firewall"
      "id_hash"
      "includes"
      "key"
      "meta"
      "name"
    ];
  };

  flake.tests.cnf-refusal.test-harness-empty-fixture-declares-no-classes = {
    expr = declaredKeysOf suppressesFixture;
    expected = [
      "description"
      "id_hash"
      "includes"
      "key"
      "meta"
      "name"
    ];
  };

  # The damage cell's green half: under a DECLARED spelling the key is an option, not a nested
  # aspect, so it carries no aspect `description`.
  flake.tests.cnf-refusal.test-declared-class-is-not-a-nested-aspect = {
    expr = recognisedSpelling.config.aspects.demo.nixos ? description;
    expected = false;
  };
}
