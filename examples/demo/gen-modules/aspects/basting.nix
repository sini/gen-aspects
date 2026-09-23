# Account-shaped settings aspect (an invented name: gen names no entities, ADR-0035).
{ config, lib, ... }:
{
  config.aspects.define-basting = {
    tags = [ "identity" ];
    settings = {
      shell = {
        default = "/run/current-system/sw/bin/bash";
      };
      groups = {
        default = [ "basting" ];
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
