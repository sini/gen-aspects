# Test: canTake introspection for module vs guard function detection.
{ lib, aspects }:
let
  inherit (aspects) canTake isModuleFn;
in
{
  test-module-fn-config =
    {
      expr = isModuleFn ({ config, ... }: { });
      expected = true;
    };

  test-module-fn-lib =
    {
      expr = isModuleFn ({ lib, ... }: { });
      expected = true;
    };

  test-module-fn-options =
    {
      expr = isModuleFn ({ options, ... }: { });
      expected = true;
    };

  test-guard-fn-host =
    {
      expr = isModuleFn ({ host, ... }: { });
      expected = false;
    };

  test-guard-fn-pkgs =
    {
      expr = isModuleFn ({ pkgs, ... }: { });
      expected = false;
    };

  test-guard-fn-mixed =
    {
      # host is required and not a module arg → guard function
      expr = isModuleFn ({ host, config, ... }: { });
      expected = false;
    };

  test-guard-fn-optional-host =
    {
      # host has default → all REQUIRED args (config) are module args → module function
      expr = isModuleFn ({ host ? null, config, ... }: { });
      expected = true;
    };

  test-guard-fn-named-only =
    {
      expr = isModuleFn ({ who }: { });
      expected = false;
    };
}
