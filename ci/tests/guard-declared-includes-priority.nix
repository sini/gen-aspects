# A priority on a guard carrier's DECLARED `includes` ranges over the fired record as the module system's
# does (den-hoag-5ov3p, ADR-0029). The carrier's typed child declares one option, `includes`, at every
# position; it is a `partialSubmodule` (lib/types.nix `carrierSub`), so the declared option's value keeps
# the priority that selected it, as fjdnf's `partialAttrsOf` keeps a nested position's, and the content
# law (lib/guard.nix `applyGuardScoped`) ranks it against the fired record's. The declared default moves
# too, as a definition at `mkOptionDefault`, so a record's `mkDefault` beats an `includes` nobody wrote.
#
# ★ THE REFERENCE IS T4, COMPUTED IN THE CELL: the same definitions with the guard record replaced by its
# body as a plain sibling, no carrier. Each cell evaluates both and compares the list it is about (`i` the
# top `includes`, `s` = `sub.includes`, `si` = `sub.inner.includes`, or a channel's or a facet's list),
# rendered as descriptions. Where the two differ in ORDER only, route (a)'s order (the typed fragment
# first, den-hoag-3849t P4's bound), the cell compares members (`members`).
#
# The declared list-valued fields beside `includes` (a channel, a facet) are routed raw to the remainder
# and resolve at fire time: controls, equal to T4 before this unit too.
#
# RED: the realizer's partial `mergeOption` (gen-merge lib/modules.nix) returning the bare value restores
# every `priority-*` cell to the pre-unit value (the plain definition's priority lost: `[Q, X]` where T4
# serves `[Q]` or `[X]`, `[X]` at a tie). The `facts.nix` read-through reverted aborts the two `sites`
# cells uncatchably (`expected a list but found a set`).
{
  aspects,
  genMerge,
  ...
}:
let
  inherit (genMerge)
    mkForce
    mkDefault
    mkIf
    mkOverride
    mkBefore
    mkAfter
    mkMerge
    ;
  ls = genMerge.types.listOf genMerge.types.str;
  cnf = {
    keySemantics = {
      tags = {
        category = "channel";
        option = genMerge.mkOption {
          type = ls;
          default = [ ];
        };
      };
      nb = {
        category = "facet";
        option = genMerge.mkOption {
          type = ls;
          default = [ ];
        };
      };
    };
  };
  gv = aspects.mkGuardVocab cnf;
  e = n: { description = n; };
  # the definitions: the record's `body` (under a guard that fires, or as T4's plain sibling) and `plains`
  evalWith =
    t4: body: plains:
    (genMerge.evalModuleTree { } (
      [
        { options.aspects = (aspects.mkAspectSchema cnf).mkAspectOption { }; }
        { aspects.dup = if t4 then body else gv.vocab.always body; }
      ]
      ++ map (p: { aspects.dup = p; }) plains
      ++ [ { aspects.q.description = "q"; } ]
    )).config.aspects;
  served =
    t4: body: plains:
    let
      dup = (evalWith t4 body plains).dup;
    in
    if t4 then dup else gv.applyGuard { thimble.name = "cortex"; } dup;
  descs = map (x: if builtins.isAttrs x then x.description or "?" else builtins.typeOf x);
  at = {
    i = v: descs (v.includes or [ ]);
    s = v: descs (v.sub.includes or [ ]);
    si = v: descs (v.sub.inner.includes or [ ]);
    tags = v: v.tags;
    nb = v: v.nb;
  };
  # one cell: the carrier's list beside T4's
  cell = sel: body: plains: {
    carrier = at.${sel} (served false body plains);
    t4 = at.${sel} (served true body plains);
  };
  sort = builtins.sort builtins.lessThan;
  members = c: builtins.mapAttrs (_: sort) c;
  # the record writes the list at the top (`x0`), one key down (`x1`), or not at all (`quiet`)
  x0.includes = [ (e "X") ];
  x1.sub.includes = [ (e "X") ];
  quiet.description = "g";
  # the declaration's include sites (`graphFacts`), read before any firing: a reader of the typed `includes`
  sites =
    t4: body: plains:
    map (s: s.kind or "?") (aspects.graphFacts cnf (evalWith t4 body plains)).includeSitesOf.dup;
  sitesCell = body: plains: {
    carrier = sites false body plains;
    t4 = sites true body plains;
  };
  # each cell's expected side is its own T4
  asT4 = c: c // { carrier = c.t4; };
  grid = cells: {
    expr = cells;
    expected = builtins.mapAttrs (_: asT4) cells;
  };
