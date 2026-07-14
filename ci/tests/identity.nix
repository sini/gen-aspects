# Test: aspect identity key computation.
{
  lib,
  aspects,
  mkSchemaEval,
  ...
}:
{
  flake.tests.identity.test-root-aspect-key =
    let
      eval = mkSchemaEval { modules = [ { config.aspects.networking.classOne = { }; } ]; };
    in
    {
      # A-IDENT (2b, container-relative): a root aspect's chain is empty, so its key is just
      # its own name — the mount segment is re-rooted away by aspectsRoot.
      expr = eval.config.aspects.networking.key;
      expected = "networking";
    };

  flake.tests.identity.test-nested-aspect-key =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.infra.networking.classOne = { }; }
        ];
      };
    in
    {
      # nested via freeform → aspectType → aspectSubmodule.
      # A-IDENT (2b): key carries the full container-RELATIVE path, no longer name-only.
      expr = eval.config.aspects.infra.networking.key;
      expected = "infra/networking";
    };

  # A-IDENT witness: two distinct aspects sharing a leaf name at DISTINCT paths must get
  # DISTINCT keys (name-only collapse fixed). hardware.cpu.intel ≠ hardware.gpu.intel.
  flake.tests.identity.test-no-name-only-collision =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.hardware.cpu.intel.classOne = { }; }
          { config.aspects.hardware.gpu.intel.classOne = { }; }
        ];
      };
      cpu = eval.config.aspects.hardware.cpu.intel.key;
      gpu = eval.config.aspects.hardware.gpu.intel.key;
    in
    {
      expr = {
        inherit cpu gpu;
        collide = cpu == gpu;
      };
      expected = {
        cpu = "hardware/cpu/intel";
        gpu = "hardware/gpu/intel";
        collide = false;
      };
    };

  flake.tests.identity.test-meaningful-name-check = {
    expr = {
      anon = aspects.isMeaningfulName "<anon>";
      fn = aspects.isMeaningfulName "<function body>";
      def = aspects.isMeaningfulName "[definition 1-entry 1]";
      real = aspects.isMeaningfulName "networking";
    };
    expected = {
      anon = false;
      fn = false;
      def = false;
      real = true;
    };
  };
}
