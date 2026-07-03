# The typed aspect SURFACE — declared PURELY inside the gen tree (gen-flake value-injection).
#
# The old flake-parts `modules/setup.nix` embedded `options.schema`/`options.aspects` gen TYPES into
# flake-parts' nixpkgs `lib.evalModules`, which walked them via `substSubModules`/`getSubOptions` and
# threw under the pure re-host. Relocating them here is the crux of the migration: gen-merge's
# `evalModuleTree` — gen-aspects' own host engine — handles the gen aspect type natively, whereas
# flake-parts' nixpkgs `lib.evalModules` could not. The kind definitions (`config.aspects.*`) live in
# ./aspects/*.nix; the resolved VALUES cross to the flake-parts reader via gen-flake's injected
# `genValues`, and the gen type never leaves this pure eval.
#
# gen-flake threads `genAspects`/`genMerge`/… into every tree module; `lib` comes via
# `gen.specialArgs`. The old `_module.args` gen-library threading is gone — reader-side libraries are
# now provided as flake-parts `_module.args` in flake.nix (distinct from the injected VALUES).
{ genAspects, lib, ... }:
let
  aspectSchema = import ./_aspect-schema.nix { inherit genAspects lib; };
in
{
  imports = [
    (aspectSchema.mkAspectModule { })
  ];

  options.schema = aspectSchema.schemaOption;

  # Schema extensions on the aspect kind. `config.schema.aspect.__defsModule` (built from these defs)
  # is threaded by `mkAspectModule` into every aspect instance, so `priority`/`tier` are available on
  # each aspect with no manual wiring.
  config.schema.aspect = {
    options.priority = lib.mkOption {
      type = lib.types.int;
      default = 50;
      description = "Aspect priority for ordering.";
    };
    options.tier = lib.mkOption {
      type = lib.types.str;
      default = "unspecified";
      description = "Deployment tier classification.";
    };
  };
}
