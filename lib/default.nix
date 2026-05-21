{ lib, schemaLib }:
let
  types = import ./types.nix { inherit lib schemaLib; };
  identity = import ./identity.nix { inherit lib; };
in
{
  inherit (types) aspectType aspectSubmodule aspectsType mkIsModuleFn canTake;
  inherit (identity) aspectPath pathKey key isMeaningfulName;

  # Re-export den-schema utilities for consumers building aspect methods/validators
  inherit (schemaLib) schemaFn mkSchemaOption;
  inherit (schemaLib._internal) mkMethodsModule;
}
