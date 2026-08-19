# gen-aspects — agent capability sheet

## Scope

Aspect-oriented composition types: a flat option type (`aspectType`) that dispatches by value shape in
merge, giving every aspect a path-derived identity (`key`, `id_hash`), one declared-key classification
surface (`keyCategory` over class/channel/facet), a defunctionalized guard vocabulary, and a flat
registry for downstream graph queries.

## Not this library's job

Quoted text is the owner's own `flake.nix` `description` field, verbatim.

| Responsibility | Owner |
|---|---|
| The module system itself — `evalModuleTree`, `mkOption`, `mkMerge`, `submodule`, `mkOptionType`, `mergeDefs`. gen-aspects builds every option and type through the injected `merge` argument | `gen-merge` — "gen-merge — pure-Nix byte-mode module MERGE engine (evalModuleTree) for the pure-gen module system" |
| Leaf type checking (`str`, `listOf`, `raw`, `lazyAttrsOf`, `deferredModule`) — reached only as `merge.types` | `gen-types` — "gen-types: pure, nixpkgs-lib-free structural type checker for the gen ecosystem" |
| Minting identity hashes and kind/registry infrastructure. gen-aspects consumes exactly two gen-schema names: `hashIdentity` (`lib/default.nix`, the `inherit (schema) hashIdentity` passed into `types.nix`) and `mkSchemaOption` (`lib/schema.nix`'s `schemaOpt`) | `gen-schema` — "gen-schema: typed record registry with extension points for the pure-gen module system" |
| General utilities (`concatStringsSep`, `genAttrs`, `filterAttrs`, `foldl'`, `last`, `init`, `functionArgs`) | `gen-prelude` — "gen-prelude: vendored, nixpkgs-lib-free pure utilities for the gen ecosystem" |
| Resolving a `keyRef` against a merged cross-origin graph; federating aspects across flakes | `gen-link` — "gen-link: cross-flake aspect federation over origin-labeled subgraphs". `lib/types.nix`'s `includesElemType` states the type passes `__keyRef` through opaquely for gen-link to resolve |
| Predicates over graph positions (matching aspects by attribute, kind, or tree position) | `gen-select` — "gen-select: selector algebra for attributed graph positions" |
| Choosing which of several matching rules wins; ordering and conflict resolution | `gen-dispatch` — "gen-dispatch: relational rule dispatch over ordered groups (the dispatch STEP)" |
| Traversal and query combinators over the facts `graphFacts` publishes (`labeledFrom`, `fromRegistry`, `materializeParents`, `query`) | `gen-graph` — "gen-graph: accessor-based graph query combinators". gen-aspects does NOT import it: the query libraries query a graph, they do not state one |
| Demand-driven attribute evaluation over scope graphs | `gen-scope` — "gen-scope: demand-driven attribute grammar evaluator over algebraic scope graphs" |
| Class partition / contract / apply / gate machinery. `keySemantics.<k>.category = "class"` only declares the key as a `deferredModule` bucket; nothing here interprets class content | `gen-class` — "gen-class — pure-Nix class-share mechanism (partition / contract / apply / gate) for the pure-gen module system" |
| Layered settings resolution and precedence | `gen-settings` — "gen-settings — stratified settings resolution as a pure layered fold, with refs-as-data, structured provenance, and the graduated injection construct" |
| Channels as dataflow. A `channel`-category key here is a raw passthrough option, not a pipe | `gen-pipe` — "gen-pipe — scoped channels + dataflow algebra (map/filter/fold/scan/route/join/tee) with B5 determinism, provenance, dedup, and class-aware contributions" |

## Exports

Entry: `inputs.gen-aspects.lib` (flake). Root `default.nix` is a function of `{ prelude, merge, schema }`,
each defaulting to a `fetchTree` of the flake-locked rev, so `import ./. { }` self-constructs.

**Types** — `lib/types.nix`

| Export | Signature |
|---|---|
| `aspectType` | `cnf -> optionType` — the flat dispatch-in-merge type |
| `aspectSubmodule` | `cnf -> optionType` — one aspect entry (structural options + declared keys + freeform) |
| `aspectsType` | `cnf -> optionType` — top container submodule; sets `_module.args.aspects` |
| `aspectsRoot` | `cnf -> optionType` — the re-rooting container element type |
| `aspectOrFn` | `cnf -> optionType` — `either aspectType aspectSubmodule` |

**Closure wraps** — `lib/types.nix`

| Export | Signature |
|---|---|
| `wrapFn` | `cnf -> name -> fn -> wrappedRecord` (`__isWrappedFn`) |
| `wrapGatedFn` | `{ functionArgs, name ? "<gated>", meta ? {}, onResult ? id } -> fn -> wrappedRecord` |

**Identity** — `lib/identity.nix`, `lib/types.nix`

| Export | Signature |
|---|---|
| `aspectId` | `[originSeg] -> aspect -> hash` — the canonical content-address for all three aspect kinds |
| `key` | `aspect -> string` — 3-way dispatch: `__guard` ⇒ `guardKey`, `__isWrappedFn` ⇒ `pathKey meta.loc`, else `pathKey (aspectPath a)` |
| `guardKey` | `guardRecord -> string` |
| `aspectPath` | `aspect -> [string]` (`meta.aspect-chain ++ [ name ]`) |
| `pathKey` | `[string] -> string` (`"/"`-joined) |
| `isMeaningfulName` | `string -> bool` |
| `keyRef` | `string | { origin, path } -> { __keyRef, origin, path, key }` |

**Key classification** — `lib/types.nix`

| Export | Signature |
|---|---|
| `keyCategory` | `cnf -> key -> "structural" \| "class" \| "channel" \| "facet" \| null` |
| `structuralKeys` | `[string]` — the six native structural option names (a value, not a function) |

**Guard vocabulary** — `lib/guard.nix`

| Export | Signature |
|---|---|
| `guard` | `pred -> body -> { __guard = true; pred; body; }` |
| `pred` | `{ host, class, user, tagEq, eq, all, any, always, custom }` — `pred.always` is a value; `pred.all`/`any` take `[pred]`; `pred.custom` takes `formName -> args` |
| `toArgData` | `attrset -> attrset` — first-order type tagging (`{ __t; v; }`) |
| `mkGuardVocab` | `cnf -> { pred, guard, fires, evalPred, vocab, applyGuard }` |
| `mkGuardVocab cnf` `.vocab` | `{ whenHost, whenClass, whenUser, whenTagEq, whenEq, whenAll, whenAny, always }` — each is `args -> body -> guardRecord` |
| `applyGuard` | `ctx -> guardRecord \| closure \| wrappedFn -> value` — the top-level binding is `(mkGuardVocab { }).applyGuard`, i.e. the base vocab with no `cnf.guardForms` |

**Introspection and registry** — `lib/can-take.nix`, `lib/walk.nix`, `lib/flatten.nix`, `lib/facts.nix`

| Export | Signature |
|---|---|
| `canTake` | `{ atLeast, upTo }` — each `params -> fn -> bool` |
| `mkIsModuleFn` | `cnf -> fn -> bool` (= `canTake.upTo (cnf.moduleArgs or defaults)`) |
| `flatten` | `aspects -> { "<path/key>" = aspect; … }` (a bare value; takes no dependency argument). The key is a RENDERING of a parent edge, never the edge — do not split it |
| `graphFacts` | `cnf -> aspects -> { nodes; parentOf; includesOf; unresolvedIncludesOf; nodeData; }` — the aspect graph's facts as plain data, keyed by the origin-qualified WALK key (`pathKey (cnf.providerPrefix ++ walkPath)`). `parentOf` is that same walk position's parent — the id and the edge come from ONE source — total over `nodes`, `null` meaning root and only root, total BY CONSTRUCTION (the walk descends only into what it emits) so nothing dangles and no refusal guards it. `includesOf` emits only LOCALLY-QUALIFIED targets that ARE nodes; a FOREIGN keyRef deliberately emits a target outside `nodes`, because it names a node in a fixpoint this library does not hold and the framework that unions providers is what resolves it — that is what `keyRef` is for. `unresolvedIncludesOf` names the declared positions holding inline content instead of a reference. ONE refusal: a keyRef carrying this tree's own origin whose target is not a node |

**Schema bridge** — `lib/schema.nix`

| Export | Signature |
|---|---|
| `mkAspectSchema` | `cnf -> schemaRecord` |
| `schemaRecord.schemaOption` | option built from `genSchema.mkSchemaOption` |
| `schemaRecord.mkAspectOption` | `{ providerPrefix ? [] } -> option` |
| `schemaRecord.mkAspectModule` | `{ providerPrefix ? [] } -> module` — declares `options.aspects` and injects `config.schema.aspect.__defsModule` into `aspectModules` |
| `schemaRecord.mkNamespaceType` | `{ } -> optionType` |
| `schemaRecord.keyCategory` | `key -> category` — `keyCategory` already closed over this schema's `cnf` |
| `schemaRecord.identity` | `{ aspectPath, pathKey, key, isMeaningfulName }` |
| re-exports | `aspectType`, `aspectPath`, `pathKey`, `key`, `isMeaningfulName`, `canTake`, `mkIsModuleFn` |

**`cnf` contract** (consumed, not exported). Every type constructor takes one `cnf` attrset:
`keySemantics : { <key> = { category = "class" | "channel" | "facet"; option ? ; module ? ; }; }`,
`aspectModules : [module]`, `metaModules : [module]`, `moduleArgs : { <arg> = bool; }`,
`providerPrefix : [string]`, `collections`, and five booleans — `closedKeys`, `recursiveClosed`,
`deferIncludeResolution`, `rejectBareModuleInclude`, plus `freeformKeys : [string]`. `mkGuardVocab`
additionally reads `cnf.guardForms : { <name> = { eval = ctx: argData: bool; reads = [[attrPath]]; }; }`.

**Record markers** (produced and consumed, not exports): `__guard` (defunctionalized guard record),
`__isWrappedFn` + `__functionArgs` (raw-closure functor wrap), `__keyRef` (out-of-fixpoint reference),
`__defsModule` (gen-schema instance-option seam), `__isPolicy` / `__fn` / `__denCanTake` (recognized only
as deferred-include markers under `cnf.deferIncludeResolution` — `lib/types.nix`'s `includesElemType`, its `isDeferredInclude`).

## Entry points by task

| Task | Reach for |
|---|---|
| Declare an aspect option inside a module | `(mkAspectSchema cnf).mkAspectModule { }` |
| Declare it as a bare option instead | `(mkAspectSchema cnf).mkAspectOption { }` — no `__defsModule` injection |
| Declare a key as a class/channel/facet | `cnf.keySemantics.<key>.category` |
| Add an option to every aspect instance | `cnf.aspectModules` (this is also the reserved-key route) |
| Add an option to every aspect's `meta` | `cnf.metaModules` |
| Ask what category a key has | `keyCategory cnf key`, or `(mkAspectSchema cnf).keyCategory key` |
| Content-address an aspect of any kind | `aspectId origin aspect` |
| Read one aspect's path key | `aspect.key` (option) or `key aspect` (bare records) |
| Reference an aspect outside the local fixpoint | `keyRef "origin/a/b"` in `includes` |
| Write a context-conditional aspect | `(mkGuardVocab cnf).vocab.whenHost "h" { … }` |
| Add a project-specific guard predicate | `cnf.guardForms.<name> = { eval; reads; }` then `pred.custom "<name>" args` |
| Fire a guard against a context | `applyGuard ctx g` (base vocab) or `(mkGuardVocab cnf).applyGuard` |
| Wrap a programmatically generated closure include | `wrapFn cnf name fn` |
| Wrap one that must be inert on missing coords | `wrapGatedFn { functionArgs; onResult ? ; } fn` |
| Classify a function as module-fn vs guard-fn | `mkIsModuleFn cnf fn` |
| Hand the aspect tree to a graph query | `graphFacts cnf aspects` (NOT `flatten` — parenthood is a published relation, not a substring of the key) |
| Reject undeclared aspect keys | `cnf.closedKeys = true` (+ `freeformKeys` / `recursiveClosed`) |

## Measured traps

Verified at rev `1689e41` by evaluating against `aspects = import ./. { }` with these shared fixtures:
`ok e = (builtins.tryEval (builtins.deepSeq e e)).success`; `mkEval cnf modules` mirrors
`ci/flake.nix`'s `mkSchemaEval` (`mkAspectSchema` + `mkAspectModule { }` through
`genMerge.evalModuleTree`, `keySemantics.classOne.category = "class"` unless a row says otherwise);
`ctx = { host.name = "h1"; class = "nixos"; user.name = "u"; tags.t = "v"; }`;
`gHost = aspects.guard (aspects.pred.host "h1") { classOne = { }; }`.

The behaviours are as verified at that rev. The **anchors** below were re-derived against `7b11e80`
and now name bindings rather than line ranges, for the reason stated next; re-deriving them is not a
re-run of the evidence.

**Cites into `lib/` are by BINDING NAME, never by line range.** Grep the name. Every range this file
used to carry was re-derived against the tree it describes and every one had drifted, most of them
onto unrelated code while the prose around them stayed true — a reader chasing a drifted range either
finds nothing or, worse, finds a plausible neighbour and closes a live finding against it. A name can
go stale too — rename the binding and it dangles — but it dangles LOUDLY, because the grep returns
nothing, whereas a drifted range fails plausibly, which is the mode that costs a reader something.
Fixing the ranges one at a time is what this file did before, and it is worse than leaving them: one
freshly verified row among wrong ones is indistinguishable from the wrong ones.

| Trap | Evidence |
|---|---|
| A wrapped-fn aspect is callable but **`isFunction` says false** — under both `builtins.isFunction` and `prelude.isFunction` | `lib/types.nix`'s `mkWrapped` (the one `__functor` / `__isWrappedFn` record both wraps build); both ⇒ `false` on a type-merge-wrapped guard fn. `applyGuard` compensates with an explicit `\|\| (g.__isWrappedFn or false)` disjunct (`lib/guard.nix`'s `applyGuard`) |
| `builtins.functionArgs` on a wrapped-fn is an **uncatchable** type error, not a throw — read `.__functionArgs` instead | observed `error: 'functionArgs' requires a function`, raised through `tryEval`; `.__functionArgs` ⇒ `{ host = false; }`. Test: `test-tag-shape` (`ci/tests/gated-wrap.nix`) |
| The native guard wrap applies **unconditionally**: a missing coord raises nix's own `called without required argument`, which `tryEval` cannot rescue | `lib/types.nix`'s `wrapGuardFn`; applying the wrap to `{ }` aborted the whole eval. Positive control, same wrapper: full coords ⇒ a merged aspect carrying `classOne`. Test: `test-native-guard-not-gated` |
| `wrapGatedFn` is the **opt-in** sibling: a missing required coord ⇒ `{ }` inert, and extra args are dropped | `lib/types.nix`'s `wrapGatedFn`; `gated { }` ⇒ `{ }`, `gated { host = "h"; extra = 1; }` ⇒ `{ classOne.x = "h"; }`. Tests: `test-gate-inert-on-missing`, `test-fires-onresult-and-intersect` |
| The two wraps return **different shapes**: `wrapGatedFn` returns the raw `onResult (fn …)` value; the native wrap returns an `aspectSubmodule`-merged aspect, so a class bucket comes back as `{ imports = [ … ]; }` | `lib/types.nix`'s `wrapGatedFn` — its `__functor` makes no `.merge` call — against `wrapGuardFn`'s `apply`, which does; gated ⇒ `{ classOne = { x = "h"; }; }`, native ⇒ `{ classOne.imports = [ … ]; }` |
| A guard record defined **twice** under one key loses guard shape: `__guard` becomes `{ _type = "merge"; contents = …; }`, so `flatten` dies with an uncatchable `expected a Boolean but found a set` | `lib/types.nix`'s `aspectType` merge, whose `TODO(guard)` comment names the limitation, + `lib/flatten.nix`'s `isGuardLeaf`; observed exactly that error. Positive control: the single-def guard flattens fine (`ok ⇒ true`). Test: `test-guard-multidef-limitation` |
| Same root cause for primitives: a **multi-def primitive key does not last-def-win** — the unresolved `mkMerge` marker leaks verbatim into `config` | `lib/types.nix`'s `aspectType` merge — the all-primitive `mkMerge` arm of its `length defs != 1` branch; two defs of `aspects.p.lit` ⇒ `{ _type = "merge"; contents = [ 1 2 ]; }`. Positive control: single def ⇒ `1`. The passthrough tests (`test-primitive-string-passthrough`, `test-primitive-list-passthrough`) are single-def only |
| `mkGuardVocab`'s custom-form validation is **lookup-lazy, not construction-eager** — a form missing `reads` builds fine and throws only when a guard *of that form* is dispatched | `lib/guard.nix`'s `checkedUserForms` (the check sits inside a `mapAttrs` value thunk); `guardForms.f2 = { eval = …; }` dispatching `gHost` ⇒ `ok true`, dispatching `pred.custom "f2"` ⇒ threw |
| Same for the core-name collision check: shadowing `host` throws only when a `host` predicate is dispatched | `lib/guard.nix`'s `checkedUserForms`, its `coreFormNames` collision arm; `guardForms.host = …` dispatching `pred.always` ⇒ `ok true` (control), dispatching `gHost` ⇒ threw. Test: `test-custom-form-collision` |
| By contrast `keySemantics` category validation **is** eager (`deepSeq`) — one bad category throws while reading an *unrelated* aspect's `name` | `lib/types.nix`'s `aspectSubmodule`, its `ks` binding (the `deepSeq` over the category check); `keySemantics.bogus.category = "widget"` ⇒ reading `aspects.a.name` threw. Positive control: `category = "channel"` ⇒ `"a"`. Test: `test-bad-category-throws` |
| A non-firing guard yields **`null`**, not `{ }` — different from `wrapGatedFn`'s inert `{ }` | `lib/guard.nix`'s `applyGuard`, its non-firing arm; `applyGuard ctx (guard (pred.host "other") …)` ⇒ `null`. Tests: `test-applyguard-not-fires`, `test-applyguard-fires` |
| `applyGuard` accepts a **raw closure** (the escape hatch) and applies it to the context; anything that is neither guard nor callable throws | `lib/guard.nix`'s `applyGuard`, its `isFunction` / `__isWrappedFn` arm and closing throw; `applyGuard ctx (c: { seen = c.class; })` ⇒ `{ seen = "nixos"; }`, `applyGuard ctx { notAGuard = 1; }` ⇒ threw. Test: `test-escape-hatch` |
| `pred.all [ ]` ⇒ true, `pred.any [ ]` ⇒ false; both reject a **guard** where a predicate is expected | `lib/guard.nix`'s `pred.all` / `pred.any` over `assertPred`; observed `true` / `false`, and `pred.all [ gHost ]` ⇒ threw |
| Predicate args must be first-order — a function anywhere in them throws at construction | `lib/guard.nix`'s `tagVal` (the closing throw) under `toArgData`; `toArgData { f = (x: x); }` ⇒ threw. Control: `{ s = "a"; i = 1; l = [ true ]; }` ⇒ `{ __t; v; }` tags. Test: `test-toargdata-throws-on-function` |
| `guardKey` is site-independent for a first-order body but falls back to **`guard-loc:<anon>`** for an opaque one, so two distinct opaque guards with no `meta.loc` collide | `lib/identity.nix`'s `guardKey` over `bodyKey`; `gHost` ⇒ `guard:host:c…`, a guard whose body holds a closure ⇒ `guard-loc:<anon>`. Two identical first-order guards ⇒ same key. Tests: `test-guardkey-site-independent`, `test-guard-opaque-body-site-distinct` |
| `aspectId` routes through gen-schema's `hashIdentity` over `[ origin, key ]`, **not** `mkIdentityModule` — so `description` is not in the preimage | `lib/types.nix`'s `aspectId`; `aspectId [ ] a == genSchema.hashIdentity "aspect" [ "origin" "key" ] …` ⇒ `true`, and two aspects differing only in `description` ⇒ same id. `git grep -n mkIdentityModule -- lib/` ⇒ no hits; positive control `git grep -n hashIdentity -- lib/` ⇒ 5 hits. Tests: `test-aspectid-is-canonical-formula`, `test-description-not-in-id` |
| There is **no `reservedKeys` surface** — a reserved key is an option declared through `cnf.aspectModules`, which the module system binds before the freeform fallback | `git grep -n reservedKeys -- lib/` ⇒ no hits; positive control `git grep -n aspectModules -- lib/` ⇒ 6 hits — `lib/cnf.nix`'s default, `lib/schema.nix`'s `mkAspectModule`, and `lib/types.nix`'s `aspectSubmodule` (its `imports = facetModules ++ cnf.aspectModules`, plus two comments). Tests: `test-reserved-key-reads-back-verbatim`, `test-undeclared-key-is-nested-aspect` |
| `aspectsRoot` **drops the mount segment**: keys are container-relative, so the option path `aspects.hardware.cpu.intel` keys as `hardware/cpu/intel`, not `aspects/hardware/…` | `lib/types.nix`'s `aspectsRootWith`, whose `merge` re-roots each child at `[ k ]`; observed `key = "hardware/cpu/intel"`, `meta.aspect-chain = [ "hardware" "cpu" ]`. Tests: `test-nested-aspect-key`, `test-no-name-only-collision` |
| `keyRef "prov/a/b"` splits the **first segment off as origin**, and the resulting `.key` excludes it | `lib/identity.nix`'s `keyRef` over `splitSlash`; ⇒ `{ __keyRef = true; origin = [ "prov" ]; path = [ "a" "b" ]; key = "a/b"; }`. Tests: `test-keyref-origin`, `test-keyref-target-key-readable` |
| With `closedKeys`, a key listed in `freeformKeys` opens an **ungated** subtree — descendants get `closedKeys = false` and admit anything | `lib/types.nix`'s `gatedFreeformElem`, its `cnf.freeformKeys` arm; an arbitrary key three levels under a listed key ⇒ `ok true`. Contrast: an undeclared key at the gate ⇒ threw. Positive control with the gate off: the same key becomes a nested aspect ⇒ `ok true`. Tests: `test-gate-on-allows-listed`, `test-gate-on-rejects-undeclared` |
| `recursiveClosed` keeps the gate all the way down, admitting an undeclared key only as a **namespace attrset** — a primitive there throws | `lib/types.nix`'s `gatedFreeformElem`, its `cnf.recursiveClosed` arm; namespace ⇒ `ok true`, `oops = 5` ⇒ threw. Tests: `test-gate-retained-below`, `test-typo-leaf-throws` |
| An `includes` element that is a bare `{ imports = [ … ]; }` module is **accepted by default**; rejection is opt-in via `rejectBareModuleInclude` | `lib/types.nix`'s `includesElemType`, its `isBareModuleInclude`; default ⇒ `ok true`, opt-in ⇒ threw. Tests: `test-default-off-absorbs`, `test-bare-module-rejected` |
| A raw closure in `includes` is wrapped by default, but passes through **unforced and still a real function** under `deferIncludeResolution` | `lib/types.nix`'s `includesElemType`, its `isDeferredInclude`; default ⇒ `__isWrappedFn = true`, opt-in ⇒ `builtins.isFunction` ⇒ `true`. Tests: `test-default-off-wraps-bare-fn`, `test-bare-fn-passes-through` |
| `aspectType`'s `check` is `_: true` — no value is ever rejected by the type check; every decision happens in `merge` | `lib/types.nix`'s `aspectType`, its `check = _: true`; `(aspectType { }).check 12345` ⇒ `true` |
| `canTake.atLeast` and `canTake.upTo` disagree on a `{ ... }:`-only function — `upTo` additionally requires a non-empty arg intersection | `lib/can-take.nix`'s `canTake` (its `satisfied` / `upTo` fields) behind the `atLeast` / `upTo` exports; `atLeast { a = 1; } ({ ... }: 1)` ⇒ `true`, `upTo` ⇒ `false`, `upTo { a = 1; } ({ a, ... }: 1)` ⇒ `true`. Since `mkIsModuleFn` is `upTo`, a bare `{ ... }:` aspect is classified as a **guard** fn, not a module fn |
| A `channel` key defaults to **`null`**, not `{ }`, and its value rides verbatim; a `class` key reads back as the `deferredModule` shape `{ imports = [ … ]; }` | `lib/types.nix`'s `aspectSubmodule`, its `channelOptions` and `classOptions`; unset channel ⇒ `null`, set ⇒ the value unchanged, class ⇒ `attrNames` `[ "imports" ]`. Tests: `test-channel-value-verbatim`, `test-class-key-is-deferred-content` |
| `keyCategory` returns **`null`** for an unregistered key — absence is not an error, so a typo is indistinguishable from a freeform child unless the closed gate is on | `lib/types.nix`'s `keyCategory` over `nativeStructuralKeys`; `"name"` ⇒ `"structural"`, declared ⇒ its category, `"zzz"` ⇒ `null`. Tests: `test-unknown-null`, `test-structural` |
| `flatten` keys nested aspects and guard/wrapped **leaves**, but never class content and never recurses into a leaf | `lib/walk.nix`'s `isGuardLeaf` / `isNestedAspect` (the membership predicate `flatten` and `graphFacts` share); a tree with class content, a nested aspect, a guard and a wrapped fn ⇒ `[ "top" "top/g" "top/nested" "top/w" ]`. Tests: `test-class-keys-excluded`, `test-guard-function-not-recursed` |
| A nested GUARD LEAF is in the registry, carries **no** `meta.aspect-chain`, and `meta.aspect-chain or [ ]` answers ROOT for it — indistinguishably from a genuine root, which yields the same `[ ]`. A framework joining the registry with that accessor gets a WRONG graph, not a re-derived one | Measured at a nested guard `top/g`: `meta` keys are `[ "file" "loc" ]` (no chain), `meta.loc` is `[ "top" "g" ]`, and `identity.key` returns `guard:<pred>:<hash>` — a content address, not the position. This is why `graphFacts` publishes the relation rather than leaving a framework to join. Test: `test-parent-is-the-walk-not-a-meta-read` |
| ★ `meta` CANNOT BE READ AS A POSITION AT ALL for two public constructors, so a shape dispatch over it is wrong in the same way it exists to prevent | `wrapFn cnf name fn` stamps `meta.loc = [ name ]` from the SITING NAME its caller passes, not a tree position: `top/wf` and `top/deeper/wf2` both read parent `null`, a non-root spelled as ROOT. `wrapGatedFn` defaults `meta ? { }`, carrying no `loc`, so the read THROWS. Control in the same run: a bare fn wrapped by the type-merge path does carry a real `meta.loc` and reads correctly. ⇒ `parentOf` is the WALK position (`lib/walk.nix`), never a `meta` read. Test: `test-parent-is-the-walk-not-a-meta-read` |
| An `includes` list holds REFERENCES and INLINE CONTENT; only a reference is an edge. Four shipped shapes at the include position reference no node — a raw closure, a `{ __fn; … }` record and an `__isPolicy` record under `cnf.deferIncludeResolution`, plus a bare closure wrapped by the DEFAULT path — and a fifth, the inline `{ … }` aspect literal, carries a `.key` that is its MERGE position (`app/includes/0`), not a walk position | Dispatching on element SHAPE refused the first four and minted a phantom id for the fifth; `gen-graph.mkGraph` unions edge targets into its node set, so that phantom would have been admitted AS a node. The dispatch is on whether the element NAMES A NODE. Tests: `test-inline-include-content-is-published-not-refused`, `test-no-include-edge-names-a-non-node` |

