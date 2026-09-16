# Test: multi-definition merging behavior at the type level.
{
  genMerge,
  lib,
  mkSchemaEval,
  ...
}:
let
  # O3's scanner — a test instrument, not library surface: a total negative over the CONFIG TREE
  # that a `{ _type = "merge"; ... }` marker never reaches anywhere, list-nested or attrs-nested.
  # Stops descending at a function (isAttrs/isList both false for one) so it never forces a guard
  # fragment's opaque closure body.
  hasMergeMarker =
    v:
    if builtins.isAttrs v && (v._type or null) == "merge" then
      true
    else if builtins.isAttrs v then
      builtins.any hasMergeMarker (builtins.attrValues v)
    else if builtins.isList v then
      builtins.any hasMergeMarker v
    else
      false;
in
{
  flake.tests.multi-def.test-attrset-multi-def-lists-merge =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.foo.classOne.names = [ "alice" ]; }
          { config.aspects.foo.classOne.names = [ "bob" ]; }
        ];
      };
      classEval = genMerge.evalModuleTree {
        modules = [
          { options.names = genMerge.mkOption { type = genMerge.types.listOf genMerge.types.str; }; }
          eval.config.aspects.foo.classOne
        ];
      };
    in
    {
      expr = lib.sort (a: b: a < b) classEval.config.names;
      expected = [
        "alice"
        "bob"
      ];
    };

  flake.tests.multi-def.test-attrset-multi-def-preserves-both-keys =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.foo.classOne.x = "from-a"; }
          { config.aspects.foo.classOne.y = "from-b"; }
        ];
      };
      classEval = genMerge.evalModuleTree {
        modules = [
          {
            options.x = genMerge.mkOption { type = genMerge.types.str; };
            options.y = genMerge.mkOption { type = genMerge.types.str; };
          }
          eval.config.aspects.foo.classOne
        ];
      };
    in
    {
      expr = {
        inherit (classEval.config) x y;
      };
      expected = {
        x = "from-a";
        y = "from-b";
      };
    };

  flake.tests.multi-def.test-mixed-attrset-and-module-fn-coerces-fn-to-include =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.foo.classOne.x = [ "static" ]; }
          {
            config.aspects.foo =
              { aspect, ... }:
              {
                classOne.x = [ "from-fn" ];
              };
          }
        ];
      };
    in
    {
      # Mixed defs: function is coerced to { includes = [fn]; }
      # The attrset content is direct, the function becomes an include
      expr = {
        hasIncludes = eval.config.aspects.foo.includes != [ ];
        includeCount = builtins.length eval.config.aspects.foo.includes;
      };
      expected = {
        hasIncludes = true;
        includeCount = 1;
      };
    };

  # den-hoag-sezf Arm A (O1a/O1b/O2): primitive multi-def routes through
  # `merge.mergeDefaultOption` instead of the marker-producing `merge.mkMerge` — witness 1's fix.
  # RED (measured pre-fix, gen-aspects f0d9d14c): `config.aspects.prim` held the raw
  # `{ _type = "merge"; contents = [ 2 1 ]; }` marker verbatim, no crash, no refusal — a wrong value
  # that looks like a value. GREEN: a catchable named `throw` (differing ints refuse).
  flake.tests.multi-def.test-primitive-differing-ints-refuses =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.prim = 1; }
          { config.aspects.prim = 2; }
        ];
      };
      # control, same run: single-def is untouched by either arm.
      control = mkSchemaEval {
        modules = [ { config.aspects.solo = 7; } ];
      };
    in
    {
      expr = {
        refuses = !(builtins.tryEval (builtins.deepSeq eval.config.aspects.prim true)).success;
        controlUnchanged = control.config.aspects.solo;
      };
      expected = {
        refuses = true;
        controlUnchanged = 7;
      };
    };

  # O1a's type-heterogeneous case: an int def and a string def at one key. Same refusal law —
  # `mergeDefaultOption` has no all-X arm any mixed-type def list satisfies, so it falls to the
  # terminal `throw` exactly as the differing-int case does.
  flake.tests.multi-def.test-primitive-type-heterogeneous-refuses =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.het = 1; }
          { config.aspects.het = "x"; }
        ];
      };
    in
    {
      expr = !(builtins.tryEval (builtins.deepSeq eval.config.aspects.het true)).success;
      expected = true;
    };

  # O1a's non-refusing scalar shapes (O12's scoping: only differing ints and type-heterogeneous
  # mixes refuse — bools `or`, strings concatenate). Measured live (not carried from the spec's
  # citation): concatenation order is gen-merge's declared reverse-flattened-module-order invariant.
  flake.tests.multi-def.test-primitive-differing-bools-or =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.flag = false; }
          { config.aspects.flag = true; }
        ];
      };
    in
    {
      expr = eval.config.aspects.flag;
      expected = true;
    };

  flake.tests.multi-def.test-primitive-differing-strings-concatenate =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.label = "a"; }
          { config.aspects.label = "b"; }
        ];
      };
    in
    {
      expr = eval.config.aspects.label;
      expected = "ba";
    };

  # O1a's list case: differing lists concatenate in gen-merge's declared reverse-flattened-module
  # order (NOT authored order — an oracle asserting authored order would be wrong per spec §3).
  flake.tests.multi-def.test-primitive-differing-lists-concatenate =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.tags = [ "web" ]; }
          { config.aspects.tags = [ "prod" ]; }
        ];
      };
    in
    {
      expr = eval.config.aspects.tags;
      expected = [
        "prod"
        "web"
      ];
    };

  # O2: primitive, agreeing — separates "resolve the agreement" from "refuse on count alone".
  flake.tests.multi-def.test-primitive-agreeing-ints-resolve =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.agree = 5; }
          { config.aspects.agree = 5; }
        ];
      };
    in
    {
      expr = eval.config.aspects.agree;
      expected = 5;
    };

  # O3: the marker has no construction site — a total negative over the CONFIG TREE. Three
  # controls per spec §3, each guarding a different hazard:
  #   (a) a forged marker (attrs-nested AND list-nested) is DETECTED, plus its negative twin —
  #       proves the scanner is not a dead instrument before it is trusted on real output;
  #   (b) a red-state characterization only (not itself a control) — nested primitive multi-def,
  #       alive at RED, vacuous at GREEN by construction;
  #   (c) a not-empty witness — guards against an empty tree passing (a) vacuously.
  flake.tests.multi-def.test-o3-scanner-detects-forged-marker-in-attrs = {
    expr = hasMergeMarker {
      x = {
        _type = "merge";
        contents = [
          1
          2
        ];
      };
    };
    expected = true;
  };
  flake.tests.multi-def.test-o3-scanner-negative-on-plain-attrs = {
    expr = hasMergeMarker {
      x = {
        y = 1;
      };
    };
    expected = false;
  };
  flake.tests.multi-def.test-o3-scanner-detects-forged-marker-in-list = {
    expr = hasMergeMarker {
      x = [
        {
          _type = "merge";
          contents = [
            1
            2
          ];
        }
      ];
    };
    expected = true;
  };
  flake.tests.multi-def.test-o3-scanner-negative-on-list = {
    expr = hasMergeMarker { x = [ { y = 1; } ]; };
    expected = false;
  };
  flake.tests.multi-def.test-o3-nested-primitive-multidef-has-no-marker =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.foo.nestedPrim = 3; }
          { config.aspects.foo.nestedPrim = 3; }
        ];
      };
    in
    {
      expr = hasMergeMarker eval.config.aspects;
      expected = false;
    };
  flake.tests.multi-def.test-o3-not-empty-witness =
    let
      eval = mkSchemaEval {
        modules = [
          { config.aspects.foo.nestedPrim = 3; }
          { config.aspects.foo.nestedPrim = 3; }
        ];
      };
    in
    {
      expr = builtins.attrNames eval.config.aspects;
      expected = [ "foo" ];
    };
}
