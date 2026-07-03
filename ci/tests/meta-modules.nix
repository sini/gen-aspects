# Test: extensible meta submodule via cnf.metaModules.
# Consumers can declare typed meta options without hardcoding them in gen-aspects.
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
      metaModules = [
        {
          options.guard = genMerge.mkOption {
            description = "Guard predicate for conditional aspects";
            type = genMerge.types.bool;
            default = false;
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
  flake.tests.meta-modules.test-meta-module-option-has-default =
    let
      eval = mkEval [ { config.aspects.foo.classOne = { }; } ];
    in
    {
      expr = {
        guard = eval.config.aspects.foo.meta.guard;
        priority = eval.config.aspects.foo.meta.priority;
      };
      expected = {
        guard = false;
        priority = 100;
      };
    };

  flake.tests.meta-modules.test-meta-module-option-settable =
    let
      eval = mkEval [
        {
          config.aspects.foo = {
            meta.guard = true;
            meta.priority = 50;
            classOne.x = "hello";
          };
        }
      ];
    in
    {
      expr = {
        guard = eval.config.aspects.foo.meta.guard;
        priority = eval.config.aspects.foo.meta.priority;
      };
      expected = {
        guard = true;
        priority = 50;
      };
    };

  flake.tests.meta-modules.test-meta-freeform-alongside-typed =
    let
      eval = mkEval [
        {
          config.aspects.foo = {
            meta.guard = true;
            meta.customField = "arbitrary";
            classOne = { };
          };
        }
      ];
    in
    {
      expr = {
        guard = eval.config.aspects.foo.meta.guard;
        customField = eval.config.aspects.foo.meta.customField;
      };
      expected = {
        guard = true;
        customField = "arbitrary";
      };
    };

  flake.tests.meta-modules.test-meta-module-on-nested-aspect =
    let
      eval = mkEval [
        {
          config.aspects.parent.child.meta.guard = true;
        }
      ];
    in
    {
      expr = eval.config.aspects.parent.child.meta.guard;
      expected = true;
    };
}
