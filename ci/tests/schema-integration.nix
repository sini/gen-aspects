# Schema integration: verify gen-schema's kind-level infrastructure
# works with aspectType via mkType delegation.
{
  genMerge,
  lib,
  aspects,
  mkSchemaEval,
  ...
}:
let
  eval = mkSchemaEval {
    classes = {
      classOne = { };
      classTwo = { };
    };
    collections = {
      settings = {
        default = { };
      };
      tags = {
        default = [ ];
      };
    };
    modules = [
      # Extend aspect kind with a custom field
      (
        { ... }:
        {
          config.schema.aspect.options.priority = genMerge.mkOption {
            type = genMerge.types.int;
            default = 50;
          };
        }
      )
      (
        { ... }:
        {
          # Aspects defined on the schema kind entry directly
          config.schema.aspect = {
            classOne.networking.hostName = "test";
            tags = [ "infra" ];
            settings.port = {
              default = 80;
            };
          };
          # Set priority on networking to verify schema extension propagates to
          # config.aspects.* entries via mkAspectModule. desktop uses the default.
          config.aspects.networking.priority = 10;
          config.aspects.desktop = { };
        }
      )
    ];
  };

  # Separate eval to test class content on standalone aspects
  classEval = mkSchemaEval {
    classes = {
      classOne = { };
      classTwo = { };
    };
    modules = [
      (
        { ... }:
        {
          config.aspects.myAspect = {
            classOne.networking.hostName = "test";
          };
        }
      )
    ];
  };

in
{
  # Introspection reports kind names
  flake.tests.schema-integration.test-introspection-kind-names = {
    expr = eval.config.schema._kindNames;
    expected = [ "aspect" ];
  };

  # Collection data is extracted onto schema kind
  flake.tests.schema-integration.test-collection-tags = {
    expr = eval.config.schema.aspect.tags;
    expected = [ "infra" ];
  };

  # Collection settings merge as attrsets
  flake.tests.schema-integration.test-collection-settings = {
    expr = eval.config.schema.aspect.settings;
    expected = {
      port = {
        default = 80;
      };
    };
  };

  # Standalone aspects preserve class content (deferredModule with imports)
  flake.tests.schema-integration.test-standalone-class-content = {
    expr =
      let
        classVal = classEval.config.aspects.myAspect.classOne;
        classResult = genMerge.evalModuleTree {
          modules = [
            { options.networking.hostName = genMerge.mkOption { type = genMerge.types.str; }; }
            classVal
          ];
        };
      in
      classResult.config.networking.hostName;
    expected = "test";
  };

  # mkAspectSchema produces a valid schemaOption
  flake.tests.schema-integration.test-schema-option-type = {
    expr = eval.config.schema ? _kindNames;
    expected = true;
  };

  # mkAspectSchema re-exports identity functions
  flake.tests.schema-integration.test-reexport-key = {
    expr =
      let
        schema = aspects.mkAspectSchema {
          classes = {
            classOne = { };
          };
        };
      in
      schema ? key;
    expected = true;
  };

  flake.tests.schema-integration.test-reexport-aspect-path = {
    expr =
      let
        schema = aspects.mkAspectSchema {
          classes = {
            classOne = { };
          };
        };
      in
      schema ? aspectPath;
    expected = true;
  };

  flake.tests.schema-integration.test-defsmodule-present = {
    expr = eval.config.schema.aspect ? __defsModule;
    expected = true;
  };

  # Schema extension fields are readable on actual aspect instances
  flake.tests.schema-integration.test-schema-extension-on-instance = {
    expr = eval.config.aspects.networking.priority;
    expected = 10;
  };

  flake.tests.schema-integration.test-schema-extension-default-on-instance = {
    expr = eval.config.aspects.desktop.priority;
    expected = 50;
  };
}
