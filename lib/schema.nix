# gen-schema integration: mkAspectSchema wraps aspectType for gen-schema's
# kind-level infrastructure (collections, introspection, extension).
# Ported: genSchema is the pure (gen-merge-backed) gen-schema; types/mkOption come from gen-merge.
{
  prelude,
  merge,
  genSchema,
  aspectType,
  aspectsRoot,
  mkIsModuleFn,
  aspectPath,
  pathKey,
  key,
  isMeaningfulName,
  canTake,
  keyCategory,
}:
let
  t = merge.types;
  inherit (import ./cnf.nix) extendCnf checkedEntry cnfKeys;
  checkedOpts = door: prelude.checkOptions "gen-aspects.mkAspectSchema.${door}";

  # Bound ONCE, outside the per-cnf function: it reads no cnf, and gen-schema's entry type compares
  # it as a sealed component by value, so a per-call lambda would make two schemas over one cnf two
  # constructions (den-hoag-bfc0k).
  mkType =
    {
      kindModule,
      collections,
      defs ? [ ],
      kind,
    }:
    let
      # Build a module from caller-declared defs on the schema kind entry
      # (e.g. options.priority = mkOption {...}). These defs extend each
      # aspect instance with the declared options.
      #
      # A def's TOP-LEVEL key naming an mkAspectSchema construction formal (`cnfKeys`) refuses by
      # name (den-hoag-q17cc): every def here is handed to the instance evaluation whole, so the key
      # would land on every aspect as a nested aspect while the kind's own formal stays what the
      # constructor fixed. gen-schema refuses its own formals first (`collections`, `keySemantics`
      # are in both sets), because its check wraps this whole result. A module the def IMPORTS is
      # reached at gen-merge's collector instead (den-hoag-8x97u): the modules built here carry
      # `reservation`, below, so each write meets exactly one of the two doors.
      formalNamed = prelude.concatMap (
        d: if builtins.isAttrs d.value then builtins.filter (k: d.value ? ${k}) cnfKeys else [ ]
      ) defs;
      defsModules =
        if formalNamed != [ ] then
          throw "gen-aspects: kind '${kind}': declaration key '${builtins.head formalNamed}' is an mkAspectSchema construction formal — it is fixed by `mkAspectSchema { ${builtins.head formalNamed} = …; }`, and written on a kind entry it is not read as one; pass it there, or write `config.${builtins.head formalNamed}` for an instance field of that name, which a `closedKeys` schema must declare or list in `freeformKeys`"
        else
          map (
            d:
            if d.value ? __functor then
              {
                __reservedKeys = reservation;
                imports = [ d.value ];
              }
            else
              d.value // { __reservedKeys = reservation; }
          ) (builtins.filter (d: builtins.isAttrs d.value) defs);
      # THE IMPORTS-ROUTE RESERVATION (den-hoag-8x97u). The instance modules here (`__defsModule`
      # and the functor's `allModules`) are built by this library, not gen-schema, so it marks them
      # itself with gen-merge's `__reservedKeys`: `cnfKeys` with this library's text, united with
      # gen-schema's `entryReservation kind` (its formals, its published names, and the kind shape the
      # `inherits` alias reads, exempt), gen-schema's text winning on the shared names as its door
      # does on direct defs. The marker rides in place on an attrset def; a functor def is wrapped,
      # because its applied result would drop an in-place key.
      reservation =
        let
          r = genSchema.entryReservation kind;
        in
        r
        // {
          names =
            builtins.listToAttrs (
              map (f: {
                name = f;
                value = "gen-aspects: kind '${kind}': declaration key '${f}' is an mkAspectSchema construction formal, written in a module this kind entry imports — it is fixed by `mkAspectSchema { ${f} = …; }`, and written there it is not read as one; pass it there, or write `config.${f}` for an instance field of that name, which a `closedKeys` schema must declare or list in `freeformKeys`";
              }) cnfKeys
            )
            // r.names;
        };
      allModules = defsModules ++ prelude.optional (kindModule != null) kindModule;
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
    // prelude.optionalAttrs (defsModules != [ ]) {
      __defsModule = {
        imports = defsModules;
      };
    };
