# Purity invariant: the gen-aspects library (../lib) is nixpkgs-lib-free — the grammar is re-hosted
# on gen-merge + gen-prelude (leaf checkers via gen-types), producing the aspect node set WITHOUT
# evalModules. A stray `lib.types`/`lib.mkOption`/`lib.evalModules`/`nixpkgs` in the library source
# fails CI. Scope: lib/**.nix + root flake.nix + default.nix. NOT ci/ (harness uses nixpkgs.lib).
{ lib, ... }:
let
  libDir = ../../lib;

  stripComments =
    text:
    lib.concatStringsSep "\n" (
      map (line: lib.head (lib.splitString "#" line)) (lib.splitString "\n" text)
    );

  walk =
    dir:
    lib.concatLists (
      lib.mapAttrsToList (
        name: type:
        if type == "directory" then
          walk (dir + "/${name}")
        else if lib.hasSuffix ".nix" name then
          [ (dir + "/${name}") ]
        else
          [ ]
      ) (builtins.readDir dir)
    );

  sources =
    map (p: {
      name = toString p;
      code = stripComments (builtins.readFile p);
    }) (walk libDir)
    ++
      map
        (rel: {
          name = rel;
          code = stripComments (builtins.readFile (../.. + "/${rel}"));
        })
        [
          "flake.nix"
          "default.nix"
        ];

  forbidden = [
    "nixpkgs"
    "lib.types"
    "lib.mkOption"
    "lib.evalModules"
    "evalModules"
    "{ lib }"
    "{ lib,"
  ];

  violations = lib.concatMap (
    src: map (tok: "${src.name}: '${tok}'") (lib.filter (tok: lib.hasInfix tok src.code) forbidden)
  ) sources;
in
{
  flake.tests.purity.test-library-source-is-nixpkgs-free = {
    expr = violations;
    expected = [ ];
  };
}
