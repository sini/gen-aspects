{ lib, aspects }:
let
  inherit (aspects) aspectsType;

  # Helper: create an evaluation with registered classes
  mkEval =
    { classes, modules }:
    lib.evalModules {
      modules = [
        {
          options.aspects = lib.mkOption {
            type = aspectsType { inherit classes; };
            default = { };
          };
        }
      ]
      ++ modules;
    };

  # Standard class set for most tests
  defaultClasses = {
    classOne = { };
    classTwo = { };
  };

  mkDefaultEval =
    modules:
    mkEval {
      classes = defaultClasses;
      inherit modules;
    };
in
{
  # Class content is clean — no structural keys
  class-content = import ./class-content.nix { inherit lib mkDefaultEval; };

  # Nested aspects get full identity treatment
  nested-aspects = import ./nested-aspects.nix { inherit lib mkDefaultEval; };

  # Includes and diamond dedup
  includes = import ./includes.nix { inherit lib mkDefaultEval; };

  # Module functions vs guard functions
  parametric = import ./parametric.nix { inherit lib mkDefaultEval; };

  # Identity
  identity = import ./identity.nix { inherit lib aspects mkDefaultEval; };

  # canTake introspection
  can-take = import ./can-take.nix { inherit lib aspects; };

  # Pipeline extensions via cnf.aspectModules
  extensions = import ./extensions.nix { inherit lib aspects; };

  # Guard function identity and provenance
  guard-identity = import ./guard-identity.nix { inherit lib aspects mkDefaultEval; };

  # Multi-definition merging
  multi-def = import ./multi-def.nix { inherit lib mkDefaultEval; };

  # Freeform dispatch: primitives, nesting, provenance
  freeform-dispatch = import ./freeform-dispatch.nix { inherit lib mkDefaultEval; };

  # Extensible meta submodule via cnf.metaModules
  meta-modules = import ./meta-modules.nix { inherit lib aspects; };
}