**Read, not exercised** in this run: `mkNamespaceType`, `mkAspectOption`, `cnf.collections`,
`cnf.metaModules`, and the `facet` variant carrying a full `module` (only the bare-`option` facet was
evaluated). Each has named CI coverage — `test-collection-tags`, `test-schema-option-type`,
`test-meta-module-option-settable`, `test-facet-module-option`.

## Theory

Claimed in `README.md`'s **Theoretical Foundations** table, which carries an explicit **Relationship** column splitting
Implements from Informed by, and restated in the code headers.

**Implements**

- **Palmer et al. (2024), *Intensional Functions*** — one flat type dispatching by value shape in merge
  (§2), identity keys (§2.2) supplied for consumer-side dedup; `name`/`meta` from `loc` for tracing
  (§5.1). Stated in `lib/types.nix`'s header comment (its "one type, dispatch in merge" paragraph).
- **Reynolds (1972), *Definitional Interpreters* §6, as formalized by Danvy & Nielsen (2001),
  *Defunctionalization at Work*** (obligations O1–O7) — the closed guard-**predicate** vocabulary:
  predicates are pure first-order data, dispatched by one global `applyGuard`, keyed by a
  site-independent `guardKey`. `lib/guard.nix`'s header names the obligations, and each is marked inline at the
  construct that discharges it — grep `O1:`, `O2:`, `O3/O4:`, `O7` in that file. The README states the honest boundary: arbitrary
  `{ host, … }:` closures cannot be defunctionalized in pure Nix and stay a tagged escape hatch.

