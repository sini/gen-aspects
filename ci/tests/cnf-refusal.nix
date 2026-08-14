# `cnf` refuses an off-domain key BY NAME (lib/cnf.nix).
#
# Before this construction a `cnf` was an ordinary attrset read with `or` defaults, so an
# unrecognised key was not reinterpreted — it was INERT, and whatever it meant to declare stayed
# undeclared and fell through the aspect submodule's freeform fallback into a nested aspect tree.
# The retired `classes` spelling is the measured instance: `mkAspectSchema { classes = { nixos = { }; }; }`
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
# message through `tryEval`, so catchability is asserted on the real call and message CONTENT on
# `cnfRefusal`, the renderer that same path throws. (2) None of these cells can catch a key declared
# in `cnfDefaults` that nothing in `lib/` reads: they all assert that a declared key CONSTRUCTS, and
# a vestigial key constructs. That direction is pinned lexically in CI, against the read set derived
# from `lib/` itself.
{
  aspects,
  cnfInternals,
  lib,
  mkSchemaEval,
  ...
}:
let
  # `cnfDefaults` is deliberately NOT public: the published surface answers whether a key is
  # recognised, and the value each key falls back to is the library's own business. The totality
  # cells need those values, so they take them through the same internal channel as `cnfRefusal`.
  inherit (cnfInternals) cnfRefusal cnfDefaults;
  inherit (aspects) cnfKeys;

  # Substring test WITHOUT a regex. `lib.hasInfix` compiles to `builtins.match ".*<sub>.*"`, and a
  # leading-`.*` match over a several-hundred-character subject is the shape that overflows the
  # evaluator's stack under the test runner. This scan is O(n·m) on strings this short and cannot.
  # Its own control is `test-substring-scan-discriminates` below: a scan that can never match reads
  # exactly like an absence.
  containsSub =
    sub: s:
    let
      n = builtins.stringLength sub;
      m = builtins.stringLength s;
    in
    m >= n && builtins.any (i: builtins.substring i n s == sub) (builtins.genList (i: i) (m - n + 1));

  refuses = e: !(builtins.tryEval (builtins.seq e null)).success;

  # The ten public entry points — every export whose first argument is a `cnf`.
  entryPoints = {
    inherit (aspects)
      aspectType
      aspectSubmodule
      aspectsType
      aspectsRoot
      aspectOrFn
      mkIsModuleFn
      wrapFn
      keyCategory
      mkAspectSchema
      mkGuardVocab
      ;
  };

  bogusMsg = cnfRefusal [ "totallyBogusKey42" ];
  retiredMsg = cnfRefusal [ "classes" ];
  multiMsg = cnfRefusal [
    "zzz1"
    "zzz2"
  ];

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

  flake.tests.cnf-refusal.test-retired-classes-key-refuses = {
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

  # ── the reach: ALL ten entry points, and the same ten still accept a recognised record ──────
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

  # ── the message contract ────────────────────────────────────────────────────────────────────
  flake.tests.cnf-refusal.test-message-names-the-key = {
    expr = containsSub "totallyBogusKey42" bogusMsg;
    expected = true;
  };

  flake.tests.cnf-refusal.test-message-renders-the-recognised-set = {
    expr = builtins.all (k: containsSub k bogusMsg) cnfKeys;
    expected = true;
  };

  flake.tests.cnf-refusal.test-retired-key-points-at-its-replacement = {
    expr = {
      names = containsSub "classes" retiredMsg;
      points = containsSub "keySemantics" retiredMsg;
    };
    expected = {
      names = true;
      points = true;
    };
  };

  # ALL offending keys, never the first: a first-offender implementation passes every other cell
  # here, so this is the requirement's only falsifier.
  flake.tests.cnf-refusal.test-all-bad-keys-are-named = {
    expr = {
      first = containsSub "zzz1" multiMsg;
      second = containsSub "zzz2" multiMsg;
    };
    expected = {
      first = true;
      second = true;
    };
  };

  # A key the library never retired gets no retirement paragraph — the pointer comes from a binding,
  # not from a branch that fires for everything.
  flake.tests.cnf-refusal.test-unretired-key-has-no-retirement-note = {
    expr = containsSub "RETIRED" multiMsg;
    expected = false;
  };

  # THE CONTROL for every `containsSub` cell above: a scan that cannot match must return false, and
  # one that must match on the same subject must return true.
  flake.tests.cnf-refusal.test-substring-scan-discriminates = {
    expr = {
      absent = containsSub "nonceTokenNotInAnyMessage" bogusMsg;
      present = containsSub "gen-aspects: unrecognised cnf key" bogusMsg;
    };
    expected = {
      absent = false;
      present = true;
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
      "deferIncludeResolution"
      "freeformKeys"
      "guardForms"
      "keySemantics"
      "metaModules"
      "moduleArgs"
      "providerPrefix"
      "recursiveClosed"
      "rejectBareModuleInclude"
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
