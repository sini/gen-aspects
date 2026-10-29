# ONE `mkAspectModule` CONSTRUCTION IMPORTED TWICE IS ONE MODULE: a serve beyond nixpkgs, (b′) (ADR-0039;
# den-hoag-xh14j, orchestrator reading 2026-10-29). The record states its reference key on the record only, so
# nixpkgs' `lib.evalModules`, which reads identity from a module's result `key`, sees two declarations of
# `options.aspects` both stating `default` and refuses; gen-merge dedups the one construction by its record key.
# The merge law is ADR-0012's "a diamond is two edges to one node, so deduplication holds BY CONSTRUCTION".
#   VALUE: imported 2..4 times, the aspects read equal the construction imported once;
#   CHECK: a planted definition the container's own type rejects (an aspect's `description`, a `str`, defined
#          as an int) is refused, as it is with the construction imported once (`checkOnce`).
# nixpkgs' twin is pinned beside them, so the serve beyond stays visible. Two DISTINCT constructions are not
# this law and are not pinned here.
{
  lib,
  aspects,
  genMerge,
  ...
}:
let
  m = (aspects.mkAspectSchema { }).mkAspectModule { };
  def = {
    aspects.stitch.description = "s";
  };
  read =
    ev: ms:
    let
      r = builtins.tryEval (
        builtins.deepSeq (builtins.mapAttrs (_: a: a.description or null) (ev ms).config.aspects) (
          builtins.mapAttrs (_: a: a.description or null) (ev ms).config.aspects
        )
      );
    in
    if r.success then r.value else "REFUSED";
  gen = read (ms: genMerge.evalModuleTree { } ms);
  np = read (ms: lib.evalModules { modules = ms; });
  copies = n: builtins.genList (_: m) n;
  bad = {
    aspects.stitch.description = 5;
  };
  ns = [
    2
    3
    4
  ];
in
{
  flake.tests.aspect-module-one-construction.test-b-prime-imported-n-times-value-and-check = {
    expr = {
      once = gen ([ m ] ++ [ def ]);
      value = map (n: gen (copies n ++ [ def ])) ns;
      checkOnce = gen [
        m
        bad
      ];
      check = map (n: gen (copies n ++ [ bad ])) ns;
      nixpkgs = map (n: np (copies n ++ [ def ])) ns;
    };
    expected = {
      once.stitch = "s";
      value = [
        { stitch = "s"; }
        { stitch = "s"; }
        { stitch = "s"; }
      ];
      checkOnce = "REFUSED";
      check = [
        "REFUSED"
        "REFUSED"
        "REFUSED"
      ];
      nixpkgs = [
        "REFUSED"
        "REFUSED"
        "REFUSED"
      ];
    };
  };
}
