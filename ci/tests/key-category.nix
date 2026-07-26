# keyCategory — the single classification surface. A key's category is read from the schema: a
# native-structural option → "structural"; a declared keySemantics class/channel/facet → that category; an
# unknown key → null (a typo, or a freeform nested-aspect namespace child — the gate, not this function,
# distinguishes them). structuralKeys names the six native options as ONE binding, shared with the submodule
# option construction so the set and the options cannot drift. Theory: scope-as-type (Néron/Tolmach/Visser/
# Wachsmuth 2015) — a key unresolved in the aspect scope is a type error at that scope.
{
  lib,
  aspects,
  mkSchemaEval,
  ...
}:
let
  cnf = {
    keySemantics = {
      myFacet = {
        category = "facet";
      };
      myClass = {
        category = "class";
      };
      myChannel = {
        category = "channel";
      };
    };
  };
  schema = aspects.mkAspectSchema cnf;
  driftEval = mkSchemaEval {
    classes = { };
    modules = [ { config.aspects.main = { }; } ];
  };
  structuralOptionNames = builtins.sort builtins.lessThan (
    builtins.filter (k: !(lib.hasPrefix "_" k)) (builtins.attrNames driftEval.config.aspects.main)
  );
in
{
  flake.tests.key-category.test-structural = {
    expr = aspects.keyCategory cnf "meta";
    expected = "structural";
  };
  flake.tests.key-category.test-facet = {
    expr = aspects.keyCategory cnf "myFacet";
    expected = "facet";
  };
  flake.tests.key-category.test-class = {
    expr = aspects.keyCategory cnf "myClass";
    expected = "class";
  };
  flake.tests.key-category.test-channel = {
    expr = aspects.keyCategory cnf "myChannel";
    expected = "channel";
  };
  flake.tests.key-category.test-unknown-null = {
    expr = aspects.keyCategory cnf "nixxos";
    expected = null;
  };
  flake.tests.key-category.test-schema-record-cnf-closed = {
    expr = schema.keyCategory "myFacet";
    expected = "facet";
  };
  flake.tests.key-category.test-schema-record-structural = {
    expr = schema.keyCategory "id_hash";
    expected = "structural";
  };
  flake.tests.key-category.test-structural-keys-value = {
    expr = builtins.sort builtins.lessThan aspects.structuralKeys;
    expected = [
      "description"
      "id_hash"
      "includes"
      "key"
      "meta"
      "name"
    ];
  };
  flake.tests.key-category.test-structural-keys-drift-pin = {
    expr = structuralOptionNames;
    expected = builtins.sort builtins.lessThan aspects.structuralKeys;
  };
}
