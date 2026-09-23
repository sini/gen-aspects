# G-c — type-native rejection of a bare-module include (owner-ratified replacement for den-hoag's
# reservedClassInclude). With `rejectBareModuleInclude` on, an includes element that is a bare module
# `{ imports = [ … ]; }` (a class-content deferredModule collapse, no aspect identity) throws NAMED at the
# type — `imports` is the module merge slot, NEVER a valid aspect content key, so this is UNIQUELY a
# class-named node mis-included as an aspect. Default OFF ⇒ unchanged (absorbed as a module: the imported
# content reaches the aspect, and `imports` never becomes a content key). Reproduces
# den-hoag's `isClassContentCollapse` discriminator at the TYPE (structural, not a value-heuristic).
{
  mkSchemaEval,
  genMerge,
  ...
}:
let
  bareModule = {
    imports = [ { classOne.marker = 1; } ];
  };
  # The include as the aspect reads it, and the class content it carries, read as a module.
  includeOf =
    inc:
    builtins.head
      (mkSchemaEval {
        modules = [ { config.aspects.main.includes = [ inc ]; } ];
      }).config.aspects.main.includes;
  absorbed = inc: {
    marker =
      if inc.classOne == null then
        "<no class content>"
      else
        (genMerge.evalModuleTree {
          modules = [
            { options.marker = genMerge.mkOption { type = genMerge.types.int; }; }
            inc.classOne
          ];
        }).config.marker;
    importsKey = inc ? imports;
  };
  forceInc =
    cnf:
    builtins.tryEval (
      builtins.deepSeq (builtins.head
        (mkSchemaEval (
          cnf
          // {
            modules = [ { config.aspects.main.includes = [ bareModule ]; } ];
          }
        )).config.aspects.main.includes
      ) true
    );
  rejected = forceInc { rejectBareModuleInclude = true; };
  legitOk = builtins.tryEval (
    builtins.deepSeq
      (mkSchemaEval {
        rejectBareModuleInclude = true;
        modules = [
          (
            { config, ... }:
            {
              config.aspects = {
                main.includes = [ config.aspects.helper ];
                helper.classOne = { };
              };
            }
          )
        ];
      }).config.aspects.main.includes
      true
  );
in
{
  flake.tests.bare-module-include.test-bare-module-rejected = {
    expr = rejected.success;
    expected = false;
  };
  # The imported CONTENT is absorbed, as the by-value control's is.
  flake.tests.bare-module-include.test-default-off-absorbs = {
    expr = absorbed (includeOf bareModule);
    expected = {
      marker = 1;
      importsKey = false;
    };
  };
  flake.tests.bare-module-include.test-by-value-include-control = {
    expr = absorbed (includeOf {
      classOne.marker = 1;
    });
    expected = {
      marker = 1;
      importsKey = false;
    };
  };
  flake.tests.bare-module-include.test-legit-aspect-include-ok = {
    expr = legitOk.success;
    expected = true;
  };
}
