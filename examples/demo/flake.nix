{
  description = "gen-aspects demo: aspect-oriented web deployment via gen-flake value-injection";

  # Value-injection migration (gen-flake v1). The gen definition tree (./gen-modules — aspect schema +
  # aspect/fleet/namespace/scopeSettings definitions) is composed PURELY via gen-merge's byte-mode
  # `evalModuleTree` (NOT flake-parts' nixpkgs `lib.evalModules`). The resolved config VALUES are
  # injected as the `genValues` module arg; NO gen TYPE enters the flake-parts options tree (the old
  # `options.schema`/`options.aspects`/`options.namespaces` embeds made flake-parts walk a gen type via
  # `substSubModules`/`getSubOptions` and throw under the pure re-host). The `modules/*` READERS render
  # over `genValues`.
  #
  # DIRECT compose/realize (not `flakeModules.default`). The other demos consume the flakeModule for
  # its one-line ergonomics, but this demo drives gen-flake's lower-level API directly, because it needs
  # two v1 knobs the flakeModule does not surface:
  #   * `compose { selectHosts; }` — the fleet lives under `fleet.hosts`, not the top-level `hosts` the
  #     default projection reads, and compose's `projectHosts` needs each host tagged with the aspects
  #     it runs (the fleet schema carries only env/role, so membership is synthesized in `selectHosts`).
  #   * `realize { bindings; }` — the TERMINAL. v0's mkSystems `wrapAll` bound only `{ host }`, so the
  #     reader-computed per-(host, aspect) settings cascade had to be hand-wrapped in a "reader
  #     terminal". v1's `realize` takes a first-class `bindings` hook, so that cascade is now a per-host
  #     binding and the terminal (`modules/terminal.nix`, a pure DATA terminal) does the wrapping.
  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } (
      {
        lib,
        inputs,
        ...
      }:
      let
        genFlake = inputs.gen-flake.lib;

        # The ONE pure compose of the gen definition tree (gen-merge's byte-mode `evalModuleTree`; NO
        # nixpkgs). `specialArgs.lib` is the extra arg the relocated definitions reach for (their kind
        # definitions use nixpkgs `lib.mkOption`/`lib.types`); gen-flake threads genMerge/genSchema/
        # genAspects itself.
        composed = genFlake.compose {
          tree = ./gen-modules;
          specialArgs = { inherit lib; };
          # Project the `fleet.hosts` registry, tagging each host with the aspects its role runs.
          # `projectHosts` reads `inst.aspects` to gather each class's deferredModules; web/all hosts run
          # the firewall + nginx parametric aspects, database hosts run firewall only.
          selectHosts =
            values:
            lib.mapAttrs (
              _name: host:
              host
              // {
                aspects =
                  if host.role == "database" then
                    [ "firewall" ]
                  else
                    [
                      "firewall"
                      "services/nginx"
                    ];
              }
            ) values.fleet.hosts;
        };
      in
      {
        imports = [
          (inputs.import-tree ./modules)
        ];

        # QUERY surface — inject the resolved VALUES as `genValues` (what `injectArgs` /
        # `flakeModules.default` would do), plus the compose result (`genComposed`, whose `.hosts` is the
        # per-host build projection) and the constructed gen-flake lib (`genFlake`, for `realize`) the
        # terminal reader folds. The reader-side gen LIBRARIES are the rendering tools the `modules/*`
        # readers run over `genValues` (distinct from the injected VALUES).
        _module.args = {
          genValues = composed.values;
          genComposed = composed;
          inherit genFlake;

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
    # gen-flake — the pure composition boundary (v1). Pinned via its published github rev. It threads
    # the published pure stack (gen-aspects / gen-schema / gen-merge / …) into the tree, so relocated
    # definition modules receive `{ genAspects, genMerge, ... }` as today.
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
