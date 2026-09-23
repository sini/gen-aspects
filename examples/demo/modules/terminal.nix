# The nixos-class TERMINAL — realize's per-thimble contribution layer replaces the old reader terminal.
#
# v0's mkSystems `wrapAll` bound only the resolved node instance, so this demo hand-rolled a per-(thimble,
# aspect) `genBind.wrap` in modules/injection.nix and rendered each aspect through a stub `evalModules`
# in outputs.nix — a "reader terminal". gen-delivery's `realize` takes a first-class `refinements`
# layer (the per-node contribution layer of its declared layer order), so the reader-computed settings
# cascade (composition.nix's `composedSettings`) is passed as a per-thimble refinement and the terminal
# itself does the wrapping.
#
# The terminal here is a DATA terminal (the design's "pure attrset builder — no nixpkgs", contrast the
# shipped nixosSystem terminal): it wraps a thimble's class deferredModules with the merged bindings
# (`genBind.wrapAll`) and renders them through a bare `lib.evalModules` over stub options, so the demo
# asserts exact resolved values without a full NixOS eval. `realize` folds it per thimble into
# `realized.nixos.<thimble> = <config>` — each thimble's firewall (+ nginx, on web/all thimbles) COMPOSED into
# one config. The intentional delta vs the reader terminal: a thimble's system is all its aspects
# merged, so `networking.firewall.allowedTCPPorts` unions the firewall cascade with nginx's public port.
#
# READER side (value-injection): consumes `genProjected` (gen-delivery's `project` result — the
# per-thimble build projection) + `genDelivery` (the constructed realization surface) + the
# reader-computed `composedSettings`, all threaded via _module.args in flake.nix.
{
  lib,
  genDelivery,
  genProjected,
  genBind,
  composedSettings,
  genValues,
  ...
}:
let
  # Stub options for the parametric aspects' nixos class content (firewall + nginx). A bare evalModules
  # has no `networking`/`services` options and would throw; these mirror the NixOS option names the
  # aspect modules set (kebab schema keys map to camelCase here). `warnings`/`assertions` are declared
  # too because `genBind.wrapAll`'s `.all` appends collision-validator modules that emit them (nixpkgs
  # supplies these in a real `nixosSystem`; a bare evalModules must stub them).
  stubOptions =
    { lib, ... }:
    {
      options.warnings = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      options.assertions = lib.mkOption {
        type = lib.types.listOf lib.types.unspecified;
        default = [ ];
      };
      options.networking.firewall.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      options.networking.firewall.allowedTCPPorts = lib.mkOption {
        type = lib.types.listOf lib.types.int;
        default = [ ];
      };
      options.networking.firewall.allowedUDPPorts = lib.mkOption {
        type = lib.types.listOf lib.types.int;
        default = [ ];
      };
      options.networking.firewall.logRefusedConnections = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      options.services.nginx.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      options.services.nginx.config = lib.mkOption {
        type = lib.types.lines;
        default = "";
      };
    };

  # The DATA terminal: wrap the thimble's class deferredModules with the merged bindings, render through
  # evalModules over the stub options, return the resolved `config`. `realize` calls this with `modules`
  # (the thimble's class deferredModules, unwrapped) + `bindings` (the layers folded in declared order);
  # the terminal owns the `wrapAll` step — the terminal contract puts the wrapping on the target side.
  dataTerminal =
    {
      modules,
      bindings,
      extraModules,
      ...
    }:
    (lib.evalModules {
      modules = [ stubOptions ] ++ (genBind.wrapAll { inherit modules bindings; }).all ++ extraModules;
    }).config;

  # The per-thimble contribution layer (gen-delivery's `refinements`): the reader-computed settings
  # cascade becomes a first-class binding. `realize` folds the projection's `{ node = <instance> }`
  # under this per-thimble refinement (the declared layer order: projection < global < refinement), so
  # each aspect's class fn receives `settings = composedSettings.<thimble>` (ALL aspect leaves; a fn
  # reads only its own — the firewall fn reads `settings.firewall.*`, nginx reads `settings.nginx.*`)
  # and the enriched `thimble` binding. This is the retro-fix for the old reader terminal, which could
  # not push settings through mkSystems.
  refinements = lib.mapAttrs (thimble: _: {
    settings = composedSettings.${thimble};
    thimble = {
      name = thimble;
    }
    // (genValues.haberdashery.thimbles.${thimble} or { });
  }) genValues.haberdashery.thimbles;

  realized = genDelivery.realize {
    projected = genProjected;
    terminals.nixos = dataTerminal;
    inherit refinements;
  };
in
{
  config._module.args = { inherit realized; };
}
