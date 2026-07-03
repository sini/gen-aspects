# Local runner for the re-hosted gen-aspects suite (until deps are published + nix-unit CI can
# resolve them). Mirrors ci/flake.nix's `mkSchemaEval`, but on gen-merge's evalModuleTree, with the
# re-hosted (pure) gen-schema. Supplies specialArgs from local sibling repos + getFlake nixpkgs
# (nixpkgs `lib` is used ONLY by the test harness/assertions, never by ../lib).
let
  prelude = import /home/sini/Documents/repos/gen-prelude/lib;
  genTypes = import /home/sini/Documents/repos/gen-types/lib { inherit prelude; };
  genMerge = import /home/sini/Documents/repos/gen-merge/lib {
    inherit prelude;
    types = genTypes;
  };
  genAlgebra = import /home/sini/Documents/repos/gen-algebra/lib;
  genSchema = import /home/sini/Documents/repos/gen-schema/.worktrees/c3-rehost/lib {
    inherit prelude;
    merge = genMerge;
    algebra = genAlgebra;
  };
  lib = (builtins.getFlake "nixpkgs").lib;

  aspects = import ../lib {
    inherit prelude;
    merge = genMerge;
    schema = genSchema;
  };

  defaultClasses = {
    classOne = { };
    classTwo = { };
  };
  mkSchemaEval =
    {
      classes ? defaultClasses,
      collections ? { },
      aspectModules ? [ ],
      metaModules ? [ ],
      modules,
    }:
    let
      schema = aspects.mkAspectSchema {
        inherit
          classes
          collections
          aspectModules
          metaModules
          ;
      };
    in
    genMerge.evalModuleTree {
      modules = [
        { options.schema = schema.schemaOption; }
        (schema.mkAspectModule { })
      ]
      ++ modules;
    };

  specialArgs = {
    inherit
      aspects
      mkSchemaEval
      genMerge
      genTypes
      lib
      ;
  };

  # collect flake.tests.<suite>.<name> across ci/tests/*.nix
  testFiles =
    let
      names = builtins.attrNames (builtins.readDir ./tests);
    in
    map (n: ./tests + "/${n}") (builtins.filter (n: lib.hasSuffix ".nix" n) names);

  collect = builtins.concatMap (
    f:
    let
      out = (import f specialArgs).flake.tests;
    in
    builtins.concatMap (
      suite:
      map (tn: {
        name = "${builtins.baseNameOf f}:${suite}.${tn}";
        inherit (out.${suite}.${tn}) expr expected;
      }) (builtins.attrNames out.${suite})
    ) (builtins.attrNames out)
  ) testFiles;

  results = map (
    tc:
    let
      e = builtins.tryEval (builtins.deepSeq tc.expr (tc.expr == tc.expected));
    in
    {
      inherit (tc) name;
      pass = e.success && e.value;
    }
  ) collect;

  failures = map (r: r.name) (builtins.filter (r: !r.pass) results);
in
{
  total = builtins.length collect;
  passed = builtins.length (builtins.filter (r: r.pass) results);
  inherit failures;
}
