# THE SECOND TEST OUTPUT — cells whose subject is an ERROR MESSAGE.
#
# `tryEval` discards a thrown text, so it can assert THAT a door refuses and never WHAT it says.
# `expectedError` asserts the message. These cells cannot live in `flake.tests`: the batch asserter
# behind `checks.default` forces every `expr` there unconditionally, so a throwing cell crashes that
# gate instead of failing. This file sits outside `./tests` (the whole of `testModules`), so the split
# is structural. `expectedError.msg` is SEARCHED, not whole-matched, so every pattern is anchored at
# both ends and built by escaping the literal text.
#
#   nix-unit --flake ./ci#testsError
{
  lib,
  aspects,
  genMerge,
  ...
}:
let
  exactly = msg: "^" + lib.escapeRegex msg + "$";
  schemaBad = aspects.mkAspectSchema { keySemantics.bad.category = "bogus"; };
  refusal =
    got:
    exactly (
      "gen-aspects.keyRef: got ${got}, expected a reference: an origin-qualified string "
      + "(\"<origin>/<path>\") or { path; origin ? [ ]; }, each a \"/\"-joined string or a list of strings"
    );
  # deepSeq, so a refusal left lazy inside a field still reaches the cell.
  cell = ref: got: {
    expr = builtins.deepSeq (aspects.keyRef ref) null;
    expectedError = {
      type = "ThrownError";
      msg = refusal got;
    };
  };
in
{
  # One cell per shape the door refuses (den-hoag-bkdkg). Each aborted uncaught before the guard:
  # `attribute 'path' missing`, `expected a list but found an integer`, `cannot coerce a set to a
  # string`; a bad `origin` was admitted and aborted downstream in gen-link.
  flake.testsError.key-ref-refusal = {
    test-set-without-path = cell { name = "a"; } "a set with no 'path' field";
    test-int = cell 3 "int";
    test-path-int = cell { path = 3; } "path = int";
    test-path-list-of-set = cell { path = [ { name = "a"; } ]; } "path = list holding a non-string";
    test-origin-int = cell {
      path = "s";
      origin = 3;
    } "origin = int";
    test-origin-list-of-set = cell {
      path = "s";
      origin = [ { } ];
    } "origin = list holding a non-string";
    # `splitSlash` drops empty segments, so these reached `builtins.head [ ]` (den-hoag-6c5s3).
    test-empty-string = cell "" "the string \"\", which has no non-empty segment";
    test-all-slash = cell "/" "the string \"/\", which has no non-empty segment";
    test-all-slashes = cell "///" "the string \"///\", which has no non-empty segment";
  };

  # den-hoag-2ejx: a malformed keySemantics category refuses BY NAME at the key that carries it, and
  # only there (an unrelated aspect's `name` read returns; ci/tests/key-semantics.nix (7)).
  flake.testsError.key-semantics-lazy-refusal.test-carrier-bad-category = {
    expr =
      builtins.deepSeq
        (genMerge.evalModuleTree {
          modules = [
            { options.schema = schemaBad.schemaOption; }
            (schemaBad.mkAspectModule { })
            { config.aspects.carrier.bad.x = 1; }
          ];
        }).config.aspects.carrier.bad
        null;
    expectedError = {
      type = "ThrownError";
      msg = exactly "gen-aspects: keySemantics key 'bad' has unknown category 'bogus' (expected class|channel|facet)";
    };
  };

  # den-hoag-plm1h: `aspectsRoot(port) ∥ aspectsRoot(int)` is refused BY NAME at the declaration.
  flake.testsError.root-element-join-refusal.test-port-int =
    let
      rootWith = (aspects.aspectsRoot { keySemantics.a.category = "class"; }).functor.type;
      res = genMerge.evalModuleTree {
        modules = [
          { options.p = genMerge.mkOption { type = rootWith lib.types.port; }; }
          { options.p = genMerge.mkOption { type = rootWith lib.types.int; }; }
          { p.a = 70000; }
        ];
      };
    in
    {
      expr = res.options.p.type.name;
      expectedError = {
        type = "ThrownError";
        msg = exactly (
          "gen-merge: option `p' is declared with types that do not merge (`aspectsRoot' and "
          + "`aspectsRoot', which the first type's own `functor' does not reconcile); "
          + "declared in <gen-merge>, <gen-merge>"
        );
      };
    };
}
