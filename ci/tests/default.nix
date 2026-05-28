{ lib, aspects }:
let
  # Standard class set for most tests
  defaultClasses = {
    classOne = { };
    classTwo = { };
  };

  mkSchemaEval =
    {
      classes ? defaultClasses,
      collections ? { },
      aspectModules ? [ ],
      metaModules ? [ ],
      modules,
    }:
    let
      schema = aspects.mkAspectSchema {
        inherit
          classes
          collections
          aspectModules
          metaModules
          ;
      };
    in
    lib.evalModules {
      modules = [
        { options.schema = schema.schemaOption; }
        (schema.mkAspectModule { })
      ]
      ++ modules;
    };
in
{
  # Class content is clean — no structural keys
  class-content = import ./class-content.nix { inherit lib mkSchemaEval; };

  # Nested aspects get full identity treatment
  nested-aspects = import ./nested-aspects.nix { inherit lib mkSchemaEval; };

  # Includes and diamond dedup
  includes = import ./includes.nix { inherit lib mkSchemaEval; };

  # Module functions vs guard functions
  parametric = import ./parametric.nix { inherit lib mkSchemaEval; };

  # Identity
  identity = import ./identity.nix { inherit lib aspects mkSchemaEval; };

  # canTake introspection
  can-take = import ./can-take.nix { inherit lib aspects; };

  # Pipeline extensions via cnf.aspectModules
  extensions = import ./extensions.nix { inherit lib mkSchemaEval; };

  # Guard function identity and provenance
  guard-identity = import ./guard-identity.nix { inherit lib aspects mkSchemaEval; };

  # Multi-definition merging
  multi-def = import ./multi-def.nix { inherit lib mkSchemaEval; };

  # Freeform dispatch: primitives, nesting, provenance
  freeform-dispatch = import ./freeform-dispatch.nix { inherit lib mkSchemaEval; };

  # Extensible meta submodule via cnf.metaModules
  meta-modules = import ./meta-modules.nix { inherit lib mkSchemaEval; };

  # Schema integration tests
  schema-integration = import ./schema-integration.nix { inherit lib aspects mkSchemaEval; };

  # Flat registry
  flat-registry = import ./flat-registry.nix { inherit lib mkSchemaEval aspects; };
}
