{ pkgs ? import <nixpkgs> { }, lib ? pkgs.lib, inputs ? {} }:
let
  # No-flakes import: resolve den-schema from flake.lock
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  lockedSchema = lock.nodes.den-schema.locked;
  schemaSrc = builtins.fetchTarball {
    url = "https://github.com/${lockedSchema.owner}/${lockedSchema.repo}/archive/${lockedSchema.rev}.zip";
    sha256 = lockedSchema.narHash;
  };
  schemaLib = inputs.den-schema or (import schemaSrc { inherit lib; });
in
import ./lib { inherit lib schemaLib; }
