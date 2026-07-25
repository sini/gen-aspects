# `wrapGatedFn` — the OPT-IN self-gating wrapped fn (N-GATE). Its applicator self-gates on required
# coords (no-default formals): all present → `onResult (fn (intersectAttrs functionArgs fnArgs))`; a
# required coord MISSING → `{ }` (INERT, no throw). This is a DISTINCT constructor from `mkWrapped`/
# `wrapGuardFn` — the native guard-fn path stays apply-unconditionally-throw-on-missing (the R1 opt-in
# invariant, pinned by test-native-guard-not-gated below). Consumers: den-hoag's compile fire-path,
# which passes an explicit `functionArgs` override (its wrapper's own formals are `{ fnArgs = false; }`)
# and an `onResult` hook (grounding); gen-aspects itself stays den-agnostic (no den vocab enters here).
{
  lib,
  aspects,
  mkSchemaEval,
  ...
}:
let
  # the INNER fire fn: a strict `{ host, user }` — its declared formals are the `functionArgs` override.
  innerFA = {
    host = false;
    user = false;
  };
  fn =
    { host, user }:
    {
      tag = "fired:${host}:${user}";
    };
in
{
  # ── (a) GATE INERT: a required coord (`user`) MISSING ⇒ `{ }`, no throw. ──
  flake.tests.gated-wrap.test-gate-inert-on-missing =
    let
      gated = aspects.wrapGatedFn { functionArgs = innerFA; } fn;
    in
    {
      expr = gated { host = "x"; }; # `user` absent
      expected = { };
    };

  # ── (b) FIRES + onResult transform + intersectAttrs drops extra args. All required coords present, an
  #    EXTRA arg `__entry` is passed; `intersectAttrs functionArgs` drops it (the strict `fn` never sees
  #    it), and `onResult` post-transforms the merged result. ──
  flake.tests.gated-wrap.test-fires-onresult-and-intersect =
    let
      gated = aspects.wrapGatedFn {
        functionArgs = innerFA;
        onResult = r: r // { grounded = true; };
      } fn;
    in
    {
      expr = gated {
        host = "h";
        user = "u";
        __entry = "DROP-ME";
      };
      expected = {
        tag = "fired:h:u"; # the `__entry` extra never reached `fn` (intersectAttrs) ⇒ no `called with unexpected argument`
        grounded = true; # onResult applied
      };
    };

  # ── (c) onResult defaults to identity (native gated caller gets the raw merged result). ──
  flake.tests.gated-wrap.test-onresult-defaults-identity =
    let
      gated = aspects.wrapGatedFn { functionArgs = innerFA; } fn;
    in
    {
      expr = gated {
        host = "h";
        user = "u";
      };
      expected = {
        tag = "fired:h:u";
      };
    };

  # ── R1 GUARD (the load-bearing invariant): the NATIVE `wrapGuardFn` path is BYTE-UNCHANGED — gating did
  #    NOT leak into the default path. A native strict `{ host, user }:` guard fn (written into an aspect,
  #    wrapped by the aspectType merge) is applied UNCONDITIONALLY: with a MISSING coord it hits nix's own
  #    `called without required argument 'user'` (the apply-unconditionally contract — NOT the gated `{ }`),
  #    an UNCATCHABLE error (`builtins.tryEval` cannot rescue a missing-arg throw), so we assert the invariant
  #    by CONTRAST, catchable-free:
  #      • the native wrapper FIRES normally with FULL coords (the native applicator, unchanged);
  #      • the GATED wrapper over the SAME `{ host, user }` fn returns `{ }` on the SAME missing-coord args
  #        (test-gate-inert-on-missing above) — the gate is OPT-IN, present ONLY on `wrapGatedFn`.
  #    The native path NOT gating is what makes its missing-coord application throw rather than `{ }`; the
  #    full gen-aspects CI (guard/guard-identity/parametric) is the byte-unchanged backstop. ──
  flake.tests.gated-wrap.test-native-guard-not-gated =
    let
      eval = mkSchemaEval {
        modules = [
          {
            config.aspects.fonts =
              { host, user }:
              {
                classOne.packages = [ "noto:${host}:${user}" ];
              };
          }
        ];
      };
      nativeWrapper = eval.config.aspects.fonts; # __isWrappedFn (via wrapGuardFn) — NOT gated
      fired = nativeWrapper {
        host = "h";
        user = "u";
      };
    in
    {
      expr = {
        # the native applicator FIRES with full coords (unconditional apply, unchanged) — the result is a
        # real aspect submodule (carries the `classOne` class bucket), NOT a gated `{ }`.
        nativeFires = fired ? classOne;
        # the SAME missing-coord shape through the GATED wrapper INERTS to `{ }` (opt-in gate — the
        # contrast that proves gating is present ONLY on `wrapGatedFn`, never the native path).
        gatedInertsOnMissing =
          (aspects.wrapGatedFn {
            functionArgs = {
              host = false;
              user = false;
            };
          } (args: args))
            { host = "only-host"; } == { };
      };
      expected = {
        nativeFires = true;
        gatedInertsOnMissing = true;
      };
    };

  # ── the gated record MIRRORS mkWrapped's tag shape (a `__isWrappedFn` consumer can't tell it apart):
  #    `__isWrappedFn`/`__functionArgs`/callable/name all present. ──
  flake.tests.gated-wrap.test-tag-shape =
    let
      gated = aspects.wrapGatedFn {
        functionArgs = innerFA;
        name = "myGated";
      } fn;
    in
    {
      expr = {
        isWrapped = gated.__isWrappedFn or false;
        hasFA = gated ? __functionArgs;
        fa = gated.__functionArgs;
        callable = lib.isFunction gated;
        name = gated.name;
      };
      expected = {
        isWrapped = true;
        hasFA = true;
        fa = innerFA;
        callable = true;
        name = "myGated";
      };
    };
}
