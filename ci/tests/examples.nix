# demo/flake.nix takes the hub, which pins this repository, so the suite cannot evaluate it against
# this tree; it is excluded by name until den-hoag-tyu25 wires it to the working tree.
{
  gen.ci.examples = { };
  gen.ci.examplesExcluded.demo = {
    row = "den-hoag-tyu25";
    reason = "its flake takes the hub, which pins a published gen-aspects";
  };
}
