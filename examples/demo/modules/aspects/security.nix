# Security aspects: hardening (plain), firewall (static settings + parametric nixos).
{ config, lib, ... }:
{
  config.aspects = {
    # Demoted from guard fn: nixos uses no host/settings, so a plain attrset suffices.
    hardening = {
      tags = [ "security" ];
      nixos = {
        security.sudo.execWheelOnly = true;
        services.openssh.settings = {
          PermitRootLogin = "no";
          PasswordAuthentication = false;
        };
      };
    };

    # Canonical parametric aspect: STATIC bare-key settings schema at top level
    # (introspectable by flatten/cascade); only class CONTENT is parametric and
    # CONSUMES resolved settings (injected in a later task). BARE leaf keys
    # (allowed-tcp, not firewall.allowed-tcp) — composition namespaces under
    # leafName "firewall", yielding cascade keys firewall.allowed-tcp etc.
    firewall = {
      includes = [ config.aspects.networking ];
      tags = [
        "security"
        "network"
      ];
      settings = {
        allowed-tcp = {
          default = [ ];
          merge = "append";
        };
        allowed-udp = {
          default = [ ];
          merge = "append";
        };
        log-dropped = {
          default = true;
        };
        rate-limiting = {
          default = { };
          merge = "recursive";
        };
      };
      # Receives resolved per-host settings (+ host) via the injection construct
      # BEFORE evalModules; lib/config/pkgs still flow from the module system.
      # Kebab schema keys map to camelCase NixOS option names here.
      nixos =
        {
          settings,
          host,
          lib,
          ...
        }:
        {
          networking.firewall.enable = lib.mkDefault true;
          networking.firewall.allowedTCPPorts = settings.firewall.allowed-tcp;
          networking.firewall.allowedUDPPorts = settings.firewall.allowed-udp;
          networking.firewall.logRefusedConnections = settings.firewall.log-dropped;
        };
    };
  };
}
