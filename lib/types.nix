# gen-aspects type system — re-hosted on gen-merge (was nixpkgs lib.types/evalModules).
#
# Palmer et al. (2024) "Intensional Functions" §2: one type, dispatch in merge.
# aspectType dispatches by value shape — attrsets and module functions to
# aspectSubmodule, guard functions to a functor wrap (deferred for pipeline resolution),
# primitives pass through.
#
# Class content uses explicit deferredModule options (from cnf.classes).
# The module system's own option/freeform separation routes class keys cleanly —
# classes must be registered.
#
# Lorenzen et al. (2025) "First-Order Laziness" §1-2.3: class content is a lazy
# constructor (deferredModule) — inspectable before forcing, evaluated only when
# the consuming NixOS/homeManager evaluation imports it.
#
# Guard functions ({ host, ... }: { ... }) are preserved via a functor wrap
# (inspectable `__functor` wrapping; cf. Reynolds 1972 defunctionalization by ANALOGY —
# the closure is preserved inside __functor, not eliminated; there is no per-form
# constructor and no single global apply, so this is not the literal §6 transform).
# Re-host note: the wrap is now a hand-built functor (gen-merge has no `functionTo`);
# it reproduces the old `(lib.types.functionTo aspectSubmodule).merge … // { __isWrappedFn; … }`
# functor byte-for-byte (isAttrs + callable via __functor, tagged __isWrappedFn/name/meta).
# The pipeline resolves them when context is available — they are NOT evaluated by
# the type system.
#
# Defunctionalized guard records (guard.nix, __guard) are passed through as first-order
# data by the __guard branch below — THAT path IS the Reynolds §6 transform (closed
# predicate vocabulary + one applyGuard); the functor wrap is the non-defunctionalized
# escape hatch for raw closures.
{ prelude, merge }:
let
  identity = import ./identity.nix { inherit prelude; };
  canTake = import ./can-take.nix { inherit prelude; };
  t = merge.types;

  # Module functions take known module args — evaluated by the submodule.
  # Guard functions take context args (host/user/etc.) — wrapped for later.
  # The set of known module args is configurable via cnf.moduleArgs.
  # Default includes standard NixOS args + aspect (provided by gen-aspects).
  defaultModuleArgs = {
    lib = true;
    config = true;
    options = true;
    pkgs = true;
    modulesPath = true;
    aspect = true;
  };
  mkIsModuleFn = cnf: canTake.upTo (cnf.moduleArgs or defaultModuleArgs);

  # Raw-closure guard wrap — a hand-built functor reproducing nixpkgs `functionTo`'s merge
  # result tagged as a wrapped fn. When the pipeline applies it to a context, each def's guard
  # closure is applied and the results merge through the aspectSubmodule (deferred resolution).
  wrapGuardFn = cnf: loc: defs: {
    __functor =
      _: fnArgs:
      (aspectSubmodule cnf).merge (loc ++ [ "<function body>" ]) (
        map (d: {
          inherit (d) file;
          value = d.value fnArgs;
        }) defs
      );
    # nixpkgs `functionTo` sets `__functionArgs` (via setFunctionArgs) = the union of the guard
    # closures' formals, so downstream `functionArgs`/`lib.isFunction` see the guard's arg shape.
    __functionArgs = prelude.foldl' (acc: d: acc // builtins.functionArgs d.value) { } defs;
    __isWrappedFn = true;
    name = prelude.last loc;
    meta = {
      inherit loc;
      file = (builtins.head defs).file or "<unknown>";
    };
  };

  # Palmer's flat type. One type, dispatch in merge, no recursive type construction.
  aspectType =
    cnf:
    let
      isModuleFn = mkIsModuleFn cnf;
    in
    merge.mkOptionType {
      name = "aspect";
      check = _: true;
      merge =
        loc: defs:
        if builtins.length defs != 1 then
          if builtins.all (d: !(builtins.isAttrs d.value) && !(builtins.isFunction d.value)) defs then
            merge.mkMerge (map (d: d.value) defs)
          else
            (aspectSubmodule cnf).merge loc (
              map (
                d:
                if builtins.isFunction d.value then
                  d
                  // {
                    value = {
                      includes = [ d.value ];
                    };
                  }
                else
                  d
              ) defs
            )
        else
          let
            v = (builtins.head defs).value;
          in
          if builtins.isAttrs v && (v.__isWrappedFn or false) then
            v
          # TODO(guard): multi-def guard records not supported (single-def only) — a guard
          # record defined twice under one key loses guard-record shape (multi-def folds via
          # the `length defs != 1` path above; see ci/tests/guard.nix multidef limitation).
          else if builtins.isAttrs v && (v.__guard or false) then
            # Guard record (guard.nix) — guard PAYLOAD (pred/body) untouched; only tracing
            # name/meta attached (meta.loc gives an opaque-body guard a site-distinguished key;
            # not hashed by guardKey).
            v
            // {
              name = prelude.last loc;
              meta = (v.meta or { }) // {
                inherit loc;
                file = (builtins.head defs).file or "<unknown>";
              };
            }
          else if builtins.isFunction v && isModuleFn v then
            (aspectSubmodule cnf).merge loc defs
          else if builtins.isFunction v then
            # Guard function — wrap as inspectable functor for pipeline resolution
            # (analogy to Reynolds defunctionalization, not the literal transform).
            # Palmer §5.1: name + meta from loc for tracing/diagramming.
            wrapGuardFn cnf loc defs
          else if builtins.isAttrs v then
            (aspectSubmodule cnf).merge loc defs
          else
            (prelude.last defs).value;
    };

  # Recursion-safe binding: either doesn't force subtypes during construction.
  aspectOrFn = cnf: merge.either (aspectType cnf) (aspectSubmodule cnf);

  # Aspect entry submodule.
  # Structural options (name, includes, meta) give each aspect identity.
  # Explicit deferredModule options per registered class keep class content clean.
  # Freeform keys that aren't classes or structural become nested aspects.
  # cnf.aspectModules extends with pipeline-specific options (excludes, policies, etc.)
  aspectSubmodule =
    cnf:
    let
      classOptions = prelude.genAttrs (builtins.attrNames (cnf.classes or { })) (
        _:
        merge.mkOption {
          description = "Class content (deferred module)";
          default = { };
          type = t.deferredModule;
        }
      );
    in
    merge.submodule (
      { name, config, ... }:
      {
        freeformType = t.lazyAttrsOf (aspectType cnf);
        config._module.args.aspect = config;
        imports = cnf.aspectModules or [ ];

        options = {
          name = merge.mkOption {
            description = "Aspect name";
            default = name;
            type = t.str;
          };

          description = merge.mkOption {
            description = "Aspect description";
            default = "Aspect ${name}";
            type = t.str;
          };

          key = merge.mkOption {
            internal = true;
            readOnly = true;
            type = t.str;
            default = identity.key config;
          };

          meta = merge.mkOption {
            description = "Aspect metadata";
            default = { };
            type = merge.submodule {
              freeformType = t.lazyAttrsOf t.raw;
              imports = cnf.metaModules or [ ];
            };
          };

          includes = merge.mkOption {
            description = "Aspects to include";
            type = t.listOf (aspectOrFn cnf);
            default = [ ];
          };
        }
        // classOptions;
      }
    );

  # Top-level aspect container. Provides fixpoint: aspects can reference siblings.
  aspectsType =
    cnf:
    merge.submodule (
      { config, ... }:
      {
        freeformType = t.lazyAttrsOf (aspectType cnf);
        config._module.args.aspects = config;
      }
    );

in
{
  inherit
    aspectType
    aspectSubmodule
    aspectsType
    aspectOrFn
    mkIsModuleFn
    canTake
    ;
}
