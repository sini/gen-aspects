# Test: unregistered freeform keys become nested aspects with full identity.
{ lib, mkSchemaEval }:
{
  test-nested-has-structural-keys =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.parent.child.classOne.foo = "bar"; }
        ];
      };
      child = eval.config.aspects.parent.child;
    in
    {
      expr = {
        hasName = child ? name;
        hasIncludes = child ? includes;
        hasMeta = child ? meta;
        name = child.name;
      };
      expected = {
        hasName = true;
        hasIncludes = true;
        hasMeta = true;
        name = "child";
      };
    };

  test-nested-class-content-is-clean =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.parent.child.classOne.foo = "bar"; }
        ];
      };
      classEval = lib.evalModules {
        modules = [
          { options.foo = lib.mkOption { type = lib.types.str; }; }
          eval.config.aspects.parent.child.classOne
        ];
      };
    in
    {
      expr = classEval.config.foo;
      expected = "bar";
    };
}
