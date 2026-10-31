# THE PER-PROCESS CELLS — relocated from gen-merge's `ci/` (den-hoag-n6dh7, ADR-0037: "there are no
# cycles" and CI-only pinning is "TIMEBOXED to the migration/validation phase that needs it"; that
# phase ended at Unit 2's publish, and gen-merge's own `ci/flake.nix` had pinned gen-schema and
# gen-aspects to a branch of THIS repository to reach them, closing a cycle in the test graph). Both
# cells drive a SPIED gen-merge instance through gen-schema and this library's own `../lib`, hosted
# here because gen-aspects' graph already carries gen-merge AND gen-schema as ordinary inputs — the
# relocation adds no CI-only pin at all.
#
# Verdict is a PROCESS EXIT read by `tests-process.nix` (one fixture per process); the spy (U2-g/
# U2-h, unchanged from gen-merge's own file) counts `scope.eval` calls on stderr via a fresh-per-run
# trace label. Sources arrive as ARGUMENTS rather than through `fetchTree`: the runner evaluates
# inside the build sandbox, and every dependency below is reconstructed from its own `lib/` with
# explicit arguments so the SPIED merge instance threads through gen-schema's and this library's own
# formals — using a flake's precomputed `.lib` output would already be bound to an unspied gen-merge.
{
  arm,
  libSrc,
  genMergeSrc,
  genSchemaSrc,
  genPreludeSrc,
  genIdentitySrc,
  genGraphSrc,
  genTypesSrc,
  genMemoSrc,
  genScopeSrc,
  genAlgebraSrc,
  genAspectsAlgebraSrc,
  # A trace label generated fresh per run by the runner, which counts its lines on stderr.
  label ? "",
  # The fixture size of a scaling cell, as a string (`--argstr`).
  n ? "0",
}:
let
  prelude = import "${genPreludeSrc}/lib";
  identity = import "${genIdentitySrc}/lib";
  graph = import "${genGraphSrc}/lib" { inherit prelude; };
  algebra = import "${genAlgebraSrc}/lib";
  scope = import "${genScopeSrc}/lib" {
    inherit
      algebra
      graph
      identity
      prelude
      ;
  };

  # THE SPY (den-hoag-n6dh7 U2-g, unchanged from gen-merge's own file): the same gen-merge library
  # over an evaluator whose `eval` traces `label`, so the label's count on stderr is the number of
  # independent gen-scope evaluations. A declaration-only evaluation (no `definitions`/`positions`)
  # is ALSO traced `<label>-plain`, so a census can tell a standalone side-evaluation from one that
  # threads as a proper nta child.
  spied = import "${genMergeSrc}/lib" {
    inherit prelude;
    types = import "${genTypesSrc}/lib" { inherit algebra identity prelude; };
    memo = import "${genMemoSrc}/lib" { inherit graph prelude; };
    scope = scope // {
      eval =
        o: attributes: s:
        builtins.trace label (
          if attributes ? definitions || attributes ? positions then
            scope.eval o attributes s
          else
            builtins.trace "${label}-plain" (scope.eval o attributes s)
        );
    };
  };
  st = spied.types;
  # U2-h: the same evaluator wrapped a second time so an explicit ROOT call also traces
  # `<label>-door` — the bridge price is `evals - doors`. Both published root entries are doors:
  # `declaredOptions` (gen-schema's kind introspection) fires its own evaluation, as `evalModuleTree` does.
  spiedDoored = spied // {
    evalModuleTree = a: builtins.trace "${label}-door" (spied.evalModuleTree a);
    declaredOptions = a: builtins.trace "${label}-door" (spied.declaredOptions a);
  };
  gs = import "${genSchemaSrc}/lib" {
    inherit
      prelude
      algebra
      identity
      graph
      ;
    merge = spiedDoored;
  };
  # `ga` is THIS library, under test, built the same way `gs` is — from raw source, over the spied
  # merge instance and the gen-schema instance above.
  ga = import libSrc {
    inherit prelude identity;
    algebra = import "${genAspectsAlgebraSrc}/lib";
    merge = spiedDoored;
    schema = gs;
  };

  # One host per `hosts` entry, each its own entity binding `host`; every reached instance's include
  # site targets, forced. The value is the count of sites read.
  appliedSites =
    { aspects, hosts }:
    let
      as =
        (spiedDoored.evalModuleTree { } [
          { options.aspects = (ga.mkAspectSchema { keySemantics.T.category = "class"; }).mkAspectOption { }; }
          { inherit aspects; }
        ]).config.aspects;
      entity = h: identity.hashIdentity "entity" [ "name" ] (_: h);
      rel =
        ga.instancesFor { } as
          {
            suppliers = builtins.listToAttrs (
              map (h: {
                name = entity h;
                value.host = h;
              }) (builtins.attrNames hosts)
            );
            containment = { };
          }
          (
            builtins.mapAttrs (h: ms: {
              members = ms;
              sources.host = entity h;
            }) hosts
          );
      at = ga.includeSitesOfInstance { } as rel;
      targets = builtins.concatMap (
        h:
        builtins.concatMap (
          m: builtins.concatMap (iid: map (s: s.target) (at iid)) rel.reaches.${h}.${m}
        ) hosts.${h}
      ) (builtins.attrNames hosts);
    in
    builtins.deepSeq targets (builtins.length targets);
  # One factory: its `name` sits at one source position however often it is called.
  wide = m: k: {
    name = "t";
    T.marks = [ m ];
    extra = builtins.listToAttrs (
      builtins.genList (i: {
        name = "e${toString i}";
        value.v = i;
      }) k
    );
  };
  appliedMixed =
    named: k:
    let
      v = m: if named then wide m k else builtins.removeAttrs (wide m k) [ "name" ];
      hs = builtins.genList (i: "h${toString i}") (builtins.fromJSON n);
    in
    appliedSites {
      aspects = {
        a = ga.guard (ga.pred.has "host") { includes = [ (v "a") ]; };
        b = ga.guard (ga.pred.has "host") { includes = [ (v "b") ]; };
      };
      hosts = builtins.listToAttrs (
        map (h: {
          name = h;
          value = [
            "a"
            "b"
          ];
        }) hs
      );
    };

  cells = {
    # den-hoag-3jyxf cell 1 (relocated verbatim, den-hoag-n6dh7 SCC build): a config-decided
    # extraModules list (gen-schema mkInstanceRegistry) — ADMITTED AS an nta CHILD. `evals - doors`
    # is the ruled bridge price (U2-h, one bridge at `schema`); `plain` is 0 when the construction
    # threads as a proper child rather than firing a standalone declaration-only evaluation.
    nta-extra-modules =
      let
        ntaSchema = gs.evalSchema { } [
          { config.schema.host.options.addr = spiedDoored.mkOption { type = st.str; }; }
        ];
        run =
          knob:
          (spiedDoored.evalModuleTree { } [
            (
              { config, ... }:
              {
                options.knob = spiedDoored.mkOption {
                  type = st.bool;
                  default = false;
                };
                options.hosts = gs.mkInstanceRegistry {
                  extraModules =
                    if config.knob then
                      [
                        {
                          options.tag = spiedDoored.mkOption {
                            type = st.str;
                            default = "on";
                          };
                        }
                      ]
                    else
                      [
                        {
                          options.tag = spiedDoored.mkOption {
                            type = st.str;
                            default = "off";
                          };
                        }
                      ];
                } ntaSchema.host;
                config.knob = knob;
                config.hosts.igloo.addr = "10.0.1.1";
              }
            )
          ]).config.hosts.igloo.tag;
      in
      [
        (run true)
        (run false)
      ];

    # den-hoag-3jyxf cell 2 (relocated verbatim, den-hoag-n6dh7 SCC build): gen-aspects
    # mkAspectModule (the inner type computed from `config.schema.aspect.__defsModule`) — ADMITTED
    # AS an nta CHILD, same shape as cell 1.
    nta-aspect-module =
      let
        ntaSchema = ga.mkAspectSchema {
          keySemantics = {
            classOne.category = "class";
          };
        };
        c = spiedDoored.evalModuleTree { } [
          { options.schema = ntaSchema.schemaOption; }
          (ntaSchema.mkAspectModule { })
          {
            config.schema.aspect.options.priority = spiedDoored.mkOption {
              type = st.int;
              default = 50;
            };
          }
          {
            config.aspects.networking.priority = 10;
            config.aspects.desktop = { };
          }
        ];
      in
      [
        c.config.aspects.networking.priority
        c.config.aspects.desktop.priority
      ];

    # den-hoag-gkar9: aspectsRoot's per-key definition collection is ONE pass. n modules each define
    # one distinct aspect, so a per-key scan of every definition costs keys × defs = n²; each aspect
    # is forced to WHNF only. The verdict is the evaluator's thunk count at three sizes, read by the
    # runner (a quadratic shows as a growing slope), not this value.
    aspects-root-linear =
      let
        ids = builtins.genList (i: "a${toString i}") (builtins.fromJSON n);
        tree =
          (spiedDoored.evalModuleTree { } (
            [ { options.aspects = (ga.mkAspectSchema { }).mkAspectOption { }; } ]
            ++ map (k: { aspects.${k}.description = k; }) ids
          )).config.aspects;
      in
      builtins.deepSeq (map (k: builtins.seq tree.${k} null) ids) (builtins.length ids);

    # den-hoag-gkar9 term 2: a fired guard whose body is plain data serves it as written, so delivering it costs the
    # same at every body width. One guard of n fields is placed and checked once, then fired 32 times at
    # a context where its condition holds (`-true`) and where it fails (`-false`). The verdict is the
    # difference of the two thunk counts, the body's delivery, at two widths, read by the runner.
    guard-fire-true = fireWidth { thimble = "p"; };
    guard-fire-false = fireWidth { };

    # den-hoag-egkyp: a guard's declaration check costs a constant per body field, its floor. One guard of
    # n plain fields is placed and fired once where its condition FAILS, so the check runs and nothing is
    # delivered (`-check`); `-data` forces the same body with no guard. The verdict is the difference of
    # the two thunk counts, the check, at two widths, read by the runner.
    guard-check-check = checkWidth true;
    guard-check-data = checkWidth false;

    # den-hoag-named-include-instance-bodies-sfkyy: an applied named value's class costs a constant per
    # sighting. `applied-factory`: n guards, each holding one factory's own content (n classes at one §2
    # key), reached by one host, every include site's target read; the runner reads the slope at
    # n = 100 / 200 / 400. `applied-mixed-w<k>`: two guards holding two values at one §2 key, each k
    # attributes wide, reached by n hosts, and `applied-unnamed-w<k>` the same values without a `name`
    # (no class work, the control); the runner reads what the width costs the classes at two host counts.
    applied-factory = appliedSites (
      let
        ix = builtins.genList (i: "a${toString i}") (builtins.fromJSON n);
      in
      {
        aspects = builtins.listToAttrs (
          map (i: {
            name = i;
            value = ga.guard (ga.pred.has "host") { includes = [ (wide i 0) ]; };
          }) ix
        );
        hosts.x = ix;
      }
    );
    applied-mixed-w16 = appliedMixed true 16;
    applied-mixed-w64 = appliedMixed true 64;
    applied-unnamed-w16 = appliedMixed false 16;
    applied-unnamed-w64 = appliedMixed false 64;

    # den-hoag-qxip5 (identity design §4 row 4, R7's declared exception): named content whose
    # structural comparison does not terminate aborts the whole graph. The verdict is the exit and its
    # channel, read by the runner; base read `nodes` 2 and 1. `named-cycle`: two DISTINCT bisimilar
    # named self-referential values (one factory, built twice) at two owners, so rung 2's `==` walks
    # the cycle. `named-unfolding`: one taker, one named value whose `includes` builds a FRESH named
    # value per level, each marked (no cycle, no bisimilarity), so the back-edge test's `==` descends
    # without end (row 4 read as "a cycle or an infinite unfolding", den-hoag-idzev).
    named-cycle =
      let
        mkS =
          _:
          let
            s = {
              name = "s";
              includes = [ s ];
            };
          in
          s;
      in
      namedNodes {
        a.includes = [ (mkS 1) ];
        b.includes = [ (mkS 2) ];
      };
    named-unfolding =
      let
        unfold = k: {
          name = "u";
          T.marks = [ (toString k) ];
          includes = [ (unfold (k + 1)) ];
        };
      in
      namedNodes { a.includes = [ (unfold 0) ]; };
  };
  namedNodes =
    aspects:
    let
      schema = ga.mkAspectSchema { keySemantics.T.category = "class"; };
    in
    builtins.length
      (ga.graphFacts { }
        (spiedDoored.evalModuleTree { } [
          { options.schema = schema.schemaOption; }
          (schema.mkAspectModule { })
          { config = { inherit aspects; }; }
        ]).config.aspects
      ).nodes;
  checkWidth =
    guarded:
    let
      w = builtins.fromJSON n;
      body = builtins.listToAttrs (
        builtins.genList (i: {
          name = "x${toString i}";
          value = "v${toString i}";
        }) w
      );
      g =
        (spiedDoored.evalModuleTree { } [
          { options.aspects = (ga.mkAspectSchema { }).mkAspectOption { }; }
          { aspects.d = ga.guard (ga.pred.eq [ "thimble" ] "p") body; }
        ]).config.aspects.d;
    in
    if guarded then
      builtins.deepSeq ((ga.mkGuardVocab { }).applyGuard { } g) w
    else
      builtins.deepSeq body w;
  fireWidth =
    ctx:
    let
      w = builtins.fromJSON n;
      gv = ga.mkGuardVocab { };
      g =
        (spiedDoored.evalModuleTree { } [
          { options.aspects = (ga.mkAspectSchema { }).mkAspectOption { }; }
          {
            aspects.d = ga.guard (ga.pred.eq [ "thimble" ] "p") (
              builtins.listToAttrs (
                builtins.genList (i: {
                  name = "x${toString i}";
                  value = "v${toString i}";
                }) w
              )
            );
          }
        ]).config.aspects.d;
    in
    builtins.deepSeq (builtins.genList (_: gv.applyGuard ctx g) 32) w;
in
cells.${arm}
