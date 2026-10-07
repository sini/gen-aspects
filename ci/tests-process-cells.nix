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
  scope = import "${genScopeSrc}/lib" { inherit graph identity prelude; };

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
  # `<label>-door` — the bridge price is `evals - doors`.
  spiedDoored = spied // {
    evalModuleTree = a: builtins.trace "${label}-door" (spied.evalModuleTree a);
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

    # den-hoag-gkar9 term 2: a fired GROUND guard serves its body as written, so delivering it costs the
    # same at every body width. One guard of n fields is placed and checked once, then fired 32 times at
    # a context where its condition holds (`-true`) and where it fails (`-false`). The verdict is the
    # difference of the two thunk counts, the body's delivery, at two widths, read by the runner.
    guard-fire-true = fireWidth { thimble = "p"; };
    guard-fire-false = fireWidth { };
  };
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
