# gen-aspects — re-hosted on the pure-gen stack (gen-prelude + gen-merge), bypassing nixpkgs.
#   prelude : gen-prelude.lib (pure utility base)
#   merge   : gen-merge.lib (evalModuleTree + structural types + mkOption/mkMerge/… ; the lib.types
#             + lib.evalModules replacement — leaf checkers come from gen-types via merge.types)
#   schema  : the (re-hosted, pure) gen-schema.lib — mkAspectSchema wraps aspectType for its
#             kind-level infrastructure.
# The grammar (types.nix) produces the aspect node set WITHOUT evalModules; nixpkgs.lib-free.
{
  prelude,
  merge,
  schema,
}:
let
  types = import ./types.nix { inherit prelude merge; };
  identity = import ./identity.nix { inherit prelude; };
  canTakeModule = import ./can-take.nix { inherit prelude; };
  flatten = import ./flatten.nix; # dep-free bare value
  guardModule = import ./guard.nix { inherit prelude; };
  schemaModule = import ./schema.nix {
    inherit prelude merge;
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
    guardKey
    ;
  # New API
  inherit (schemaModule) mkAspectSchema;
  inherit flatten;
  inherit (guardModule)
    mkGuardVocab
    toArgData
    pred
    guard
    ;
  # base (form-less) vocab; consumers with cnf.guardForms use (mkGuardVocab cnf).applyGuard
  applyGuard = (guardModule.mkGuardVocab { }).applyGuard;
}
