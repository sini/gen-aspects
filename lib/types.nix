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
{ lib }:
let
  identity = import ./identity.nix { inherit lib; };
  canTake = import ./can-take.nix { inherit lib; };

  # Module functions take lib/config/options — evaluated by the submodule.
  # Guard functions take other args (host/user/etc.) — wrapped for later.
  isModuleFn = canTake.upTo {
    lib = true;
    config = true;
    options = true;
    aspect = true;
  };

  # Palmer's flat type. One type, dispatch in merge, no recursive type construction.
  aspectType =
    cnf:
    lib.types.mkOptionType {
      name = "aspect";
      check = _: true;
      merge =
        loc: defs:
        if builtins.length defs != 1 then
          if builtins.all (d: !(builtins.isAttrs d.value) && !(builtins.isFunction d.value)) defs then
            lib.mkMerge (map (d: d.value) defs)
          else
            (aspectSubmodule cnf).merge loc (
              map (
                d:
                if builtins.isFunction d.value then
                  d // { value = { includes = [ d.value ]; }; }
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
          else if builtins.isFunction v && isModuleFn v then
            (aspectSubmodule cnf).merge loc defs
          else if builtins.isFunction v then
            # Guard function — wrap for pipeline resolution (Reynolds defunctionalization)
            (lib.types.functionTo (aspectSubmodule cnf)).merge (loc ++ [ "<function body>" ]) defs
            // { __isWrappedFn = true; }
          else if builtins.isAttrs v then
            (aspectSubmodule cnf).merge loc defs
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
        imports = [ (lib.mkAliasOptionModule [ "_" ] [ "provides" ]) ];

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
                options.aspect-chain = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = cnf.aspectChain or [ ];
                };
              };
            };

            includes = lib.mkOption {
              description = "Aspects to include";
              type = lib.types.listOf (aspectOrFn cnf);
              default = [ ];
            };

            provides = lib.mkOption {
              description = "Named sub-aspects";
              default = { };
              type = lib.types.submodule (
                { config, ... }:
                {
                  freeformType = lib.types.lazyAttrsOf (
                    aspectOrFn (cnf // { aspectChain = (cnf.aspectChain or [ ]) ++ [ name ]; })
                  );
                  config._module.args.aspects = config;
                }
              );
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
  inherit aspectType aspectSubmodule aspectsType isModuleFn canTake;
}
