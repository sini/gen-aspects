# Test: aspect identity key computation.
{ lib, aspects, mkDefaultEval }:
{
  test-root-aspect-key =
    let
      eval = mkDefaultEval [{ config.aspects.networking.classOne = { }; }];
    in
    {
      expr = eval.config.aspects.networking.key;
      expected = "networking";
    };

  test-nested-aspect-key =
    let
      eval = mkDefaultEval [
        { config.aspects.infra.networking.classOne = { }; }
      ];
    in
    {
      # nested via freeform → aspectType → aspectSubmodule
      expr = eval.config.aspects.infra.networking.key;
      expected = "networking";
    };

  test-meaningful-name-check =
    {
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
