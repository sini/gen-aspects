# G-c — type-native rejection of a bare-module include (owner-ratified replacement for den-hoag's
# reservedClassInclude). With `rejectBareModuleInclude` on, an includes element that is a bare module
# `{ imports = [ … ]; }` (a class-content deferredModule collapse, no aspect identity) throws NAMED at the
# type — `imports` is the module merge slot, NEVER a valid aspect content key, so this is UNIQUELY a
# class-named node mis-included as an aspect. Default OFF ⇒ unchanged (absorbed as a module). Reproduces
# den-hoag's `isClassContentCollapse` discriminator at the TYPE (structural, not a value-heuristic).
{
  mkSchemaEval,
  ...
}:
let
  bareModule = {
    imports = [ { config = { }; } ];
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
  offOk = forceInc { };
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
  flake.tests.bare-module-include.test-default-off-absorbs = {
    expr = offOk.success;
    expected = true;
  };
  flake.tests.bare-module-include.test-legit-aspect-include-ok = {
    expr = legitOk.success;
    expected = true;
  };
}
