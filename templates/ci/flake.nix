{
  inputs = {
    target.url = "github:sini/gen-aspects";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { target, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      aspects = import "${target}/lib" { inherit lib; };
      tests = import ./tests { inherit lib aspects; };
    in
    {
      inherit tests;
    };
}
