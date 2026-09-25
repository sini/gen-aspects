# `wrapFn` — the API sibling of the aspect type's `wrapGuardFn` (types.nix). A NATIVE author writes a
# bare guard fn into an aspect and the option-type merge wraps it; a PROGRAMMATICALLY-GENERATED include
# (built off the type) must call `wrapFn` explicitly. These pin: (1) the wrap shape, (2) the EQUIVALENCE
# to the type-merge path (a `wrapFn`'d include is indistinguishable from a type-merge-wrapped bare fn —
# the property the generating consumer relies on), (3) that a `wrapFn`'d include survives the fixpoint.
{
  lib,
  aspects,
  mkSchemaEval,
  ...
}:
let
  cnf = {
    keySemantics = {
      classOne = {
        category = "class";
      };
      classTwo = {
        category = "class";
      };
    };
  };
  # A raw guard closure (REQUIRES `host`, so the aspect type routes it to wrapGuardFn, not the
  # module-fn path). Returns freeform aspect content parameterised by the context.
  fn =
    { host, ... }:
    {
      description = "d-${host}";
    };
in
{
  flake.tests.wrap-fn = {
    # (1) wrapFn yields an `__isWrappedFn` functor carrying the closure's formals + a siting name.
    test-wrapfn-shape = {
      expr =
        let
          w = aspects.wrapFn cnf "myFn" fn;
        in
        {
          isWrapped = w.__isWrappedFn or false;
          args = w.__functionArgs;
          name = w.name;
          callable = builtins.isFunction w.__functor;
        };
      expected = {
        isWrapped = true;
        args = {
          host = false;
        };
        name = "myFn";
        callable = true;
      };
    };

    # (2) EQUIVALENCE WITNESS: the SAME closure through the aspect TYPE's merge (wrapGuardFn, the path a
    # native bare-fn include takes) and through `wrapFn` produce equivalent wraps — same formals, and
    # applied to the same context, the same merged content. This is the invariant a generating consumer
    # depends on: it can hand-wrap without diverging from what the type would have produced.
    test-wrapfn-equiv-type-merge = {
      expr =
        let
          tm =
            (aspects.aspectType cnf).merge
              [ "myFn" ]
              [
                {
                  file = "<t>";
                  value = fn;
                }
              ];
          api = aspects.wrapFn cnf "myFn" fn;
          ctx = {
            host = "cortex";
          };
        in
        {
          bothWrapped = (tm.__isWrappedFn or false) && (api.__isWrappedFn or false);
          sameArgs = tm.__functionArgs == api.__functionArgs;
          sameContent = (tm ctx).description == (api ctx).description;
        };
      expected = {
        bothWrapped = true;
        sameArgs = true;
        sameContent = true;
      };
    };

    # (3) A `wrapFn`'d include survives the fixpoint (included in an aspect, resolved through
    # mkSchemaEval) as an `__isWrappedFn`, and applies to a context on demand.
    test-wrapfn-include-materializes = {
      expr =
        let
          wrapped = aspects.wrapFn cnf "gen" (
            { host, ... }:
            {
              description = "D-${host}";
            }
          );
          eval = mkSchemaEval {
            modules = [ { config.aspects.a.includes = [ wrapped ]; } ];
          };
          inc = builtins.head eval.config.aspects.a.includes;
        in
        {
          isWrapped = inc.__isWrappedFn or false;
          applied = (inc { host = "web"; }).description;
        };
      expected = {
        isWrapped = true;
        applied = "D-web";
      };
    };
  };

  # den-hoag-khnhi: the doors (lib/require-wrapped-closure.nix) — the cells whose RED cannot abort.
  # Aborting REDs live on ci/tests-error.nix's `wrap-totality`.
  flake.tests.wrap-totality =
    let
      ctx = {
        host = "cortex";
      };
      selfF =
        let
          f = _: f;
        in
        f;
      under = p: q: { description = "x"; };
      caught = e: !(builtins.tryEval (builtins.deepSeq e e)).success;
      native =
        v:
        (aspects.aspectType cnf).merge
          [ "n" ]
          [
            {
              file = "<t>";
              value = v;
            }
          ];
      gv = aspects.mkGuardVocab { };
      carrier =
        v:
        (aspects.aspectType cnf).merge
          [ "n" ]
          [
            {
              file = "<a>";
              value = v;
            }
            {
              file = "<b>";
              value = gv.vocab.whenEq [ "host" ] "nope" { description = "b"; };
            }
          ];
    in
    {
      # THE EQUIVALENCE OVER THE DEFECT DOMAIN (gate C4): the under-applied closure through both
      # applicators. RED: { api = false; native = false; } — both silently admitted ("x").
      test-equiv-under-applied-both-refused = {
        expr = {
          api = caught ((aspects.wrapFn cnf "n" under) ctx);
          native = caught ((native under) ctx);
        };
        expected = {
          api = true;
          native = true;
        };
      };
      # LIVE CONTROLS: what works today still works, through both applicators.
      test-controls-admitted = {
        expr = {
          good = ((aspects.wrapFn cnf "ok" fn) { host = "cortex"; }).description;
          nativeGood = ((native fn) ctx).description;
          moduleFnReturn =
            ((aspects.wrapFn cnf "n" (_: ({ config, ... }: { description = "m"; }))) ctx).description;
          nativeModuleFnReturn = ((native (_: ({ config, ... }: { description = "m"; }))) ctx).description;
          openPatternSuperset =
            ((aspects.wrapFn cnf "n" ({ x, ... }: { description = x; })) {
              x = "a";
              y = "b";
            }).description;
          exactStrictPattern =
            ((aspects.wrapFn cnf "n" ({ x }: { description = x; })) { x = "a"; }).description;
          bareFormalNonAttrsContext =
            (
              (aspects.wrapFn cnf "n" (_: {
                description = "b";
              }))
                "s"
            ).description;
          carrierGood = aspects.applyGuard ctx (carrier fn);
          gatedGood = (aspects.wrapGatedFn { functionArgs.host = false; } fn) ctx;
          gatedFunctorFn =
            (aspects.wrapGatedFn { functionArgs.host = false; } (aspects.wrapFn cnf "i" fn)) ctx ? description;
          # applyGuard's escape-hatch arm: a well-formed raw closure applies, and a gated record is
          # applied as built, so its self-gating (`{ }` on a missing coord) is not overridden by the door.
          hatchGood = aspects.applyGuard ctx fn;
          hatchGatedInert = aspects.applyGuard { } (aspects.wrapGatedFn { functionArgs.host = false; } fn);
        };
        expected = {
          good = "d-cortex";
          nativeGood = "d-cortex";
          moduleFnReturn = "m";
          nativeModuleFnReturn = "m";
          openPatternSuperset = "a";
          exactStrictPattern = "a";
          bareFormalNonAttrsContext = "b";
          carrierGood = {
            description = "d-cortex";
          };
          gatedGood = {
            description = "d-cortex";
          };
          gatedFunctorFn = true;
          hatchGood = {
            description = "d-cortex";
          };
          hatchGatedInert = { };
        };
      };
      # The M4b falsifier's CAUSE (its abort is ci/tests-error.nix): `functionArgs` erases the ellipsis.
      test-falsifier-functionargs-erases-ellipsis = {
        expr = {
          closedVsOpen = builtins.functionArgs ({ x }: 1) == builtins.functionArgs ({ x, ... }: 1);
          bareVsEmpty = builtins.functionArgs (q: 1) == builtins.functionArgs ({ }: 1);
        };
        expected = {
          closedVsOpen = true;
          bareVsEmpty = true;
        };
      };
      # FALSIFIERS, defaulted and reversible: the codomains no door types in this landing.
      # wrapGatedFn's result (retires under den-hoag-lwbb1): `onResult`'s return is handed back raw,
      # and `fn` returning a closure comes back a closure.
      test-falsifier-gated-result-untyped = {
        expr = {
          onResultInt =
            (aspects.wrapGatedFn {
              functionArgs.host = false;
              onResult = _: 42;
            } fn)
              ctx;
          fnReturnsClosure = builtins.isFunction (
            (aspects.wrapGatedFn { functionArgs.host = false; } (_: selfF)) ctx
          );
        };
        expected = {
          onResultInt = 42;
          fnReturnsClosure = true;
        };
      };
      # The carrier function fragment's RETURN (Q4, disposition (c), defaulted-reversible): a single
      # survivor is handed back raw. Retires with the function fragment under den-hoag-lwbb1.
      test-falsifier-carrier-fn-return-untyped = {
        expr = {
          selfReturning = builtins.typeOf (aspects.applyGuard ctx (carrier selfF));
          int = aspects.applyGuard ctx (carrier (_: 42));
        };
        expected = {
          selfReturning = "lambda";
          int = 42;
        };
      };
      # applyGuard's ESCAPE-HATCH arm's RETURN (the same enumerated exception as the carrier's, Q4 (c)):
      # a raw closure's return is handed back raw. Retires with `deferIncludeResolution` under lwbb1.
      test-falsifier-hatch-return-untyped = {
        expr = {
          selfReturning = builtins.typeOf (aspects.applyGuard ctx selfF);
          int = aspects.applyGuard ctx (_: 42);
        };
        expected = {
          selfReturning = "lambda";
          int = 42;
        };
      };
    };
}
