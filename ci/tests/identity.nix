# Test: aspect identity key computation.
{
  lib,
  aspects,
  mkSchemaEval,
  ...
}:
{
  flake.tests.identity.test-root-aspect-key =
    let
      eval = mkSchemaEval { modules = [ { config.aspects.networking.classOne = { }; } ]; };
    in
    {
      expr = eval.config.aspects.networking.key;
      expected = "networking";
    };

  flake.tests.identity.test-nested-aspect-key =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.infra.networking.classOne = { }; }
        ];
      };
    in
    {
      # nested via freeform → aspectType → aspectSubmodule
      expr = eval.config.aspects.infra.networking.key;
      expected = "networking";
    };

  flake.tests.identity.test-meaningful-name-check = {
    expr = {
      anon = aspects.isMeaningfulName "<anon>";
      fn = aspects.isMeaningfulName "<function body>";
      def = aspects.isMeaningfulName "[definition 1-entry 1]";
      real = aspects.isMeaningfulName "networking";
    };
    expected = {
      anon = false;
      fn = false;
      def = false;
      real = true;
    };
  };
}
