# Test: module functions vs guards.
# Module functions ({ config, ... }:) are evaluated by the submodule.
# A parametric aspect is a first-order guard (`guard (pred.has "who") { … readCtx … }`), fired by
# `applyGuard` at a context; a context closure there is refused (`closure-door`).
{
  genMerge,
  aspects,
  genAlgebra,
  genIdentity,
  mkSchemaEval,
  ...
}:
let
  t = (genAlgebra.term genIdentity.hashIdentity).term;
  greeter = aspects.guard (aspects.pred.has "who") {
    description = t.concat [
      (t.lit "hello ")
      (t.readCtx "who" [ ])
    ];
    classOne.message = "hi";
  };
in
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
      classEval = genMerge.evalModuleTree {
        modules = [
          { options.setting = genMerge.mkOption { type = genMerge.types.str; }; }
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
        modules = [ { config.aspects.parent.provides.greeter = greeter; } ];
      };
      provider = eval.config.aspects.parent.provides.greeter;
    in
    {
      expr = {
        isGuard = provider.__guard or false;
        fired = (aspects.applyGuard { who = "world"; } provider).description;
      };
      expected = {
        isGuard = true;
        fired = "hello world";
      };
    };

  flake.tests.parametric.test-guard-function-result-has-aspect-structure =
    let
      eval = mkSchemaEval {
        modules = [ { config.aspects.parent.provides.greeter = greeter; } ];
      };
      result = aspects.applyGuard { who = "world"; } eval.config.aspects.parent.provides.greeter;
    in
    {
      # the fired body is aspect content: its class key and its read coordinate
      expr = {
        hasClassOne = result ? classOne;
        description = result.description;
      };
      expected = {
        hasClassOne = true;
        description = "hello world";
      };
    };
}
