# G-a — the opt-in deferred-include pass-through (design §3.4). Under `cnf.deferIncludeResolution`,
# `includesElemType` carries a raw guard closure, a `{ __fn; … }` battery record, and a policy record
# (`__isPolicy`/`__denCanTake`) THROUGH opaquely for consumer resolution — the SAME arm shape as the
# shipped `__keyRef` pass-through. Default OFF ⇒ native guard-wrapping unchanged. Theory: First-Order
# Laziness (Lorenzen et al. 2025) — a deferred-resolution include passes the type unforced.
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
  fnRecord = {
    __fn =
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
            fnRecord
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
  flake.tests.deferred-include.test-fn-record-passes-through = {
    expr = (builtins.elemAt onIncludes 1).__fn or null != null;
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