in
{
  flake.tests.guard-declared-includes-priority = {
    # the plain definition carries the priority, at the top `includes`
    test-priority-at-depth-0 = grid {
      force = cell "i" x0 [ { includes = mkForce [ (e "Q") ]; } ];
      default = cell "i" x0 [ { includes = mkDefault [ (e "Q") ]; } ];
      override = cell "i" x0 [ { includes = mkOverride 60 [ (e "Q") ]; } ];
      # two plain definitions, at 50 and 100, the record at 100
      twoPlain = cell "i" x0 [
        { includes = mkForce [ (e "Q") ]; }
        { includes = [ (e "R") ]; }
      ];
      ifForce = cell "i" x0 [ { includes = mkIf true (mkForce [ (e "Q") ]); } ];
      mergeForce = cell "i" x0 [ { includes = mkMerge [ (mkForce [ (e "Q") ]) ]; } ];
      # a module function as the forced element: applied in the typed evaluation, carried at its priority
      fnForce = cell "i" x0 [ { includes = mkForce [ ({ config, ... }: { description = "F"; }) ]; } ];
      # the typed default (an `includes` nobody wrote, beside a nested position) against a record's `mkDefault`
      recDefaultNested = cell "i" { includes = mkDefault [ (e "X") ]; } [
        { sub.includes = [ (e "Q") ]; }
      ];
    };
    # a nested position's declared `includes`, one and two keys down
    test-priority-at-depth-1-and-2 = grid {
      force1 = cell "s" x1 [ { sub.includes = mkForce [ (e "Q") ]; } ];
      default1 = cell "s" x1 [ { sub.includes = mkDefault [ (e "Q") ]; } ];
      recDefaultNested1 = cell "s" { sub.includes = mkDefault [ (e "X") ]; } [
        { sub.inner.includes = [ (e "Q") ]; }
      ];
      force2 = cell "si" { sub.inner.includes = [ (e "X") ]; } [
        { sub.inner.includes = mkForce [ (e "Q") ]; }
      ];
    };
    # a tie at the forced priority keeps both, in route (a)'s order
    test-priority-tie-keeps-both = grid {
      tie = members (
        cell "i" { includes = mkForce [ (e "X") ]; } [ { includes = mkForce [ (e "Q") ]; } ]
      );
    };
    # controls: the priority on the record, a priority with nothing to beat, a discharged condition, no
    # priority, the order axis, and the raw-routed declared lists
    test-priority-controls = grid {
      recForce = cell "i" { includes = mkForce [ (e "X") ]; } [ { includes = [ (e "Q") ]; } ];
      recDefault = cell "i" { includes = mkDefault [ (e "X") ]; } [ { includes = [ (e "Q") ]; } ];
      quietForce = cell "i" quiet [ { includes = mkForce [ (e "Q") ]; } ];
      ifFalse = cell "i" x0 [ { includes = mkIf false [ (e "Q") ]; } ];
      plain = members (cell "i" x0 [ { includes = [ (e "Q") ]; } ]);
      before = cell "i" x0 [ { includes = mkBefore [ (e "Q") ]; } ];
      after = members (cell "i" x0 [ { includes = mkAfter [ (e "Q") ]; } ]);
      chanForce = cell "tags" { tags = [ "X" ]; } [ { tags = mkForce [ "Q" ]; } ];
      chanDefault = cell "tags" { tags = [ "X" ]; } [ { tags = mkDefault [ "Q" ]; } ];
      facetForce = cell "nb" { nb = [ "X" ]; } [ { nb = mkForce [ "Q" ]; } ];
      facetDefault = cell "nb" { nb = [ "X" ]; } [ { nb = mkDefault [ "Q" ]; } ];
    };
    # the declaration's static include sites read a typed `includes` under a priority, or default-only
    # (lib/facts.nix `declInfo`)
    test-include-sites-read-through-a-priority = grid {
      force = sitesCell quiet [ { includes = mkForce [ (e "Q") ]; } ];
      defaultOnly = sitesCell quiet [ { sub.includes = [ (e "Q") ]; } ];
      plain = sitesCell quiet [ { includes = [ (e "Q") ]; } ];
    };
  };
}
