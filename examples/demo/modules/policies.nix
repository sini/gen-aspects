# Legacy single-sample policy dispatch.
#
# The action vocabulary and the per-host rules now live in the shared
# `_policy-rules.nix` helper. This module keeps only the legacy single-sample
# fixpoint dispatch (sample context: prod-web-1) that feeds the existing
# `policyIterations` / `policyActionCounts` outputs.
{
  config,
  lib,
  genDispatch,
  genGraph,
  genScope,
  ...
}:
let
  policyRules = import ./_policy-rules.nix { inherit lib genDispatch genGraph; };
  inherit (policyRules)
    act
    phaseOrder
    rules
    extract
    fromFunctionMatch
    ;

  # Sample context: prod-web-1
  sampleEnv = config.fleet.environments.prod;
  sampleHost = config.fleet.hosts.prod-web-1 // {
    name = "prod-web-1";
  };

  # gen-dispatch is the STEP; gen-scope.circular is the LOOP (Kleene ascent).
  cfg = {
    inherit rules extract phaseOrder;
    id = null;
    match = fromFunctionMatch;
    classify = act.classify;
    combine = ctx: ext: ctx // ext;
  };
  step = genDispatch.dispatchStep { inherit (genDispatch) dispatch; } cfg;

  policyResult =
    (genScope.circular {
      init = genDispatch.dispatchInit {
        env = sampleEnv;
        host = sampleHost;
      };
      eq = a: b: builtins.attrNames a.context == builtins.attrNames b.context;
    } step)
      { }
      null;
in
{
  config._module.args = {
    inherit policyResult;
  };
}
