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

  # P2-OQ15 arm (i): `canTake` reads through the prelude's functor-aware PAIR, so a functor carrying
  # `__functionArgs` (nixpkgs `setFunctionArgs`, a gen `door`) is introspected by its published
  # formals, as a lambda is. Before the readers moved it answered `false` for every functor.
  flake.tests.can-take.test-functor-with-published-formals-is-read = {
    expr = [
      (isModuleFn (lib.setFunctionArgs (_: { }) { config = false; }))
      (isModuleFn (lib.setFunctionArgs (_: { }) { host = false; }))
      (canTake.atLeast { host = 1; } (lib.setFunctionArgs (_: { }) { host = false; }))
    ];
    expected = [
      true
      false
      true
    ];
  };
}
