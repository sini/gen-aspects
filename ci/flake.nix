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
      aspects = import ../lib {
        inherit lib;
        inputs = {
          gen-schema = import inputs.gen-schema { inherit lib; };
        };
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
