# User management aspect.
{ config, lib, ... }:
{
  config.aspects.define-user = {
    tags = [ "identity" ];
    settings = {
      shell = {
        default = "/run/current-system/sw/bin/bash";
      };
      groups = {
        default = [ "users" ];
        merge = "append";
      };
      ssh.authorized-keys = {
        default = [ ];
        merge = "append";
      };
      ssh.agent-forwarding = {
        default = false;
      };
      limits.open-files = {
        default = 1024;
      };
      limits.nproc = {
        default = 4096;
      };
    };
  };
}
