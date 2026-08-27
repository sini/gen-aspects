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
    fixtureKeySemantics = { };
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

  # den-hoag-7cya: keyCategory is the documented "single classification surface" but read
  # cnf.keySemantics.${key}.category directly, with no validation — a malformed entry rode straight
  # through as garbage (or a generic, unnamed Nix error on a non-attrset entry), never touching
  # aspectSubmodule's eager check. SEEDED RED — an unrecognised category string refuses BY NAME,
  # naming both the key and the bogus value.
  flake.tests.key-category.test-bad-category-refuses-by-name = {
    expr =
      (builtins.tryEval (
        builtins.deepSeq (aspects.keyCategory {
          keySemantics = {
            amd = {
              category = "bogus";
            };
          };
        } "amd") true
      )).success;
    expected = false;
  };
  # SEEDED RED — a bare-string keySemantics entry (the shape the 2026-08-02 spike measured pinned
  # consumers on) refuses by name instead of throwing nixpkgs' generic "value is a string while a set
  # was expected".
  flake.tests.key-category.test-bare-string-entry-refuses-by-name = {
    expr =
      (builtins.tryEval (
        builtins.deepSeq (aspects.keyCategory {
          keySemantics = {
            amd = "amd";
          };
        } "amd") true
      )).success;
    expected = false;
  };
  # GREEN TWIN — the three well-formed categories still classify exactly as before (test-facet /
  # test-class / test-channel above already cover this; this cell pins the un-declared-key null
  # result survives the membership-test rewrite too).
  flake.tests.key-category.test-green-twin-unknown-key-still-null = {
    expr = aspects.keyCategory cnf "nixxos";
    expected = null;
  };
}
