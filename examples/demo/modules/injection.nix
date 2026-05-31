# Per-(host, aspect) resolved-settings -> class-content injection.
# Generalizes bindings.nix's manual gen-bind wiring into a first-class construct.
# Promotion target (later, out of scope): gen-aspects.lib.injectAspectSettings / assembleHost.
{
  config,
  lib,
  genAspects,
  genBind,
  composedSettings,
  ...
}:
let
  flat = genAspects.flatten config.aspects;
  # MUST match composition.nix's leafName — the injected `settings.<leaf>` key has
  # to line up with the cascade's composedSettings.<host>.<leaf> namespace.
  leafName = path: lib.last (lib.splitString "/" path);
  hostNames = builtins.attrNames config.fleet.hosts;

  # The per-(host, aspect) unit: thin glue over genBind.wrap.
  # classContent comes from a deferredModule option, so BOTH a parametric fn and a
  # static attrset arrive coerced to { imports = [ ... ]; }. We therefore do NOT
  # guard on isFunction (the top-level value is never a bare function): wrapCore's
  # wrapImportsModule recurses per-import — a parametric fn import gets settings/host
  # bound, a static attrset import passes through (wrapped=false). settings is a
  # plain attrset -> no thunk needed.
  injectAspectSettings =
    {
      host,
      aspectLeaf,
      classContent,
    }:
    (genBind.wrap {
      module = classContent;
      bindings = {
        settings = {
          ${aspectLeaf} = composedSettings.${host}.${aspectLeaf} or { };
        };
        host = {
          name = host;
        }
        // (config.fleet.hosts.${host} or { });
      };
      contracts.settings = genBind.contract.isType "set";
      provenance.settings = {
        source = "scope-settings";
        scope = "host:${host}";
      };
    }).module;

  # Bulk per-host driver: wrap every aspect's class content (always; static
  # content passes through wrapped=false). Aspects with no `nixos` wrap `{}` — a
  # benign empty-module no-op; a library form would filterAttrs these out.
  assembleHostAspects =
    host:
    lib.mapAttrs' (
      path: aspect:
      lib.nameValuePair (leafName path) (injectAspectSettings {
        inherit host;
        aspectLeaf = leafName path;
        classContent = aspect.nixos or { };
      })
    ) flat;

  assembledClasses = lib.genAttrs hostNames assembleHostAspects;
in
{
  config._module.args = { inherit injectAspectSettings assembledClasses; };
}
