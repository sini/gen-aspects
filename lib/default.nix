{
  inputs ? { },
  lib,
}:
let
  # gen-schema resolution: flake input or CI flake.lock fallback
  lock = builtins.fromJSON (builtins.readFile ../ci/flake.lock);
  inherit (lock.nodes.gen-schema) locked;
  schemaSrc = builtins.fetchTarball {
    url = "https://github.com/${locked.owner}/${locked.repo}/archive/${locked.rev}.zip";
    sha256 = locked.narHash;
  };
  genSchemaRaw = inputs.gen-schema or (import schemaSrc { inherit lib; });
  schemaLib =
    if builtins.isFunction genSchemaRaw then genSchemaRaw { inherit lib; } else genSchemaRaw;

  types = import ./types.nix { inherit lib; };
  identity = import ./identity.nix { inherit lib; };
  canTakeModule = import ./can-take.nix { inherit lib; };
  flatten = import ./flatten.nix { inherit lib; };
  schema = import ./schema.nix {
    inherit lib schemaLib;
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
  inherit (schema) mkAspectSchema;
  inherit flatten;
}
