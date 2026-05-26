# Test: guard functions (wrapped via functionTo) preserve positional identity
# from loc for diamond dedup. Palmer §5.1: ℓ (program point) from merge location.
{
  lib,
  aspects,
  mkDefaultEval,
}:
{
  test-guard-function-has-name =
    let
      eval = mkDefaultEval [
        {
          config.aspects.fonts =
            { host }:
            {
              classOne.packages = [ "noto" ];
            };
        }
      ];
    in
    {
      # Guard function wrapper preserves name from loc
      expr = eval.config.aspects.fonts.name or null;
      expected = "fonts";
    };

  test-guard-function-name-matches-key =
    let
      eval = mkDefaultEval [
        {
          config.aspects.parent.child =
            { host }:
            {
              classOne.setting = "value";
            };
        }
      ];
    in
    {
      # Nested guard function gets name from its position
      expr = eval.config.aspects.parent.child.name or null;
      expected = "child";
    };

  test-guard-identity-key =
    let
      eval = mkDefaultEval [
        {
          config.aspects.fonts =
            { host }:
            {
              classOne.packages = [ "noto" ];
            };
        }
      ];
      wrapper = eval.config.aspects.fonts;
    in
    {
      # identity.key on a wrapped guard returns loc-based key
      expr = aspects.key wrapper;
      expected = "aspects/fonts";
    };

  test-guard-nested-identity-key =
    let
      eval = mkDefaultEval [
        {
          config.aspects.theme.fonts =
            { host }:
            {
              classOne.packages = [ "noto" ];
            };
        }
      ];
      wrapper = eval.config.aspects.theme.fonts;
    in
    {
      # nested guard: loc includes full module path
      expr = aspects.key wrapper;
      expected = "aspects/theme/fonts";
    };

  test-static-vs-guard-keys-differ =
    let
      eval = mkDefaultEval [
        {
          config.aspects.staticOne.classOne.setting = "a";
          config.aspects.guardOne =
            { host }:
            {
              classOne.setting = "b";
            };
        }
      ];
    in
    {
      # static uses aspectPath, guard uses loc — both produce stable strings
      expr = {
        static = aspects.key eval.config.aspects.staticOne;
        guard = aspects.key eval.config.aspects.guardOne;
      };
      expected = {
        static = "staticOne";
        guard = "aspects/guardOne";
      };
    };

  test-guard-has-functionArgs =
    let
      eval = mkDefaultEval [
        {
          config.aspects.fonts =
            { host, user }:
            {
              classOne.packages = [ "noto" ];
            };
        }
      ];
      wrapper = eval.config.aspects.fonts;
    in
    {
      expr = {
        isCallable = lib.isFunction wrapper;
        hasArgs = wrapper ? __functionArgs;
        args = wrapper.__functionArgs;
      };
      expected = {
        isCallable = true;
        hasArgs = true;
        args = {
          host = false;
          user = false;
        };
      };
    };
}
