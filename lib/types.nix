# gen-aspects type system.
#
# Palmer et al. (2024) "Intensional Functions" §3: one type, dispatch in merge.
# aspectType dispatches by value shape — attrsets and module functions to
# aspectSubmodule, guard functions to functionTo (deferred for pipeline resolution),
# primitives pass through.
#
# Class content uses explicit deferredModule options (from cnf.classes).
# The module system's own option/freeform separation routes class keys cleanly —
# no extractClass, no structural key stripping. Classes must be registered.
#
# Lorenzen et al. (2025) "First-Order Laziness" §2.4: class content is a lazy
# constructor (deferredModule) — inspectable before forcing, evaluated only when
# the consuming NixOS/homeManager evaluation imports it.
#
# Guard functions ({ host, ... }: { ... }) are preserved via functionTo wrapping
# (Reynolds 1972 defunctionalization). The pipeline resolves them when context
# is available — they are NOT evaluated by the type system.
{ lib, schemaLib }:
let
  inherit (schemaLib._internal) mkMethodsModule;
  identity = import ./identity.nix { inherit lib; };
  canTake = import ./can-take.nix { inherit lib; };

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

  # Palmer's flat type. One type, dispatch in merge, no recursive type construction.
  aspectType =
    cnf:
    let
      isModuleFn = mkIsModuleFn cnf;
    in
    lib.types.mkOptionType {
      name = "aspect";
      check = _: true;
      merge =
        loc: defs:
        let
          # Palmer §5.1: inject ℓ (program point) for tracing/diagramming/visibility.
          # loc = option path, file = definition source, defs = all contributing definitions.
          injectMeta =
            result:
            result
            // {
              meta = (result.meta or { }) // {
                loc = loc;
                file = (lib.last defs).file or "<unknown>";
                definitionCount = builtins.length defs;
              };
            };
        in
        if builtins.length defs != 1 then
          if builtins.all (d: !(builtins.isAttrs d.value) && !(builtins.isFunction d.value)) defs then
            lib.mkMerge (map (d: d.value) defs)
          else
            injectMeta (
              (aspectSubmodule cnf).merge loc (
                map (
                  d:
                  if builtins.isFunction d.value then
                    d // { value = { includes = [ d.value ]; }; }
                  else
                    d
                ) defs
              )
            )
        else
          let
            v = (builtins.head defs).value;
          in
          if builtins.isAttrs v && (v.__isWrappedFn or false) then
            v
          else if builtins.isFunction v && isModuleFn v then
            injectMeta ((aspectSubmodule cnf).merge loc defs)
          else if builtins.isFunction v then
            # Guard function — wrap for pipeline resolution (Reynolds defunctionalization).
            (lib.types.functionTo (aspectSubmodule cnf)).merge (loc ++ [ "<function body>" ]) defs
            // {
              __isWrappedFn = true;
              name = lib.last loc;
              meta = {
                loc = loc;
                file = (builtins.head defs).file or "<unknown>";
              };
            }
          else if builtins.isAttrs v then
            injectMeta ((aspectSubmodule cnf).merge loc defs)
          else
            (lib.last defs).value;
    };

  # Recursion-safe binding: either doesn't force subtypes during construction.
  aspectOrFn = cnf: lib.types.either (aspectType cnf) (aspectSubmodule cnf);

  # Aspect entry submodule.
  # Structural options (name, includes, meta, provides) give each aspect identity.
  # Explicit deferredModule options per registered class keep class content clean.
  # Freeform keys that aren't classes or structural become nested aspects.
  aspectSubmodule =
    cnf:
    let
      classOptions = lib.genAttrs (builtins.attrNames (cnf.classes or { })) (
        _:
        lib.mkOption {
          description = "Class content (deferred module)";
          default = { };
          type = lib.types.deferredModule;
        }
      );
    in
    lib.types.submodule (
      { name, config, ... }:
      {
        freeformType = lib.types.lazyAttrsOf (aspectType cnf);
        config._module.args.aspect = config;
        imports =
          (cnf.aspectModules or [ ])
          ++ lib.optional ((cnf.aspectMethods or { }) != { })
            (mkMethodsModule "aspect" cnf.aspectMethods);

        options =
          {
            name = lib.mkOption {
              description = "Aspect name";
              default = name;
              type = lib.types.str;
            };

            description = lib.mkOption {
              description = "Aspect description";
              default = "Aspect ${name}";
              type = lib.types.str;
            };

            key = lib.mkOption {
              internal = true;
              readOnly = true;
              type = lib.types.str;
              default = identity.key config;
            };

            meta = lib.mkOption {
              description = "Aspect metadata";
              default = { };
              type = lib.types.submodule {
                freeformType = lib.types.lazyAttrsOf lib.types.raw;
              };
            };

            includes = lib.mkOption {
              description = "Aspects to include";
              type = lib.types.listOf (aspectOrFn cnf);
              default = [ ];
            };
          }
          // classOptions;
      }
    );

  # Top-level aspect container. Provides fixpoint: aspects can reference siblings.
  aspectsType =
    cnf:
    lib.types.submodule (
      { config, ... }:
      {
        freeformType = lib.types.lazyAttrsOf (aspectType cnf);
        config._module.args.aspects = config;
      }
    );

in
{
  inherit aspectType aspectSubmodule aspectsType mkIsModuleFn canTake;
}
