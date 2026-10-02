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
  schema = aspects.mkAspectSchema { };
in
{
  # The three options doors `mkAspectSchema` hands back, each set closed: every field optional except
  # `mkNamespaceType`'s `config` (den-hoag-nwshf G1: a namespace reads the enclosing kind).
  flake.tests.doors.test-schema-options-doors = {
    expr = {
      optionValid = caught (schema.mkAspectOption { });
      optionWithPrefix = caught (schema.mkAspectOption { providerPrefix = [ "acme" ]; });
      optionUnknownRefused = !(caught (schema.mkAspectOption { notAnOption = 1; }));
      moduleValid = builtins.isFunction (schema.mkAspectModule { });
      moduleUnknownRefused = !(caught (schema.mkAspectModule { notAnOption = 1; }));
      namespaceValid = caught (schema.mkNamespaceType { config = { }; });
      namespaceConfigRequired = !(caught (schema.mkNamespaceType { }));
      namespaceUnknownRefused =
        !(caught (
          schema.mkNamespaceType {
            config = { };
            notAnOption = 1;
          }
        ));
    };
    expected = {
      optionValid = true;
      optionWithPrefix = true;
      optionUnknownRefused = true;
      moduleValid = true;
      moduleUnknownRefused = true;
      namespaceValid = true;
      namespaceConfigRequired = true;
      namespaceUnknownRefused = true;
    };
  };
}
