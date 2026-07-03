# Test: multi-definition merging behavior at the type level.
{
  genMerge,
  lib,
  mkSchemaEval,
  ...
}:
{
  flake.tests.multi-def.test-attrset-multi-def-lists-merge =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.foo.classOne.names = [ "alice" ]; }
          { config.aspects.foo.classOne.names = [ "bob" ]; }
        ];
      };
      classEval = genMerge.evalModuleTree {
        modules = [
          { options.names = genMerge.mkOption { type = genMerge.types.listOf genMerge.types.str; }; }
          eval.config.aspects.foo.classOne
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

  flake.tests.multi-def.test-attrset-multi-def-preserves-both-keys =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.foo.classOne.x = "from-a"; }
          { config.aspects.foo.classOne.y = "from-b"; }
        ];
      };
      classEval = genMerge.evalModuleTree {
        modules = [
          {
            options.x = genMerge.mkOption { type = genMerge.types.str; };
            options.y = genMerge.mkOption { type = genMerge.types.str; };
          }
          eval.config.aspects.foo.classOne
        ];
      };
    in
    {
      expr = {
        inherit (classEval.config) x y;
      };
      expected = {
        x = "from-a";
        y = "from-b";
      };
    };

  flake.tests.multi-def.test-mixed-attrset-and-module-fn-coerces-fn-to-include =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.foo.classOne.x = [ "static" ]; }
          {
            config.aspects.foo =
              { aspect, ... }:
              {
                classOne.x = [ "from-fn" ];
              };
          }
        ];
      };
    in
    {
      # Mixed defs: function is coerced to { includes = [fn]; }
      # The attrset content is direct, the function becomes an include
      expr = {
        hasIncludes = eval.config.aspects.foo.includes != [ ];
        includeCount = builtins.length eval.config.aspects.foo.includes;
      };
      expected = {
        hasIncludes = true;
        includeCount = 1;
      };
    };
}
