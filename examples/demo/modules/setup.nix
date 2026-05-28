# Instantiate all 8 gen libraries and wire up the aspect schema.
{
  lib,
  inputs,
  config,
  ...
}:
let
  genAlgebra = inputs.gen-algebra { inherit lib; };
  genSchema = inputs.gen-schema.lib;
  genAspects = inputs.gen-aspects { inherit lib; };
  genScope = inputs.gen-scope { inherit lib; };
  genGraph = inputs.gen-graph { inherit lib; };
  genSelect = inputs.gen-select.lib;
  genBind = inputs.gen-bind.lib;
  genDerive = inputs.gen-derive.lib;

  aspectSchema = genAspects.mkAspectSchema {
    classes = {
      nixos = { };
    };
    collections = {
      settings = {
        default = { };
      };
      tags = {
        default = [ ];
      };
    };
    # Declare `settings` as a typed option so it doesn't fall through to
    # freeform (which would treat each settings leaf as a nested aspect).
    # This is the gen-schema replacement for den.reservedKeys.
    aspectModules = [
      {
        options.settings = lib.mkOption {
          type = lib.types.lazyAttrsOf lib.types.raw;
          default = { };
          description = "Settings schema declarations for this aspect.";
        };
      }
    ];
  };
in
{
  imports = [
    (aspectSchema.mkAspectModule { })
  ];

  options.schema = aspectSchema.schemaOption;

  config = {
    # Schema extensions on the aspect kind
    schema.aspect = {
      options.priority = lib.mkOption {
        type = lib.types.int;
        default = 50;
        description = "Aspect priority for ordering.";
      };
      options.tier = lib.mkOption {
        type = lib.types.str;
        default = "unspecified";
        description = "Deployment tier classification.";
      };
    };

    _module.args = {
      inherit
        genAlgebra
        genSchema
        genAspects
        genScope
        genGraph
        genSelect
        genBind
        genDerive
        aspectSchema
        inputs
        ;
    };
  };
}
