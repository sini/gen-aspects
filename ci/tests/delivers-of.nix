# den-hoag-ouuwg: `graphFacts.deliversOf`, total over `nodes`, and the dead-nested view it names.
{ aspects, mkSchemaEval, ... }:
let
  cnf.keySemantics.nixos.category = "class";
  dead =
    body:
    let
      f =
        aspects.graphFacts cnf
          (mkSchemaEval {
            keySemantics = cnf.keySemantics;
            modules = [ { config.aspects = body; } ];
          }).config.aspects;
    in
    f.deadNested;
in
{
  flake.tests.delivers-of.test-names-the-typos-iv-misses = {
    expr = {
      attrsetOnly = dead {
        stitch.nixos.x = { };
        stitch.nixso.boot.loader = { };
      };
      empty = dead {
        stitch.nixos.x = { };
        stitch.nixso = { };
      };
      placeholder = dead {
        asp.nixos.x = { };
        asp.child.description = "child";
      };
    };
    expected = {
      attrsetOnly = [
        "stitch/nixso"
        "stitch/nixso/boot"
        "stitch/nixso/boot/loader"
      ];
      empty = [ "stitch/nixso" ];
      placeholder = [ "asp/child" ];
    };
  };
  flake.tests.delivers-of.test-delivering-nested-is-not-named = {
    expr = {
      classContent = dead { stitch.trim.nixos.x = { }; };
      includes = dead {
        stitch.trim.includes = [ "other" ];
        other.nixos.x = { };
      };
      guardChild = dead { stitch.trim.g = { host }: { nixos.x = { }; }; };
      topLevel = dead { lonely = { }; };
    };
    expected = {
      classContent = [ ];
      includes = [ ];
      guardChild = [ ];
      topLevel = [ ];
    };
  };
  # The view is the one filter over the relation, and the record still reads as a value when it
  # warns: the warning is a message, never a refusal.
  flake.tests.delivers-of.test-view-is-the-filter-and-warns-without-refusing =
    let
      f =
        aspects.graphFacts cnf
          (mkSchemaEval {
            keySemantics = cnf.keySemantics;
            modules = [
              {
                config.aspects = {
                  stitch.nixos.x = { };
                  stitch.nixso = { };
                };
              }
            ];
          }).config.aspects;
    in
    {
      expr = {
        same =
          f.deadNested == builtins.filter (id: f.parentOf.${id} != null && !f.deliversOf.${id}) f.nodes;
        readable = (builtins.tryEval (builtins.deepSeq f.nodes true)).success;
      };
      expected = {
        same = true;
        readable = true;
      };
    };
}
