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
      ] ++ modules;
    };

  # Standard class set for most tests
  defaultClasses = {
    classOne = { };
    classTwo = { };
  };

  mkDefaultEval = modules: mkEval { classes = defaultClasses; inherit modules; };
in
{
  # Class content is clean — no structural keys
  class-content = import ./class-content.nix { inherit lib mkDefaultEval; };

  # Nested aspects get full identity treatment
  nested-aspects = import ./nested-aspects.nix { inherit lib mkDefaultEval; };

  # Includes and diamond dedup
  includes = import ./includes.nix { inherit lib mkDefaultEval; };

  # Provides namespace
  provides = import ./provides.nix { inherit lib mkDefaultEval; };

  # Parametric aspects (function defs)
  parametric = import ./parametric.nix { inherit lib mkDefaultEval; };

  # Identity
  identity = import ./identity.nix { inherit lib aspects mkDefaultEval; };
}
