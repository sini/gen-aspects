# THE PER-PROCESS RUNNER — relocated from gen-merge's `ci/` (den-hoag-n6dh7 SCC build; ADR-0037,
# den-hoag-3jyxf). Evaluates each cell in `tests-process-cells.nix` in its OWN evaluator process and
# asserts on the EXIT STATUS, the channel a death is on, and the printed value — gen-scope's
# `ci/tests-process.nix` is the precedent gen-merge's own runner cited, and the reasons are
# unchanged: the verdict is a process predicate, not a nix-unit output, and it is evidence only for
# the evaluator that computed it. As `apps.<system>.tests-process` it calls the `nix-instantiate` on
# PATH, and gen-harness's `ci --tests-process` runs it in every column of `evaluators.yml`. Locally:
#   nix develop ./ci --command ci --tests-process
#
# gen-types, gen-memo and gen-scope are read off gen-merge's own `inputs` and gen-graph and
# gen-algebra off gen-schema's — the edges `flake.lock` already records for each — rather than
# declared as inputs of this flake: gen-aspects' graph already carries gen-merge and gen-schema, so
# relocating these two cells here adds no CI-only pin at all (den-hoag-n6dh7).
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      apps.tests-process.program = pkgs.writeShellScriptBin "tests-process" (
        ''
          set -e
          # The tools the body calls, declared rather than ambient — and never an evaluator.
          export PATH=${
            pkgs.lib.makeBinPath [
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.gnused
            ]
          }:$PATH
          export cells=${./tests-process-cells.nix} libSrc=${../lib}
          export genPreludeSrc=${inputs.gen-prelude} genIdentitySrc=${inputs.gen-identity}
          export genMergeSrc=${inputs.gen-merge} genSchemaSrc=${inputs.gen-schema}
          export genTypesSrc=${inputs.gen-merge.inputs.gen-types} genMemoSrc=${inputs.gen-merge.inputs.gen-memo}
          export genScopeSrc=${inputs.gen-merge.inputs.gen-scope}
          export genGraphSrc=${inputs.gen-schema.inputs.gen-graph} genAlgebraSrc=${inputs.gen-schema.inputs.gen-algebra}
          # This library's OWN gen-algebra (its guard terms, den-hoag-lwbb1), which gen-schema's pin need
          # not carry: the same input `ci/flake.nix` builds `aspects` with.
          export genAspectsAlgebraSrc=${inputs.gen-algebra}
          # A fresh working directory per run, as gen-scope's runner needs (den-hoag-jutgv).
          TMPDIR=$(mktemp -d) out=$(mktemp)
          export TMPDIR out
          trap 'rm -rf "$TMPDIR" "$out"' EXIT
          cd "$TMPDIR"
          # The evaluator the cells run under, from this process and the binary they call.
          echo "evaluator: $(nix-instantiate --version | sed -n 1p)"
        ''
        + ''
          export NIX_STATE_DIR=$TMPDIR/nix-state NIX_LOG_DIR=$TMPDIR/nix-log
          ran=0
          # The spy's trace label, generated fresh per run and never written down, so no text a cell
          # or a document carries can be mistaken for a firing.
          label="spy-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
          # traced <arm>: the number of lines on stderr carrying this run's label.
          traced() {
            grep -c "trace: $label\$" "$TMPDIR/err" || true
          }
          die() {
            echo "tests-process: FAILED at cell $1: $2" >&2
            exit 1
          }
          # evalArm <arm> [n]: runs one cell in its own process; leaves rc/val set. The value variable
          # is `val`, never `out` — `out` is the derivation's own output path.
          evalArm() {
            rc=0
            val=$(nix-instantiate --eval --strict --readonly-mode \
              --argstr arm "$1" \
              --argstr libSrc "$libSrc" \
              --argstr genMergeSrc "$genMergeSrc" \
              --argstr genSchemaSrc "$genSchemaSrc" \
              --argstr genPreludeSrc "$genPreludeSrc" \
              --argstr genIdentitySrc "$genIdentitySrc" \
              --argstr genGraphSrc "$genGraphSrc" \
              --argstr genTypesSrc "$genTypesSrc" \
              --argstr genMemoSrc "$genMemoSrc" \
              --argstr genScopeSrc "$genScopeSrc" \
              --argstr genAlgebraSrc "$genAlgebraSrc" \
              --argstr genAspectsAlgebraSrc "$genAspectsAlgebraSrc" \
              --argstr label "$label" \
              --argstr n "''${2:-0}" \
              "$cells" 2> "$TMPDIR/err") || rc=$?
            ran=$((ran + 1))
          }
          # tracedSuffix <suffix>: the number of lines on stderr carrying "$label-<suffix>".
          tracedSuffix() {
            grep -c "trace: $label-$1\$" "$TMPDIR/err" || true
          }

          # den-hoag-3jyxf: the two same-mechanism constructions ADMITTED AS nta CHILDREN at the
          # 09-25 sitting, relocated verbatim from gen-merge's own runner (den-hoag-n6dh7 SCC build).
          # `evals - doors` is the ruled bridge price (U2-h: one bridge at `schema`); `plain` (a
          # declaration-only evaluation, no `definitions`/`positions`) is 0 exactly when the
          # construction threads as a proper nta child rather than firing a standalone evaluation.
          evalArm nta-extra-modules
          [ "$rc" -eq 0 ] || die nta-extra-modules "expected exit 0, got $rc"
          [ "$val" = '[ "on" "off" ]' ] || die nta-extra-modules "expected [ \"on\" \"off\" ], got '$val'"
          n=$(traced); nd=$(tracedSuffix door); np=$(tracedSuffix plain)
          [ "$n" = "5" ] || die nta-extra-modules "expected 5 evaluations (the ruled bridge price), counted $n"
          [ "$nd" = "4" ] || die nta-extra-modules "expected 4 doors, counted $nd"
          [ "$np" = "0" ] || die nta-extra-modules "expected 0 declaration-only evaluations (an nta child, not a standalone evaluation), counted $np"

          evalArm nta-aspect-module
          [ "$rc" -eq 0 ] || die nta-aspect-module "expected exit 0, got $rc"
          [ "$val" = '[ 10 50 ]' ] || die nta-aspect-module "expected [ 10 50 ], got '$val'"
          n=$(traced); nd=$(tracedSuffix door); np=$(tracedSuffix plain)
          [ "$n" = "2" ] || die nta-aspect-module "expected 2 evaluations (the ruled bridge price), counted $n"
          [ "$nd" = "1" ] || die nta-aspect-module "expected 1 door, counted $nd"
          [ "$np" = "0" ] || die nta-aspect-module "expected 0 declaration-only evaluations (an nta child, not a standalone evaluation), counted $np"

          # den-hoag-gkar9: aspectsRoot's per-key collection is linear. thunksAt <n> runs the cell at
          # size n with the evaluator's statistics on and leaves `thunks` set; statistics that were
          # not written die as COULD NOT MEASURE, never read as a count.
          thunksAt() {
            rm -f "$TMPDIR/stats"
            export NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="$TMPDIR/stats"
            evalArm aspects-root-linear "$1"
            unset NIX_SHOW_STATS NIX_SHOW_STATS_PATH
            [ "$rc" -eq 0 ] || die aspects-root-linear "n=$1: expected exit 0, got $rc"
            [ "$val" = "$1" ] || die aspects-root-linear "n=$1: expected $1, got '$val'"
            [ -s "$TMPDIR/stats" ] || die aspects-root-linear "n=$1: could not measure, no statistics written"
            thunks=$(sed -n 's/.*"nrThunks": *\([0-9][0-9]*\).*/\1/p' "$TMPDIR/stats")
            [ -n "$thunks" ] || die aspects-root-linear "n=$1: could not measure, no nrThunks in the statistics"
          }
          thunksAt 100; t1=$thunks
          thunksAt 200; t2=$thunks
          thunksAt 400; t3=$thunks
          echo "aspects-root-linear: thunks $t1 / $t2 / $t3 at n = 100 / 200 / 400"
          # Linear, the second slope is exactly twice the first (measured on all three evaluators); a
          # per-key scan of every definition adds 4n² and roughly quadruples it. 0.5% slack.
          [ $((100 * (t3 - t2))) -le $((201 * (t2 - t1))) ] \
            || die aspects-root-linear "thunks grow faster than linear in n: $t1 / $t2 / $t3 at n = 100 / 200 / 400"

          # den-hoag-gkar9 term 2: delivering a fired ground guard's body costs the same at every width.
          # fireAt <arm> <n> leaves `thunks` set, read as above.
          fireAt() {
            rm -f "$TMPDIR/stats"
            export NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="$TMPDIR/stats"
            evalArm "$1" "$2"
            unset NIX_SHOW_STATS NIX_SHOW_STATS_PATH
            [ "$rc" -eq 0 ] || die guard-fire-width "$1 n=$2: expected exit 0, got $rc"
            [ "$val" = "$2" ] || die guard-fire-width "$1 n=$2: expected $2, got '$val'"
            [ -s "$TMPDIR/stats" ] || die guard-fire-width "$1 n=$2: could not measure, no statistics written"
            thunks=$(sed -n 's/.*"nrThunks": *\([0-9][0-9]*\).*/\1/p' "$TMPDIR/stats")
            [ -n "$thunks" ] || die guard-fire-width "$1 n=$2: could not measure, no nrThunks in the statistics"
          }
          fireAt guard-fire-true 16; a1=$thunks
          fireAt guard-fire-false 16; b1=$thunks
          fireAt guard-fire-true 64; a2=$thunks
          fireAt guard-fire-false 64; b2=$thunks
          d1=$((a1 - b1)); d2=$((a2 - b2))
          echo "guard-fire-width: delivery $d1 / $d2 thunks over 32 firings at width 16 / 64"
          # Served as written, the delivery is the same at both widths; resolving the body back from its
          # term costs per field per firing. 1% slack.
          [ "$d1" -gt 0 ] || die guard-fire-width "could not measure: no delivery at width 16 ($a1 - $b1)"
          [ $((100 * d2)) -le $((101 * d1)) ] \
            || die guard-fire-width "delivery grows with body width: $d1 / $d2 thunks over 32 firings at width 16 / 64"

          # 0/0 is a false pass: the runner must have executed every cell above.
          [ "$ran" = "9" ] || die runner "expected 9 evaluations, ran $ran"
          echo "tests-process: 4 cells, every exit read unpiped, every death on its named channel, every count read" > $out
        ''
        + ''
          cat "$out"
        ''
      );
    };
}
