# THE ASPECT KIND STATES ITS INSTANCES' DEFINITIONS (den-hoag-ien5k T3, arm (i) of the mkType ruling). `mkAspectSchema`'s
# `mkType` constructs each instance's modules, so it states the definitions they give each field, by gen-schema's own
# walk over the same defs, stamped as gen-schema's; gen-schema publishes them as the kind's datum, and `declaredField`
# serves a node's `aspects` from its declarations where they decide it alone. A kind declaring nothing for the field,
# or setting it under `mkDefault`, is SERVED; one setting it plainly falls back (two survivors at one priority).
# Red at gen-aspects c2a700a: the `mkType` result states no datum, so every node falls back.
{
  aspects,
  genMerge,
  genSchema,
  ...
}:
let
  inherit (genMerge) mkOption mkDefault types;
  sch = aspects.mkAspectSchema { keySemantics.nixos.category = "class"; };
  kindWith =
    cfg:
    (genSchema.evalSchema { schemaOption = sch.schemaOption; } [
      {
        config.schema.spindle = {
          options.aspects = mkOption {
            type = types.listOf types.str;
            default = [ ];
          };
          options.idx = mkOption { type = types.int; };
          config = cfg;
        };
      }
    ]).spindle;
  read =
    k:
    let
      ev = genMerge.evalModuleTree { } [
        {
          options.spindles = genSchema.mkInstanceRegistry { } k;
          config.spindles = {
            s0 = {
              aspects = [ "loom" ];
              idx = 0;
            };
            s1 = {
              aspects = [ "loom" ];
              idx = 1;
            };
          };
        }
      ];
      syn = genSchema.declaredField ev.options.spindles "aspects";
    in
    builtins.mapAttrs (n: i: {
      s = syn n;
      m = i.aspects;
    }) ev.config.spindles;
  both = v: {
    s0 = v;
    s1 = v;
  };
in
{
  flake.tests.declared-membership = {
    test-a-kind-declaring-nothing-is-served = {
      expr = read (kindWith { });
      expected = both {
        s = [ "loom" ];
        m = [ "loom" ];
      };
    };
    test-a-kind-default-is-served = {
      expr = read (kindWith {
        aspects = mkDefault [ "spare" ];
      });
      expected = both {
        s = [ "loom" ];
        m = [ "loom" ];
      };
    };
    test-a-kind-definition-falls-back = {
      expr = read (kindWith {
        aspects = [ "spare" ];
      });
      expected = both {
        s = null;
        m = [
          "spare"
          "loom"
        ];
      };
    };
  };
}
