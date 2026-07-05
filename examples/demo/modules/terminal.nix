# The nixos-class TERMINAL — realize's `bindings` hook replaces the old reader terminal.
#
# v0's mkSystems `wrapAll` bound only `{ host = <instance> }`, so this demo hand-rolled a per-(host,
# aspect) `genBind.wrap` in modules/injection.nix and rendered each aspect through a stub `evalModules`
# in outputs.nix — a "reader terminal". v1's `realize` takes a first-class `bindings` hook, so the
# reader-computed settings cascade (composition.nix's `composedSettings`) is passed as a per-host
# binding and the terminal itself does the wrapping.
#
# The terminal here is a DATA terminal (the design's "pure attrset builder — no nixpkgs", contrast the
# shipped `terminals.nixosSystem`): it wraps a host's class deferredModules with the merged bindings
# (`genBind.wrapAll`) and renders them through a bare `lib.evalModules` over stub options, so the demo
# asserts exact resolved values without a full NixOS eval. `realize` folds it per host into
# `realized.nixos.<host> = <config>` — each host's firewall (+ nginx, on web/all hosts) COMPOSED into
# one config. The intentional v1 delta vs the reader terminal: a host's system is all its aspects
# merged, so `networking.firewall.allowedTCPPorts` unions the firewall cascade with nginx's public port.
#
# READER side (gen-flake value-injection): consumes `genComposed` (the compose result; `.hosts` is the
# per-host build projection) + the reader-computed `composedSettings`, both threaded via _module.args.
{
  lib,
  genFlake,
  genComposed,
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

  # The DATA terminal: wrap the host's class deferredModules with the merged bindings, render through
  # evalModules over the stub options, return the resolved `config`. `realize` calls this with `modules`
  # (the host's class deferredModules, unwrapped) + `bindings` (the merged binding set); the terminal
  # owns the `wrapAll` step, exactly as `terminals.nixosSystem` does.
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

  # The per-host bindings hook: the reader-computed settings cascade becomes a first-class binding.
  # `realize` merges compose's `{ host = <instance> }` under this per-host refinement, so each aspect's
  # class fn receives `settings = composedSettings.<host>` (ALL aspect leaves; a fn reads only its own —
  # the firewall fn reads `settings.firewall.*`, nginx reads `settings.nginx.*`). This is the retro-fix
  # for the old reader terminal, which could not push settings through mkSystems.
  bindings = lib.mapAttrs (host: _: {
    settings = composedSettings.${host};
    host = {
      name = host;
    }
    // (genValues.fleet.hosts.${host} or { });
  }) genValues.fleet.hosts;

  realized = genFlake.realize {
    composed = genComposed;
    terminals.nixos = dataTerminal;
    inherit bindings;
  };
in
{
  config._module.args = { inherit realized; };
}
