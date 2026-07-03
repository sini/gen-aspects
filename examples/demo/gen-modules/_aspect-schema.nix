# Shared aspect-schema construction for the PURE gen tree (gen-flake value-injection).
#
# NON-module helper: the leading underscore excludes it from the import-tree tree load (gen-flake's
# import-tree fork skips `/_`-prefixed paths). It is imported by relative path from setup.nix and
# namespace.nix so both share ONE `mkAspectSchema` cnf — the `nixos` class, the settings/tags
# collections, and the `settings` aspectModule that keeps a `settings` leaf a typed option rather than
# falling through freeform (which would treat each settings leaf as a nested aspect). This is the
# gen-schema replacement for den.reservedKeys.
{ genAspects, lib }:
genAspects.mkAspectSchema {
  classes = {
    nixos = { };
  };
  collections = {
    settings = {
      default = { };
    };
    tags = {
      default = [ ];
    };
  };
  aspectModules = [
    {
      options.settings = lib.mkOption {
        type = lib.types.lazyAttrsOf lib.types.raw;
        default = { };
        description = "Settings schema declarations for this aspect.";
      };
    }
  ];
}
