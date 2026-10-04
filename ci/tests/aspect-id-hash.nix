# Partition-identity through the exported `aspects.aspectId` — THE canonical, uniform aspect content-
# address for every kind (plain / parametric guard / guard — identity.nix `key`, whose dispatch IS
# that enumeration). `aspectId origin aspect` = gen-identity hashIdentity over [origin, path] for a
# declaration (its declared path, a list) and [origin, key] for a record with none (NOT mkIdentityModule
# reflection — that would fold `description` in and break the `.key` partition, design §Identity note).
# With origin = []: aspectId [] a == aspectId [] b ⟺ key(a) == key(b), over all three kinds + a custom-
# `description` pair (description must NOT change the id). A non-empty origin distinguishes two same-key
# aspects. The convenience `id_hash` option on plain submodules is computed VIA aspectId (proven no
# drift); aspectId itself is proven equal to gen-schema's canonical hashIdentity (no private re-hash).
{
  aspects,
  mkSchemaEval,
  genMerge,
  genSchema,
  genIdentity,
  ...
}:
let
  inherit (aspects) aspectId; # THE canonical id — works for plain and guard alike.

  # plain
  plainFoo =
    (mkSchemaEval { modules = [ { config.aspects.foo.classOne = { }; } ]; }).config.aspects.foo;

  # distinct paths → distinct keys → distinct id
  hwEval = mkSchemaEval {
    modules = [
      { config.aspects.hardware.cpu.intel.classOne = { }; }
      { config.aspects.hardware.gpu.intel.classOne = { }; }
    ];
  };
  cpu = hwEval.config.aspects.hardware.cpu.intel;
  gpu = hwEval.config.aspects.hardware.gpu.intel;

  # custom-description pair: same path (key "svc"), different description → SAME id. Two separate evals
  # so both can key as "svc".
  descA =
    (mkSchemaEval {
      modules = [
        {
          config.aspects.svc = {
            description = "Alpha svc";
            classOne = { };
          };
        }
      ];
    }).config.aspects.svc;
  descB =
    (mkSchemaEval {
      modules = [
        {
          config.aspects.svc = {
            description = "Beta svc";
            classOne = { };
          };
        }
      ];
    }).config.aspects.svc;

  # the parametric kind: a first-order guard over `host` (a context closure is refused), a BARE record
  # (no id_hash option). Its TERM key (`guardKey`) is the mint over (condition, body), site-independent;
  # its declaration key is its declared path (identity design §1). `wfElsewhere` is the same guard
  # placed at another path.
  wfGuard = aspects.guard (aspects.pred.has "host") { classOne.networking.hostName = "x"; };
  wf = (mkSchemaEval { modules = [ { config.aspects.wf = wfGuard; } ]; }).config.aspects.wf;
  wfElsewhere =
    (mkSchemaEval { modules = [ { config.aspects.deeper.wf2 = wfGuard; } ]; })
    .config.aspects.deeper.wf2;
  plainWf = (mkSchemaEval { modules = [ { config.aspects.wf.classOne = { }; } ]; }).config.aspects.wf;

  # guard (__guard), a BARE record (no id_hash option): key = guardKey — site-independent for a first-
  # order body.
  g1 =
    (mkSchemaEval {
      modules = [
        {
          config.aspects.g = aspects.guard (aspects.pred.eq [ "thimble" "name" ] "h1") { classOne = { }; };
        }
      ];
    }).config.aspects.g;
  g2 =
    (mkSchemaEval {
      modules = [
        {
          config.aspects.g = aspects.guard (aspects.pred.eq [ "thimble" "name" ] "h1") { classOne = { }; };
        }
      ];
    }).config.aspects.g;

  # providerPrefix feeds the option's origin: bypass mkSchemaEval (which hardcodes providerPrefix = []).
  mkEvalPP =
    providerPrefix: modules:
    let
      schema = aspects.mkAspectSchema {
        keySemantics = {
          classOne = {
            category = "class";
          };
        };
      };
    in
    genMerge.evalModuleTree { } (
      [
        { options.schema = schema.schemaOption; }
        (schema.mkAspectModule { inherit providerPrefix; })
      ]
      ++ modules
    );
  ppDefault = (mkEvalPP [ ] [ { config.aspects.foo.classOne = { }; } ]).config.aspects.foo;
  ppProv = (mkEvalPP [ "prov" ] [ { config.aspects.foo.classOne = { }; } ]).config.aspects.foo;
