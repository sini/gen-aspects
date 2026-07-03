# Test: registered class content is clean (deferredModule, no structural keys).
{
  genMerge,
  lib,
  mkSchemaEval,
  ...
}:
{
  flake.tests.class-content.test-class-is-deferred-module =
    let
      eval = mkSchemaEval { modules = [ { config.aspects.myAspect.classOne.setting = "hello"; } ]; };
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

  flake.tests.class-content.test-class-content-evaluates-cleanly =
    let
      eval = mkSchemaEval { modules = [ { config.aspects.myAspect.classOne.setting = "hello"; } ]; };
      classEval = genMerge.evalModuleTree {
        modules = [
          { options.setting = genMerge.mkOption { type = genMerge.types.str; }; }
          eval.config.aspects.myAspect.classOne
        ];
      };
    in
    {
      expr = classEval.config.setting;
      expected = "hello";
    };

  flake.tests.class-content.test-multi-def-class-merges =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.myAspect.classOne.names = [ "alice" ]; }
          { config.aspects.myAspect.classOne.names = [ "bob" ]; }
        ];
      };
      classEval = genMerge.evalModuleTree {
        modules = [
          { options.names = genMerge.mkOption { type = genMerge.types.listOf genMerge.types.str; }; }
          eval.config.aspects.myAspect.classOne
        ];
      };
    in
    {
      expr = lib.sort (a: b: a < b) classEval.config.names;
      expected = [
        "alice"
        "bob"
      ];
    };

  flake.tests.class-content.test-function-def-class-content =
    let
      eval = mkSchemaEval {
        modules = [
          {
            config.aspects.myAspect =
              { aspect, ... }:
              {
                classOne.greeting = "hello ${aspect.name}";
              };
          }
        ];
      };
      classEval = genMerge.evalModuleTree {
        modules = [
          { options.greeting = genMerge.mkOption { type = genMerge.types.str; }; }
          eval.config.aspects.myAspect.classOne
        ];
      };
    in
    {
      expr = classEval.config.greeting;
      expected = "hello myAspect";
    };
}
