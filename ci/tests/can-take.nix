# Test: canTake introspection for module vs guard function detection.
{ lib, aspects, ... }:
let
  inherit (aspects) canTake mkIsModuleFn;
  # Use default module args for tests
  isModuleFn = mkIsModuleFn { };
in
{
  flake.tests.can-take.test-module-fn-config = {
    expr = isModuleFn ({ config, ... }: { });
    expected = true;
  };

  flake.tests.can-take.test-module-fn-lib = {
    expr = isModuleFn ({ lib, ... }: { });
    expected = true;
  };

  flake.tests.can-take.test-module-fn-options = {
    expr = isModuleFn ({ options, ... }: { });
    expected = true;
  };

  flake.tests.can-take.test-module-fn-pkgs = {
    expr = isModuleFn ({ pkgs, ... }: { });
    expected = true;
  };

  flake.tests.can-take.test-module-fn-aspect = {
    expr = isModuleFn ({ aspect, ... }: { });
    expected = true;
  };

  flake.tests.can-take.test-guard-fn-host = {
    expr = isModuleFn ({ host, ... }: { });
    expected = false;
  };

  flake.tests.can-take.test-guard-fn-mixed = {
    # host is required and not a module arg → guard function
    expr = isModuleFn ({ host, config, ... }: { });
    expected = false;
  };

  flake.tests.can-take.test-guard-fn-optional-host = {
    # host has default → all REQUIRED args (config) are module args → module function
    expr = isModuleFn (
      {
        host ? null,
        config,
        ...
      }:
      { }
    );
    expected = true;
  };

  flake.tests.can-take.test-guard-fn-named-only = {
    expr = isModuleFn ({ who }: { });
    expected = false;
  };

  flake.tests.can-take.test-custom-module-args = {
    # Custom module args via cnf.moduleArgs
    expr =
      (mkIsModuleFn {
        moduleArgs = {
          foo = true;
        };
      })
        ({ foo, ... }: { });
    expected = true;
  };
}
