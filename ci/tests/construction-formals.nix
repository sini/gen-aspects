# den-hoag-q17cc · a construction formal at the kind entry's top level — the cells that must stay GREEN,
# and the population pin. The by-name refusals are in `ci/tests-error.nix`
# (`construction-formal-refusals`). A door that refused every top-level key, or every instance field
# named like a formal, reds the controls here; a door that perturbed the kind reds the mark cell.
{
  lib,
  genMerge,
  aspects,
  mkSchemaEval,
  prelude,
  ...
}:
let
  int0 = genMerge.mkOption {
    type = genMerge.types.int;
    default = 0;
  };
  evalWith =
    modules:
    (mkSchemaEval {
      modules = [
        {
          config.schema.aspect.options.priority = int0;
          config.aspects.foo = { };
          config.aspects.bar = { };
        }
      ]
      ++ modules;
    }).config;
  refuses = v: !(builtins.tryEval (builtins.deepSeq v v)).success;
  kindKeysWith =
    entry: builtins.attrNames (evalWith [ { config.schema.aspect = entry; } ]).schema.aspect;

  # THE POPULATION, read off the bindings: this library's `cnfKeys`, and gen-schema's half off its
  # published `_reservedCollectionKeys` (its module keys, shorthand metadata and `_`-prefixed names
  # taken back out leave exactly the names its declaration-key door reserves).
  schemaConfig = (evalWith [ ]).schema;
  genSchemaHalf = builtins.filter (
    k:
    !(prelude.hasPrefix "_" k)
    && !(builtins.elem k (schemaConfig._declarationKeys ++ genMerge.moduleSyntax.shorthandMeta))
  ) schemaConfig._reservedCollectionKeys;
  population = prelude.unique (aspects.cnfKeys ++ genSchemaHalf);
in
{
  flake.tests.construction-formals = {
    # ★ THE KIND VALUE MOUNTS IN NIXPKGS (den-hoag-r05lc). The reservation rides on a functor record
    # nixpkgs never reads, so a nixpkgs `lib.evalModules` importing `config.schema.aspect` serves an
    # attrset entry carrying `options` (a content-level marker is an unsupported attribute there) and
    # a function entry (where it landed as a `__reservedKeys` key on an open freeform), each as the
    # same definitions mounted raw. den imports the kind value into its nixpkgs aspect submodule.
    test-kind-value-mounts-in-nixpkgs =
      let
        port = lib.mkOption {
          type = lib.types.int;
          default = 1;
        };
        kindOf =
          entry: (mkSchemaEval { modules = [ { config.schema.aspect = entry; } ]; }).config.schema.aspect;
        mount =
          m:
          (lib.evalModules {
            modules = [
              {
                options.h = lib.mkOption {
                  type = lib.types.submodule {
                    imports = [ m ];
                    freeformType = lib.types.lazyAttrsOf lib.types.anything;
                  };
                  default = { };
                };
              }
            ];
          }).config.h;
        attrsDef = {
          options.port = port;
        };
        functionDef = { lib, ... }: { };
      in
      {
        expr = {
          attrs = mount (kindOf attrsDef);
          function = mount (kindOf functionDef);
        };
        expected = {
          attrs = mount attrsDef;
          function = mount functionDef;
        };
      };

    # G8 · every member refuses on the mkAspectSchema path. The value is the list of members that did
    # NOT refuse. Both halves non-empty and an ordinary key admitted are the live controls.
    test-population-refuses = {
      expr = {
        halves = {
          cnf = builtins.elem "providerPrefix" population;
          genSchema = builtins.elem "computed" population;
        };
        admitted = builtins.filter (
          f:
          !(refuses (kindKeysWith {
            ${f} = { };
          }))
        ) population;
        ordinary = refuses (kindKeysWith {
          priority = 7;
        });
      };
      expected = {
        halves = {
          cnf = true;
          genSchema = true;
        };
        admitted = [ ];
        ordinary = false;
      };
    };

    # G3/G4 · the routes that are not the misreading still write: a declared extension as shorthand,
    # a formal-named field on the instance, and one under `config.` on the entry.
    test-instance-routes-still-write =
      let
        # Two evaluations: the entry's `config.` route applies to every instance, so in one tree the
        # instance's own write would merge with it.
        c = evalWith [
          { config.schema.aspect.priority = 7; }
          { config.schema.aspect.config.keySemantics = "viaConfig"; }
        ];
        d = evalWith [ { config.aspects.foo.keySemantics = "direct"; } ];
      in
      {
        expr = {
          priority = c.aspects.bar.priority;
          direct = d.aspects.foo.keySemantics;
          viaConfig = c.aspects.bar.keySemantics;
        };
        expected = {
          priority = 7;
          direct = "direct";
          viaConfig = "viaConfig";
        };
      };

    # G9 · the clean kind's mark is the one it minted before the door existed.
    test-clean-kind-mark-unmoved = {
      expr = (evalWith [ ]).schema.aspect.__mint.minted;
      expected = "schemakind:076e00e60a6ad55a288d5c067a560186877622488d5c40127bf98408638c9410";
    };

    # ★ THE IMPORTS ROUTE IS REFUSED (den-hoag-8x97u). A formal at the top level of a module the entry
    # IMPORTS refuses at gen-merge's collector, which reads the reservation `mkType` marks its
    # modules with; the message is pinned in `ci/tests-error.nix` (`imports-route-refusals`). This
    # cell was the boundary pin while the route was residue, reading `true` for "still lands". The
    # read stays shallow (the key list).
    test-imported-formal-refused = {
      expr = refuses (
        builtins.attrNames
          (evalWith [ { config.schema.aspect.imports = [ { keySemantics.darwin.category = "class"; } ]; } ])
          .aspects.bar
      );
      expected = true;
    };
  };
}
