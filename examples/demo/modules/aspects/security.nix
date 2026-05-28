# Security aspects: hardening (guard), firewall (guard).
{ config, lib, ... }:
{
  config.aspects = {
    hardening =
      { host, ... }:
      {
        tags = [ "security" ];
        nixos = {
          security.sudo.execWheelOnly = true;
          services.openssh.settings = {
            PermitRootLogin = "no";
            PasswordAuthentication = false;
          };
        };
      };

    firewall =
      { host, ... }:
      {
        includes = [ config.aspects.networking ];
        tags = [
          "security"
          "network"
        ];
        settings = {
          firewall.allowed-tcp = {
            default = [ ];
            merge = "append";
          };
          firewall.allowed-udp = {
            default = [ ];
            merge = "append";
          };
          firewall.log-dropped = {
            default = true;
          };
          firewall.rate-limiting = {
            default = { };
            merge = "recursive";
          };
        };
        nixos = {
          networking.firewall.enable = lib.mkDefault true;
        };
      };
  };
}
