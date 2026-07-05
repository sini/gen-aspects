# Expose verification outputs for the demo.
#
# READER side (gen-flake value-injection): the demo's encoded invariants render over the injected
# `genValues.aspects` (the gen tree's resolved config) and the cascade/query/policy/bind results
# threaded from sibling reader modules via `_module.args` — no flake-parts `config.*` gen option tree.
{
  lib,
  genValues,
  composedSettings,
  settingsProvenance,
  scopeResult,
  flat,
  queryResults,
  policyResult,
  policyResultsByHost,
  bindResults,
  realized,
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

  # The append-strategy cascade values (the resolved settings, BEFORE the terminal renders them).
  fwTcpDevAll = composedSettings.dev-all.firewall.allowed-tcp; # [8080 8443 9090 3000]
  fwTcpProdWeb1 = composedSettings.prod-web-1.firewall.allowed-tcp; # []

  # The REALIZED per-host nixos systems (realize + the bindings hook; modules/terminal.nix). Each is the
  # host's firewall (+ nginx, on web/all hosts) class content COMPOSED into one config — contrast the
  # old reader terminal, which rendered one aspect in isolation.
  devAllSys = realized.nixos.dev-all;
  prodWeb1Sys = realized.nixos.prod-web-1;
  prodDb1Sys = realized.nixos.prod-db-1;

  fwPortsDevAll = devAllSys.networking.firewall.allowedTCPPorts; # cascade fw ++ nginx 443
  fwPortsProdWeb1 = prodWeb1Sys.networking.firewall.allowedTCPPorts; # [] ++ nginx 443 = [443]
in
{
  flake = {
    aspectCount = builtins.length (builtins.attrNames flat);
    aspectNames = lib.sort (a: b: a < b) (builtins.attrNames flat);
    hasTags = (genValues.aspects.base-system.tags or [ ]) != [ ];
    hasNestedSettings = (genValues.aspects.networking.settings or { }) != { };

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

    # --- (iv) FIREWALL FULL LOOP: the cascade-resolved settings injected into the PARAMETRIC nixos via
    # realize's `bindings` hook → assert the rendered module value. v1 delta vs the reader terminal: a
    # host's system COMPOSES all its aspects, so the firewall ports UNION the cascade firewall ports with
    # nginx's public port (443) on web/all hosts. ---
    inherit fwPortsDevAll fwPortsProdWeb1; # dev-all = cascade ∪ {443}; prod-web-1 = [443]
    fwEnableDevAll = devAllSys.networking.firewall.enable; # true (firewall aspect, mkDefault)
    # The cascade firewall ports survive the compose (subset), and nginx contributes exactly its port.
    fwCascadePortsPreserved =
      lib.subtractLists fwPortsDevAll fwTcpDevAll == [ ] # cascade ⊆ merged (dev-all)
      && lib.subtractLists fwPortsProdWeb1 fwTcpProdWeb1 == [ ]; # cascade ⊆ merged (prod-web-1)
    nginxPortAddDevAll = lib.subtractLists fwTcpDevAll fwPortsDevAll; # [443] (merged − cascade)
    nginxPortAddProdWeb1 = lib.subtractLists fwTcpProdWeb1 fwPortsProdWeb1; # [443]

    # DISCRIMINATING (membership drives the build): a database host runs firewall ONLY (no nginx), so its
    # ports carry no 443 and its nginx config is empty.
    dbHasNoNginxPort = !(builtins.elem 443 prodDb1Sys.networking.firewall.allowedTCPPorts); # true
    dbNginxConfigEmpty = prodDb1Sys.services.nginx.config == ""; # true

    # --- (v) NGINX FULL LOOP (second aspect): resolved settings reach nginx ---
    nginxInjectionResolved = lib.hasInfix "worker_processes 32" prodWeb1Sys.services.nginx.config; # true

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
