# Legacy single-sample policy dispatch.
#
# The action vocabulary and the per-host rules now live in the shared
# `_policy-rules.nix` helper. This module keeps only the legacy single-sample
# fixpoint dispatch (sample context: prod-web-1) that feeds the existing
# `policyIterations` / `policyActionCounts` outputs.
{
  config,
  lib,
  genDerive,
  ...
}:
let
  inherit (genDerive) fixpoint;

  policyRules = import ./_policy-rules.nix { inherit lib genDerive; };
  inherit (policyRules)
    act
    phases
    rules
    extract
    fromFunctionMatch
    ;

  # Sample context: prod-web-1
  sampleEnv = config.fleet.environments.prod;
  sampleHost = config.fleet.hosts.prod-web-1 // {
    name = "prod-web-1";
  };

  policyResult = fixpoint {
    inherit rules phases extract;
    context = {
      env = sampleEnv;
      host = sampleHost;
    };
    match = fromFunctionMatch;
    classify = act.classify;
    combine = ctx: ext: ctx // ext;
    eq = a: b: builtins.attrNames a == builtins.attrNames b;
  };
in
{
  config._module.args = {
    inherit policyResult;
  };
}
