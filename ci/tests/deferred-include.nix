# G-a — the opt-in deferred-include pass-through (design §3.4). Under `cnf.deferIncludeResolution`,
# `includesElemType` carries a raw guard closure and a gen-program policy record (`__isPolicy`, that
# library's stated contract) THROUGH opaquely for consumer resolution — the SAME arm shape as the
# shipped `__keyRef` pass-through. Any other record is aspect content, whatever fields it carries.
# Default OFF ⇒ native guard-wrapping unchanged. Theory: First-Order Laziness (Lorenzen et al. 2025) —
# a deferred-resolution include passes the type unforced.
{
  mkSchemaEval,
  ...
}:
let
  bareFn =
    { host, ... }:
    {
      classOne = { };
    };
  # A record carrying a closure under a field of its own choosing, and no policy marker.
  closureRecord = {
    batteryFn =
      { host, ... }:
      {
        classOne = { };
      };
    name = "batt";
  };
  policyRecord = {
    __isPolicy = true;
    name = "pol";
    fn = { host, ... }: [ ];
  };

  onIncludes =
    (mkSchemaEval {
      deferIncludeResolution = true;
      modules = [
        {
          config.aspects.main.includes = [
            bareFn
            closureRecord
            policyRecord
          ];
        }
      ];
    }).config.aspects.main.includes;

  offIncludes =
    (mkSchemaEval {
      modules = [ { config.aspects.main.includes = [ bareFn ]; } ];
    }).config.aspects.main.includes;

  staticIncludes =
    (mkSchemaEval {
      deferIncludeResolution = true;
      modules = [ { config.aspects.main.includes = [ { classOne = { }; } ]; } ];
    }).config.aspects.main.includes;
in
{
  flake.tests.deferred-include.test-bare-fn-passes-through = {
    expr = builtins.isFunction (builtins.elemAt onIncludes 0);
    expected = true;
  };
  # A passed-through record comes back as written (`[ "batteryFn" "name" ]`); aspect content comes
  # back merged, carrying the aspect's own `id_hash`.
  flake.tests.deferred-include.test-closure-record-is-aspect-content = {
    expr = (builtins.elemAt onIncludes 1) ? id_hash;
    expected = true;
  };
  flake.tests.deferred-include.test-policy-record-passes-through = {
    expr = (builtins.elemAt onIncludes 2).__isPolicy or false;
    expected = true;
  };
  flake.tests.deferred-include.test-default-off-wraps-bare-fn = {
    expr = (builtins.elemAt offIncludes 0).__isWrappedFn or false;
    expected = true;
  };
  flake.tests.deferred-include.test-static-include-still-nests = {
    expr = (builtins.elemAt staticIncludes 0) ? name;
    expected = true;
  };
}
