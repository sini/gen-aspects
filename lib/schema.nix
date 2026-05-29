# gen-schema integration: mkAspectSchema wraps aspectType for gen-schema's
# kind-level infrastructure (collections, introspection, extension).
{
  lib,
  genSchema,
  aspectType,
  mkIsModuleFn,
  aspectPath,
  pathKey,
  key,
  isMeaningfulName,
  canTake,
}:
{
  mkAspectSchema =
    cnf:
    let
      schemaOpt = genSchema.mkSchemaOption {
        collections = cnf.collections or { };
        mkType =
          {
            kindModule,
            collections,
            defs ? [ ],
            kind,
          }:
          let
            # Build a module from user-declared defs on the schema kind entry
            # (e.g. options.priority = mkOption {...}). These defs extend each
            # aspect instance with the declared options.
            defsModules = map (d: d.value) (builtins.filter (d: builtins.isAttrs d.value) defs);
            allModules = defsModules ++ lib.optional (kindModule != null) kindModule;
          in
          # Return a merged VALUE (not a type). This is what config.schema.aspect
          # evaluates to. __functor makes it importable as a module.
          # __defsModule carries schema-declared options for mkAspectModule to inject.
          {
            __functor =
              _:
              { ... }:
              {
                imports = allModules;
              };
            inherit kind;
          }
          // collections
          // lib.optionalAttrs (defsModules != [ ]) {
            __defsModule = {
              imports = defsModules;
            };
          };
      };
    in
    {
      schemaOption = schemaOpt;

      mkAspectOption =
        {
          providerPrefix ? [ ],
        }:
        lib.mkOption {
          description = "Aspects";
          default = { };
          type = lib.types.lazyAttrsOf (aspectType (cnf // { inherit providerPrefix; }));
        };

      # mkAspectModule is a NixOS module that declares options.aspects and
      # options.schema together, lazily threading schema-declared options
      # (e.g. options.priority on schema.aspect) into each aspect instance.
      # Use instead of mkAspectOption when schema extension should propagate
      # to instances.
      mkAspectModule =
        {
          providerPrefix ? [ ],
        }:
        { config, ... }:
        {
          options.aspects = lib.mkOption {
            description = "Aspects";
            default = { };
            type = lib.types.lazyAttrsOf (
              aspectType (
                cnf
                // {
                  inherit providerPrefix;
                  # Lazily inject schema-declared option modules into every instance.
                  # config.schema.aspect.__defsModule carries the merged module built
                  # from user defs on the schema kind entry (e.g. options.priority).
                  aspectModules =
                    (cnf.aspectModules or [ ])
                    ++ lib.optional (
                      config ? schema && config.schema ? aspect && config.schema.aspect ? __defsModule
                    ) config.schema.aspect.__defsModule;
                }
              )
            );
          };
        };

      mkNamespaceType =
        { }:
        lib.types.submodule (
          { name, ... }:
          {
            options.schema = lib.mkOption {
              description = "Namespace schema";
              default = { };
              type = lib.types.submodule {
                freeformType = lib.types.lazyAttrsOf lib.types.deferredModule;
              };
            };
            options.classes = lib.mkOption {
              description = "Class declarations";
              default = { };
              type = lib.types.lazyAttrsOf lib.types.raw;
            };
            freeformType = lib.types.lazyAttrsOf (aspectType (cnf // { providerPrefix = [ name ]; }));
          }
        );

      # Re-exports for convenience
      inherit aspectType;
      inherit
        aspectPath
        pathKey
        key
        isMeaningfulName
        ;
      inherit canTake;
      inherit mkIsModuleFn;

      # Bundled identity functions for structured access
      identity = {
        inherit
          aspectPath
          pathKey
          key
          isMeaningfulName
          ;
      };
    };
}
