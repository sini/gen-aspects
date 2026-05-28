# Expose verification outputs for the demo.
{
  config,
  lib,
  genAspects,
  composedSettings,
  scopeResult,
  flat,
  queryResults,
  policyResult,
  bindResults,
  ...
}:
{
  flake = {
    aspectCount = builtins.length (builtins.attrNames flat);
    aspectNames = lib.sort (a: b: a < b) (builtins.attrNames flat);
    hasTags = (config.aspects.base-system.tags or [ ]) != [ ];
    hasGuard = (flat.hardening or { }).__isWrappedFn or false;
    hasNestedSettings = (config.aspects.networking.settings or { }) != { };

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

    # Policy dispatch
    policyIterations = policyResult.iterations;
    policyActionCounts = lib.mapAttrs (_: builtins.length) policyResult.actions;

    # gen-bind wrapping
    inherit (bindResults)
      wrappedIsWrapped
      signatureRequires
      signatureBound
      advertisedArgs
      ;
  };
}
