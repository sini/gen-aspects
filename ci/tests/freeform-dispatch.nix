# Test: freeform key dispatch — primitives pass through, nested aspects get identity,
# registered classes get deferredModule.
{ lib, mkSchemaEval }:
{
  test-primitive-string-passthrough =
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

  test-primitive-list-passthrough =
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

  test-deep-nesting-identity =
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

  test-deep-nesting-class-clean =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.infra.networking.dns.classOne.nameservers = [ "1.1.1.1" ]; }
        ];
      };
      classEval = lib.evalModules {
        modules = [
          {
            options.nameservers = lib.mkOption { type = lib.types.listOf lib.types.str; };
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

  test-meta-is-freeform =
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
