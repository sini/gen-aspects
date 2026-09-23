{
  description = "gen-aspects demo: aspect-oriented web deployment via the gen hub's successor compose (value-injection)";

  # Value-injection over the SUCCESSOR COMPOSE (`gen.lib.compose`, the hub's S2 core — formerly
  # gen-flake v1, dissolving under ADR-0031). The gen definition tree (./gen-modules — aspect schema +
  # aspect/haberdashery/namespace/scopeSettings definitions) is composed PURELY via gen-merge's byte-mode
  # `evalModuleTree` (NOT flake-parts' nixpkgs `lib.evalModules`). The resolved config VALUES are
  # injected as the `genValues` module arg; NO gen TYPE enters the flake-parts options tree (the old
  # `options.schema`/`options.aspects`/`options.namespaces` embeds made flake-parts walk a gen type via
  # `substSubModules`/`getSubOptions` and throw once moved onto the pure evaluator). The `modules/*` READERS render
  # over `genValues`.
  #
  # DIRECT compose/project/realize (not `gen.flakeModules.default`). The other demos consume the hub
  # flakeModule for its one-line ergonomics, but this demo drives the lower-level surfaces directly,
  # because it needs two knobs the flakeModule does not surface:
  #   * `project { selectNodes; }` (gen-delivery) — the node selector, required and without a default:
  #     it names `haberdashery.thimbles` as the node registry, and the projection needs each thimble
  #     tagged with the aspects it runs (the thimble kind carries only env/role, so membership is
  #     synthesized in `selectNodes`).
  #   * `realize { refinements; }` (gen-delivery) — the TERMINAL. The reader-computed per-(thimble,
  #     aspect) settings cascade is a per-thimble contribution layer, and the terminal
  #     (`modules/terminal.nix`, a pure DATA terminal) does the wrapping.
  #
  # The successor compose takes `specialArgs` CALLER-TOTAL (it binds no constructor vocabulary), so
  # the two acts gen-flake's compose performed internally are this caller's own wiring now: the
  # CONSTRUCTOR MERGE (`genLibs // { inherit lib; }` below) and TREE LOADING (the import-tree fork's
  # bare path list; the fork's pin lives at the hub root).
  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } (
      {
        lib,
        inputs,
        ...
      }:
      let
        # The hub roster: every gen library at the hub's pins, constructed once. `delivery` arrives
        # CONSTRUCTED (its algebra + aspects injected from the same roster), so the projection below
        # and the tree's constructor set share one gen-aspects instance by construction.
        roster = inputs.gen.lib.mkGenLibs { inherit lib; };

        # The constructor set a hub-fronted gen tree receives (the F1 constructor merge, performed by
        # the caller because the successor compose is caller-total). `lib` is the extra arg the
        # relocated definitions reach for (their kind definitions use nixpkgs `lib.mkOption`/
        # `lib.types`).
        genLibs = {
          genMerge = roster.merge;
          genSchema = roster.schema;
          genAspects = roster.aspects;
          genTypes = roster.types;
          genPrelude = roster.prelude;
        };

        # The ONE pure compose of the gen definition tree (gen-merge's byte-mode `evalModuleTree`; NO
        # nixpkgs).
        composed = inputs.gen.lib.compose {
          modules = (inputs.gen.inputs.import-tree.addPath ./gen-modules).files;
          specialArgs = genLibs // {
            inherit lib;
          };
        };

        # The per-thimble build projection (gen-delivery `project` — the successor compose deliberately
        # does not project thimbles). `cnf` is the demo's own mkAspectSchema argument
        # (./gen-modules/_aspect-cnf.nix): the key-category DECLARATION the realization predicate
        # reads — a delivery class realizes on DECLARED content, never on structural shape.
        # `selectNodes` projects the `haberdashery.thimbles` registry, tagging each thimble with the aspects its
        # role runs; web/all thimbles run the firewall + nginx parametric aspects, database thimbles run
        # firewall only.
        projected = roster.delivery.project {
          values = composed.values;
          cnf = import ./gen-modules/_aspect-cnf.nix { inherit lib; };
          selectNodes =
            values:
            lib.mapAttrs (
              _name: thimble:
              thimble
              // {
                aspects =
                  if thimble.role == "database" then
                    [ "firewall" ]
                  else
                    [
                      "firewall"
                      "services/nginx"
                    ];
              }
            ) values.haberdashery.thimbles;
        };
      in
      {
        imports = [
          (inputs.import-tree ./modules)
        ];

        # QUERY surface — inject the resolved VALUES as `genValues` (what the hub flakeModule's
        # inject would do), plus the compose result (`genComposed`, carrying the `.override` handle
        # the trace showcase drives), the per-thimble build projection (`genProjected`) and the
        # constructed delivery surface (`genDelivery`, for `realize`) the terminal reader folds. The
        # reader-side gen LIBRARIES come off the same roster — the rendering tools the `modules/*`
        # readers run over `genValues` (distinct from the injected VALUES).
        _module.args = {
          genValues = composed.values;
          genComposed = composed;
          genProjected = projected;
          genDelivery = roster.delivery;

          genAspects = roster.aspects;
          genAlgebra = roster.algebra;
          genScope = roster.scope;
          genGraph = roster.graph;
          genSelect = roster.select;
          genBind = roster.bind;
          genDispatch = roster.dispatch;
        };
      }
    );

  inputs = {
    # The hub — the single sanctioned gen input (ADR-0031 F1). It carries the successor compose
    # (`gen.lib.compose`), the roster (`gen.lib.mkGenLibs` — every gen library at the hub's pins,
    # including the CONSTRUCTED gen-delivery), and the import-tree FORK pin
    # (`inputs.gen.inputs.import-tree`, nixpkgs-lib-free) the tree load uses.
    gen.url = "github:sini/gen";

    # The reader-side tree loader (flake-parts) + the nixpkgs/flake-parts it runs on. Distinct from the
    # hub's import-tree fork (which loads ./gen-modules purely).
    import-tree.url = "github:vic/import-tree";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
}
