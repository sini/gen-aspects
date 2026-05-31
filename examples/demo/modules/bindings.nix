# Module bindings: route the nginx aspect's class content through the
# injectAspectSettings construct (the same per-(host, aspect) unit that powers
# the firewall aspect), proving the construct generalizes across a SECOND aspect.
#
# The nginx config logic now lives in the aspect itself (aspects/web.nix's
# parametric `nixos`), so there is no out-of-band module here — we source the
# class content from the aspect and inject resolved settings via the construct.
{
  config,
  lib,
  genAspects,
  genBind,
  composedSettings,
  injectAspectSettings,
  ...
}:
let
  # The nginx aspect's parametric class content (reads settings.nginx.*).
  # flat keys aspects by FULL PATH — nginx is "services/nginx".
  # `nixos` is a deferredModule option, so the parametric fn arrives coerced to
  # `{ imports = [ <fn> ]; }` — the same imports-form the construct consumes.
  nginxClass = (genAspects.flatten config.aspects)."services/nginx".nixos;

  # Produce the wrapped, settings-injected module via the construct. This is the
  # same path the firewall aspect uses; it returns only `.module`.
  wrappedModule = injectAspectSettings {
    host = "prod-web-1";
    aspectLeaf = "nginx";
    classContent = nginxClass;
  };

  # The construct returns only `.module`, so for the signature/wrapped METADATA
  # we call genBind.wrap / buildSignature directly with the SAME uniform binding
  # shape the construct uses (settings namespaced under the aspect leaf + host).
  # Uniform `settings` arg name — never `nginxSettings`.
  #
  # We sign over the underlying parametric fn (unwrapped from the deferredModule
  # imports-form) so the signature reflects the real `settings`/`host`/`lib`
  # interface; wrapping the imports-attrset directly would erase arg metadata.
  # deferredModule nests the fn under `{ imports = [ { _file; imports = [ fn ]; } ]; }`,
  # so descend `imports` lists until the parametric function surfaces.
  unwrapToFn =
    v:
    if builtins.isFunction v then
      v
    else if builtins.isAttrs v && v ? imports && v.imports != [ ] then
      unwrapToFn (builtins.head v.imports)
    else
      v;
  nginxFn = unwrapToFn nginxClass;

  uniformBindings = {
    settings = {
      nginx = composedSettings.prod-web-1.nginx;
    };
    host = {
      name = "prod-web-1";
    };
  };

  wrappedResult = genBind.wrap {
    module = nginxFn;
    bindings = uniformBindings;
    contracts.settings = genBind.contract.isType "set";
    provenance.settings = {
      source = "scope-settings";
      scope = "host:prod-web-1";
    };
  };

  signature = genBind.buildSignature {
    module = nginxFn;
    bindings = uniformBindings;
    defaultMergeStrategy = genBind.mergeStrategy.bindWins;
    mergeStrategies = { };
    provenance.settings = {
      source = "scope-settings";
      scope = "host:prod-web-1";
    };
  };

  bindResults = {
    wrappedIsWrapped = wrappedResult.wrapped;
    signatureRequires = signature.requires;
    signatureBound = signature.bound;
    advertisedArgs = wrappedResult.advertisedArgs;
    # Sanity: the construct path produces a usable module (consumed downstream
    # via assembledClasses); keep a reference so wrappedModule isn't dead.
    viaConstruct = builtins.isAttrs wrappedModule || builtins.isFunction wrappedModule;
  };

in
{
  config._module.args = {
    inherit bindResults;
  };
}
