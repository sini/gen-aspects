# Test: parametric (function) aspects — submodule functions and curried providers.
{ lib, mkDefaultEval }:
{
  test-submodule-function-aspect =
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
    in
    {
      expr = eval.config.aspects.myAspect.name;
      expected = "myAspect";
    };

  test-parametric-provider =
    let
      eval = mkDefaultEval [
        {
          config.aspects.parent.provides.greeter =
            { who }:
            {
              classOne.message = "hello ${who}";
            };
        }
      ];
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

  test-parametric-provider-callable =
    let
      eval = mkDefaultEval [
        {
          config.aspects.parent.provides.greeter =
            { who }:
            {
              classOne.message = "hello ${who}";
            };
        }
      ];
      result = eval.config.aspects.parent.provides.greeter { who = "world"; };
    in
    {
      # functionTo(aspectSubmodule) wrapping gives the result aspect structure
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
