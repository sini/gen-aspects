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
{ lib, aspects, ... }:
let
  exactly = msg: "^" + lib.escapeRegex msg + "$";
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
  };
}
