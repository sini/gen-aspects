{
  inputs = {
    gen.url = "github:sini/gen";
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
      gen,
      gen-prelude,
      gen-merge,
      gen-schema,
      nixpkgs,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      genMerge = gen-merge.lib;
      genSchema = gen-schema.lib;
      aspects = import ../lib {
        prelude = gen-prelude.lib;
        merge = genMerge;
        schema = gen-schema.lib;
      };
      defaultClasses = {
        classOne = { };
        classTwo = { };
      };
      mkSchemaEval =
        {
          # `classes` is sugar: each key lowers to a keySemantics entry with category = "class".
          # Prefer `keySemantics` directly for channel/facet keys. Both merge (keySemantics wins).
          classes ? defaultClasses,
          keySemantics ? { },
          collections ? { },
          aspectModules ? [ ],
          metaModules ? [ ],
          closedKeys ? false,
          freeformKeys ? [ ],
          recursiveClosed ? false,
          deferIncludeResolution ? false,
          rejectBareModuleInclude ? false,
          modules,
        }:
        let
          classSemantics = lib.mapAttrs (_: _: { category = "class"; }) classes;
          schema = aspects.mkAspectSchema {
            keySemantics = classSemantics // keySemantics;
            inherit
              collections
              aspectModules
              metaModules
              closedKeys
              freeformKeys
              recursiveClosed
              deferIncludeResolution
              rejectBareModuleInclude
              ;
          };
        in
        genMerge.evalModuleTree {
          modules = [
            { options.schema = schema.schemaOption; }
            (schema.mkAspectModule { })
          ]
          ++ modules;
        };
    in
    gen.lib.mkCi {
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
      };
    };
}
