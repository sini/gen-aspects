# Test: registered class content is clean (deferredModule, no structural keys).
{ lib, mkDefaultEval }:
{
  test-class-is-deferred-module =
    let
      eval = mkDefaultEval [{ config.aspects.myAspect.classOne.setting = "hello"; }];
      classVal = eval.config.aspects.myAspect.classOne;
    in
    {
      expr = {
        hasImports = classVal ? imports;
        noName = !(classVal ? name);
        noIncludes = !(classVal ? includes);
        noMeta = !(classVal ? meta);
      };
      expected = {
        hasImports = true;
        noName = true;
        noIncludes = true;
        noMeta = true;
      };
    };

  test-class-content-evaluates-cleanly =
    let
      eval = mkDefaultEval [{ config.aspects.myAspect.classOne.setting = "hello"; }];
      classEval = lib.evalModules {
        modules = [
          { options.setting = lib.mkOption { type = lib.types.str; }; }
          eval.config.aspects.myAspect.classOne
        ];
      };
    in
    {
      expr = classEval.config.setting;
      expected = "hello";
    };

  test-multi-def-class-merges =
    let
      eval = mkDefaultEval [
        { config.aspects.myAspect.classOne.names = [ "alice" ]; }
        { config.aspects.myAspect.classOne.names = [ "bob" ]; }
      ];
      classEval = lib.evalModules {
        modules = [
          { options.names = lib.mkOption { type = lib.types.listOf lib.types.str; }; }
          eval.config.aspects.myAspect.classOne
        ];
      };
    in
    {
      expr = lib.sort (a: b: a < b) classEval.config.names;
      expected = [ "alice" "bob" ];
    };

  test-function-def-class-content =
    let
      eval = mkDefaultEval [
        {
          config.aspects.myAspect =
            { aspect, ... }:
            {
              classOne.greeting = "hello ${aspect.name}";
            };
        }
      ];
      classEval = lib.evalModules {
        modules = [
          { options.greeting = lib.mkOption { type = lib.types.str; }; }
          eval.config.aspects.myAspect.classOne
        ];
      };
    in
    {
      expr = classEval.config.greeting;
      expected = "hello myAspect";
    };
}
