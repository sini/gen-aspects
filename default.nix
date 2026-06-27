{
  lib ? (import <nixpkgs> { }).lib,
  schema ?
    let
      lock = builtins.fromJSON (builtins.readFile ./flake.lock);
    in
    import "${builtins.fetchTree lock.nodes.gen-schema.locked}" { inherit lib; },
  ...
}:
import ./lib { inherit lib schema; }
