# Fleet structure: environments and hosts.
{ lib, ... }:
{
  options.fleet = {
    environments = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.tier = lib.mkOption {
            type = lib.types.str;
            description = "Deployment tier classification.";
          };
        }
      );
      default = { };
      description = "Environment definitions.";
    };

    hosts = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.env = lib.mkOption {
            type = lib.types.str;
            description = "Environment this host belongs to.";
          };
          options.role = lib.mkOption {
            type = lib.types.str;
            description = "Host role.";
          };
        }
      );
      default = { };
      description = "Host definitions.";
    };
  };

  config.fleet = {
    environments = {
      prod = {
        tier = "production";
      };
      staging = {
        tier = "staging";
      };
      dev = {
        tier = "development";
      };
    };

    hosts = {
      prod-web-1 = {
        env = "prod";
        role = "web";
      };
      prod-web-2 = {
        env = "prod";
        role = "web";
      };
      prod-db-1 = {
        env = "prod";
        role = "database";
      };
      staging-web = {
        env = "staging";
        role = "web";
      };
      staging-db = {
        env = "staging";
        role = "database";
      };
      dev-all = {
        env = "dev";
        role = "all";
      };
    };
  };
}
