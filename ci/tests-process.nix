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
          # evalArm <arm>: runs one cell in its own process; leaves rc/val set. The value variable
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

          # 0/0 is a false pass: the runner must have executed every cell above.
          [ "$ran" = "2" ] || die runner "expected 2 evaluations, ran $ran"
          echo "tests-process: 2 cells, every exit read unpiped, every death on its named channel, every count read" > $out
        ''
        + ''
          cat "$out"
        ''
      );
    };
}
