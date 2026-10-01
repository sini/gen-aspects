# demo/flake.nix takes the hub, which pins this repository: an INTEGRATION example. Its lock is not
# committed (`/examples/demo/flake.lock` in the root `.gitignore`); `relock` locks it fresh in a
# scratch copy and forces this value over the working tree (den-hoag-tyu25).
#
# The forced domain is the flake's outputs minus the flake plumbing and the derivation-bearing and
# system-keyed outputs, which are built rather than read as values.
{ exampleAtOwnLock, ... }:
{
  gen.ci.examples.demo = exampleAtOwnLock "demo" (
    flake:
    removeAttrs flake [
      "inputs"
      "outputs"
      "sourceInfo"
      "outPath"
      "_type"
      "apps"
      "checks"
      "devShells"
      "formatter"
      "legacyPackages"
      "nixosConfigurations"
      "nixosModules"
      "overlays"
      "packages"
    ]
  );
}
