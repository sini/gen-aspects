# Expose verification outputs for the demo.
{
  config,
  lib,
  genAspects,
  composedSettings,
  settingsProvenance,
  scopeResult,
  flat,
  queryResults,
  policyResult,
  policyResultsByHost,
  bindResults,
  assembledClasses,
  ...
}:
let
  # Winner derivation — VALID ONLY for replace fields. For append/recursive every
  # listed layer genuinely contributed; "last" is the last CONTRIBUTOR, not a winner.
  effectiveLayerReplace = prov: field: (lib.last prov.${field}).layer;

  # Per-subkey provenance for ONE recursive field (consumer-side; no library change).
  recursiveSubkeyProvenance =
    prov: field:
    builtins.foldl' (acc: e: acc // builtins.mapAttrs (_k: _v: e.layer) e.value) { } prov.${field};

  # Stub options so a bare evalModules can render the class content (a bare
  # evalModules has no `networking`/`services` options and would throw).
  fwStubOptions =
    { lib, ... }:
    {
      options.networking.firewall.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      options.networking.firewall.allowedTCPPorts = lib.mkOption {
        type = lib.types.listOf lib.types.int;
        default = [ ];
      };
      options.networking.firewall.allowedUDPPorts = lib.mkOption {
        type = lib.types.listOf lib.types.int;
        default = [ ];
      };
      options.networking.firewall.logRefusedConnections = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
    };
  evalFw =
    host:
    (lib.evalModules {
      modules = [
        fwStubOptions
        assembledClasses.${host}.firewall
      ];
    }).config;

  nginxStubOptions =
    { lib, ... }:
    {
      options.services.nginx.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      options.services.nginx.config = lib.mkOption {
        type = lib.types.lines;
        default = "";
      };
      options.networking.firewall.allowedTCPPorts = lib.mkOption {
        type = lib.types.listOf lib.types.int;
        default = [ ];
      };
    };
  nginxConfigProdWeb1 =
    (lib.evalModules {
      modules = [
        nginxStubOptions
        assembledClasses.prod-web-1.nginx
      ];
    }).config.services.nginx.config;

  # The append-strategy cascade values and the rendered firewall ports, bound
  # here so the full-loop equality below can compare them (sibling flake attrs
  # can't reference each other without rec/let).
  fwTcpDevAll = composedSettings.dev-all.firewall.allowed-tcp; # [8080 8443 9090 3000]
  fwTcpProdWeb1 = composedSettings.prod-web-1.firewall.allowed-tcp; # []
  fwPortsDevAll = (evalFw "dev-all").networking.firewall.allowedTCPPorts; # [8080 8443 9090 3000]
  fwPortsProdWeb1 = (evalFw "prod-web-1").networking.firewall.allowedTCPPorts; # []
in
{
  flake = {
    aspectCount = builtins.length (builtins.attrNames flat);
    aspectNames = lib.sort (a: b: a < b) (builtins.attrNames flat);
    hasTags = (config.aspects.base-system.tags or [ ]) != [ ];
    hasNestedSettings = (config.aspects.networking.settings or { }) != { };

    # --- aspect shape (replaces hasGuard) ---
    firewallIsPlain = !(flat.firewall.__isWrappedFn or false); # true
    firewallSettingsReachable = (flat.firewall.settings.allowed-tcp.merge or null) == "append"; # true

    # --- (i) POLICY OVERRIDES HOST (replace) — discriminating: env sets "warn",
    # policy sets "error"; only reachable if the policy layer is folded LAST ---
    loggingLevelProdWeb1 = composedSettings.prod-web-1.app.logging.level; # "error"
    loggingLevelProdWeb1Winner = effectiveLayerReplace settingsProvenance.prod-web-1 "app.logging.level"; # "policy"
    loggingLevelProdWeb1Chain = map (e: e.layer) settingsProvenance.prod-web-1."app.logging.level"; # ["default" "env" "policy"]

    # --- NEGATIVE CONTROL: policy doesn't touch nginx workers → host still wins ---
    workersProdWeb1 = composedSettings.prod-web-1.nginx.performance.workers; # 32
    workersProdWeb1Winner = effectiveLayerReplace settingsProvenance.prod-web-1 "nginx.performance.workers"; # "host"

    # --- (ii) APPEND: firewall.allowed-tcp accumulates the policy contribution ---
    inherit fwTcpDevAll fwTcpProdWeb1; # [8080 8443 9090 3000] / []
    fwTcpProvenanceDev = settingsProvenance.dev-all."firewall.allowed-tcp";

    # --- (iii) RECURSIVE: per-subkey attribution on postgres.backup ---
    dbBackupSubkeyProvenance = recursiveSubkeyProvenance settingsProvenance.prod-db-1 "postgres.backup";
    # => { schedule="policy"; retention="policy"; method="host"; destination="host"; }

    # --- (iv) FIREWALL FULL LOOP: resolved+appended settings injected into the
    # PARAMETRIC nixos via the construct → assert the rendered module value ---
    inherit fwPortsDevAll fwPortsProdWeb1; # [8080 8443 9090 3000] / []
    fwEnableDevAll = (evalFw "dev-all").networking.firewall.enable; # true
    fwInjectionMatchesCascade = fwPortsDevAll == fwTcpDevAll && fwPortsProdWeb1 == fwTcpProdWeb1; # true

    # --- (v) NGINX FULL LOOP (second aspect): resolved settings reach nginx ---
    nginxInjectionResolved = lib.hasInfix "worker_processes 32" nginxConfigProdWeb1; # true

    # --- per-host policy dispatch smoke ---
    policyActionCountsByHost = lib.mapAttrs (
      _: r: lib.mapAttrs (_: builtins.length) r.accActions
    ) policyResultsByHost;

    # Settings cascade verification
    nginxWorkersProdWeb1 = composedSettings.prod-web-1.nginx.performance.workers;
    nginxWorkersProdWeb2 = composedSettings.prod-web-2.nginx.performance.workers;
    nginxWorkersDev = composedSettings.dev-all.nginx.performance.workers;
    prodWeb1Locations = composedSettings.prod-web-1.nginx.locations;
    prodWeb1Upstream = composedSettings.prod-web-1.nginx.upstream.servers;
    prodDb1SharedBuffers = composedSettings.prod-db-1.postgres.memory.shared-buffers;
    prodDb1Backup = composedSettings.prod-db-1.postgres.backup;
    devFeatures = composedSettings.dev-all.app.features;

    # Namespace aspects
    namespaceAspects = lib.sort (a: b: a < b) (
      builtins.filter (k: lib.hasPrefix "observability/" k) (builtins.attrNames flat)
    );

    # Graph traversal results
    inherit (queryResults)
      webDeps
      dbImpact
      allRoots
      allLeaves
      hasCycles
      publicFacing
      statefulAspects
      securityAspects
      frontendTier
      dataTier
      observabilityInNamespace
      childrenOfCore
      ;

    # Policy dispatch (gen-dispatch STEP driven by gen-scope.circular's LOOP:
    # actions accumulate across passes into `accActions`, keyed by phase).
    policyActionCounts = lib.mapAttrs (_: builtins.length) policyResult.accActions;

    # gen-bind wrapping
    inherit (bindResults)
      wrappedIsWrapped
      signatureRequires
      signatureBound
      advertisedArgs
      ;
  };
}
