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
    fixtureKeySemantics = {
      classOne = {
        category = "class";
      };
      classTwo = {
        category = "class";
      };
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
    fixtureKeySemantics = {
      classOne = {
        category = "class";
      };
      classTwo = {
        category = "class";
      };
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

  # den-hoag-ndwvn: the priority an aspect reads when the kind entry carries `defs` beside a declared
  # `options.priority` (default 0).
  priorityOf =
    defs:
    (mkSchemaEval {
      modules = [
        {
          config.schema.aspect.options.priority = genMerge.mkOption {
            type = genMerge.types.int;
            default = 0;
          };
        }
      ]
      ++ map (d: { config.schema.aspect = d; }) defs
      ++ [ { config.aspects.x = { }; } ];
    }).config.aspects.x.priority;
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
        classResult = genMerge.evalModuleTree { } [
          { options.networking.hostName = genMerge.mkOption { type = genMerge.types.str; }; }
          classVal
        ];
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
          keySemantics = {
            classOne = {
              category = "class";
            };
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
          keySemantics = {
            classOne = {
              category = "class";
            };
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

  # den-hoag-ndwvn (ADR-0025 item 1): a kind entry def that is a function or a path is a MODULE, as
  # gen-schema's default branch and nixpkgs' submodule type treat it, and its content lands. RED
  # (measured at gen-aspects 9827a96): both read the declared default, `0`, with no message.
  flake.tests.schema-integration.test-kind-entry-function-def-lands = {
    expr = priorityOf [ ({ ... }: { priority = 7; }) ];
    expected = 7;
  };
  flake.tests.schema-integration.test-kind-entry-module-function-def-lands = {
    expr = priorityOf [ ({ ... }: { config.priority = 7; }) ];
    expected = 7;
  };
  flake.tests.schema-integration.test-kind-entry-path-def-lands = {
    expr = priorityOf [ ../fixtures/kind-entry-priority.nix ];
    expected = 7;
  };
  # controls, same fixture: an attrset def lands, and no def reads the default.
  flake.tests.schema-integration.test-kind-entry-attrset-def-lands = {
    expr = priorityOf [ { priority = 7; } ];
    expected = 7;
  };
  flake.tests.schema-integration.test-kind-entry-no-def-reads-default = {
    expr = priorityOf [ ];
    expected = 0;
  };
}
