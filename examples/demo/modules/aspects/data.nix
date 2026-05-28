# Data service aspects: postgres, redis — nested under services.
{ config, lib, ... }:
{
  config.aspects.services = {
    postgres = {
      includes = [ config.aspects.networking ];
      tags = [
        "database"
        "stateful"
      ];
      tier = "data";
      settings = {
        connection.port = {
          default = 5432;
        };
        connection.max-connections = {
          default = 100;
        };
        connection.listen-addresses = {
          default = "localhost";
        };
        memory.shared-buffers = {
          default = "128MB";
        };
        memory.work-mem = {
          default = "4MB";
        };
        memory.effective-cache-size = {
          default = "4GB";
        };
        replication.wal-level = {
          default = "replica";
        };
        replication.max-wal-senders = {
          default = 3;
        };
        replication.synchronous-commit = {
          default = "on";
        };
        backup = {
          default = { };
          merge = "recursive";
        };
      };
      nixos = {
        services.postgresql.enable = lib.mkDefault true;
      };
    };

    redis = {
      includes = [ config.aspects.networking ];
      tags = [
        "cache"
        "stateful"
      ];
      tier = "data";
      settings = {
        connection.port = {
          default = 6379;
        };
        connection.bind = {
          default = "127.0.0.1";
        };
        memory.maxmemory = {
          default = "256mb";
        };
        memory.eviction-policy = {
          default = "allkeys-lru";
        };
        persistence.rdb-enabled = {
          default = true;
        };
        persistence.aof-enabled = {
          default = false;
        };
        cluster.enabled = {
          default = false;
        };
        cluster.nodes = {
          default = [ ];
          merge = "append";
        };
      };
      nixos = {
        services.redis.servers.default.enable = lib.mkDefault true;
      };
    };
  };
}
