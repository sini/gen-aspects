# Test: module functions vs guard functions.
# Module functions ({ config, ... }:) are evaluated by the submodule.
# Guard functions ({ host, ... }:) are wrapped via functionTo for pipeline resolution.
{ lib, mkSchemaEval, ... }:
{
  flake.tests.parametric.test-module-function-aspect =
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
    in
    {
      expr = eval.config.aspects.myAspect.name;
      expected = "myAspect";
    };

  flake.tests.parametric.test-module-function-with-config =
    let
      eval = mkSchemaEval {
        modules = [
          {
            config.aspects.myAspect =
              { config, ... }:
              {
                classOne.setting = config.name;
              };
          }
        ];
      };
      classEval = lib.evalModules {
        modules = [
          { options.setting = lib.mkOption { type = lib.types.str; }; }
          eval.config.aspects.myAspect.classOne
        ];
      };
    in
    {
      expr = classEval.config.setting;
      expected = "myAspect";
    };

  flake.tests.parametric.test-guard-function-is-callable =
    let
      eval = mkSchemaEval {
        modules = [
          {
            config.aspects.parent.provides.greeter =
              { who }:
              {
                classOne.message = "hello ${who}";
              };
          }
        ];
      };
      provider = eval.config.aspects.parent.provides.greeter;
    in
    {
      expr = {
        isCallable = lib.isFunction provider;
        hasFunctionArgs = provider ? __functionArgs;
      };
      expected = {
        isCallable = true;
        hasFunctionArgs = true;
      };
    };

  flake.tests.parametric.test-guard-function-result-has-aspect-structure =
    let
      eval = mkSchemaEval {
        modules = [
          {
            config.aspects.parent.provides.greeter =
              { who }:
              {
                classOne.message = "hello ${who}";
              };
          }
        ];
      };
      result = eval.config.aspects.parent.provides.greeter { who = "world"; };
    in
    {
      # functionTo(aspectSubmodule) wrapping gives the result full aspect structure
      expr = {
        hasIncludes = result ? includes;
        hasClassOne = result ? classOne;
      };
      expected = {
        hasIncludes = true;
        hasClassOne = true;
      };
    };
}
