# Module bindings: gen-bind wrap with contracts and provenance.
#
# Demonstrates wrapping a NixOS module function with external bindings,
# contract validation, provenance tracking, and signature inference.
{
  lib,
  genBind,
  composedSettings,
  ...
}:
let
  # --- NixOS module that consumes nginx settings ---
  nginxModule =
    {
      nginxSettings,
      config,
      lib,
      ...
    }:
    {
      services.nginx = {
        enable = true;
        config = ''
          worker_processes ${toString nginxSettings.performance.workers};
          events {
            worker_connections ${toString (nginxSettings.performance.worker-connections or 1024)};
          }
        '';
      };
      networking.firewall.allowedTCPPorts = [
        (if nginxSettings.listen.ssl-enabled or false then 443 else 80)
      ];
    };

  # --- Wrap with gen-bind ---
  wrappedResult = genBind.wrap {
    module = nginxModule;
    bindings = {
      nginxSettings = composedSettings.prod-web-1.nginx;
    };
    contracts = {
      nginxSettings = genBind.contract.hasFields [
        "listen"
        "performance"
        "security"
      ];
    };
    provenance = {
      nginxSettings = {
        source = "scope-settings";
        scope = "host:prod-web-1";
      };
    };
  };

  # --- Signature ---
  signature = genBind.buildSignature {
    module = nginxModule;
    bindings = {
      nginxSettings = composedSettings.prod-web-1.nginx;
    };
    defaultMergeStrategy = genBind.mergeStrategy.bindWins;
    mergeStrategies = { };
    provenance = {
      nginxSettings = {
        source = "scope-settings";
        scope = "host:prod-web-1";
      };
    };
  };

  bindResults = {
    wrappedIsWrapped = wrappedResult.wrapped;
    signatureRequires = signature.requires;
    signatureBound = signature.bound;
    advertisedArgs = wrappedResult.advertisedArgs;
  };

in
{
  config._module.args = {
    inherit bindResults;
  };
}
