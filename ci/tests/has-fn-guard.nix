# The structural function-scan behind `guardKey` REFUSES a body it cannot finish walking, instead of
# aborting inside it (lib/identity.nix, `hasFn`).
#
# Measured on the shipped definition before the guard existed, each arm its own `nix eval` with the
# exit read unpiped: a cyclic attrset, a list containing itself, and a derivation value ALL reached
# `stack overflow; max-call-depth exceeded` through `aspects.guardKey`, while in the same run a deep
# finite body minted `guard:always:b75e2b04…` and a lambda-carrying body took the `guard-loc:` branch.
# An abort is not a `tryEval` failure, so not one of the three was catchable: the library detonated at
# a position whose whole job is to return a boolean.
#
# ★ EVERY REFUSAL CELL CARRIES ITS CONTROL IN THE SAME EXPRESSION, so no cell can go green by
# refusing everything or by walking nothing. A scan that answered `true` unconditionally is caught by
# the inert payload sitting beside the arm; one that answered `false` for everything is caught by the
# lambda beside it; and a refusal blamed on depth is separated from one blamed on shape by walking the
# SAME chain shape on both sides of the bound.
#
# ★ WHAT THESE CELLS DO NOT COVER, stated rather than left silent: a value whose own thunk is a black
# hole (`l = [ 1 ] ++ l`) aborts when it is FORCED — a bare `builtins.isList l`, with no walk alive at
# all, aborts identically — so no cell here can hold one. That divergence is in the value, not in the
# walk over it, and nothing below claims otherwise.
{
  aspects,
  identityInternals,
  lib,
  ...
}:
let
  inherit (identityInternals) hasFn hasFnMaxDepth hasFnDepthRefusal;

  # REFUSED = forcing it fails CATCHABLY. The distinction this whole file exists for is invisible to a
  # cell that only reads a value: an abort takes the runner with it, a refusal returns `false` here.
  refuses = e: !(builtins.tryEval (builtins.seq e null)).success;

  # Substring test WITHOUT a regex. `lib.hasInfix` compiles to `builtins.match ".*<sub>.*"`, and a
  # leading-`.*` match over a several-hundred-character subject is the shape that overflows the
  # evaluator's stack under the test runner. Its own control is the last row of
  # `test-refusal-names-itself`: a scan that can never match reads exactly like an absence.
  containsSub =
    sub: s:
    let
      n = builtins.stringLength sub;
      m = builtins.stringLength s;
    in
    m >= n && builtins.any (i: builtins.substring i n s == sub) (builtins.genList (i: i) (m - n + 1));

  # `chainTo leaf n` = n nested attrsets over `leaf`. The only payload whose DEPTH is exactly known,
  # which is what a cell straddling a depth bound needs on both sides of it.
  chainTo = leaf: n: builtins.foldl' (acc: _: { n = acc; }) leaf (builtins.genList (i: i) n);
  chain = chainTo { leaf = "bottom"; };

  inertPayload = {
    a = "s";
    b = {
      c = 1;
      d = [
        1
        2
        { e = "deep"; }
      ];
    };
    deep = chain 40;
  };
  lambdaPayload = {
    a = "s";
    nested = {
      f = x: x;
    };
  };

  cyclic = {
    a = "s";
    self = cyclic;
  };
  selfRefList = [
    1
    selfRefList
  ];
  drv = builtins.derivation {
    name = "probe";
    system = "x86_64-linux";
    builder = "/bin/sh";
  };
