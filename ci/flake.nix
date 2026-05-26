{
  inputs = {
    gen-aspects.url = "github:sini/gen-aspects";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
    nix-unit.url = "github:nix-community/nix-unit";
    nix-unit.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      gen-aspects,
      nixpkgs,
      nix-unit,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      aspects = import "${gen-aspects}/lib" { inherit lib; };
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;
      tests = import ./tests { inherit lib aspects; };
    in
    {
      inherit tests;
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          assertTests = lib.mapAttrsToList (
            suite: subtests:
            lib.mapAttrsToList (
              name: t:
              if t.expr == t.expected then true
              else throw "FAIL ${suite}.${name}: got ${builtins.toJSON t.expr}, expected ${builtins.toJSON t.expected}"
            ) subtests
          ) tests;
        in
        {
          default = pkgs.runCommand "gen-aspects-tests" { } ''
            echo "${toString (builtins.length (lib.flatten assertTests))} tests passed"
            touch $out
          '';
        }
      );
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              nix-unit.packages.${system}.default
              pkgs.just
            ];
          };
        }
      );
    };
}
