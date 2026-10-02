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
      closedX = { x }: { description = x; };
      wide = {
        x = "a";
        y = "b";
      };
      closedNarrowed = got: {
        expr = got;
        expected = "a";
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
      # THE CLOSED PATTERN GIVEN AN EXTRA COORD (0cmbt §3, N1), one cell per applicator: the context door
      # narrows to the declared formals. RED on all but `wrapGatedFn` (which intersected locally before
      # folding into the door): `called with unexpected argument 'y'`, uncatchable.
      test-closed-pattern-wrapfn = closedNarrowed ((aspects.wrapFn cnf "n" closedX) wide).description;
      test-closed-pattern-native = closedNarrowed ((native closedX) wide).description;
      test-closed-pattern-carrier = closedNarrowed (aspects.applyGuard wide (carrier closedX))
        .description;
      test-closed-pattern-hatch = closedNarrowed (aspects.applyGuard wide closedX).description;
      test-closed-pattern-gated =
        closedNarrowed
          ((aspects.wrapGatedFn { functionArgs.x = false; } closedX) wide).description;
      # `wrapGatedFn` hands a closure whose `functionArgs` is empty `{ }`, never the context: a closed
      # `{ }:` pattern aborts uncatchably on a wider one and `functionArgs` cannot tell it from `ctx:`.
      test-gated-no-formals-empty-context = {
        expr = (aspects.wrapGatedFn { functionArgs = { }; } (c: c)) wide;
        expected = { };
      };
      test-gated-closed-empty-pattern = {
        expr = (aspects.wrapGatedFn { functionArgs = builtins.functionArgs ({ }: "ce"); } ({ }: "ce")) wide;
        expected = "ce";
      };
      # Why the door narrows rather than inspects: `functionArgs` erases the ellipsis.
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

  # THE SHAPE CLASSIFIER (den-hoag-t5hli ruled arm (a); 0cmbt spec §2.3, cells S1-S3, S5): a function
  # declaring no formals is classified by its `toXML` pattern at every site of the context door. S1's
  # RED, before the classifier: every `{ }:` arm aborted uncatchably, `function 'anonymous lambda'
  # called with unexpected argument 'host'` (`'name'` at the predicate-argument position).
  flake.tests.shape-classifier =
    let
      ctx = {
        host = "h";
        extra = "x";
      };
      keys = c: builtins.concatStringsSep "," (builtins.attrNames c);
      closedEmpty = { }: { description = "ce"; };
      functorClosedEmpty = {
        __functor = self: { }: { description = "fce"; };
      };
      bare = c: { description = "bare:${keys c}"; };
      atEllipsis =
        a@{ ... }:
        {
          description = "at:${keys a}";
        };
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
      via = f: {
        wrapFn = ((aspects.wrapFn cnf "n" f) ctx).description;
        merge = ((native f) ctx).description;
        carrier = (aspects.applyGuard ctx (carrier f)).description;
        applyGuard = (aspects.applyGuard ctx f).description;
      };
    in
    {
      # S1: `{ }:` is handed `{ }` at every site of the door.
      test-closed-empty = {
        expr = via closedEmpty // {
          functor = (aspects.applyGuard ctx functorClosedEmpty).description;
        };
        expected = {
          wrapFn = "ce";
          merge = "ce";
          carrier = "ce";
          applyGuard = "ce";
          functor = "fce";
        };
      };
      # S2, the control that the classifier moves only `{ }:`: `ctx:` and `a@{ ... }:` are handed the
      # context whole, as before it.
      test-context-shapes-unmoved = {
        expr = {
          bare = via bare;
          atEllipsis = via atEllipsis;
        };
        expected = {
          bare = {
            wrapFn = "bare:extra,host";
            merge = "bare:extra,host";
            carrier = "bare:extra,host";
            applyGuard = "bare:extra,host";
          };
          atEllipsis = {
            wrapFn = "at:extra,host";
            merge = "at:extra,host";
            carrier = "at:extra,host";
            applyGuard = "at:extra,host";
          };
        };
      };
      # S3, the control that formals still narrow (76cmu's door, unmoved).
      test-formals-narrow-unmoved = {
        expr = via ({ host }: { description = "d-${host}"; });
        expected = {
          wrapFn = "d-h";
          merge = "d-h";
          carrier = "d-h";
          applyGuard = "d-h";
        };
      };
      # S5, the classifier table (0cmbt spec §2.3, item 15): what each shape is handed, read through the
      # escape hatch, whose return is handed back raw. A formal's throwing default is never forced.
      test-classifier-table = {
        expr = builtins.mapAttrs (_: f: aspects.applyGuard ctx f) {
          bare = c: c;
          ellipsis = { ... }@a: a;
          atEllipsis = a@{ ... }: a;
          atClosedEmpty = a@{ }: a;
          closedEmptyAt = { }@a: a;
          defaultThrows =
            a@{
              host ? throw "default forced",
            }:
            a;
          functorBare = {
            __functor = self: c: c;
          };
          functorClosedEmpty = {
            __functor = self: a@{ }: a;
          };
          setFunctionArgsEmpty = {
            __functor = self: c: c;
            __functionArgs = { };
          };
        };
        expected = {
          bare = ctx;
          ellipsis = ctx;
          atEllipsis = ctx;
          atClosedEmpty = { };
          closedEmptyAt = { };
          defaultThrows = {
            host = "h";
          };
          functorBare = ctx;
          functorClosedEmpty = { };
          setFunctionArgsEmpty = ctx;
        };
      };
    };

  # ENTITY-KIND NARROWING AND `__receives` (0cmbt spec §2.4, cells K-a and K-b). A framework declares
  # its entity kinds as `cnf.entityKinds`, the context keys that carry them; a context shape (`ctx:`,
  # `{ ... }:`) is handed the context narrowed to those keys at every instance-producing applicator,
  # formals are narrowed to exactly the formals, and a guard's condition, which mints no instance, is
  # never narrowed. Every wrap record publishes `__receives`,
  # the keys its door hands at a context.
  # K-a's RED, before the key: `gen-aspects: unrecognised cnf key 'entityKinds'.`
  flake.tests.entity-kinds =
    let
      ctx = {
        host = "h";
        extra = "x";
      };
      keys = c: builtins.concatStringsSep "," (builtins.attrNames c);
      kcnf = cnf // {
        entityKinds = [ "host" ];
      };
      bare = c: { description = "bare:${keys c}"; };
      atEllipsis =
        a@{ ... }:
        {
          description = "at:${keys a}";
        };
      via =
        c: f:
        let
          gv = aspects.mkGuardVocab c;
          native =
            v:
            (aspects.aspectType c).merge
              [ "n" ]
              [
                {
                  file = "<t>";
                  value = v;
                }
              ];
          carrier =
            v:
            (aspects.aspectType c).merge
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
          wrapFn = ((aspects.wrapFn c "n" f) ctx).description;
          merge = ((native f) ctx).description;
          carrier = (gv.applyGuard ctx (carrier f)).description;
          applyGuard = (gv.applyGuard ctx f).description;
          receivesWrapFn = (aspects.wrapFn c "n" f).__receives ctx;
          receivesMerge = (native f).__receives ctx;
        };
    in
    {
      # K-a: with `entityKinds = [ "host" ]`, the context shapes are handed `{ host }` only at the
      # instance-producing applicators (`wrapFn`, `wrapGuardFn`, the carrier's function fragment, the
      # hatch), and `__receives` names `host` alone. A guard's condition is never narrowed.
      test-kinds-narrow-context-shapes = {
        expr = {
          bare = via kcnf bare;
          atEllipsis = via kcnf atEllipsis;
        };
        expected = {
          bare = {
            wrapFn = "bare:host";
            merge = "bare:host";
            carrier = "bare:host";
            applyGuard = "bare:host";
            receivesWrapFn = [ "host" ];
            receivesMerge = [ "host" ];
          };
          atEllipsis = {
            wrapFn = "at:host";
            merge = "at:host";
            carrier = "at:host";
            applyGuard = "at:host";
            receivesWrapFn = [ "host" ];
            receivesMerge = [ "host" ];
          };
        };
      };
      # K-b, the control that the default reproduces the behaviour before the key: unset, the context
      # is handed whole and every supplied key is received.
      test-kinds-unset-hands-whole = {
        expr = via cnf bare;
        expected = {
          wrapFn = "bare:extra,host";
          merge = "bare:extra,host";
          carrier = "bare:extra,host";
          applyGuard = "bare:extra,host";
          receivesWrapFn = [
            "extra"
            "host"
          ];
          receivesMerge = [
            "extra"
            "host"
          ];
        };
      };
      # Formals are narrowed to exactly the formals, whatever the kinds: `extra` is not a kind and is
      # still handed to the closure that names it. `{ }:` receives nothing.
      test-kinds-leave-formals-and-empty = {
        expr = {
          formals = via kcnf ({ extra, ... }: { description = "f:${extra}"; });
          empty = via kcnf ({ }: { description = "ce"; });
        };
        expected = {
          formals = {
            wrapFn = "f:x";
            merge = "f:x";
            carrier = "f:x";
            applyGuard = "f:x";
            receivesWrapFn = [ "extra" ];
            receivesMerge = [ "extra" ];
          };
          empty = {
            wrapFn = "ce";
            merge = "ce";
            carrier = "ce";
            applyGuard = "ce";
            receivesWrapFn = [ ];
            receivesMerge = [ ];
          };
        };
      };
      # A guard's condition is never narrowed: under the kinds, the built-in `tagEq` reads `tags.role`
      # (a field of this library's own, in the declared set the kinds widen) and fires where the role
      # matches, and a mismatch does not fire.
      test-kinds-condition-not-narrowed =
        let
          tctx = {
            host = "h";
            tags.role = "web";
          };
          v = aspects.mkGuardVocab kcnf;
          run = pr: (v.applyGuard tctx (v.guard pr { description = "fired"; })).description or "not fired";
        in
        {
          expr = {
            web = run (aspects.pred.tagEq "role" "web");
            db = run (aspects.pred.tagEq "role" "db");
          };
          expected = {
            web = "fired";
            db = "not fired";
          };
        };
      # `wrapGatedFn`'s hand-built record carries `__receives` too: the narrowed formals when it fires,
      # `[ ]` when a required coord is missing, and `[ ]` for declared-empty formals.
      test-gated-receives = {
        expr = {
          fires = (aspects.wrapGatedFn { functionArgs.host = false; } (_: { })).__receives ctx;
          inert = (aspects.wrapGatedFn { functionArgs.user = false; } (_: { })).__receives ctx;
          empty = (aspects.wrapGatedFn { functionArgs = { }; } (_: { })).__receives ctx;
        };
        expected = {
          fires = [ "host" ];
          inert = [ ];
          empty = [ ];
        };
      };
    };
}