in
{
  mkAspectSchema = checkedEntry (
    cnf:
    let
      # A collection named for a construction formal would make that formal's key on a kind entry
      # read as a collection, and the door in `mkType` would no longer see it.
      formalCollections = builtins.filter (k: cnf.collections ? ${k}) cnfKeys;
      schemaOpt =
        if formalCollections != [ ] then
          throw "gen-aspects: mkAspectSchema: collection '${builtins.head formalCollections}' is reserved — it is an mkAspectSchema construction formal"
        else
          genSchema.mkSchemaOption {
            collections = cnf.collections;
            # Record per-key semantics opaquely on each schema entry (load-bearing introspection).
            keySemantics = cnf.keySemantics;
            inherit mkType;
          };
    in
    {
      schemaOption = schemaOpt;

      # cnf-closed classification surface: `schema.keyCategory key` reads a key's category against THIS
      # schema's keySemantics (the single-authority read; see lib/types.nix keyCategory).
      keyCategory = keyCategory cnf;

      # Three options doors (every field optional, the set closed). Each refuses an unknown field by
      # name through the shared check, and forces that check at the call rather than inside the type,
      # where a native closed formal refused it uncatchably.
      mkAspectOption =
        opts:
        let
          providerPrefix = (checkedOpts "mkAspectOption" [ "providerPrefix" ] opts).providerPrefix or [ ];
        in
        builtins.seq providerPrefix merge.mkOption {
          description = "Aspects";
          default = { };
          # aspectsRoot (re-rooting container) → nested aspect identity is container-relative (A-IDENT 2b).
          type = aspectsRoot (extendCnf cnf { inherit providerPrefix; });
        };

      # mkAspectModule is a NixOS module that declares options.aspects and
      # options.schema together, lazily threading schema-declared options
      # (e.g. options.priority on schema.aspect) into each aspect instance.
      # Use instead of mkAspectOption when schema extension should propagate
      # to instances.
      mkAspectModule =
        opts:
        let
          providerPrefix = (checkedOpts "mkAspectModule" [ "providerPrefix" ] opts).providerPrefix or [ ];
        in
        builtins.seq providerPrefix (
          { config, ... }:
          {
            options.aspects = merge.mkOption {
              description = "Aspects";
              default = { };
              # aspectsRoot (re-rooting container) → nested aspect identity is container-relative (A-IDENT 2b).
              type = aspectsRoot (
                extendCnf cnf {
                  inherit providerPrefix;
                  # Lazily inject schema-declared option modules into every instance.
                  # config.schema.aspect.__defsModule carries the merged module built
                  # from caller defs on the schema kind entry (e.g. options.priority).
                  # Stated as a term, not appended to `aspectModules`: the type relation must
                  # not read `config` (lib/cnf.nix `schemaDefs`).
                  schemaDefs = {
                    term = "config.schema.aspect.__defsModule";
                    module = {
                      imports = prelude.optional (
                        config ? schema && config.schema ? aspect && config.schema.aspect ? __defsModule
                      ) config.schema.aspect.__defsModule;
                    };
                  };
                }
              );
            };
          }
        );

      mkNamespaceType =
        opts:
        builtins.seq (checkedOpts "mkNamespaceType" [ ] opts) merge.submodule (
          { name, ... }:
          {
            options.schema = merge.mkOption {
              description = "Namespace schema";
              default = { };
              type = merge.submodule {
                freeformType = t.lazyAttrsOf t.deferredModule;
              };
            };
            options.classes = merge.mkOption {
              description = "Class declarations";
              default = { };
              type = t.lazyAttrsOf t.raw;
            };
            # aspectsRoot (re-rooting) → aspect identity is relative to the namespace's aspect root (A-IDENT 2b).
            freeformType = aspectsRoot (extendCnf cnf { providerPrefix = [ name ]; });
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
    }
  );
}
