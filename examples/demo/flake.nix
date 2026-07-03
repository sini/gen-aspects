{
  description = "gen-aspects demo: aspect-oriented web deployment via gen-flake value-injection";

  # Value-injection migration (gen-flake). The gen definition tree (./gen-modules — aspect schema +
  # aspect/fleet/namespace/scopeSettings definitions) is composed PURELY by gen-flake's
  # `flakeModules.default` — gen-merge's byte-mode `evalModuleTree`, NOT flake-parts' nixpkgs
  # `lib.evalModules`. The resolved config VALUES are injected as the `genValues` module arg; NO gen
  # TYPE enters the flake-parts options tree (the old `options.schema`/`options.aspects`/
  # `options.namespaces` embeds made flake-parts walk a gen type via `substSubModules`/`getSubOptions`
  # and throw under the pure re-host). The `modules/*` READERS render over `genValues`.
  #
  # TERMINAL (class content). This demo assembles its `nixos` class content via a documented READER
  # terminal, NOT gen-flake's `mkSystems`. Rationale: the demo's terminal injects reader-COMPUTED
  # per-(host, aspect) resolved settings (the `composedSettings` cascade from gen-scope/gen-algebra/
  # gen-dispatch, run on the flake-parts side) into each aspect's parametric `nixos` via
  # `genBind.wrap` (modules/injection.nix → `assembledClasses`), then renders precise values through a
  # tiny stub `evalModules` (modules/outputs.nix). `mkSystems`'s `wrapAll` binds only the resolved
  # `host` instance (+ `nodes` via specialArgs) and builds a full `nixpkgs.lib.nixosSystem`; it has no
  # hook for the richer settings binding this demo needs, and the demo asserts exact rendered values
  # without a full NixOS eval. gen-flake's `flakeModules.default` still emits
  # `flake.nixosConfigurations = mkSystems { … }`, but the fleet lives under `fleet.hosts` (not the
  # top-level `hosts` compose projects over), so that projection is empty here — harmless, matching the
  # gen-schema demo. See the gen-flake README "reader terminal" escape hatch.
  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } (
      {
        lib,
        inputs,
        ...
      }:
      {
        # gen-flake injects a `perSystem` (to spread `genValues` into per-system args), so flake-parts
        # requires `systems`. The demo produces no per-system outputs; one system suffices.
        systems = [ "x86_64-linux" ];

        imports = [
          inputs.gen-flake.flakeModules.default
          (inputs.import-tree ./modules)
        ];

        # PURE composition of the gen definition tree. gen-flake threads its own
        # gen-merge/gen-schema/gen-aspects into every tree module; the demo adds `lib` (the relocated
        # definitions use nixpkgs `lib.mkOption`/`lib.types`). Passed via `gen.specialArgs` so the pure
        # `evalModuleTree` sees it (it auto-provides only `config`/`options`).
        gen.tree = ./gen-modules;
        gen.specialArgs = {
          inherit lib;
        };

        # READER-side gen LIBRARIES (distinct from the injected VALUES). The `modules/*` readers run
        # the settings cascade + graph/selector/policy/bind demos over the injected `genValues` with
        # these. Injected into the flake's top-level module args alongside gen-flake's `genValues`.
        _module.args = {
          genAspects = inputs.gen-aspects.lib;
          genAlgebra = inputs.gen-algebra.lib;
          genScope = inputs.gen-scope.lib;
          genGraph = inputs.gen-graph.lib;
          genSelect = inputs.gen-select.lib;
          genBind = inputs.gen-bind.lib;
          genDispatch = inputs.gen-dispatch.lib;
        };
      }
    );

  inputs = {
    # gen-flake — the pure composition boundary. Consumed LOCAL (unpublished) via a path pin. It
    # threads the published pure stack (gen-aspects@64c3c25 / gen-schema / gen-merge / …) into the
    # tree, so relocated definition modules receive `{ genAspects, genMerge, ... }` as today.
    gen-flake.url = "github:sini/gen-flake";

    # Reuse the EXACT gen-aspects instance gen-flake threads into the pure tree, so the reader-side
    # `genAspects.flatten` operates on aspect values structurally identical to the injected
    # `genValues.aspects` (and no duplicate fetch). gen-bind rides gen-flake's own pin; gen-algebra
    # rides gen-schema's pin (the record algebra behind the settings cascade).
    gen-aspects.follows = "gen-flake/gen-aspects";
    gen-bind.follows = "gen-flake/gen-bind";
    gen-algebra.follows = "gen-flake/gen-schema/gen-algebra";

    # Reader-only libraries not in gen-flake's closure (they operate on plain values — scope-node id
    # strings, settings attrsets — so they need no structural identity with the tree types).
    gen-scope.url = "github:sini/gen-scope";
    gen-graph.url = "github:sini/gen-graph";
    gen-select.url = "github:sini/gen-select";
    gen-dispatch.url = "github:sini/gen-dispatch";

    # The reader-side tree loader (flake-parts) + its nixpkgs/flake-parts host. Distinct from
    # gen-flake's internal nixpkgs-lib-free import-tree fork (which loads ./gen-modules purely).
    import-tree.url = "github:vic/import-tree";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
}
