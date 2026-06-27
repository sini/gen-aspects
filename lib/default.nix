{
  lib,
  schema,
}:
let
  types = import ./types.nix { inherit lib; };
  identity = import ./identity.nix { inherit lib; };
  canTakeModule = import ./can-take.nix { inherit lib; };
  flatten = import ./flatten.nix { inherit lib; };
  schemaModule = import ./schema.nix {
    inherit lib;
    genSchema = schema;
    inherit (types) aspectType mkIsModuleFn;
    inherit (identity)
      aspectPath
      pathKey
      key
      isMeaningfulName
      ;
    canTake = canTakeModule;
  };
in
{
  # Legacy API preserved for backward compat
  inherit (types)
    aspectType
    aspectSubmodule
    aspectsType
    aspectOrFn
    mkIsModuleFn
    canTake
    ;
  inherit (identity)
    aspectPath
    pathKey
    key
    isMeaningfulName
    ;
  # New API
  inherit (schemaModule) mkAspectSchema;
  inherit flatten;
}
