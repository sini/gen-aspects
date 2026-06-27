{
  description = "gen-aspects: aspect-oriented composition types for Nix module systems";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    gen-schema.url = "github:sini/gen-schema";
  };

  outputs =
    { nixpkgs, gen-schema, ... }:
    {
      lib = import ./lib {
        lib = nixpkgs.lib;
        schema = gen-schema.lib;
      };
    };
}
