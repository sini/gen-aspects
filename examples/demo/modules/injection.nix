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
  leafName = path: lib.last (lib.splitString "/" path);
  hostNames = builtins.attrNames config.fleet.hosts;

  # The per-(host, aspect) unit: thin glue over genBind.wrap.
  # classContent is the deferredModule-coerced value ({ imports = [fn]; } for a
  # parametric aspect, or a plain attrset for a static one). We do NOT guard on
  # isFunction — wrapCore dispatches; static attrset content passes through
  # unchanged (wrapped=false). settings is a plain attrset -> no thunk needed.
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
  # content passes through with wrapped=false).
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
