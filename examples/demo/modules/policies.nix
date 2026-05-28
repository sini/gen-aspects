# Policy dispatch: gen-derive rules with fixpoint convergence.
#
# Demonstrates mkActions vocabulary, fromFunction/mkRule constructors,
# multi-phase DAG, and fixpoint iteration with context enrichment.
{
  config,
  lib,
  genDerive,
  composedSettings,
  ...
}:
let
  inherit (genDerive)
    fixpoint
    fromFunction
    fromFunctionMatch
    mkRule
    mkActions
    entryAnywhere
    entryAfter
    ;

  # --- Action vocabulary ---
  # Two phases: structural actions run first, configuration actions second.
  fx = mkActions {
    structural = [
      "edge"
      "enrich"
    ];
    configuration = [ "settings" ];
  };

  # --- Phase DAG ---
  phases = {
    structural = entryAnywhere { };
    configuration = entryAfter [ "structural" ] { };
  };

  # --- Rules ---

  # 1. Prod hardening: add a structural edge for production environments
  prodHardening = fromFunction (
    { env, ... }: if env.tier == "production" then [ (fx.edge { target = "hardening"; }) ] else [ ]
  );

  # 2. Database backup: enrich context and emit backup settings for DB hosts
  databaseBackup = fromFunction (
    { host, ... }:
    if host.role == "database" then
      [
        (fx.enrich {
          key = "backup-enabled";
          value = true;
        })
        (fx.settings {
          backup.schedule = "0 2 * * *";
          backup.retention = 7;
        })
      ]
    else
      [ ]
  );

  # 3. Node exporter: universal prometheus scrape target
  nodeExporter = fromFunction (
    { host, ... }: [ (fx.settings { prometheus.scrape.targets = [ "${host.name}:9100" ]; }) ]
  );

  # 4. Dev relaxed firewall: open ports in development
  devRelaxedFirewall = fromFunction (
    { env, ... }:
    if env.tier == "development" then
      [
        (fx.settings {
          firewall.allowedTCPPorts = [
            8080
            8443
            9090
            3000
          ];
        })
      ]
    else
      [ ]
  );

  # 5. Prod logging: mkRule with explicit priority
  prodLogging = mkRule {
    condition = {
      env = false;
    };
    produce =
      _id: ctx:
      if ctx.env.tier == "production" then
        [
          (fx.settings {
            logging.level = "warn";
            logging.structured = true;
            logging.destination = "syslog";
          })
        ]
      else
        [ ];
    identity = "prod-logging";
    priority = 10;
  };

  rules = [
    prodHardening
    databaseBackup
    nodeExporter
    devRelaxedFirewall
    prodLogging
  ];

  # --- Fixpoint dispatch ---
  # Sample context: prod-web-1
  sampleEnv = config.fleet.environments.prod;
  sampleHost = config.fleet.hosts.prod-web-1 // {
    name = "prod-web-1";
  };

  # Extract feedback: enrich actions feed back into context
  extract =
    actions:
    lib.foldl' (acc: a: if a.__action == "enrich" then acc // { ${a.key} = a.value; } else acc) { } (
      actions.structural or [ ]
    );

  policyResult = fixpoint {
    inherit rules phases;
    context = {
      env = sampleEnv;
      host = sampleHost;
    };
    match = fromFunctionMatch;
    classify = fx.classify;
    inherit extract;
    combine = ctx: ext: ctx // ext;
    eq = a: b: builtins.attrNames a == builtins.attrNames b;
  };

in
{
  config._module.args = {
    inherit policyResult;
  };
}
