# Test: a placed guard record carries its name from its position (Palmer §5.1: ℓ, the program point,
# from the merge location), and its key is the mint over (condition, body), never a path.
{
  lib,
  aspects,
  mkSchemaEval,
  ...
}:
{
  flake.tests.guard-identity.test-guard-function-has-name =
    let
      eval = mkSchemaEval {
        modules = [
          {
            config.aspects.fonts = aspects.guard (aspects.pred.has "host") {
              classOne.packages = [ "noto" ];
            };
          }
        ];
      };
    in
    {
      # A placed guard record carries its name from loc
      expr = eval.config.aspects.fonts.name or null;
      expected = "fonts";
    };

  flake.tests.guard-identity.test-guard-function-name-matches-key =
    let
      eval = mkSchemaEval {
        modules = [
          {
            config.aspects.parent.child = aspects.guard (aspects.pred.has "host") {
              classOne.setting = "value";
            };
          }
        ];
      };
    in
    {
      # A nested guard record gets its name from its position
      expr = eval.config.aspects.parent.child.name or null;
      expected = "child";
    };

  flake.tests.guard-identity.test-static-vs-guard-keys-differ =
    let
      eval = mkSchemaEval {
        modules = [
          {
            config.aspects.staticOne.classOne.setting = "a";
            config.aspects.guardOne = aspects.guard (aspects.pred.has "host") {
              classOne.setting = "b";
            };
          }
        ];
      };
    in
    {
      # static uses aspectPath (meta.aspect-chain ++ name); a guard record keys by the mint over its
      # condition and body (`guard:` prefix), so the two never share a key.
      expr = {
        static = aspects.key eval.config.aspects.staticOne;
        guardIsMinted = lib.hasPrefix "guard:" (aspects.key eval.config.aspects.guardOne);
      };
      expected = {
        static = "staticOne";
        guardIsMinted = true;
      };
    };

}
