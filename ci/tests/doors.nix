# THE DOOR CHECKS (den-hoag-7gp66 P2 L5 — `prelude.door`, R7 argument structure / R5 field closure) —
# every published step of gen-aspects that takes a RECORD catches its own violations, at its own
# application, catchably, and publishes its contract as data.
#
# After P2 a door step is one of three kinds (spec §p2.3.1; orchestrator ruling Q2 (A); Q1 (C)'s
# retired arm was dropped at den-hoag-c54n4):
#   · the `cnf` step — the library-construction options set, closed over `cnfKeys`, first at every
#     entry point; a key outside `cnfKeys`, `classes` included, is refused as a plain unknown key;
#   · an OPTIONS step after it — `mkAspectSchema`'s `mkAspectOption { providerPrefix?; }` and
#     `mkAspectModule { providerPrefix?; }`, and `instanceOf cnf { scope?; }`;
#   · a RECORD step — open, all fields required (R5), the keyed-record ruling's configuration
#     operands: `instanceOf cnf { } { aspect; context; sources; } value` (guarded by its options
#     step, G10), `instancesFor cnf aspects { suppliers; containment; } scopes`, and the vocabulary's
#     `applyGuardWith` / `applyGuardScoped { context; sources; scope; } guard`.
# `mkNamespaceType config` is positional (rule 4) and carries no row.
#
# WHICH refusal fired is a claim about the message and `tryEval` yields only `success`; the byte
# goldens naming each door (R6) live in `ci/tests-error.nix`'s `flake.testsError.doors`.
{
  aspects,
  genIdentity,
  prelude,
  ...
}:
let
  # `firesAtApplication` forces the step's application to WHNF only — never `deepSeq` — so a check
  # that ran only behind a later field read reads `false` (spec §p2.5, premise 5).
  firesAtApplication = e: !(builtins.tryEval (builtins.seq e null)).success;
  answers = e: (builtins.tryEval (builtins.seq e null)).success;

  inherit (aspects) cnfKeys;
  schema = aspects.mkAspectSchema { };
  vocab = aspects.mkGuardVocab { };
  entity = n: genIdentity.hashIdentity "entity" [ "name" ] (_: n);
  probe = aspects.guard (aspects.pred.has "host") { description = "p"; };
  firing = {
    context.host = "h1";
    sources.host = entity "h1";
    scope = { };
  };
  instance = {
    aspect = aspects.aspectId [ "probe" ] { name = "p"; };
    inherit (firing) context sources;
  };

  # The `cnf` doors: every export whose first argument is a `cnf`.
  cnfDoorNames = [
    "aspectType"
    "aspectSubmodule"
    "aspectsType"
    "aspectsRoot"
    "aspectOrFn"
    "mkIsModuleFn"
    "keyCategory"
    "mkAspectSchema"
    "graphFacts"
    "includeSitesOfInstance"
    "instanceOf"
    "instancesFor"
    "mkGuardVocab"
  ];
  perCnf = f: prelude.genAttrs cnfDoorNames f;

  # The options steps after `cnf`.
  optionsRows = {
    mkAspectOption = {
      step = schema.mkAspectOption;
      optional = [ "providerPrefix" ];
    };
    mkAspectModule = {
      step = schema.mkAspectModule;
      optional = [ "providerPrefix" ];
    };
    instanceOf = {
      step = aspects.instanceOf { };
      optional = [ "scope" ];
    };
  };
  perOptions = f: builtins.mapAttrs f optionsRows;

  # The record steps: the step, its required fields, and one complete record.
  recordRows = {
    instanceOf = {
      step = aspects.instanceOf { } { };
      required = [
        "aspect"
        "context"
        "sources"
      ];
      good = instance;
    };
    instancesFor = {
      step = aspects.instancesFor { } { };
      required = [
        "suppliers"
        "containment"
      ];
      good = {
        suppliers = { };
        containment = { };
      };
    };
    applyGuardWith = {
      step = vocab.applyGuardWith;
      required = [
        "context"
        "sources"
        "scope"
      ];
      good = firing;
    };
    applyGuardScoped = {
      step = vocab.applyGuardScoped;
      required = [
        "context"
        "sources"
        "scope"
      ];
      good = firing;
    };
  };
  perRecord = f: builtins.mapAttrs f recordRows;

  # A field name no door declares, generated per evaluation from the door names themselves.
  stranger = "not-a-field-of-" + builtins.concatStringsSep "-" cnfDoorNames;
