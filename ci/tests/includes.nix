# Test: includes and sibling references via fixpoint.
{ lib, mkSchemaEval }:
{
  test-include-sibling =
    let
      eval = mkSchemaEval {
        modules = [
          (
            { config, ... }:
            {
              config.aspects = {
                main = {
                  includes = [ config.aspects.helper ];
                  classOne.names = [ "from-main" ];
                };
                helper.classOne.names = [ "from-helper" ];
              };
            }
          )
        ];
      };
      aspect = eval.config.aspects.main;
    in
    {
      expr = {
        hasIncludes = aspect.includes != [ ];
        includeCount = builtins.length aspect.includes;
      };
      expected = {
        hasIncludes = true;
        includeCount = 1;
      };
    };

  test-fixpoint-aspects-reference =
    let
      eval = mkSchemaEval {
        modules = [
          (
            { config, ... }:
            {
              config.aspects = {
                a = {
                  includes = [ config.aspects.b ];
                  classOne.x = [ "from-a" ];
                };
                b.classOne.x = [ "from-b" ];
              };
            }
          )
        ];
      };
    in
    {
      expr = builtins.length eval.config.aspects.a.includes;
      expected = 1;
    };
}
