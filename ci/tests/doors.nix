# The closed doors' shared checks (den-hoag-7gp66 P1): each takes `prelude.checkOptions` /
# `prelude.checkRequired` rather than native closed formals, which refused a missing or unknown field
# past `tryEval`. Catchability is asserted here; each message is pinned on the real path in
# `ci/tests-error.nix` (`doors`).
{
  aspects,
  ...
}:
let
  # WHNF only: each door forces its check at the call, so the refusal meets the caller there.
  caught = e: (builtins.tryEval e).success;
  fn = { host }: { };
  schema = aspects.mkAspectSchema { };
in
{
  # `wrapGatedFn`'s spec is MIXED: `functionArgs` required, the rest optional, the set closed.
  flake.tests.doors.test-wrap-gated-fn = {
    expr = {
      valid = builtins.isAttrs (aspects.wrapGatedFn { functionArgs.host = false; } fn);
      validWithOptions = builtins.isAttrs (
        aspects.wrapGatedFn {
          functionArgs.host = false;
          name = "n";
          meta = { };
          onResult = x: x;
        } fn
      );
      missingRequiredRefused = !(caught (aspects.wrapGatedFn { name = "n"; }));
      unknownOptionRefused =
        !(caught (
          aspects.wrapGatedFn {
            functionArgs.host = false;
            notAnOption = 1;
          }
        ));
      nonSetRefused = !(caught (aspects.wrapGatedFn 1));
    };
    expected = {
      valid = true;
      validWithOptions = true;
      missingRequiredRefused = true;
      unknownOptionRefused = true;
      nonSetRefused = true;
    };
  };

  # The three options doors `mkAspectSchema` hands back: every field optional, the set closed.
  flake.tests.doors.test-schema-options-doors = {
    expr = {
      optionValid = caught (schema.mkAspectOption { });
      optionWithPrefix = caught (schema.mkAspectOption { providerPrefix = [ "acme" ]; });
      optionUnknownRefused = !(caught (schema.mkAspectOption { notAnOption = 1; }));
      moduleValid = builtins.isFunction (schema.mkAspectModule { });
      moduleUnknownRefused = !(caught (schema.mkAspectModule { notAnOption = 1; }));
      namespaceValid = caught (schema.mkNamespaceType { });
      namespaceUnknownRefused = !(caught (schema.mkNamespaceType { notAnOption = 1; }));
    };
    expected = {
      optionValid = true;
      optionWithPrefix = true;
      optionUnknownRefused = true;
      moduleValid = true;
      moduleUnknownRefused = true;
      namespaceValid = true;
      namespaceUnknownRefused = true;
    };
  };
}
