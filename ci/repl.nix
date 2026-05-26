# gen-aspects REPL — all exports in scope.
let
  nixpkgs = import (builtins.getFlake "nixpkgs") { };
  aspects = import ../lib { inherit (nixpkgs) lib; };
in
{
  inherit (nixpkgs) lib;
  inherit aspects;
}
// aspects
