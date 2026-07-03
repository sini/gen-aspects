# Foundation aspects: base-system, networking, monitoring-base.
{ config, lib, ... }:
{
  config.aspects = {
    base-system = {
      tags = [
        "core"
        "foundation"
      ];
      priority = 0;
      settings = {
        timezone = {
          default = "UTC";
        };
        locale = {
          default = "en_US.UTF-8";
        };
        ntp.enabled = {
          default = true;
        };
        ntp.servers = {
          default = [ "pool.ntp.org" ];
          merge = "append";
        };
      };
      nixos = {
        time.timeZone = lib.mkDefault "UTC";
        i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
        services.timesyncd.enable = lib.mkDefault true;
      };
    };

    networking = {
      includes = [ config.aspects.base-system ];
      tags = [
        "core"
        "network"
      ];
      settings = {
        dns.nameservers = {
          default = [ "1.1.1.1" ];
          merge = "append";
        };
        dns.search-domains = {
          default = [ ];
          merge = "append";
        };
        network.domain = {
          default = "";
        };
        network.mtu = {
          default = 1500;
        };
      };
      nixos = {
        networking.useDHCP = lib.mkDefault true;
      };
    };

    monitoring-base = {
      tags = [
        "observability"
        "core"
      ];
      settings = {
        alerting.enabled = {
          default = false;
        };
        alerting.channels = {
          default = [ ];
          merge = "append";
        };
        scrape.targets = {
          default = [ ];
          merge = "append";
        };
      };
    };
  };
}
