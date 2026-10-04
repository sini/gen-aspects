# Test: aspect identity key computation.
{
  lib,
  aspects,
  mkSchemaEval,
  ...
}:
let
  id = aspects.aspectId [ ];
  ok = x: (builtins.tryEval (builtins.deepSeq x x)).success;
  # `p` beside `q` and `ctl`, with `top` including `p` and `ctl` by value. `pDef` is what a caller
  # writes on `p`.
  aside =
    pDef:
    (mkSchemaEval {
      modules = [
        (
          { config, ... }:
          {
            config.aspects = {
              p = pDef // {
                classOne.p = true;
              };
              q.classOne.q = true;
              ctl.classOne.ctl = true;
              top.includes = [
                config.aspects.p
                config.aspects.ctl
              ];
            };
          }
        )
      ];
    }).config.aspects;
  readAside = o: {
    keyP = aspects.key o.p;
    pIsQ = id o.p == id o.q;
    includesTop = (aspects.graphFacts { } o).includesOf.top;
  };
  # A single declaration `x` whose `meta.loc` a caller writes.
  locOf =
    loc:
    (mkSchemaEval {
      modules = [ { config.aspects.x.meta.loc = loc; } ];
    }).config.aspects.x;
  # Two modules, each writing one NAMED element into `owner.includes`, merged in the given order.
  ownerIncludes =
    order:
    let
      mods = {
        a.config.aspects.owner.includes = [
          {
            name = "toolA";
            description = "A";
          }
        ];
        b.config.aspects.owner.includes = [
          {
            name = "toolB";
            description = "B";
          }
        ];
      };
    in
    builtins.listToAttrs (
      map (e: {
        name = e.description;
        value = {
          inherit (e) key;
          id = id e;
        };
      }) (mkSchemaEval { modules = map (m: mods.${m}) order; }).config.aspects.owner.includes
    );
