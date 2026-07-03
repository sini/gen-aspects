# Entity-level settings overrides.
# Plain attrsets keyed by scope node ID ("env:<name>" or "host:<name>").
# Nested paths match aspect settings schemas.
{ lib, ... }:
{
  options.scopeSettings = lib.mkOption {
    type = lib.types.attrsOf lib.types.raw;
    default = { };
    description = "Per-scope settings overrides keyed by scope node ID.";
  };

  config.scopeSettings = {
    # --- Environment-level overrides ---

    "env:prod" = {
      nginx.performance.workers = 16;
      nginx.security.rate-limit = 1000;
      nginx.listen.ssl-enabled = true;
      nginx.security.allowed-origins = [ "https://app.example.com" ];
      nginx.locations."/" = {
        proxy-pass = "http://upstream";
      };
      nginx.locations."/api" = {
        proxy-pass = "http://api-upstream";
        rate-limit = 500;
      };
      postgres.connection.max-connections = 500;
      postgres.memory.shared-buffers = "4GB";
      postgres.replication.wal-level = "logical";
      redis.memory.maxmemory = "2gb";
      redis.persistence.aof-enabled = true;
      app.logging.level = "warn";
      app.server.workers = 8;
    };

    "env:staging" = {
      nginx.performance.workers = 4;
      nginx.listen.ssl-enabled = true;
      postgres.connection.max-connections = 200;
      app.logging.level = "info";
      app.features.beta-ui = true;
    };

    "env:dev" = {
      nginx.performance.workers = 1;
      postgres.connection.max-connections = 20;
      app.logging.level = "debug";
      app.features = {
        beta-ui = true;
        experimental-api = true;
        new-auth = true;
      };
      app.database.pool-size = 3;
    };

    # --- Host-level overrides ---

    "host:prod-web-1" = {
      nginx.performance.workers = 32;
      nginx.performance.worker-connections = 4096;
      nginx.upstream.servers = [
        "app-1:3000"
        "app-2:3000"
        "app-3:3000"
      ];
      nginx.locations."/static" = {
        root = "/var/www/static";
        cache-control = "max-age=86400";
      };
    };

    "host:prod-db-1" = {
      postgres.memory.shared-buffers = "8GB";
      postgres.memory.work-mem = "16MB";
      postgres.connection.max-connections = 1000;
      postgres.backup = {
        schedule = "0 2 * * *";
        retention = 7;
        method = "pg_basebackup";
        destination = "s3://backups/postgres";
      };
    };
  };
}
