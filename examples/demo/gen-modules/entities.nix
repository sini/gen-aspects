# Fleet structure: environments and hosts.
#
# Marked `pureModule` (gen-merge README §"The pureModule contract"). The fleet inventory is a CONSTANT
# declaration — the inner module reads only `lib` (threaded from `compose`'s `specialArgs`), never
# `config`/`options`, so both contract clauses hold: it reads only its declared formals, and every
# formal resolves from `specialArgs`. Marking it lets a WARM override (a modules-only append) SPLICE the
# fleet registry leaves (`fleet.hosts` / `fleet.environments`) unchanged from the previous eval instead
# of re-merging them (the trace showcase in modules/override-trace.nix reads them out of `reused`). The
# outer wrapper is a function (dirty by default) but declares/defines nothing itself, so it adds nothing
# to the warm path's dirty footprint — only the marked inner entry carries the fleet leaves.
{ genMerge, ... }:
{
  imports = [
    (genMerge.pureModule (
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
    ))
  ];
}
