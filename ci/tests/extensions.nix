# Test: pipeline-provided aspect extensions via cnf.aspectModules.
# Den uses this to add excludes, policies, and other pipeline options.
{
  genMerge,
  lib,
  mkSchemaEval,
  ...
}:
let
  mkEval =
    modules:
    mkSchemaEval {
      classes.classOne = { };
      aspectModules = [
        {
          options.excludes = genMerge.mkOption {
            description = "Aspects to exclude from resolution";
            type = genMerge.types.listOf genMerge.types.str;
            default = [ ];
          };
          options.priority = genMerge.mkOption {
            description = "Resolution priority";
            type = genMerge.types.int;
            default = 100;
          };
        }
      ];
      inherit modules;
    };
in
{
  flake.tests.extensions.test-extension-option-has-default =
    let
      eval = mkEval [ { config.aspects.foo.classOne = { }; } ];
    in
    {
      expr = {
        excludes = eval.config.aspects.foo.excludes;
        priority = eval.config.aspects.foo.priority;
      };
      expected = {
        excludes = [ ];
        priority = 100;
      };
    };

  flake.tests.extensions.test-extension-option-settable =
    let
      eval = mkEval [
        {
          config.aspects.foo = {
            excludes = [
              "bar"
              "baz"
            ];
            priority = 50;
            classOne.x = "hello";
          };
        }
      ];
    in
    {
      expr = {
        excludes = eval.config.aspects.foo.excludes;
        priority = eval.config.aspects.foo.priority;
      };
      expected = {
        excludes = [
          "bar"
          "baz"
        ];
        priority = 50;
      };
    };

  flake.tests.extensions.test-extension-on-nested-aspect =
    let
      eval = mkEval [
        { config.aspects.parent.child.excludes = [ "something" ]; }
      ];
    in
    {
      expr = eval.config.aspects.parent.child.excludes;
      expected = [ "something" ];
    };

  flake.tests.extensions.test-extension-coexists-with-class-content =
    let
      eval = mkEval [
        {
          config.aspects.foo = {
            excludes = [ "bar" ];
            classOne.setting = "hello";
          };
        }
      ];
      classEval = genMerge.evalModuleTree {
        modules = [
          { options.setting = genMerge.mkOption { type = genMerge.types.str; }; }
          eval.config.aspects.foo.classOne
        ];
      };
    in
    {
      expr = {
        excludes = eval.config.aspects.foo.excludes;
        setting = classEval.config.setting;
      };
      expected = {
        excludes = [ "bar" ];
        setting = "hello";
      };
    };
}
