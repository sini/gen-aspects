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
  types = import ./types.nix {
    inherit prelude merge;
    inherit (schema) hashIdentity;
  };
  identity = import ./identity.nix { inherit prelude; };
  cnfModule = import ./cnf.nix;
  canTakeModule = import ./can-take.nix { inherit prelude; };
  flatten = import ./flatten.nix; # dep-free bare value
  guardModule = import ./guard.nix { inherit prelude; };
  schemaModule = import ./schema.nix {
    inherit prelude merge;
    genSchema = schema;
    inherit (types)
      aspectType
      aspectsRoot
      mkIsModuleFn
      keyCategory
      ;
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
    aspectsRoot
    aspectOrFn
    mkIsModuleFn
    canTake
    ;
  # `wrapFn cnf name fn` — wrap a single raw closure as an inspectable `__isWrappedFn` aspect include
  # (the API sibling of the type-merge's `wrapGuardFn`, for programmatically-generated includes that
  # bypass the option-type merge). See lib/types.nix.
  # `wrapGatedFn { functionArgs; onResult ? id; … } fn` — the OPT-IN self-gating sibling: its applicator
  # gates on required coords (inert `{ }` on missing, no throw) + threads `onResult` (N-GATE). See types.nix.
  inherit (types) wrapFn wrapGatedFn;
  # THE canonical, uniform aspect content-address (all three kinds). gen-link builds node ids with it;
  # den-hoag retires its `sha256 "den-aspect:${key}"` hand-roll onto it. `aspectId origin aspect`.
  inherit (types) aspectId;
  # `structuralKeys` (the six native structural option names as ONE binding) + `keyCategory cnf key` — the
  # single aspect-key classification surface a consumer reads a key's category from. See lib/types.nix.
  inherit (types) structuralKeys keyCategory;
  inherit (identity)
    aspectPath
    pathKey
    key
    isMeaningfulName
    guardKey
    keyRef
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
  # The recognised `cnf` key set as data. Every entry point above whose first argument is a `cnf`
  # constructs it through this vocabulary and refuses an off-domain key by name; `cnfKeys` is the set
  # the refusal renders, exported so a consumer — and the drift pin that checks it against the
  # library's own reads — reads it from here rather than restating it. The defaults behind it stay
  # internal: a consumer asks whether a key is RECOGNISED, and nothing outside this library needs the
  # value each key falls back to.
  inherit (cnfModule) cnfKeys;
}
