{ lib }:
let
  types = import ./types.nix { inherit lib; };
  identity = import ./identity.nix { inherit lib; };
in
{
  inherit (types) aspectType aspectSubmodule aspectsType;
  inherit (identity) aspectPath pathKey key isMeaningfulName;
}
