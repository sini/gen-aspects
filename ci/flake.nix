{
  inputs = {
    gen-harness.url = "github:sini/gen-harness";
    gen-prelude.url = "github:sini/gen-prelude";
    gen-merge.url = "github:sini/gen-merge";
    gen-schema.url = "github:sini/gen-schema";
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
      nixpkgs,
      ...
    }:
    let
      genMerge = gen-merge.lib;
      genSchema = gen-schema.lib;
      aspects = import ../lib {
        prelude = gen-prelude.lib;
        merge = genMerge;
        schema = gen-schema.lib;
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
        genMerge.evalModuleTree {
          modules = [
            { options.schema = schema.schemaOption; }
            (schema.mkAspectModule { })
          ]
          ++ modules;
        };
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
          ;
        # The `cnf` module itself, so the suite can assert what a refusal SAYS. Nix cannot recover a
        # thrown message through `tryEval`, so message content is asserted on the renderer the throw
        # path calls, while catchability is asserted on the real path.
        cnfInternals = import ../lib/cnf.nix;
        # The published-facts module, for the same split over its one refusal. Its renderer is
        # deliberately absent from `lib/default.nix` — a consumer reads a refusal, never renders one.
        factsInternals = import ../lib/facts.nix { prelude = gen-prelude.lib; };
      };
    };
}
