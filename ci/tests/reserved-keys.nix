# Test (parity with den #563 + den.reservedKeys): a reserved metadata key reads
# back VERBATIM and is never content-wrapped or turned into a nested aspect, while
# the rest of the aspect (class content, nested aspects) resolves normally.
#
# den #563 special-cased structural/reserved keys in aspectKeyType.merge to pass
# `(lib.last defs).value` through instead of content-wrapping it (__contentValues/
# __provider). gen-aspects has no content-wrapper at all: a reserved key is declared
# as an explicit option via cnf.aspectModules (the documented replacement for
# den.reservedKeys), which the module system binds BEFORE the freeform fallback, so
# the value reads back unwrapped. Both systems require opt-in (reservedKeys /
# aspectModules); an UNDECLARED key falls through to a nested aspect in either.
#
# NOTE on merge discipline: den's reserved passthrough is last-def-wins; declaring
# the option as `lazyAttrsOf` here deep-merges instead. Verbatim read-back holds
# either way; pick the option type per intended semantics (see den-hoag ISSUES #13d).
{ lib, mkSchemaEval, ... }:
let
  withSettings =
    modules:
    mkSchemaEval {
      classes = {
        nixos = { };
      };
      aspectModules = [
        {
          options.settings = lib.mkOption {
            description = "Reserved free-form metadata (den.reservedKeys analogue)";
            type = lib.types.lazyAttrsOf lib.types.anything;
            default = { };
          };
        }
      ];
      inherit modules;
    };

  eval = withSettings [
    {
      config.aspects.igloo = {
        settings.theme = "dark";
        nixos.networking.hostName = "reserved-test";
      };
    }
  ];

  nixosEval = lib.evalModules {
    modules = [
      { options.networking.hostName = lib.mkOption { type = lib.types.str; }; }
      eval.config.aspects.igloo.nixos
    ];
  };

  # Contrast: WITHOUT declaring `settings`, the same key becomes a nested aspect
  # (parity with den's un-reserved dispatch — both require opt-in).
  undeclared = mkSchemaEval {
    classes = {
      nixos = { };
    };
    modules = [ { config.aspects.igloo.settings.theme = "dark"; } ];
  };
in
{
  # Reserved key reads back verbatim, unwrapped — not a nested aspect, no content-wrap.
  flake.tests.reserved-keys.test-reserved-key-reads-back-verbatim = {
    expr = eval.config.aspects.igloo.settings;
    expected = {
      theme = "dark";
    };
  };

  # The rest of the aspect still resolves normally alongside the reserved key.
  flake.tests.reserved-keys.test-aspect-resolves-alongside-reserved-key = {
    expr = nixosEval.config.networking.hostName;
    expected = "reserved-test";
  };

  # Opt-in parity: an UNDECLARED key is dispatched to a nested aspect (gets identity),
  # exactly as den dispatches an un-reserved key.
  flake.tests.reserved-keys.test-undeclared-key-is-nested-aspect = {
    expr = undeclared.config.aspects.igloo.settings.name;
    expected = "settings";
  };
}
