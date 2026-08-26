# The `mkAspectSchema` ARGUMENT (the `cnf`) — ONE declaration, two readers:
#   * ./_aspect-schema.nix constructs the shared aspect schema from it (setup.nix + namespace.nix);
#   * flake.nix hands it to gen-delivery's `project` as the key-category DECLARATION. The
#     realization predicate reads `keySemantics.<key>.category` (a delivery class realizes on
#     DECLARED content, never structural shape), and it must read the SAME declaration the tree was
#     composed under — so the argument lives in one file rather than being restated at the caller.
#
# NON-module helper: the leading underscore excludes it from the import-tree tree load.
#
# The declaration: the `nixos` class, the settings/tags collections, and the `settings`
# aspectModule that keeps a `settings` leaf a typed option rather than falling through freeform
# (which would treat each settings leaf as a nested aspect). This is the gen-schema replacement for
# den.reservedKeys.
{ lib }:
{
  keySemantics = {
    nixos = {
      category = "class";
    };
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
