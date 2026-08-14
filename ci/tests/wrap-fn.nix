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
}
