# Module bindings METADATA probe: sign the nginx aspect's parametric class content with gen-bind, to
# surface signature/wrapped introspection (the `bindResults` output). The end-to-end settings injection
# itself runs through realize's `bindings` hook (modules/terminal.nix); this module only exercises
# gen-bind's `buildSignature`/`wrap` on the same binding SHAPE, so the demo can assert what a binding
# advertises without going through the terminal.
#
# READER side (value-injection): the aspect class content comes from the injected
# `genValues.aspects` (the gen tree's resolved config), not a flake-parts `config.aspects` option tree.
{
  lib,
  genValues,
  genAspects,
  genBind,
  composedSettings,
  ...
}:
let
  # The nginx aspect's parametric class content (reads settings.nginx.*).
  # flat keys aspects by FULL PATH — nginx is "services/nginx".
  # `nixos` is a deferredModule option, so the parametric fn arrives coerced to
  # `{ imports = [ <fn> ]; }` — the same imports-form the construct consumes.
  nginxClass = (genAspects.flatten genValues.aspects)."services/nginx".nixos;

  # Demo-only metadata path: this exists ONLY to surface signature/wrapped info in
  # the bindResults verification output. The real injection runs through realize's
  # bindings hook (modules/terminal.nix → `realized`, asserted in outputs.nix) — do
  # NOT fold this metadata probe into that path.
  #
  # For the signature/wrapped METADATA we call genBind.wrap / buildSignature
  # directly with the SAME uniform binding shape the terminal uses (settings
  # namespaced under the aspect leaf + host). Uniform `settings` arg name — never
  # `nginxSettings`.
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

  # Mirrors the construct's binding shape; `host` omits the construct's fleet-host
  # enrichment (`// genValues.fleet.hosts.<h>`) — fine here since the signature only
  # reads arg presence, not host fields.
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
  };

in
{
  config._module.args = {
    inherit bindResults;
  };
}
