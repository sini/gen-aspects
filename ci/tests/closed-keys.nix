# Closed-key typo-gate (design decision 2, opt-in, default OFF). The freeform fallback silently absorbs
# any undeclared key as a nested aspect (types.nix:288), so a misspelled class/facet key becomes a
# stray sub-aspect. When `closedKeys` is on, an undeclared key NOT in `freeformKeys` throws a named
# error; default off preserves today's absorption exactly.
{
  genMerge,
  mkSchemaEval,
  ...
}:
let
  # default (flag off): undeclared key → nested aspect (unchanged behavior)
  off = mkSchemaEval { modules = [ { config.aspects.svc.extra.setting = "x"; } ]; };

  # flag on, `typoKey` not allowed → throw when forced
  rejected = builtins.tryEval (
    builtins.deepSeq
      (mkSchemaEval {
        closedKeys = true;
        modules = [
          {
            config.aspects.svc.typoKey = {
              a = 1;
            };
          }
        ];
      }).config.aspects.svc.typoKey
      true
  );

  # flag on, `extra` allowed → still nests as an aspect, AND its subtree stays ungated: the DEEPER
  # undeclared key `child` still nests (does not re-throw under the gate). `k = "x"` is a leaf string,
  # returned verbatim by aspectType.merge — not asserted on.
  allowed = mkSchemaEval {
    closedKeys = true;
    freeformKeys = [ "extra" ];
    modules = [ { config.aspects.svc.extra.child.k = "x"; } ];
  };

  # flag on: a DECLARED facet key still resolves to its default
  declared = mkSchemaEval {
    closedKeys = true;
    keySemantics = {
      tier = {
        category = "facet";
        option = genMerge.mkOption {
          type = genMerge.types.str;
          default = "t0";
        };
      };
    };
    modules = [ { config.aspects.svc = { }; } ];
  };
in
{
  flake.tests.closed-keys.test-default-off-absorbs = {
    expr = off.config.aspects.svc.extra ? name;
    expected = true;
  };
  flake.tests.closed-keys.test-gate-on-rejects-undeclared = {
    expr = rejected.success;
    expected = false;
  };
  flake.tests.closed-keys.test-gate-on-allows-listed = {
    expr = allowed.config.aspects.svc.extra ? name;
    expected = true;
  };
  # the ungated subtree still NESTS a deeper undeclared key (proves the allowed key opened an ungated
  # subtree — `child` is absorbed as a nested aspect, not re-thrown by the gate).
  flake.tests.closed-keys.test-gate-on-allows-nested-subtree = {
    expr = allowed.config.aspects.svc.extra.child ? name;
    expected = true;
  };
  flake.tests.closed-keys.test-gate-on-declared-facet-works = {
    expr = declared.config.aspects.svc.tier;
    expected = "t0";
  };
}
