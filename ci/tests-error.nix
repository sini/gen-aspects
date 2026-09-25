# THE SECOND TEST OUTPUT — cells whose subject is an ERROR MESSAGE.
#
# `tryEval` discards a thrown text, so it can assert THAT a door refuses and never WHAT it says.
# `expectedError` asserts the message. These cells cannot live in `flake.tests`: the batch asserter
# behind `checks.default` forces every `expr` there unconditionally, so a throwing cell crashes that
# gate instead of failing. This file sits outside `./tests` (the whole of `testModules`), so the split
# is structural. `expectedError.msg` is SEARCHED, not whole-matched, so every pattern is anchored at
# both ends and built by escaping the literal text.
#
#   nix-unit --flake ./ci#testsError
{
  lib,
  aspects,
  genMerge,
  ...
}:
let
  exactly = msg: "^" + lib.escapeRegex msg + "$";
  # den-hoag-khnhi: the raw-closure applicators' doors (lib/require-wrapped-closure.nix).
  wcnf.keySemantics.classOne.category = "class";
  wctx.host = "cortex";
  selfF =
    let
      f = _: f;
    in
    f;
  modSelf = { lib, ... }: modSelf;
  native =
    v:
    (aspects.aspectType wcnf).merge
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
    (aspects.aspectType wcnf).merge
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
  d1 =
    entry: at: detail:
    exactly (
      "gen-aspects.${entry}: the value wrapped at ${at} must be a raw closure `ctx: <aspect>`; ${detail}. "
      + "Pass the closure itself: the wrap is what makes a closure inspectable, so a value that is "
      + "already a wrap, or is not a closure at all, has nothing to wrap."
    );
  d2 =
    entry: at: detail:
    exactly (
      "gen-aspects.${entry}: the closure at ${at} must return aspect content, an attrset or a module "
      + "function of the declared `cnf.moduleArgs`; ${detail}. Return the aspect attrset itself. A closure "
      + "returning another closure is under-applied: it is applied to ONE context and its result merged, "
      + "so a second parameter is never supplied."
    );
  d3 =
    entry: at: missing: carries:
    exactly (
      "gen-aspects.${entry}: the closure at ${at} requires context coord(s) `${missing}` that the applied "
      + "context does not carry (context carries: ${carries}). Supply them, or give the formal a default "
      + "so the closure can run without it."
    );
  fnRet =
    formals:
    "returned a function whose formals are not module args (`${formals}`; "
    + "empty means a bare formal or an ellipsis-only pattern `{ ... }:`, which cannot be told apart; "
    + "a module function names a module arg it reads, as in `{ config, ... }:`)";
  thrown = expr: msg: {
    expr = builtins.deepSeq expr null;
    expectedError = {
      type = "ThrownError";
      inherit msg;
    };
  };
  schemaBad = aspects.mkAspectSchema { keySemantics.bad.category = "bogus"; };
  refusal =
    got:
    exactly (
      "gen-aspects.keyRef: got ${got}, expected a reference: an origin-qualified string "
      + "(\"<origin>/<path>\") or { path; origin ? [ ]; }, each a \"/\"-joined string or a list of strings"
    );
  # deepSeq, so a refusal left lazy inside a field still reaches the cell.
  cell = ref: got: {
    expr = builtins.deepSeq (aspects.keyRef ref) null;
    expectedError = {
      type = "ThrownError";
      msg = refusal got;
    };
  };
