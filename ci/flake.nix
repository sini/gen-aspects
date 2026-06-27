{
  inputs = {
    gen.url = "github:sini/gen";
    gen-schema = {
      url = "github:sini/gen-schema";
      flake = false;
    };
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    inputs@{ gen, nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;
      # gen-schema is flake=false here; `import "${inputs.gen-schema}" { inherit lib; }`
      # runs gen-schema's root default.nix → the genSchema flat value (it auto-pins its
      # own gen-algebra from gen-schema's flake.lock). The interpolated path form (rather
      # than `import inputs.<dep>`) keeps the sweep free of flake-functor call literals.
      aspects = import ../lib {
        inherit lib;
        schema = import "${inputs.gen-schema}" { inherit lib; };
      };
      defaultClasses = {
        classOne = { };
        classTwo = { };
      };
      mkSchemaEval =
        {
          classes ? defaultClasses,
          collections ? { },
          aspectModules ? [ ],
          metaModules ? [ ],
          modules,
        }:
        let
          schema = aspects.mkAspectSchema {
            inherit
              classes
              collections
              aspectModules
              metaModules
              ;
          };
        in
        lib.evalModules {
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
      specialArgs = { inherit aspects mkSchemaEval; };
    };
}
