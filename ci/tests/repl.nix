# The repl entry (`ci/repl.nix`, the harness `repl` command's file) loads, and loads exactly the
# library surface plus `lib` and `aspects`. Nothing else in the suite reaches that file, which is
# how it came to import `../lib` without the `prelude` it requires (den-hoag-s34cm).
{
  lib,
  aspects,
  prelude,
  genMerge,
  genSchema,
  genIdentity,
  ...
}:
{
  flake.tests.repl.test-entry-loads-the-surface = {
    expr = builtins.attrNames (
      import ../repl.nix {
        inherit lib prelude;
        merge = genMerge;
        schema = genSchema;
        identity = genIdentity;
      }
    );
    expected = builtins.attrNames ({ inherit lib aspects; } // aspects);
  };
}