in
{
  # One cell per shape the door refuses (den-hoag-bkdkg). Each aborted uncaught before the guard:
  # `attribute 'path' missing`, `expected a list but found an integer`, `cannot coerce a set to a
  # string`; a bad `origin` was admitted and aborted downstream in gen-link.
  flake.testsError.key-ref-refusal = {
    test-set-without-path = cell { name = "a"; } "a set with no 'path' field";
    test-int = cell 3 "int";
    test-path-int = cell { path = 3; } "path = int";
    test-path-list-of-set = cell { path = [ { name = "a"; } ]; } "path = list holding a non-string";
    test-origin-int = cell {
      path = "s";
      origin = 3;
    } "origin = int";
    test-origin-list-of-set = cell {
      path = "s";
      origin = [ { } ];
    } "origin = list holding a non-string";
    # `splitSlash` drops empty segments, so these reached `builtins.head [ ]` (den-hoag-6c5s3).
    test-empty-string = cell "" "the string \"\", which has no non-empty segment";
    test-all-slash = cell "/" "the string \"/\", which has no non-empty segment";
    test-all-slashes = cell "///" "the string \"///\", which has no non-empty segment";
  };

  # den-hoag-2ejx: a malformed keySemantics category refuses BY NAME at the key that carries it, and
  # only there (an unrelated aspect's `name` read returns; ci/tests/key-semantics.nix (7)).
  flake.testsError.key-semantics-lazy-refusal.test-carrier-bad-category = {
    expr =
      builtins.deepSeq
        (genMerge.evalModuleTree {
          modules = [
            { options.schema = schemaBad.schemaOption; }
            (schemaBad.mkAspectModule { })
            { config.aspects.carrier.bad.x = 1; }
          ];
        }).config.aspects.carrier.bad
        null;
    expectedError = {
      type = "ThrownError";
      msg = exactly "gen-aspects: keySemantics key 'bad' has unknown category 'bogus' (expected class|channel|facet)";
    };
  };

  # den-hoag-plm1h: `aspectsRoot(port) ∥ aspectsRoot(int)` is refused BY NAME at the declaration.
  flake.testsError.root-element-join-refusal.test-port-int =
    let
      rootWith = (aspects.aspectsRoot { keySemantics.a.category = "class"; }).functor.type;
      res = genMerge.evalModuleTree {
        modules = [
          { options.p = genMerge.mkOption { type = rootWith lib.types.port; }; }
          { options.p = genMerge.mkOption { type = rootWith lib.types.int; }; }
          { p.a = 70000; }
        ];
      };
    in
    {
      expr = res.options.p.type.name;
      expectedError = {
        type = "ThrownError";
        msg = exactly (
          "gen-merge: option `p' is declared with types that do not merge (`aspectsRoot' and "
          + "`aspectsRoot', which the first type's own `functor' does not reconcile); "
          + "declared in <gen-merge>, <gen-merge>"
        );
      };
    };

  # den-hoag-khnhi: each mode of a caller-supplied closure at the raw-closure applicators is refused
  # BY NAME at this library's door. Every RED here was an interpreter abort minted in gen-merge (or a
  # silent success), named in the cell's comment.
  flake.testsError.wrap-totality = {
    # RED: `expected a set but found a function` (TypeError, gen-merge `configOf`), uncatchable.
    test-wrapfn-self-returning = thrown ((aspects.wrapFn wcnf "n" selfF) wctx) (
      d2 "wrapFn" "`n`" (fnRet "")
    );
    # The same cell's catchability, evaluator-neutral (the runner cannot read `type`). RED: rc 1.
    test-wrapfn-self-returning-caught = {
      expr = (builtins.tryEval (builtins.deepSeq ((aspects.wrapFn wcnf "n" selfF) wctx) null)).success;
      expected = false;
    };
    # RED ×4: gen-merge's own refusal, `option `n.<function body>' has definitions `submodule' cannot consume (<wrapFn>)`.
    test-wrapfn-returns-int = thrown ((aspects.wrapFn wcnf "n" (_: 42)) wctx) (
      d2 "wrapFn" "`n`" "returned: int"
    );
    test-wrapfn-returns-string = thrown ((aspects.wrapFn wcnf "n" (_: "s")) wctx) (
      d2 "wrapFn" "`n`" "returned: string"
    );
    test-wrapfn-returns-list = thrown (
      (aspects.wrapFn wcnf "n" (_: [
        1
        2
      ]))
        wctx
    ) (d2 "wrapFn" "`n`" "returned: list");
    test-wrapfn-returns-null = thrown ((aspects.wrapFn wcnf "n" (_: null)) wctx) (
      d2 "wrapFn" "`n`" "returned: null"
    );
    # RED: no error; a well-formed aspect materialises, its residual handed the module args.
    test-wrapfn-under-applied = thrown ((aspects.wrapFn wcnf "n" (p: q: { description = "x"; })) wctx) (
      d2 "wrapFn" "`n`" (fnRet "")
    );
    # RED: no error at WHNF; the field is a poisoned thunk (`module argument `host' is not defined`).
    test-wrapfn-under-applied-context-residual = thrown (
      (aspects.wrapFn wcnf "n" (p: { host, ... }: { description = host; }))
        wctx
    ) (d2 "wrapFn" "`n`" (fnRet "host"));
    # RED ×4: no error; `.name` answers "n" / "o" / "o" / "o" (a latent record).
    test-wrapfn-input-int = thrown (aspects.wrapFn wcnf "n" 42).name (
      d1 "wrapFn" "`n`" "received: int"
    );
    test-wrapfn-input-wrap-record =
      thrown (aspects.wrapFn wcnf "o" (aspects.wrapFn wcnf "i" (_: { }))).name
        (
          d1 "wrapFn" "`o`"
            "received a wrap record already built; pass it at the `includes` position rather than wrapping it again"
        );
    test-wrapfn-input-guard-record = thrown (aspects.wrapFn wcnf "o" (gv.vocab.always { })).name (
      d1 "wrapFn" "`o`"
        "received a defunctionalised guard record (`gen-aspects.guard`); it rides the `includes` position as first-order data and is never wrapped"
    );
    test-wrapfn-input-attrset = thrown (aspects.wrapFn wcnf "o" { some = "attrs"; }).name (
      d1 "wrapFn" "`o`" "received an attrset no wrap constructor built"
    );
    # RED: `function 'anonymous lambda' called without required argument 'x'`, uncatchable.
    test-wrapfn-missing-coord = thrown ((aspects.wrapFn wcnf "myFn" ({ x }: { description = x; }))
      wctx
    ) (d3 "wrapFn" "`myFn`" "x" "host");
    # RED: `expected a set but found a string`, uncatchable (and the v0 door's own renderer aborted here).
    test-wrapfn-context-not-attrset =
      thrown ((aspects.wrapFn wcnf "n" ({ x }: { description = x; })) "s")
        (
          exactly "gen-aspects.wrapFn: the closure at `n` was applied to a value of type string, not a context; a context is an attrset of coords."
        );
    # THE NATIVE PATH (aspectType's merge → wrapGuardFn): the same doors, naming the aspect's loc.
    # RED: the wrapFn headline's abort, uncatchable.
    test-native-self-returning = thrown ((native selfF) wctx) (d2 "aspectType" "aspect `n`" (fnRet ""));
    # RED: no error, "x".
    test-native-under-applied = thrown ((native (p: q: { description = "x"; })) wctx) (
      d2 "aspectType" "aspect `n`" (fnRet "")
    );
    # RED: `called without required argument 'x'`, uncatchable.
    test-native-missing-coord = thrown ((native ({ x }: { description = x; })) wctx) (
      d3 "aspectType" "aspect `n`" "x" "host"
    );
    # THE MULTI-DEF CARRIER's function fragment (guard.nix `dischargeFragment`): the context door.
    # RED: `called without required argument 'x'`, uncatchable.
    test-carrier-fn-missing-coord = thrown (aspects.applyGuard wctx (
      carrier ({ x }: { description = x; })
    )) (d3 "guard" "aspect `n`" "x" "host");
    # `applyGuard`'s ESCAPE-HATCH arm (a raw closure, reached via `cnf.deferIncludeResolution`): the
    # context door. RED: `called without required argument 'x'`, uncatchable.
    test-hatch-missing-coord = thrown (aspects.applyGuard wctx ({ x }: { description = x; })) (
      d3 "guard" "`applyGuard`" "x" "host"
    );
    # N3, a NAMED narrowing: an ellipsis-only module-function return `{ ... }:` has the same
    # `functionArgs` as a bare formal, so admitting it would re-admit the headline. RED ×2: no error, "m".
    test-wrapfn-ellipsis-only-return = thrown (
      (aspects.wrapFn wcnf "n" (_: ({ ... }: { description = "m"; })))
        wctx
    ) (d2 "wrapFn" "`n`" (fnRet ""));
    test-native-ellipsis-only-return = thrown ((native (_: ({ ... }: { description = "m"; }))) wctx) (
      d2 "aspectType" "aspect `n`" (fnRet "")
    );
    # wrapGatedFn's two caller functions. RED ×2: `attempt to call something which is not a function but an integer: 42`.
    test-gated-fn-not-callable = thrown ((aspects.wrapGatedFn { functionArgs.host = false; } 42) wctx) (
      exactly "gen-aspects.wrapGatedFn: the value wrapped at `<gated>` must be callable (a function, or a record carrying `__functor`); received: int."
    );
    test-gated-onresult-not-callable =
      thrown
        (
          (aspects.wrapGatedFn {
            functionArgs.host = false;
            onResult = 42;
          } ({ host, ... }: { }))
            wctx
        )
        (
          exactly "gen-aspects.wrapGatedFn: `onResult` at `<gated>` must be callable (a function, or a record carrying `__functor`); received: int."
        );
    # ── FALSIFIERS: the bound, pinned where a reader meets it. GREEN = RED = these aborts. ──
    # M4b: a closed pattern given an extra coord. `functionArgs` erases the ellipsis, so no door can
    # see it (the erasure itself is a flake.tests cell, wrap-fn.nix). A refusal here = over-reach.
    test-falsifier-closed-pattern-extra-coord = {
      expr = builtins.deepSeq ((aspects.wrapFn wcnf "n" ({ x }: { description = x; })) {
        x = "a";
        y = "b";
      }) null;
      expectedError = {
        type = "TypeError";
        msg = "^" + lib.escapeRegex "function 'anonymous lambda' called with unexpected argument 'y'";
      };
    };
    # The RETURN bound: a module-function return is admitted one level, and what IT returns is
    # gen-merge's module reader's contract, so the headline's own message survives here.
    test-falsifier-module-fn-self-returning = {
      expr = builtins.deepSeq ((aspects.wrapFn wcnf "n" (_: modSelf)) wctx) null;
      expectedError = {
        type = "TypeError";
        msg = "^" + lib.escapeRegex "expected a set but found a function: «lambda modSelf";
      };
    };
  };
}
