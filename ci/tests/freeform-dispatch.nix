# Test: freeform key dispatch — primitives pass through, nested aspects get identity,
# registered classes get deferredModule.
{
  genMerge,
  lib,
  mkSchemaEval,
  ...
}:
{
  flake.tests.freeform-dispatch.test-primitive-string-passthrough =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.foo.tag = "production"; }
        ];
      };
    in
    {
      # Unregistered freeform key with string value → primitive passthrough
      expr = eval.config.aspects.foo.tag;
      expected = "production";
    };

  flake.tests.freeform-dispatch.test-primitive-list-passthrough =
    let
      eval = mkSchemaEval {
        modules = [
          {
            config.aspects.foo.tags = [
              "web"
              "prod"
            ];
          }
        ];
      };
    in
    {
      expr = eval.config.aspects.foo.tags;
      expected = [
        "web"
        "prod"
      ];
    };

  flake.tests.freeform-dispatch.test-deep-nesting-identity =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.infra.networking.dns.classOne = { }; }
        ];
      };
    in
    {
      expr = {
        infraName = eval.config.aspects.infra.name;
        netName = eval.config.aspects.infra.networking.name;
        dnsName = eval.config.aspects.infra.networking.dns.name;
      };
      expected = {
        infraName = "infra";
        netName = "networking";
        dnsName = "dns";
      };
    };

  flake.tests.freeform-dispatch.test-deep-nesting-class-clean =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.infra.networking.dns.classOne.nameservers = [ "1.1.1.1" ]; }
        ];
      };
      classEval = genMerge.evalModuleTree {
        modules = [
          {
            options.nameservers = genMerge.mkOption { type = genMerge.types.listOf genMerge.types.str; };
          }
          eval.config.aspects.infra.networking.dns.classOne
        ];
      };
    in
    {
      # Class content clean at 3 levels deep — no structural keys
      expr = classEval.config.nameservers;
      expected = [ "1.1.1.1" ];
    };

  flake.tests.freeform-dispatch.test-meta-is-freeform =
    let
      eval = mkSchemaEval {
        modules = [
          {
            config.aspects.parent = {
              meta.custom = "hello";
              classOne = { };
            };
          }
        ];
      };
    in
    {
      # meta is a freeform submodule — user fields preserved
      expr = eval.config.aspects.parent.meta.custom;
      expected = "hello";
    };
}
