# Test: guard functions (wrapped via functionTo) preserve positional identity
# from loc for diamond dedup. Palmer §5.1: ℓ (program point) from merge location.
{ lib, aspects, mkDefaultEval }:
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