in
{
  # aspectId IS the ecosystem's one canonical hashIdentity formula — no private re-hash inside
  # gen-aspects. The formula now lives in gen-identity, a dependency-free leaf, rather than being
  # reached through gen-schema's re-export; the assertion is unchanged and only its subject's
  # address moved. ★ Reading it against gen-schema here would compare TWO PINS rather than one
  # formula — gen-aspects' ci pins gen-schema independently, so that comparison silently becomes
  # "do these two pins agree" the moment either moves, which is the failure this cell exists to
  # exclude.
  # A declaration mints over its declared path as a LIST (identity design §1: "no preimage is a
  # rendered string"), and the origin enters as a list too.
  flake.tests.aspect-id-hash.test-aspectid-is-canonical-formula = {
    expr =
      aspectId [ ] plainFoo == genIdentity.hashIdentity "aspect" [ "origin" "path" ] (
        k:
        {
          origin = [ ];
          path = [ "foo" ];
        }
        .${k}
      );
    expected = true;
  };

  # no-drift: the convenience option EQUALS the exported aspectId (origin [] here).
  flake.tests.aspect-id-hash.test-option-matches-aspectid = {
    expr = plainFoo.id_hash == aspectId [ ] plainFoo;
    expected = true;
  };

  # plain: same key ⟹ same id; description is NOT in the preimage (reflection-rejection witness).
  flake.tests.aspect-id-hash.test-description-not-in-id = {
    expr = {
      same = aspectId [ ] descA == aspectId [ ] descB;
      a = descA.description;
      b = descB.description;
    };
    expected = {
      same = true;
      a = "Alpha svc";
      b = "Beta svc";
    };
  };

  # plain: distinct key ⟹ distinct id.
  flake.tests.aspect-id-hash.test-distinct-paths-distinct = {
    expr = {
      collide = aspectId [ ] cpu == aspectId [ ] gpu;
      keyC = cpu.key;
      keyG = gpu.key;
    };
    expected = {
      collide = false;
      keyC = "hardware/cpu/intel";
      keyG = "hardware/gpu/intel";
    };
  };

  # parametric kind: uniform id via aspectId (bare record, no option), keyed by the declared path, so
  # the same guard at two paths is two declarations with two ids, and shares one plain aspect's key
  # space; its term key stays the mint, site-independent.
  flake.tests.aspect-id-hash.test-wrapped-fn-key = {
    expr = {
      key = aspects.key wf;
      elsewhere = aspects.key wfElsewhere;
      term = builtins.substring 0 6 (aspects.guardKey wf);
    };
    expected = {
      key = "wf";
      elsewhere = "deeper/wf2";
      term = "guard:";
    };
  };
  flake.tests.aspect-id-hash.test-wrapped-fn-uniform = {
    expr = {
      sameGuardTwoPaths = aspectId [ ] wf == aspectId [ ] wfElsewhere;
      sameTermTwoPaths = aspects.guardKey wf == aspects.guardKey wfElsewhere;
      plainAtItsPath = aspectId [ ] wf == aspectId [ ] plainWf;
    };
    expected = {
      sameGuardTwoPaths = false;
      sameTermTwoPaths = true;
      plainAtItsPath = true;
    };
  };

  # guard kind: uniform id; identical guards share id; guard ≠ plain "foo".
  flake.tests.aspect-id-hash.test-guard-uniform = {
    expr = aspectId [ ] g1 == aspectId [ ] g2;
    expected = true;
  };
  flake.tests.aspect-id-hash.test-guard-vs-plain-distinct = {
    expr = aspectId [ ] g1 == aspectId [ ] plainFoo;
    expected = false;
  };

  # origin distinguishes two otherwise same-key aspects (via the exported aspectId directly).
  flake.tests.aspect-id-hash.test-origin-distinguishes = {
    expr = aspectId [ ] plainFoo == aspectId [ "prov" ] plainFoo;
    expected = false;
  };
  # providerPrefix feeds the option's origin: the option under providerPrefix ["prov"] == aspectId ["prov"].
  flake.tests.aspect-id-hash.test-providerprefix-is-origin = {
    expr = ppProv.id_hash == aspectId [ "prov" ] ppProv;
    expected = true;
  };
  # providerPrefix distinguishes at the option level.
  flake.tests.aspect-id-hash.test-providerprefix-distinguishes = {
    expr = ppDefault.id_hash == ppProv.id_hash;
    expected = false;
  };
  # providerPrefix does NOT change `.key` or `meta.aspect-chain` (additive, non-regressing).
  flake.tests.aspect-id-hash.test-providerprefix-key-unchanged = {
    expr = {
      key = ppProv.key == ppDefault.key;
      chain = ppProv.meta.aspect-chain == ppDefault.meta.aspect-chain;
    };
    expected = {
      key = true;
      chain = true;
    };
  };
}