in
{
  flake.tests.doors = {
    # ── LIVE CONTROLS, first: the predicates are not dead ──
    test-control-firesAtApplication-is-true-for-an-ordinary-throw = {
      expr = firesAtApplication (throw "control probe, not this suite's subject");
      expected = true;
    };
    test-control-firesAtApplication-is-false-for-a-throw-behind-an-unread-field = {
      expr = firesAtApplication { culprit = throw "control probe, not this suite's subject"; };
      expected = false;
    };

    # ── THE `cnf` STEP (no retired keys, den-hoag-c54n4) ──
    test-each-cnf-door-publishes-its-contract = {
      expr = perCnf (n: aspects.${n}.__contract);
      expected = perCnf (n: {
        name = "gen-aspects.${n}";
        open = false;
        optional = cnfKeys;
        required = [ ];
      });
    };
    test-each-cnf-door-reads-its-keys-through-the-functor-aware-reader = {
      expr = perCnf (n: prelude.functionArgs aspects.${n});
      expected = perCnf (_: prelude.genAttrs cnfKeys (_: true));
    };
    test-an-unknown-cnf-key-is-refused-at-each-door = {
      expr = perCnf (n: firesAtApplication (aspects.${n} { ${stranger} = 1; }));
      expected = perCnf (_: true);
    };
    test-the-former-classes-key-is-refused-at-each-door = {
      expr = perCnf (n: firesAtApplication (aspects.${n} { classes.nixos = { }; }));
      expected = perCnf (_: true);
    };
    test-control-each-cnf-door-answers-on-a-recognised-key = {
      expr = perCnf (n: answers (aspects.${n} { keySemantics = { }; }));
      expected = perCnf (_: true);
    };
    # G3: a non-default `cnf` key reaches the result (`differ`), and the partially applied door agrees
    # with the full call (`agree`).
    test-a-non-default-cnf-key-reaches-the-result = {
      expr =
        let
          opt.keySemantics.nixos.category = "class";
          f1 = aspects.keyCategory opt;
        in
        {
          agree = f1 "nixos" == aspects.keyCategory opt "nixos";
          differ = f1 "nixos" != aspects.keyCategory { } "nixos";
        };
      expected = {
        agree = true;
        differ = true;
      };
    };

    # ── OPTIONS STEPS AFTER `cnf` ──
    test-an-unknown-option-is-refused-at-the-options-application = {
      expr = perOptions (_: r: firesAtApplication (r.step { ${stranger} = 1; }));
      expected = perOptions (_: _: true);
    };
    test-control-the-empty-options-answer = {
      expr = perOptions (_: r: answers (r.step { }));
      expected = perOptions (_: _: true);
    };
    test-each-options-step-publishes-its-contract = {
      expr = perOptions (
        _: r: {
          inherit (r.step.__contract) optional open required;
          args = prelude.functionArgs r.step;
        }
      );
      expected = perOptions (
        _: r: {
          inherit (r) optional;
          open = false;
          required = [ ];
          args = prelude.genAttrs r.optional (_: true);
        }
      );
    };
    # G3: `scope` handed to `instanceOf` is the scope its instance carries.
    test-a-non-default-scope-reaches-the-instance = {
      expr =
        let
          handed.marker = "kept";
          f1 = aspects.instanceOf { } { scope = handed; };
          scopeOf = f: (f instance probe).scope;
        in
        {
          agree = scopeOf f1 == scopeOf (aspects.instanceOf { } { scope = handed; });
          differ = scopeOf f1 != scopeOf (aspects.instanceOf { } { });
        };
      expected = {
        agree = true;
        differ = true;
      };
    };
    # The old one-record `instanceOf` shape is refused at its options application, by name.
    test-the-old-one-record-instanceOf-shape-is-refused-at-the-application = {
      expr = firesAtApplication (aspects.instanceOf { } (instance // { value = probe; }));
      expected = true;
    };

    # ── RECORD STEPS (R5: open, all fields required) ──
    test-each-missing-required-field-is-refused-at-the-application = {
      expr = perRecord (
        _: r: map (f: firesAtApplication (r.step (builtins.removeAttrs r.good [ f ]))) r.required
      );
      expected = perRecord (_: r: map (_: true) r.required);
    };
    test-an-extra-field-is-admitted-at-the-application = {
      expr = perRecord (_: r: !firesAtApplication (r.step (r.good // { ${stranger} = 1; })));
      expected = perRecord (_: _: true);
    };
    test-each-record-step-publishes-its-contract = {
      expr = perRecord (
        _: r: {
          inherit (r.step.__contract) required open;
        }
      );
      expected = perRecord (
        _: r: {
          inherit (r) required;
          open = true;
        }
      );
    };
    # G10: `scope`, an option of `instanceOf`'s options step, given on its record is refused by name
    # rather than silently ignored; the options step names the record as its next step.
    test-scope-given-on-the-instanceOf-record-is-refused = {
      expr = firesAtApplication (aspects.instanceOf { } { } (instance // { scope = { }; }));
      expected = true;
    };
    test-instanceOf-options-step-names-its-record-step = {
      expr = (aspects.instanceOf { }).__contract.next == (aspects.instanceOf { } { }).__contract;
      expected = true;
    };

    # ── POSITIONAL ──
    test-mkNamespaceType-takes-its-config-positionally = {
      expr = {
        lambda = builtins.isFunction schema.mkNamespaceType;
        answers = answers (schema.mkNamespaceType { });
      };
      expected = {
        lambda = true;
        answers = true;
      };
    };
  };
}
