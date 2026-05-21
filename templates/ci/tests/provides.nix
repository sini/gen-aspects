# Test: provides namespace for named sub-aspects.
{ lib, mkDefaultEval }:
{
  test-provides-basic =
    let
      eval = mkDefaultEval [
        {
          config.aspects.parent = {
            provides.child.classOne.foo = "bar";
          };
        }
      ];
      child = eval.config.aspects.parent.provides.child;
    in
    {
      expr = {
        hasName = child ? name;
        name = child.name;
      };
      expected = {
        hasName = true;
        name = "child";
      };
    };

  test-provides-alias =
    let
      eval = mkDefaultEval [
        { config.aspects.parent._.child.classOne.foo = "bar"; }
      ];
    in
    {
      expr = eval.config.aspects.parent.provides.child.name;
      expected = "child";
    };

  test-provides-aspect-chain =
    let
      eval = mkDefaultEval [
        {
          config.aspects.parent.provides.child.classOne.foo = "bar";
        }
      ];
      child = eval.config.aspects.parent.provides.child;
    in
    {
      expr = child.meta.aspect-chain;
      expected = [ "parent" ];
    };
}
