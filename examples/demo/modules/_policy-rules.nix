# Policy action vocabulary + rules + the blessed convergence composition (NON-module:
# imported by relative path, NOT a flake-parts module — the leading underscore excludes
# it from import-tree ./modules).
{
  lib,
  genDispatch,
  genGraph,
  genScope,
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
  # Group ORDERING is gen-graph's job now (gen-dispatch is the pure dispatch STEP).
  # `groupOrder` is a `[ groupName ]` list; dispatch walks it, threading context.
  groupOrder = genGraph.phaseOrder {
    structural = genGraph.entryAnywhere;
    configuration = genGraph.entryAfter [ "structural" ];
  };

  prodHardening = mkRule {
    condition.env = false;
    produce =
      _id: ctx: lib.optional (ctx.env.tier == "production") (act.edge { target = "hardening"; });
    identity = "prod-hardening";
    group = "structural";
  };

  # databaseBackup is two rules: a single rule may not emit actions across two
  # groups (gen-dispatch dispatch throws), so the structural enrich and the
  # configuration patch are separate bindings.
  databaseBackupEnrich = mkRule {
    condition.thimble = false;
    produce =
      _id: ctx:
      lib.optional (ctx.thimble.role == "database") (
        act.enrich {
          key = "backup-enabled";
          value = true;
        }
      );
    identity = "database-backup-enrich";
    group = "structural";
  };

  databaseBackupConfig = mkRule {
    condition.thimble = false;
    produce =
      _id: ctx:
      lib.optional (ctx.thimble.role == "database") (
        act.configure {
          aspect = "postgres";
          settings.backup = {
            schedule = "0 2 * * *";
            retention = 7;
          };
        }
      );
    identity = "database-backup-config";
    group = "configuration";
  };

  nodeExporter = mkRule {
    condition.thimble = false;
    produce = _id: ctx: [
      (act.configure {
        aspect = "monitoring-base";
        settings.scrape.targets = [ "${ctx.thimble.name}:9100" ];
      })
    ];
    identity = "node-exporter";
    group = "configuration";
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
    group = "configuration";
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
    group = "configuration";
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

  # The dispatch config sans context — once a context is applied, `dispatch` is a pure
  # function of it (a given context always yields the same actions).
  cfg = {
    inherit rules extract groupOrder;
    id = null;
    match = fromFunctionMatch;
    classify = act.classify;
    combine = ctx: ext: ctx // ext;
  };

  # The keys an `enrich` action can add to the context — a fact about the RULES above (only
  # `databaseBackupEnrich` enriches), so it is declared beside them rather than derived.
  enrichKeys = [ "backup-enabled" ];

  # THE CONVERGENCE CARRIER (Söderberg & Hedin 2013 §4.1: a bottom, an order, a bounded height).
  # The order is EXTENSION: `b` carries every key of `a` with the same value, so an `enrich` that
  # overwrote a key with a different value is not an ascent and gen-scope refuses it by name. Each
  # strict ascent adds at least one key, so the declared enrich keys bound the chain by their count.
  # The order is over the whole context value (antisymmetric), so this is not a quotient carrier.
  mkCarrier = context: {
    bottom = context;
    leq = a: b: builtins.all (k: (b ? ${k}) && b.${k} == a.${k}) (builtins.attrNames a);
    height = builtins.length enrichKeys;
    quotient = false;
  };

  # The loop⊥step composition. gen-dispatch is a pure STEP; gen-scope.circular is the LOOP.
  # We thread the PLAIN domain state (context): each pass is one one-shot `dispatch` whose
  # output context is the next iterate, and `enrich` widens context via extract/combine. The
  # `circular` declaration is reached THROUGH gen-scope's evaluator (one node, one attribute),
  # which runs the ascent where the carrier is readable. The policy actions are then a function
  # of the CONVERGED context — one post-convergence dispatch — never the iteration path.
  # Recompute-at-fixpoint cannot double-emit, so no cross-pass accumulator rides the value.
  resolve =
    context:
    let
      converged =
        (genScope.eval {
          scope = genScope.buildRoots {
            parentGraph = genScope.vertex "context";
            decls.context = { };
          };
          attributes = {
            children = _self: _id: { };
            imports = _self: _id: [ ];
            converged-context = genScope.circular { carrier = mkCarrier context; } (
              _self: _id: ctx:
              (genDispatch.dispatch (cfg // { context = ctx; })).context
            );
          };
        }).get
          "context"
          "converged-context";
    in
    genDispatch.dispatch (cfg // { context = converged; });
in
{
  inherit
    act
    groupOrder
    rules
    extract
    fromFunctionMatch
    cfg
    resolve
    ;
}
