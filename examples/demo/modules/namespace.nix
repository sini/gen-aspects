# Observability namespace: prometheus, grafana, loki.
# Demonstrates mkNamespaceType for aspect namespacing.
{
  config,
  lib,
  aspectSchema,
  ...
}:
{
  options.namespaces = lib.mkOption {
    type = lib.types.attrsOf (aspectSchema.mkNamespaceType { });
    default = { };
    description = "Named aspect namespaces.";
  };

  config.namespaces.observability = {
    prometheus = {
      includes = [ config.aspects.monitoring-base ];
      tags = [
        "observability"
        "metrics"
        "stateful"
      ];
      settings = {
        scrape.interval = {
          default = 15;
        };
        scrape.timeout = {
          default = 10;
        };
        scrape.targets = {
          default = [ ];
          merge = "append";
        };
        storage.retention-days = {
          default = 30;
        };
        storage.retention-size = {
          default = "50GB";
        };
        alerting.rules-dir = {
          default = "/etc/prometheus/rules";
        };
        alerting.evaluation-interval = {
          default = 15;
        };
      };
    };

    grafana = {
      includes = [ config.namespaces.observability.prometheus ];
      tags = [
        "observability"
        "dashboards"
        "public-facing"
      ];
      settings = {
        server.port = {
          default = 3000;
        };
        server.root-url = {
          default = "http://localhost:3000";
        };
        auth.admin-password = {
          default = "admin";
        };
        auth.anonymous-enabled = {
          default = false;
        };
        datasources = {
          default = { };
          merge = "recursive";
        };
      };
    };

    loki = {
      tags = [
        "observability"
        "logging"
      ];
      settings = {
        storage.retention-days = {
          default = 14;
        };
        storage.chunk-target-size = {
          default = "1536KB";
        };
        ingestion.rate-limit = {
          default = 10;
        };
        ingestion.burst-size = {
          default = 20;
        };
      };
    };
  };
}
