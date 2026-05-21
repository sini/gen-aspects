# Test: den-schema methods on aspects via cnf.aspectMethods.
{ lib, aspects }:
let
  inherit (aspects) aspectsType schemaFn;

  mkEval =
    modules:
    lib.evalModules {
      modules = [
        {
          options.aspects = lib.mkOption {
            type = aspectsType {
              classes.classOne = { };
              aspectMethods = {
                label = schemaFn "Human-readable label" lib.types.str (
                  { name, description, ... }: "${name}: ${description}"
                );
              };
            };
            default = { };
          };
        }
      ] ++ modules;
    };
in
{
  test-method-computed-from-config =
    let
      eval = mkEval [
        {
          config.aspects.networking = {
            description = "Network configuration";
            classOne = { };
          };
        }
      ];
    in
    {
      expr = eval.config.aspects.networking.label;
      expected = "networking: Network configuration";
    };

  test-method-uses-default-description =
    let
      eval = mkEval [{ config.aspects.foo.classOne = { }; }];
    in
    {
      expr = eval.config.aspects.foo.label;
      expected = "foo: Aspect foo";
    };

  test-method-on-nested-aspect =
    let
      eval = mkEval [
        {
          config.aspects.parent.child = {
            description = "A child aspect";
            classOne = { };
          };
        }
      ];
    in
    {
      expr = eval.config.aspects.parent.child.label;
      expected = "child: A child aspect";
    };

  test-method-is-read-only =
    let
      eval = mkEval [
        {
          config.aspects.foo = {
            classOne = { };
            label = "manual override attempt";
          };
        }
      ];
      result = builtins.tryEval (builtins.deepSeq eval.config.aspects.foo.label eval.config.aspects.foo.label);
    in
    {
      # Should fail — methods are read-only
      expr = result.success;
      expected = false;
    };
}
