# Test: flat registry walks recursive aspect tree into path-keyed attrset.
{
  lib,
  mkSchemaEval,
  aspects,
}:
let
  inherit (aspects) flatten;

  # Helper: derive parent from path key (implicit in key structure)
  parentOf =
    id:
    let
      parts = lib.splitString "/" id;
    in
    if builtins.length parts <= 1 then null else lib.concatStringsSep "/" (lib.init parts);

  eval = mkSchemaEval {
    classes = {
      nixos = { };
    };
    modules = [
      {
        config.aspects.networking = {
          nixos.networking.hostName = "test";
          firewall = {
            nixos.networking.firewall.enable = true;
          };
        };
        config.aspects.desktop = {
          nixos.environment.systemPackages = [ ];
        };
      }
    ];
  };

  flat = flatten eval.config.aspects;

  # Test with guard function
  guardEval = mkSchemaEval {
    classes = {
      nixos = { };
    };
    modules = [
      {
        config.aspects.conditional =
          { host }:
          {
            nixos.networking.hostName = host.name;
          };
      }
    ];
  };

  guardFlat = flatten guardEval.config.aspects;

  # Test deep nesting
  deepEval = mkSchemaEval {
    classes = {
      nixos = { };
    };
    modules = [
      {
        config.aspects.infra.networking.dns = {
          nixos.networking.nameservers = [ "1.1.1.1" ];
        };
      }
    ];
  };

  deepFlat = flatten deepEval.config.aspects;
in
{
  test-top-level-keys = {
    expr = lib.sort (a: b: a < b) (builtins.attrNames flat);
    expected = [
      "desktop"
      "networking"
      "networking/firewall"
    ];
  };

  test-nested-parent-from-key = {
    expr = parentOf "networking/firewall";
    expected = "networking";
  };

  test-top-level-parent-from-key = {
    expr = parentOf "networking";
    expected = null;
  };

  test-preserves-name = {
    expr = flat."networking".name;
    expected = "networking";
  };

  test-no-parent-field-injected = {
    # flatten does NOT inject __parent — parent is implicit in key
    expr = flat."networking/firewall" ? __parent;
    expected = false;
  };

  test-guard-function-appears = {
    expr = guardFlat ? "conditional";
    expected = true;
  };

  test-guard-function-not-recursed = {
    expr = builtins.filter (k: lib.hasPrefix "conditional/" k) (builtins.attrNames guardFlat);
    expected = [ ];
  };

  test-deep-nesting = {
    expr = lib.sort (a: b: a < b) (builtins.attrNames deepFlat);
    expected = [
      "infra"
      "infra/networking"
      "infra/networking/dns"
    ];
  };

  test-deep-parent-chain = {
    expr = {
      infra = parentOf "infra";
      networking = parentOf "infra/networking";
      dns = parentOf "infra/networking/dns";
    };
    expected = {
      infra = null;
      networking = "infra";
      dns = "infra/networking";
    };
  };

  test-class-keys-excluded = {
    expr = builtins.any (k: k == "networking/nixos") (builtins.attrNames flat);
    expected = false;
  };
}