**Informed by** (README's own label; no result claimed)

- **Lorenzen et al. (2025), *First-Order Laziness*** §1–2.3 — class content as `deferredModule` is
  inspectable before forcing. The README states this comes from Nix's native laziness, **not** from
  Lorenzen's mechanism, and that the citation is provenance for the idea only (`lib/types.nix`'s header, its Lorenzen paragraph).

Two further attributions appear in code but not in the README table: **Reynolds, *Elimination of
Higher-Order Functions*** for the constructor tag replacing source position in `guardKey`
(`lib/identity.nix`'s `guardKey` comment), and Reynolds 1972 cited **by analogy only** for the `__isWrappedFn` functor
wrap — `lib/types.nix`'s header explicitly disclaims it as not the literal §6 transform.

**Checked invariant**: the library is nixpkgs-lib-free. `ci/tests/purity.nix` strips comments and scans
`lib/**.nix` + root `flake.nix` + `default.nix` for `lib.types` / `lib.mkOption` / `lib.evalModules` /
`nixpkgs`; test `test-library-source-is-nixpkgs-free`. `ci/` itself is exempt (the harness uses
`nixpkgs.lib`).

## Drift check

```sh
nix eval --json .#lib --apply 'l: {
  top = builtins.attrNames l;
  canTake = builtins.attrNames l.canTake;
  pred = builtins.attrNames l.pred;
  guardVocab = builtins.attrNames (l.mkGuardVocab { });
  vocab = builtins.attrNames (l.mkGuardVocab { }).vocab;
  schema = builtins.attrNames (l.mkAspectSchema { });
  schemaIdentity = builtins.attrNames (l.mkAspectSchema { }).identity;
  structuralKeys = l.structuralKeys;
}'
```

Current output (verbatim):

```json
{"canTake":["atLeast","upTo"],"guardVocab":["applyGuard","evalPred","fires","guard","pred","vocab"],"pred":["all","always","any","class","custom","eq","host","tagEq","user"],"schema":["aspectPath","aspectType","canTake","identity","isMeaningfulName","key","keyCategory","mkAspectModule","mkAspectOption","mkIsModuleFn","mkNamespaceType","pathKey","schemaOption"],"schemaIdentity":["aspectPath","isMeaningfulName","key","pathKey"],"structuralKeys":["name","description","key","id_hash","meta","includes"],"top":["applyGuard","aspectId","aspectOrFn","aspectPath","aspectSubmodule","aspectType","aspectsRoot","aspectsType","canTake","cnfKeys","flatten","graphFacts","guard","guardKey","isMeaningfulName","key","keyCategory","keyRef","mkAspectSchema","mkGuardVocab","mkIsModuleFn","pathKey","pred","structuralKeys","toArgData","wrapFn","wrapGatedFn"],"vocab":["always","whenAll","whenAny","whenClass","whenEq","whenHost","whenTagEq","whenUser"]}
```

**Checks.** Test-runner invocation (from the repo root; CI runs the same command from the
`check` job's `working-directory: ci`, `.github/workflows/ci.yml`):

```sh
nix flake check ./ci
```
