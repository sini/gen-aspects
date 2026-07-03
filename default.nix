# Standalone (non-flake) entry. Flake consumers should use the `.lib` output.
# gen-aspects is a function of three named values — gen-prelude, the gen-merge engine, and the
# (re-hosted) gen-schema. Defaults fetch the flake-locked revs (content-addressed via narHash, so the
# plain-import path stays pure). gen-merge / gen-schema self-construct their own deps from their locks.
{
  lock ? builtins.fromJSON (builtins.readFile ./flake.lock),
  fetch ? name: builtins.fetchTree (lock.nodes.${lock.nodes.root.inputs.${name}}.locked),
  prelude ? import "${fetch "gen-prelude"}/lib",
  merge ? import "${fetch "gen-merge"}" { inherit prelude; },
  schema ? import "${fetch "gen-schema"}" { inherit prelude merge; },
}:
import ./lib { inherit prelude merge schema; }