in
{
  flake.tests.identity.test-root-aspect-key =
    let
      eval = mkSchemaEval { modules = [ { config.aspects.networking.classOne = { }; } ]; };
    in
    {
      # A-IDENT (2b, container-relative): a root aspect's chain is empty, so its key is just
      # its own name — the mount segment is re-rooted away by aspectsRoot.
      expr = eval.config.aspects.networking.key;
      expected = "networking";
    };

  flake.tests.identity.test-nested-aspect-key =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.infra.networking.classOne = { }; }
        ];
      };
    in
    {
      # nested via freeform → aspectType → aspectSubmodule.
      # A-IDENT (2b): key carries the full container-RELATIVE path, no longer name-only.
      expr = eval.config.aspects.infra.networking.key;
      expected = "infra/networking";
    };

  # A-IDENT witness: two distinct aspects sharing a leaf name at DISTINCT paths must get
  # DISTINCT keys (name-only collapse fixed). hardware.cpu.intel ≠ hardware.gpu.intel.
  flake.tests.identity.test-no-name-only-collision =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.hardware.cpu.intel.classOne = { }; }
          { config.aspects.hardware.gpu.intel.classOne = { }; }
        ];
      };
      cpu = eval.config.aspects.hardware.cpu.intel.key;
      gpu = eval.config.aspects.hardware.gpu.intel.key;
    in
    {
      expr = {
        inherit cpu gpu;
        collide = cpu == gpu;
      };
      expected = {
        cpu = "hardware/cpu/intel";
        gpu = "hardware/gpu/intel";
        collide = false;
      };
    };

  flake.tests.identity.test-meaningful-name-check = {
    expr = {
      anon = aspects.isMeaningfulName "<anon>";
      fn = aspects.isMeaningfulName "<function body>";
      def = aspects.isMeaningfulName "[definition 1-entry 1]";
      real = aspects.isMeaningfulName "networking";
    };
    expected = {
      anon = false;
      fn = false;
      def = false;
      real = true;
    };
  };

  # ── identity's inputs (den-hoag-qseuh) ──────────────────────────────────────────────────────
  # A declaration's identity is its declared path, `meta.loc`, which the type stamps from the merge
  # position (identity design §1). `name` and `meta.aspect-chain` are its renderings, never inputs.

  # `name` is presentation: setting it to another declaration's name moves neither `key` nor
  # `aspectId`, and a by-value include of `p` resolves to `p`. Before, `key p == "q"`, the two ids were
  # one, and `includesOf.top` read `[ "q" "ctl" ]`.
  flake.tests.identity.test-name-is-a-rendering-not-an-input =
    let
      o = aside { name = "q"; };
    in
    {
      expr = readAside o // {
        keyOption = o.p.key;
        nameStillReads = o.p.name;
        # CONTROL: an unrelated declaration is not q either.
        ctlIsQ = id o.ctl == id o.q;
      };
      expected = {
        keyP = "p";
        pIsQ = false;
        includesTop = [
          "p"
          "ctl"
        ];
        keyOption = "p";
        nameStillReads = "q";
        ctlIsQ = false;
      };
    };

  # A chain that contradicts the declared path refuses by name (identity design Q4), so `c` can
  # neither take `k.c`'s identity (as it did before) nor silently keep its own. `k.c` is untouched.
  # The message is the error plane's (`tests-error.nix`, `identity-inputs`).
  flake.tests.identity.test-a-contradicting-chain-refuses =
    let
      o =
        (mkSchemaEval {
          modules = [
            {
              config.aspects = {
                c = {
                  meta.aspect-chain = [ "k" ];
                  classOne.c = true;
                };
                k.c.classOne.kc = true;
              };
            }
          ];
        }).config.aspects;
    in
    {
      expr = {
        keyRefuses = !(ok (aspects.key o.c));
        idRefuses = !(ok (id o.c));
        chainStillReads = o.c.meta.aspect-chain;
        kcKey = aspects.key o.k.c;
      };
      expected = {
        keyRefuses = true;
        idRefuses = true;
        chainStillReads = [ "k" ];
        kcKey = "k/c";
      };
    };

  # CONTROL (over-fix): a chain set to exactly the rendering the type stamps anyway is coherent and
  # keys as declared.
  flake.tests.identity.test-a-redundant-chain-keys-as-declared = {
    expr =
      aspects.key
        (mkSchemaEval {
          modules = [ { config.aspects.d.a.meta.aspect-chain = [ "d" ]; } ];
        }).config.aspects.d.a;
    expected = "d/a";
  };

  # CONTROL (over-fix): a typed value carried by value keeps the identity it was declared with, at an
  # include position and aliased at another tree position alike (its stamps are definitions, and they
  # beat the receiving position's mkDefault).
  flake.tests.identity.test-a-carried-value-keeps-its-declared-identity =
    let
      o =
        (mkSchemaEval {
          modules = [
            (
              { config, ... }:
              {
                config.aspects = {
                  base.classOne.b = true;
                  user.includes = [ config.aspects.base ];
                  lib.alias = config.aspects.base;
                };
              }
            )
          ];
        }).config.aspects;
    in
    {
      expr = {
        includesUser = (aspects.graphFacts { } o).includesOf.user;
        aliasKey = aspects.key o.lib.alias;
        aliasIsBase = id o.lib.alias == id o.base;
      };
      expected = {
        includesUser = [ "base" ];
        aliasKey = "base";
        aliasIsBase = true;
      };
    };

  # An element written in an `includes` list has no declared path (its merge position moves with
  # module order), so it carries no `meta.loc` and keeps its field-keyed identity: swapping the two
  # modules moves neither element's key nor id (ADR-0034's den-module rider, "reordering includes
  # changes nothing"). Keyed by the merge position, A and B swapped `[definition N-entry 1]` keys and ids
  # with the order.
  flake.tests.identity.test-named-include-elements-keep-their-identity-across-module-order =
    let
      ab = ownerIncludes [
        "a"
        "b"
      ];
      ba = ownerIncludes [
        "b"
        "a"
      ];
    in
    {
      expr = {
        orderInvariant = ab == ba;
        keys = lib.mapAttrs (_: e: e.key) ab;
      };
      expected = {
        orderInvariant = true;
        keys = {
          A = "owner/includes/toolA";
          B = "owner/includes/toolB";
        };
      };
    };

  # `meta` is freeform, so a caller can write any `meta.loc`; one that is not a non-empty list of
  # strings refuses by name and catchably (ADR-0025 item 1), where `"zz"` and `[ 1 ]` aborted the
  # evaluator inside the key. The message is the error plane's (`tests-error.nix`, `identity-inputs`).
  flake.tests.identity.test-a-malformed-declared-path-refuses-catchably = {
    expr = {
      string = ok (aspects.key (locOf "zz"));
      nonString = ok (aspects.key (locOf [ 1 ]));
      empty = ok (aspects.key (locOf [ ]));
      # CONTROL: a well-formed one is read.
      wellFormed = aspects.key (locOf [ "x" ]);
    };
    expected = {
      string = false;
      nonString = false;
      empty = false;
      wellFormed = "x";
    };
  };

  # STATED BOUNDARY, pinned as open (spec OQ1): the stamps themselves stay writable, because they are
  # the channel a typed value's identity rides on when carried by value. So one write of
  # `meta.loc = [ "q" ]`, or a forged `key` + `id_hash` pair, still makes `includes = [ p ]` resolve to
  # `q`: the one-write impersonation MOVED from `name` to `meta.loc`, and closes when the carriage
  # channel does (den-hoag-gywcg). This cell flips then; it is a pin, not a guarantee.
  flake.tests.identity.test-the-stamp-channel-is-still-open =
    let
      qIdHash = (aside { }).q.id_hash;
    in
    {
      expr = {
        loc = readAside (aside {
          meta.loc = [ "q" ];
        });
        forgedPair =
          (readAside (aside {
            key = "q";
            id_hash = qIdHash;
          })).includesTop;
      };
      expected = {
        loc = {
          keyP = "q";
          pIsQ = true;
          includesTop = [
            "q"
            "ctl"
          ];
        };
        forgedPair = [
          "q"
          "ctl"
        ];
      };
    };
}
