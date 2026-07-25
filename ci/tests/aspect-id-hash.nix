# Partition-identity through the exported `aspects.aspectId` — THE canonical, uniform aspect content-
# address for ALL three kinds (plain / wrapped-fn / guard, identity.nix:69-77). `aspectId origin aspect`
# = gen-schema hashIdentity over [origin, key], key = identity.key aspect (NOT mkIdentityModule
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
  ...
}:
let
  inherit (aspects) aspectId; # THE canonical id — works for plain, wrapped-fn, and guard alike.

  # plain
  plainFoo = (mkSchemaEval { modules = [ { config.aspects.foo.classOne = { }; } ]; }).config.aspects.foo;

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
    (mkSchemaEval { modules = [ { config.aspects.svc = { description = "Alpha svc"; classOne = { }; }; } ]; }).config.aspects.svc;
  descB =
    (mkSchemaEval { modules = [ { config.aspects.svc = { description = "Beta svc"; classOne = { }; }; } ]; }).config.aspects.svc;

  # wrapped-fn (__isWrappedFn), a BARE functor record (no id_hash option): key = pathKey meta.loc. `host`
  # is not a module arg → guard closure → wrap.
  wf =
    (mkSchemaEval { modules = [ { config.aspects.wf = { host, ... }: { classOne.networking.hostName = host.name or "x"; }; } ]; }).config.aspects.wf;
  plainWf = (mkSchemaEval { modules = [ { config.aspects.wf.classOne = { }; } ]; }).config.aspects.wf;

  # guard (__guard), a BARE record (no id_hash option): key = guardKey — site-independent for a first-
  # order body.
  g1 =
    (mkSchemaEval { modules = [ { config.aspects.g = aspects.guard (aspects.pred.host "h1") { classOne = { }; }; } ]; }).config.aspects.g;
  g2 =
    (mkSchemaEval { modules = [ { config.aspects.g = aspects.guard (aspects.pred.host "h1") { classOne = { }; }; } ]; }).config.aspects.g;

  # providerPrefix feeds the option's origin: bypass mkSchemaEval (which hardcodes providerPrefix = []).
  mkEvalPP =
    providerPrefix: modules:
    let
      schema = aspects.mkAspectSchema { keySemantics = { classOne = { category = "class"; }; }; };
    in
    genMerge.evalModuleTree {
      modules = [
        { options.schema = schema.schemaOption; }
        (schema.mkAspectModule { inherit providerPrefix; })
      ]
      ++ modules;
    };
  ppDefault = (mkEvalPP [ ] [ { config.aspects.foo.classOne = { }; } ]).config.aspects.foo;
  ppProv = (mkEvalPP [ "prov" ] [ { config.aspects.foo.classOne = { }; } ]).config.aspects.foo;
in
{
  # aspectId IS gen-schema's one canonical hashIdentity formula (no private re-hash inside gen-aspects).
  flake.tests.aspect-id-hash.test-aspectid-is-canonical-formula = {
    expr =
      aspectId [ ] plainFoo == genSchema.hashIdentity "aspect" [ "origin" "key" ] (
        k:
        {
          origin = "";
          key = aspects.key plainFoo;
        }.${k}
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

  # wrapped-fn kind: uniform id via aspectId (bare record, no option); same-key cross-kind ⟹ same id.
  flake.tests.aspect-id-hash.test-wrapped-fn-key = {
    expr = aspects.key wf;
    expected = "wf";
  };
  flake.tests.aspect-id-hash.test-wrapped-fn-uniform = {
    expr = aspectId [ ] wf == aspectId [ ] plainWf;
    expected = true;
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
