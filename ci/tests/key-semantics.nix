# Test: generic per-key dispatch over cnf.keySemantics (Shape B).
#
# aspectSubmodule builds each declared aspect key's option FROM keySemantics:
#   class   → deferredModule option (lazy class content)
#   channel → raw passthrough (mkOption { type = raw; default = null; }); value rides
#             VERBATIM, is NOT turned into a nested aspect
#   facet   → the entry's own option (bare mkOption) or module (mounted via imports)
# An UNDECLARED key falls through to the freeform fallback → a nested aspect (gets identity).
#
# This retires the old hardcoded `cnf.classes → classOptions` arm: a class key is now
# just a keySemantics entry with category = "class".
{
  genMerge,
  lib,
  mkSchemaEval,
  ...
}:
let
  # A schema whose aspect keys exercise all three categories.
  eval = mkSchemaEval {
    keySemantics = {
      nixos = {
        category = "class";
      };
      firewall = {
        category = "channel";
      };
      neededBy = {
        category = "facet";
        option = genMerge.mkOption {
          description = "Facet: neededBy list";
          type = genMerge.types.listOf genMerge.types.str;
          default = [ ];
        };
      };
    };
    modules = [
      {
        config.aspects.svc = {
          firewall = {
            ports = [ 80 ];
          };
          nixos.networking.hostName = "svc-host";
        };
      }
    ];
  };

  # A separate eval where the channel value is set and an undeclared key is used.
  eval2 = mkSchemaEval {
    keySemantics = {
      firewall = {
        category = "channel";
      };
    };
    modules = [
      {
        config.aspects.svc = {
          firewall = {
            ports = [ 443 ];
          };
          # undeclared key → nested aspect
          extra.setting = "x";
        };
      }
    ];
  };

  nixosEval = genMerge.evalModuleTree {
    modules = [
      { options.networking.hostName = genMerge.mkOption { type = genMerge.types.str; }; }
      eval.config.aspects.svc.nixos
    ];
  };
in
{
  # (1) A channel value rides raw — it is NOT a nested aspect (no `name` identity field).
  flake.tests.key-semantics.test-channel-value-is-raw-not-nested-aspect = {
    expr = eval2.config.aspects.svc.firewall ? name;
    expected = false;
  };

  # Channel value reads back verbatim.
  flake.tests.key-semantics.test-channel-value-verbatim = {
    expr = eval2.config.aspects.svc.firewall;
    expected = {
      ports = [ 443 ];
    };
  };

  # (2) A class key is present as deferred (lazy) content — imports cleanly into a NixOS eval.
  flake.tests.key-semantics.test-class-key-is-deferred-content = {
    expr = nixosEval.config.networking.hostName;
    expected = "svc-host";
  };

  # (3) A facet option applies with its declared default.
  flake.tests.key-semantics.test-facet-option-default = {
    expr = eval.config.aspects.svc.neededBy;
    expected = [ ];
  };

  # (4) An UNDECLARED key IS a nested aspect (gets identity).
  flake.tests.key-semantics.test-undeclared-key-is-nested-aspect = {
    expr = eval2.config.aspects.svc.extra ? name;
    expected = true;
  };

  # (5) A facet declared via a full `module` (mounted through imports) applies.
  flake.tests.key-semantics.test-facet-module-option = {
    expr =
      (mkSchemaEval {
        keySemantics = {
          tier = {
            category = "facet";
            module = {
              options.tier = genMerge.mkOption {
                type = genMerge.types.str;
                default = "default";
              };
            };
          };
        };
        modules = [ { config.aspects.svc = { }; } ];
      }).config.aspects.svc.tier;
    expected = "default";
  };

  # (6) An unknown category throws at construction (named, not a silent no-match).
  flake.tests.key-semantics.test-bad-category-throws = {
    expr =
      (builtins.tryEval (
        builtins.deepSeq
          (mkSchemaEval {
            keySemantics = {
              bad = {
                category = "bogus";
              };
            };
            modules = [ { config.aspects.svc = { }; } ];
          }).config.aspects.svc.name
          true
      )).success;
    expected = false;
  };
}
