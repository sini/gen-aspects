# Test: pipeline-provided aspect extensions via cnf.aspectModules.
# Den uses this to add excludes, policies, and other pipeline options.
{ lib }:
let
  aspects = import ../../../lib { inherit lib; };
  inherit (aspects) aspectsType;

  mkEval =
    modules:
    lib.evalModules {
      modules = [
        {
          options.aspects = lib.mkOption {
            type = aspectsType {
              classes.classOne = { };
              aspectModules = [
                {
                  options.excludes = lib.mkOption {
                    description = "Aspects to exclude from resolution";
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                  };
                  options.priority = lib.mkOption {
                    description = "Resolution priority";
                    type = lib.types.int;
                    default = 100;
                  };
                }
              ];
            };
            default = { };
          };
        }
      ] ++ modules;
    };
in
{
  test-extension-option-has-default =
    let
      eval = mkEval [{ config.aspects.foo.classOne = { }; }];
    in
    {
      expr = {
        excludes = eval.config.aspects.foo.excludes;
        priority = eval.config.aspects.foo.priority;
      };
      expected = {
        excludes = [ ];
        priority = 100;
      };
    };

  test-extension-option-settable =
    let
      eval = mkEval [
        {
          config.aspects.foo = {
            excludes = [ "bar" "baz" ];
            priority = 50;
            classOne.x = "hello";
          };
        }
      ];
    in
    {
      expr = {
        excludes = eval.config.aspects.foo.excludes;
        priority = eval.config.aspects.foo.priority;
      };
      expected = {
        excludes = [ "bar" "baz" ];
        priority = 50;
      };
    };

  test-extension-on-nested-aspect =
    let
      eval = mkEval [
        { config.aspects.parent.child.excludes = [ "something" ]; }
      ];
    in
    {
      expr = eval.config.aspects.parent.child.excludes;
      expected = [ "something" ];
    };

  test-extension-coexists-with-class-content =
    let
      eval = mkEval [
        {
          config.aspects.foo = {
            excludes = [ "bar" ];
            classOne.setting = "hello";
          };
        }
      ];
      classEval = lib.evalModules {
        modules = [
          { options.setting = lib.mkOption { type = lib.types.str; }; }
          eval.config.aspects.foo.classOne
        ];
      };
    in
    {
      expr = {
        excludes = eval.config.aspects.foo.excludes;
        setting = classEval.config.setting;
      };
      expected = {
        excludes = [ "bar" ];
        setting = "hello";
      };
    };
}
