# gen-aspects parity oracle (C2 gate: "parity vs old grammar"): drive the SAME representative aspect
# tree through the RE-HOSTED grammar (gen-merge) AND the ORIGINAL nixpkgs-lib grammar (main), and
# compare the flatten node set + structural identity + the guard-fn wrap. Mutation-teeth prove the
# oracle discriminates. nixpkgs is REFERENCE-side only.
let
  prelude = import /home/sini/Documents/repos/gen-prelude/lib;
  genTypes = import /home/sini/Documents/repos/gen-types/lib { inherit prelude; };
  genMerge = import /home/sini/Documents/repos/gen-merge/lib {
    inherit prelude;
    types = genTypes;
  };
  genAlgebra = import /home/sini/Documents/repos/gen-algebra/lib;
  lib = (builtins.getFlake "nixpkgs").lib;

  # re-hosted grammar (worktree) + re-hosted gen-schema
  genSchemaNew = import /home/sini/Documents/repos/gen-schema/.worktrees/c3-rehost/lib {
    inherit prelude;
    merge = genMerge;
    algebra = genAlgebra;
  };
  newAspects = import ../lib {
    inherit prelude;
    merge = genMerge;
    schema = genSchemaNew;
  };
  # original grammar (main) + original nixpkgs gen-schema (main)
  genSchemaOld = import /home/sini/Documents/repos/gen-schema/lib {
    inherit lib;
    algebra = genAlgebra;
  };
  oldAspects = import /home/sini/Documents/repos/gen-aspects/lib {
    inherit lib;
    schema = genSchemaOld;
  };

  classes = {
    nixos = { };
    home = { };
  };

  # a representative aspect config: structural options, nested aspect, class content, raw guard fn
  cfg = dbName: {
    config.aspects = {
      web = {
        description = "Web aspect";
        nixos = {
          services.nginx.enable = true;
        };
        nested = {
          description = "nested one";
        };
      };
      ${dbName} = {
        includes = [
          (
            { host, ... }:
            {
              fromHost = host.name;
            }
          )
        ];
      };
    };
  };

  driveNew =
    c:
    let
      schema = newAspects.mkAspectSchema { inherit classes; };
    in
    (genMerge.evalModuleTree {
      modules = [
        { options.schema = schema.schemaOption; }
        (schema.mkAspectModule { })
        c
      ];
    }).config.aspects;
  driveOld =
    c:
    let
      schema = oldAspects.mkAspectSchema { inherit classes; };
    in
    (lib.evalModules {
      modules = [
        { options.schema = schema.schemaOption; }
        (schema.mkAspectModule { })
        c
      ];
    }).config.aspects;

  # structural projection of the flatten node set (name/description/key per node)
  proj =
    flatten: aspectsVal:
    lib.mapAttrs (_: a: {
      inherit (a) name;
      description = a.description or null;
      key = a.key or null;
    }) (flatten aspectsVal);

  newFlat = proj newAspects.flatten (driveNew (cfg "db"));
  oldFlat = proj oldAspects.flatten (driveOld (cfg "db"));

  # guard-fn wrap parity: the raw closure under aspects.db.includes[0]
  newGuard =
    let
      g = builtins.head (driveNew (cfg "db")).db.includes;
    in
    {
      wrapped = g.__isWrappedFn or false;
      args = g.__functionArgs or null;
      applied =
        (g {
          host = {
            name = "H";
          };
        }).fromHost or "?";
    };
  oldGuard =
    let
      g = builtins.head (driveOld (cfg "db")).db.includes;
    in
    {
      wrapped = g.__isWrappedFn or false;
      args = g.__functionArgs or null;
      applied =
        (g {
          host = {
            name = "H";
          };
        }).fromHost or "?";
    };
in
{
  # PARITY: flatten node set (keys + name/description/key) identical across grammars
  parity-flatten = newFlat == oldFlat;
  parity-flatten-keys = builtins.attrNames newFlat == builtins.attrNames oldFlat;
  # PARITY: the guard-fn wrap (isWrappedFn + __functionArgs + resolution) identical
  parity-guard = newGuard == oldGuard;

  # TEETH: renaming a node changes the flatten key set (so the match above is content-meaningful)
  teeth-rename-diverges =
    builtins.attrNames (proj oldAspects.flatten (driveOld (cfg "database")))
    != builtins.attrNames oldFlat;
  # TEETH: the re-hosted grammar tracks that rename identically
  teeth-rename-parity =
    builtins.attrNames (proj newAspects.flatten (driveNew (cfg "database")))
    == builtins.attrNames (proj oldAspects.flatten (driveOld (cfg "database")));

  sample = {
    new = newFlat;
    guard = newGuard;
  };
}
