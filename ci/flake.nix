{
  inputs = {
    gen-harness.url = "github:sini/gen-harness";
    gen-prelude.url = "github:sini/gen-prelude";
    gen-merge.url = "github:sini/gen-merge";
    gen-schema.url = "github:sini/gen-schema";
    gen-identity.url = "github:sini/gen-identity";
    gen-algebra.url = "github:sini/gen-algebra";
    # nixpkgs is the CI runner's dependency (nix-unit harness, treefmt) and supplies the `lib` the
    # test modules use for assertions. The library itself (../lib) is nixpkgs-lib-free
    # (ci/tests/purity.nix enforces this); it is driven via gen-merge's evalModuleTree, not evalModules.
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    inputs@{
      gen-harness,
      gen-prelude,
      gen-merge,
      gen-schema,
      gen-identity,
      gen-algebra,
      nixpkgs,
      ...
    }:
    let
      genMerge = gen-merge.lib;
      genSchema = gen-schema.lib;
      genIdentity = gen-identity.lib;
      genAlgebra = gen-algebra.lib;
      aspects = import ../lib {
        prelude = gen-prelude.lib;
        merge = genMerge;
        schema = gen-schema.lib;
        identity = gen-identity.lib;
        algebra = genAlgebra;
      };
      # The class fixture, written in the library's own keySemantics shape. The harness used to take a
      # `classes` knob and lower it, which is how a spelling the published API had RETIRED stayed
      # green in this suite for a month: the suite's `cnf` surface differed in SHAPE from the
      # consumer's, so suite-green stopped implying consumer-green. Nothing here translates a
      # vocabulary any more.
      defaultKeySemantics = {
        classOne = {
          category = "class";
        };
        classTwo = {
          category = "class";
        };
      };
      # A PASS-THROUGH: every argument other than the two harness-only ones is forwarded to the
      # library verbatim, so the harness cannot accept a `cnf` key the library refuses — the ellipsis
      # moves arity checking off Nix's formals and onto the library's own named refusal, which is
      # `tryEval`-catchable where an "unexpected argument" abort is not.
      #
      # TWO knobs, not one, and the reason is measured: `fixtureKeySemantics` is DEFAULTED and a
      # caller's `keySemantics` is not, so their composition is what lets a caller either add to the
      # fixture (pass `keySemantics`, keep the two fixture classes) or suppress it (pass
      # `fixtureKeySemantics = { }`). Folding them into a single `keySemantics` argument drops the
      # fixture's declarations for the first caller shape and invents them for the second.
      #
      # `fixtureKeySemantics` is deliberately not a library word: a harness-only name colliding with
      # a future recognised `cnf` key would be stripped by the `removeAttrs` below and so become
      # unreachable from the suite.
      mkSchemaEval =
        {
          modules,
          fixtureKeySemantics ? defaultKeySemantics,
          ...
        }@args:
        let
          cnfArgs = removeAttrs args [
            "modules"
            "fixtureKeySemantics"
          ];
          schema = aspects.mkAspectSchema (
            cnfArgs // { keySemantics = fixtureKeySemantics // (args.keySemantics or { }); }
          );
        in
        genMerge.evalModuleTree { } (
          [
            { options.schema = schema.schemaOption; }
            (schema.mkAspectModule { })
          ]
          ++ modules
        );
    in
    gen-harness.lib.mkCi {
      inherit inputs;
      name = "gen-aspects";
      testModules = ./tests;
      specialArgs = {
        inherit
          aspects
          mkSchemaEval
          genMerge
          genSchema
          genIdentity
          genAlgebra
          ;
        # `prelude` reaches the suite because `tests/entry.nix` applies the STANDALONE root entry
        # with explicit arguments — which is what keeps that cell pure, since supplying every
        # dependency formal means the shim's fetching defaults are never forced. It is the SAME
        # instance `aspects` above is built from, so the two sides of that comparison differ in
        # entry point and in nothing else.
        prelude = gen-prelude.lib;
        # The `cnf` module itself, so the suite can assert what a refusal SAYS. Nix cannot recover a
        # thrown message through `tryEval`, so message content is asserted on the renderer the throw
        # path calls, while catchability is asserted on the real path.
        cnfInternals = import ../lib/cnf.nix;
        # The published-facts module, for the same split over its one refusal. Its renderer is
        # deliberately absent from `lib/default.nix` — a consumer reads a refusal, never renders one.
        factsInternals = import ../lib/facts.nix {
          prelude = gen-prelude.lib;
          # Unread by the renderers but `declarationMemberRefusal`, which renders through guard-term's
          # `render` (it reads only the refusal it is handed, so the instance's inputs stay unforced).
          T = null;
          GT = import ../lib/guard-term.nix {
            prelude = gen-prelude.lib;
            T = null;
            hashIdentity = null;
            identityOf = null;
            isExact = null;
            keyCategory = null;
            mkIsModuleFn = null;
            refusalShapeOf = null;
            refusalReachedText = null;
          };
          # Unread here: the suite takes only the refusal renderer, and the published surface (pinned in
          # AGENTS.md) does not carry the default. `graphFacts` itself reads `types.includesDefault`.
          includesDefault = [ ];
          # Unread here too: only `graphFacts`' `deliversOf` reads them.
          keyCategory = _: _: null;
          hasClassContent = _: false;
        };
        # The identity module, for the guarded function-scan behind `guardKey`. That scan is reachable
        # from the public surface only through a key, and a key is a string: out there, a body whose
        # walk was REFUSED is indistinguishable from a body that merely carried a function, since both
        # answer with the same source-position fallback. The cells that must tell those apart take the
        # scan itself through this channel, and its refusal renderer with it.
        identityInternals = import ../lib/identity.nix {
          prelude = gen-prelude.lib;
          inherit (genAlgebra) identityOf isExact;
        };
        # The guard-term instance's depth budget, so the cells straddling it read the bound rather than
        # restate it, and the instance a guard is checked under, for the cell that checks a checked
        # record's whole body against gen-algebra as published (den-hoag-egkyp). `instanceFor` takes a
        # cnf as `mkSchemaEval` places it: the fixture's classes under the caller's keySemantics.
        guardTermInternals =
          let
            GT = import ../lib/guard-term.nix {
              prelude = gen-prelude.lib;
              T = genAlgebra.term genIdentity.hashIdentity;
              inherit (genIdentity) hashIdentity;
              inherit (genAlgebra) identityOf isExact;
              inherit (aspects) keyCategory mkIsModuleFn;
              refusalShapeOf = null;
              refusalReachedText = null;
            };
          in
          {
            inherit (GT) maxLiftDepth;
            instanceFor =
              cnf:
              GT.instanceFor (
                (import ../lib/cnf.nix).cnfDefaults
                // cnf
                // {
                  keySemantics = defaultKeySemantics // (cnf.keySemantics or { });
                }
              );
          };
      };
      # Cells whose subject is an error MESSAGE: outside `testModules`, read by
      # `nix-unit --flake ./ci#testsError` (see the file's header). `tests-process.nix` is a PROCESS
      # cell (den-hoag-n6dh7 SCC build, relocated from gen-merge's own `ci/`): its verdict is a
      # process exit, not a nix-unit output, so it lives here beside `tests-error.nix` for the same
      # reason and is read by `apps.tests-process`, not `testModules`.
      extraModules = [
        ./tests-error.nix
        ./tests-process.nix
      ];
    };
}
