# Web service aspects: nginx, app server — nested under services.
{ config, lib, ... }:
{
  config.aspects.services = {
    nginx = {
      includes = [ config.aspects.networking ];
      tags = [
        "web"
        "proxy"
        "public-facing"
      ];
      tier = "frontend";
      settings = {
        listen.port = {
          default = 80;
        };
        listen.ssl-port = {
          default = 443;
        };
        listen.ssl-enabled = {
          default = true;
        };
        performance.workers = {
          default = 4;
        };
        performance.worker-connections = {
          default = 1024;
        };
        performance.keepalive-timeout = {
          default = 65;
        };
        security.rate-limit = {
          default = "10r/s";
        };
        security.allowed-origins = {
          default = [ ];
          merge = "append";
        };
        upstream.servers = {
          default = [ ];
          merge = "append";
        };
        upstream.health-check-interval = {
          default = 30;
        };
        locations = {
          default = { };
          merge = "recursive";
        };
      };
      nixos = {
        services.nginx.enable = lib.mkDefault true;
      };
    };

    app = {
      includes = [ config.aspects.networking ];
      tags = [
        "web"
        "application"
      ];
      tier = "backend";
      settings = {
        server.port = {
          default = 8080;
        };
        server.workers = {
          default = 4;
        };
        server.bind-address = {
          default = "127.0.0.1";
        };
        logging.level = {
          default = "info";
        };
        logging.format = {
          default = "json";
        };
        logging.outputs = {
          default = [ "stdout" ];
          merge = "append";
        };
        features = {
          default = { };
          merge = "recursive";
        };
        database.pool-size = {
          default = 10;
        };
        database.timeout = {
          default = 5000;
        };
        cache.backend = {
          default = "memory";
        };
        cache.ttl = {
          default = 300;
        };
      };
    };
  };
}