in
{
  flake.tests.has-fn-guard.test-cyclic-attrset-refused-with-live-controls = {
    expr = {
      cyclicRefused = refuses (hasFn cyclic);
      inertWalksClean = hasFn inertPayload;
      lambdaIsFound = hasFn lambdaPayload;
    };
    expected = {
      cyclicRefused = true;
      inertWalksClean = false;
      lambdaIsFound = true;
    };
  };

  flake.tests.has-fn-guard.test-self-referential-list-refused = {
    expr = {
      selfRefRefused = refuses (hasFn selfRefList);
      # Controls of the SAME shape — an int beside a nested list — so the refusal above is
      # attributable to the cycle and not to lists as such.
      finiteListWalksClean = hasFn [
        1
        [
          2
          [ 3 ]
        ]
      ];
      lambdaInListIsFound = hasFn [
        1
        (x: x)
      ];
    };
    expected = {
      selfRefRefused = true;
      finiteListWalksClean = false;
      lambdaInListIsFound = true;
    };
  };

  flake.tests.has-fn-guard.test-derivation-short-circuits-before-descent = {
    # A derivation VALUE passes WITHOUT descent, and answering at all is what proves it: the `out`
    # attribute is self-referential (`drv.out.out.out…`), so a scan that descended would abort rather
    # than return anything. Nested inside an ordinary body it is reached BY the walk and short-
    # circuits there, which is where a consumer's derivation actually sits.
    expr = {
      bareDrv = hasFn drv;
      bareDrvNotRefused = refuses (hasFn drv);
      nestedDrv = hasFn {
        tag = "x";
        pkg = drv;
      };
      # Control: the short-circuit is the DERIVATION's, not the whole body's — a function beside it is
      # still reported.
      lambdaBesideDrvIsFound = hasFn {
        pkg = drv;
        f = x: x;
      };
    };
    expected = {
      bareDrv = false;
      bareDrvNotRefused = false;
      nestedDrv = false;
      lambdaBesideDrvIsFound = true;
    };
  };

  flake.tests.has-fn-guard.test-depth-budget-refuses-at-its-bound = {
    # The bound is READ from the library, never restated: a cell carrying its own copy of the number
    # keeps passing after the budget moves, testing a bound that no longer exists.
    expr = {
      overBudget = refuses (hasFn (chain (hasFnMaxDepth + 8)));
      # The same chain shape UNDER the bound walks clean — so `overBudget` is the depth being spent
      # and not the chain being unwalkable.
      withinBudget = hasFn (chain (hasFnMaxDepth - 8));
      # …and the walk genuinely reaches the bottom of one, rather than answering `false` early: a
      # lambda placed at the far end of a within-budget chain is still found.
      withinBudgetReachesTheBottom = hasFn (chainTo (x: x) (hasFnMaxDepth - 8));
    };
    expected = {
      overBudget = true;
      withinBudget = false;
      withinBudgetReachesTheBottom = true;
    };
  };

  flake.tests.has-fn-guard.test-refusal-names-itself = {
    # Nix cannot recover a thrown message through `tryEval`, so catchability is asserted on the real
    # path (above) and message CONTENT here, on the renderer that path throws.
    expr = {
      namesTheLibrary = containsSub "gen-aspects" hasFnDepthRefusal;
      namesWhatWasExhausted = containsSub "depth budget" hasFnDepthRefusal;
      # Rendered FROM the constant, so the message cannot go stale against the bound it reports.
      carriesTheBound = containsSub (toString hasFnMaxDepth) hasFnDepthRefusal;
      saysWhatHappensInstead = containsSub "guard-loc:" hasFnDepthRefusal;
      scanDiscriminates = containsSub "no-such-token-in-this-message" hasFnDepthRefusal;
    };
    expected = {
      namesTheLibrary = true;
      namesWhatWasExhausted = true;
      carriesTheBound = true;
      saysWhatHappensInstead = true;
      scanDiscriminates = false;
    };
  };

  flake.tests.has-fn-guard.test-guard-key-survives-a-cyclic-body = {
    # THE CONSUMER-VISIBLE PROPERTY, on the public path the defect was found through. Minting a key
    # for a guard whose body is cyclic used to abort the evaluator uncatchably; it now takes the
    # opaque-body branch — the same answer that path already gives any body it cannot content-address
    # — and the two bodies it CAN answer for are unchanged beside it.
    expr = {
      cyclicKey = aspects.guardKey (aspects.guard aspects.pred.always cyclic);
      cyclicKeyDoesNotAbort = refuses (aspects.guardKey (aspects.guard aspects.pred.always cyclic));
      inertIsStillContentAddressed = lib.hasPrefix "guard:always:" (
        aspects.guardKey (aspects.guard aspects.pred.always inertPayload)
      );
      lambdaBodyStillFallsBack = lib.hasPrefix "guard-loc:" (
        aspects.guardKey (aspects.guard aspects.pred.always lambdaPayload)
      );
      # The derivation arm end to end: it used to abort here, and now content-addresses.
      drvBodyIsContentAddressed = lib.hasPrefix "guard:always:" (
        aspects.guardKey (aspects.guard aspects.pred.always drv)
      );
    };
    expected = {
      cyclicKey = "guard-loc:<anon>";
      cyclicKeyDoesNotAbort = false;
      inertIsStillContentAddressed = true;
      lambdaBodyStillFallsBack = true;
      drvBodyIsContentAddressed = true;
    };
  };
}
