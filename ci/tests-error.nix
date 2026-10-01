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
  mkSchemaEval,
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
    # ── FALSIFIERS: the bound, pinned where a reader meets it. GREEN = RED = these aborts — except
    # the RETURN bound below, which gen-merge now refuses catchably (a ThrownError, not an abort). ──
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
    # gen-merge's module reader's contract — now a catchable refusal (gen-merge 1420cb7's third
    # `moduleSyntaxChecked` arm), not an abort, so the headline's own message still surfaces here.
    test-refused-module-fn-self-returning = thrown ((aspects.wrapFn wcnf "n" (_: modSelf)) wctx) (
      exactly "gen-merge: module `<wrapFn>' is a function whose result is lambda, not an attribute set. A module function is applied once, to the module arguments, and must return the module itself; a function that returns another function (`a: b: { … }`) is not a module."
    );
  };
  # den-hoag-7gp66 P1: the closed doors' shared checks, message pinned on the real path.
  flake.testsError.doors =
    let
      gated = "gen-aspects.wrapGatedFn";
      schema = aspects.mkAspectSchema { };
      unknown =
        door: accepted:
        exactly "${door}: 'notAnOption' is not an option of this door; the options are closed (accepted: ${accepted}) (in prelude.checkOptions)";
    in
    {
      test-wrap-gated-fn-missing = thrown (aspects.wrapGatedFn { name = "n"; }) (
        exactly "${gated}: required field 'functionArgs' is missing (required: 'functionArgs') (in prelude.checkRequired)"
      );
      test-wrap-gated-fn-unknown = thrown (aspects.wrapGatedFn {
        functionArgs = { };
        notAnOption = 1;
      }) (unknown gated "'functionArgs', 'name', 'meta', 'onResult'");
      test-mk-aspect-option-unknown = thrown (schema.mkAspectOption { notAnOption = 1; }) (
        unknown "gen-aspects.mkAspectSchema.mkAspectOption" "'providerPrefix'"
      );
      test-mk-aspect-module-unknown = thrown (schema.mkAspectModule { notAnOption = 1; }) (
        unknown "gen-aspects.mkAspectSchema.mkAspectModule" "'providerPrefix'"
      );
      test-mk-namespace-type-unknown = thrown (schema.mkNamespaceType { notAnOption = 1; }) (
        unknown "gen-aspects.mkAspectSchema.mkNamespaceType" ""
      );
    };

  # den-hoag-7gp66 P1: an include reference resolved by `prelude.resolve`, refused naming the door,
  # the aspect and the include position first.
  flake.testsError.includes-resolve =
    let
      tree =
        elems:
        mkSchemaEval {
          fixtureKeySemantics.nixos.category = "class";
          modules = [
            (
              { config, ... }:
              {
                config.aspects.lib.base.nixos.networking.domain = "b";
                config.aspects.app.includes = elems config;
              }
            )
          ];
        };
      read = elems: (aspects.graphFacts { } (tree elems).config.aspects).includesOf.app;
      door = "gen-aspects.includes (aspect 'app', include position 0): ";
      notMember =
        h:
        exactly "${door}declaration '${h}' is not a member of the registry (available: 'app', 'lib', 'lib/base') (in prelude.resolve)";
      a = (tree (_: [ ])).config.aspects;
    in
    {
      # 6-c: a member re-keyed to spell another member.
      test-rekeyed-member = thrown (read (config: [ (config.aspects.lib.base // { key = "app"; }) ])) (
        notMember "app"
      );
      # gate C1: a stampless value naming a real member (handed to graphFacts directly — the include
      # element type re-mints the stamp from the value's own identity).
      test-stampless-real-member =
        thrown
          (aspects.graphFacts { } (
            a
            // {
              app = a.app // {
                includes = [ (removeAttrs a.lib.base [ "id_hash" ]) ];
              };
            }
          )).includesOf.app
          (notMember "lib/base");
      # A value from another tree whose key names no node here.
      test-key-naming-no-node = thrown (read (_: [ { key = "no/such"; } ])) (notMember "no/such");
      test-bare-string-naming-nothing = thrown (read (_: [ "lib/bsae" ])) (
        exactly "${door}reference 'lib/bsae' names no entry of the registry (in prelude.resolve)"
      );
    };

  # den-hoag-661s2: the closed-key gate names the aspect beside the key, on both of its refusals.
  flake.testsError.closed-key-names-aspect =
    let
      gated =
        extra: body:
        (mkSchemaEval (
          {
            closedKeys = true;
            keySemantics.nixos.category = "class";
            modules = [ { config.aspects.hem = body; } ];
          }
          // extra
        )).config.aspects.hem;
    in
    {
      test-open-gate = thrown (gated { } { nixso.boot = { }; }).nixso (
        exactly "gen-aspects: aspect `hem`: undeclared aspect key 'nixso' (closed-key gate on; declare it in keySemantics or list it in freeformKeys)"
      );
      # An inline `includes` element is gated by the same submodule, and is named by its position.
      test-open-gate-include =
        thrown (builtins.head (gated { } { includes = [ { nixso.x = 1; } ]; }).includes).nixso
          (
            exactly "gen-aspects: aspect `hem.includes.0`: undeclared aspect key 'nixso' (closed-key gate on; declare it in keySemantics or list it in freeformKeys)"
          );
      test-recursive-gate = thrown (gated { recursiveClosed = true; } { ns.nixso = "x"; }).ns.nixso (
        exactly (
          "gen-aspects: aspect `hem.ns`: undeclared aspect key 'nixso' (value is not a nested aspect — a closed "
          + "aspect vocabulary admits an undeclared key only as a namespace attrset that recurses to a "
          + "declared class/channel/facet; a primitive/function/list value here is a typo or misplaced "
          + "content). Declare it in keySemantics, or nest it under a declared key."
        )
      );
      test-bare-module-include =
        thrown
          (builtins.head
            (mkSchemaEval {
              rejectBareModuleInclude = true;
              modules = [ { config.aspects.hem.includes = [ { imports = [ { } ]; } ]; } ];
            }).config.aspects.hem.includes
          )
          (
            exactly (
              "gen-aspects: includes element is a bare module ({ imports = [ … ]; }) with no aspect identity — "
              + "a class-content node included AS an aspect? An include must be an aspect (by value or fixpoint "
              + "ref), a keyRef, or a deferred fn/policy; `imports` is the module merge slot, never an aspect "
              + "content key."
            )
          );
    };

  # den-hoag-q17cc · a construction formal written at the kind entry's top level. Before the door each
  # evaluated at exit 0 and landed on EVERY aspect as a nested aspect, while the kind's own formal
  # stayed what the constructor fixed. Each cell reads the instance's key set, the read that used to
  # show the landed key, and never forces the landed value itself (it is self-similar).
  flake.testsError.construction-formal-refusals =
    let
      barKeysWith =
        entry:
        builtins.attrNames
          (mkSchemaEval {
            modules = [
              {
                config.schema.aspect = entry;
                config.aspects.bar = { };
              }
            ];
          }).config.aspects.bar;
    in
    {
      # G1 · a formal both libraries take: gen-schema's door answers, because its check wraps this
      # library's whole `mkType` result.
      test-shared-formal-gets-gen-schema-text =
        thrown (barKeysWith { keySemantics.darwin.category = "class"; })
          (
            exactly "gen-schema: kind 'aspect': declaration key 'keySemantics' is a construction formal of this schema — it is fixed by the call that builds the schema option (`mkSchemaOption`, `mkSchemaEntryType`), and written on a kind entry it is not read as one; pass 'keySemantics' to that constructor, or write `config.keySemantics` for an instance field of that name, which a strict instance must declare as an option"
          );

      # G2 · a formal only mkAspectSchema takes.
      test-cnf-formal-refuses-by-name = thrown (barKeysWith { providerPrefix = [ ]; }) (
        exactly "gen-aspects: kind 'aspect': declaration key 'providerPrefix' is an mkAspectSchema construction formal — it is fixed by `mkAspectSchema { providerPrefix = …; }`, and written on a kind entry it is not read as one; pass it there, or write `config.providerPrefix` for an instance field of that name, which a `closedKeys` schema must declare or list in `freeformKeys`"
      );

      # C2 on this path · a name gen-schema writes onto the kind value.
      test-published-name-refuses-on-this-path = thrown (barKeysWith { refs.forged = 1; }) (
        exactly "gen-schema: kind 'aspect': declaration key 'refs' is a name gen-schema writes onto the kind value — written on a kind entry it lands on every instance, while reading `config.schema.aspect.refs` returns the published one; write `config.refs` for an instance field of that name, which a strict instance must declare as an option"
      );

      # G7 · a collection named for a cnf formal.
      test-collection-named-for-a-formal-is-reserved =
        thrown
          (builtins.attrNames
            (mkSchemaEval {
              collections.providerPrefix.default = [ ];
              modules = [ { config.schema.aspect = { }; } ];
            }).config.schema.aspect
          )
          (
            exactly "gen-aspects: mkAspectSchema: collection 'providerPrefix' is reserved — it is an mkAspectSchema construction formal"
          );
    };
}
