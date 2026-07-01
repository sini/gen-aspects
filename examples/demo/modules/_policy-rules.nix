# Policy action vocabulary + rules (NON-module: imported by relative path, NOT a
# flake-parts module — the leading underscore excludes it from import-tree ./modules).
{
  lib,
  genDispatch,
  genGraph,
}:
let
  inherit (genDispatch)
    mkActions
    mkRule
    fromFunctionMatch
    ;
  act = mkActions {
    structural = [
      "edge"
      "enrich"
    ];
    configuration = [ "configure" ];
  };
  # Phase ORDERING is gen-graph's job now (gen-dispatch is the pure dispatch STEP).
  # `phaseOrder` is a `[ phaseName ]` list; dispatch walks it, threading context.
  phaseOrder = genGraph.phaseOrder {
    structural = genGraph.entryAnywhere;
    configuration = genGraph.entryAfter [ "structural" ];
  };

  prodHardening = mkRule {
    condition.env = false;
    produce =
      _id: ctx: lib.optional (ctx.env.tier == "production") (act.edge { target = "hardening"; });
    identity = "prod-hardening";
    phase = "structural";
  };

  # databaseBackup is two rules: a single rule may not emit actions across two
  # phases (gen-dispatch dispatch throws), so the structural enrich and the
  # configuration patch are separate bindings.
  databaseBackupEnrich = mkRule {
    condition.host = false;
    produce =
      _id: ctx:
      lib.optional (ctx.host.role == "database") (
        act.enrich {
          key = "backup-enabled";
          value = true;
        }
      );
    identity = "database-backup-enrich";
    phase = "structural";
  };

  databaseBackupConfig = mkRule {
    condition.host = false;
    produce =
      _id: ctx:
      lib.optional (ctx.host.role == "database") (
        act.configure {
          aspect = "postgres";
          settings.backup = {
            schedule = "0 2 * * *";
            retention = 7;
          };
        }
      );
    identity = "database-backup-config";
    phase = "configuration";
  };

  nodeExporter = mkRule {
    condition.host = false;
    produce = _id: ctx: [
      (act.configure {
        aspect = "monitoring-base";
        settings.scrape.targets = [ "${ctx.host.name}:9100" ];
      })
    ];
    identity = "node-exporter";
    phase = "configuration";
  };

  devRelaxedFirewall = mkRule {
    condition.env = false;
    produce =
      _id: ctx:
      lib.optional (ctx.env.tier == "development") (
        act.configure {
          aspect = "firewall";
          settings.allowed-tcp = [
            8080
            8443
            9090
            3000
          ];
        }
      );
    identity = "dev-relaxed-firewall";
    phase = "configuration";
  };

  prodLogging = mkRule {
    condition.env = false;
    produce =
      _id: ctx:
      lib.optional (ctx.env.tier == "production") (
        act.configure {
          aspect = "app";
          settings.logging = {
            level = "error";
            structured = true;
            destination = "syslog";
          };
        }
      );
    identity = "prod-logging";
    # rule fire-order only (lower fires earlier); NOT settings-merge precedence
    # (settings merge by cascade layer position) — do not copy to other rules.
    priority = 10;
    phase = "configuration";
  };

  rules = [
    prodHardening
    databaseBackupEnrich
    databaseBackupConfig
    nodeExporter
    devRelaxedFirewall
    prodLogging
  ];

  extract =
    actions:
    lib.foldl' (acc: a: if a.__action == "enrich" then acc // { ${a.key} = a.value; } else acc) { } (
      actions.structural or [ ]
    );
in
{
  inherit
    act
    phaseOrder
    rules
    extract
    fromFunctionMatch
    ;
}
