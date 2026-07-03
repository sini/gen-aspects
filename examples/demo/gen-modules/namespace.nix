# Observability namespace: prometheus, grafana, loki.
# Demonstrates mkNamespaceType for aspect namespacing — declared PURELY in the gen tree (gen-flake
# value-injection); the resolved values cross to the reader as `genValues.namespaces`. The aspect-schema
# `cnf` is shared with setup.nix via ./_aspect-schema.nix so the namespaced aspect grammar matches.
# The `namespaces` option is declared with a gen-merge type (`genMerge.types.lazyAttrsOf`) so the whole
# surface stays native to `evalModuleTree` — no nixpkgs `lib.types.attrsOf` wrapping a gen submodule.
{
  config,
  lib,
  genAspects,
  genMerge,
  ...
}:
let
  aspectSchema = import ./_aspect-schema.nix { inherit genAspects lib; };
in
{
  options.namespaces = genMerge.mkOption {
    type = genMerge.types.lazyAttrsOf (aspectSchema.mkNamespaceType { });
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
