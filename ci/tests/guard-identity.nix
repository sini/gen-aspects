# Test: guard functions (wrapped via functionTo) preserve positional identity
# from loc for diamond dedup. Palmer §5.1: ℓ (program point) from merge location.
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
            config.aspects.fonts =
              { host }:
              {
                classOne.packages = [ "noto" ];
              };
          }
        ];
      };
    in
    {
      # Guard function wrapper preserves name from loc
      expr = eval.config.aspects.fonts.name or null;
      expected = "fonts";
    };

  flake.tests.guard-identity.test-guard-function-name-matches-key =
    let
      eval = mkSchemaEval {
        modules = [
          {
            config.aspects.parent.child =
              { host }:
              {
                classOne.setting = "value";
              };
          }
        ];
      };
    in
    {
      # Nested guard function gets name from its position
      expr = eval.config.aspects.parent.child.name or null;
      expected = "child";
    };

  flake.tests.guard-identity.test-guard-identity-key =
    let
      eval = mkSchemaEval {
        modules = [
          {
            config.aspects.fonts =
              { host }:
              {
                classOne.packages = [ "noto" ];
              };
          }
        ];
      };
      wrapper = eval.config.aspects.fonts;
    in
    {
      # identity.key on a wrapped guard returns loc-based key (container-relative under A-IDENT 2b —
      # re-rooted by aspectsRoot, same form as a plain aspect at this path).
      expr = aspects.key wrapper;
      expected = "fonts";
    };

  flake.tests.guard-identity.test-guard-nested-identity-key =
    let
      eval = mkSchemaEval {
        modules = [
          {
            config.aspects.theme.fonts =
              { host }:
              {
                classOne.packages = [ "noto" ];
              };
          }
        ];
      };
      wrapper = eval.config.aspects.theme.fonts;
    in
    {
      # nested guard: loc includes full module path (container-relative under A-IDENT 2b).
      expr = aspects.key wrapper;
      expected = "theme/fonts";
    };

  flake.tests.guard-identity.test-static-vs-guard-keys-differ =
    let
      eval = mkSchemaEval {
        modules = [
          {
            config.aspects.staticOne.classOne.setting = "a";
            config.aspects.guardOne =
              { host }:
              {
                classOne.setting = "b";
              };
          }
        ];
      };
    in
    {
      # static uses aspectPath (meta.aspect-chain ++ name), guard uses meta.loc — and after
      # A-IDENT (2b) BOTH are container-relative, so plain and guard aspects live in ONE unified
      # namespace (spec §2 UNIFY): a plain aspect and a guard fn at the same path key identically
      # and dedup, as the collision law requires. Previously static was name-only while guard was
      # mount-loc-based — that namespace split is now closed, at relative form.
      expr = {
        static = aspects.key eval.config.aspects.staticOne;
        guard = aspects.key eval.config.aspects.guardOne;
      };
      expected = {
        static = "staticOne";
        guard = "guardOne";
      };
    };

  flake.tests.guard-identity.test-guard-has-functionArgs =
    let
      eval = mkSchemaEval {
        modules = [
          {
            config.aspects.fonts =
              { host, user }:
              {
                classOne.packages = [ "noto" ];
              };
          }
        ];
      };
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
