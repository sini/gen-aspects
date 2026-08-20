# gen-aspects — aspect type system (traits, classification, dispatch)

[![CI](https://github.com/sini/gen-aspects/actions/workflows/ci.yml/badge.svg)](https://github.com/sini/gen-aspects/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT) [![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/sini)

Aspect-oriented composition types for Nix module systems.

A pure type library: no resolve, no pipeline, no framework. It provides the structural types for defining aspects — composable configuration units with identity, includes, and class-separated content. Consumers (like [den](https://github.com/sini/den)) bring their own evaluation pipeline.

Dependency class: **Class D** (nixpkgs-lib-tethered). gen-aspects depends on nixpkgs `lib` (`lib.types` + `evalModules`) and on [gen-schema](https://github.com/sini/gen-schema). It is not nixpkgs-lib-free — the module-system machinery it builds on is nixpkgs `lib.types`.

## Table of Contents

- [Terminology](#terminology)
- [Overview](#overview)
- [Gen Ecosystem](#gen-ecosystem)
- [Usage](#usage)
- [Core Concepts](#core-concepts)
- [Schema Integration](#schema-integration)
- [Flat Registry](#flat-registry)
- [API Reference](#api-reference)
  - [Types](#types)
  - [Configuration (`cnf`)](#configuration-cnf)
  - [Utilities](#utilities)
  - [Schema & Registry](#schema--registry)
- [Demo](#demo)
- [Testing](#testing)
- [Theoretical Foundations](#theoretical-foundations)

## Terminology

| Term | Definition |
|------|-----------|
| Traits | The aspect type — one type, dispatch in merge (Palmer 2024) |
| Classes | Output targets (NixOS, darwin, homeManager module systems) |
| Collections | Named data aggregation (aspect keys matching registered collection names) |
| Edges | `includes` (forward I) — the one core structural edge, declared inline on each aspect. `neededBy` (reverse I) — a *consumer-declared, predicate-based* reverse reference; its semantics live in the consumer's dispatch layer, not in these types. |
| Constraints | Pruning rules: meta.guard, meta.drop, meta.substitute |

## Overview

gen-aspects gives you the *types*, not a framework. An **aspect** is a submodule carrying structural identity (`name`, `key`, `meta`, `includes`) plus freeform, class-separated content. You register your target module systems as **classes** (`nixos`, `homeManager`, `darwin`); each class becomes a clean `deferredModule` option so content stays free of the structural keys.

One flat type (`aspectType`) dispatches by value shape at merge time (Palmer 2024): attrsets and module functions become aspect submodules, context-dependent guard functions are wrapped as inspectable, tagged functors, and primitives pass through unchanged. The library computes stable identity keys, and via `graphFacts` publishes the aspect graph's facts — the node set, the parent and includes relations, and the node values — for a framework to assemble a graph from. `flatten` renders the same walk as a flat path-keyed registry.

Everything downstream — evaluation, scheduling, conflict resolution, dispatch policy — is the consumer's job. gen-aspects supplies the type surface and the identity keys; the pipeline lives in [gen-resolve](https://github.com/sini/gen-resolve) / [gen-dispatch](https://github.com/sini/gen-dispatch) / [den](https://github.com/sini/den).

## Gen Ecosystem

| Library | Role |
|---------|------|
| [gen-prelude](https://github.com/sini/gen-prelude) | Pure nixpkgs-lib-free utility base (builtins re-exports + vendored lib utils) |
| [gen-algebra](https://github.com/sini/gen-algebra) | Pure primitives (record, search monad, either, intensional identity) |
| [gen-types](https://github.com/sini/gen-types) | Clean-room MIT structural type checker (leaf/poly checkers; `verify: v → null\|err`) |
| [gen-merge](https://github.com/sini/gen-merge) | Byte-mode module merge engine (`evalModuleTree`, byte-identical to nixpkgs `lib.evalModules` over the priority subset) |
| [gen-schema](https://github.com/sini/gen-schema) | Typed registries (kinds, instances, collections, refs); re-hosted on gen-merge |
| [gen-aspects](https://github.com/sini/gen-aspects) | **This lib** — Aspect type system (traits, classification, dispatch); re-hosted on gen-merge |
| [gen-scope](https://github.com/sini/gen-scope) | HOAG scope-graph evaluator (demand-driven, \_eval memoization, circular attributes) |
| [gen-graph](https://github.com/sini/gen-graph) | Accessor-based graph query combinators (traversal, condensation, phaseOrder) |
| [gen-select](https://github.com/sini/gen-select) | Selector algebra (pattern matching over graph positions) |
| [gen-bind](https://github.com/sini/gen-bind) | Module binding (inject external args into NixOS modules) |
| [gen-dispatch](https://github.com/sini/gen-dispatch) | Relational rule dispatch STEP (stratified phases, conflict resolution) |
| [gen-resolve](https://github.com/sini/gen-resolve) | Demand-driven RAG evaluator over scope graphs (attribute schedule + convergence loop) |
| [gen-memo](https://github.com/sini/gen-memo) | The incremental plane — decides reuse, never evaluates (change propagation, AFFECTED set) |
| [gen-vars](https://github.com/sini/gen-vars) | Pure-Nix vars/secrets (den-agnostic) |
| [gen-flake](https://github.com/sini/gen-flake) | The nixpkgs boundary — compose purely, inject resolved values, build NixOS systems (value-injection) |

## Usage

The flake exposes a single `.lib` value output (no `__functor`); nixpkgs `lib` and gen-schema are wired in by the flake.

### As a flake input

```nix
# flake.nix
{
  inputs.gen-aspects.url = "github:sini/gen-aspects";
  outputs = { gen-aspects, ... }: {
    # bind the value directly — lib + gen-schema are wired in by the flake
    lib.aspects = gen-aspects.lib;
  };
}
```

### Without flakes

`default.nix` takes `lib` and auto-fetches gen-schema from the pinned `flake.lock`:

```nix
aspects = import gen-aspects { inherit lib; };
```

### Example

```nix
let
  aspects = gen-aspects.lib;
  eval = lib.evalModules {
    modules = [{
      options.aspects = lib.mkOption {
        type = aspects.aspectsType {
          keySemantics = {
            nixos = { category = "class"; };
            homeManager = { category = "class"; };
          };
        };
        default = {};
      };
      config.aspects.networking = {
        nixos.networking.hostName = "myhost";
        nixos.networking.firewall.enable = true;
      };
      config.aspects.desktop = {
        includes = [ eval.config.aspects.fonts ];
        homeManager.programs.alacritty.enable = true;
      };
      config.aspects.fonts = {
        nixos.fonts.packages = [ pkgs.noto-fonts ];
      };
    }];
  };
in
  eval.config.aspects.networking.nixos
  # => { imports = [{ networking.hostName = "myhost"; ... }]; }
  # Clean deferredModule — no structural keys (name, includes, meta, etc.)
```

## Core Concepts

**Aspects** are submodules with structural identity (`name`, `key`, `meta`, `includes`) and freeform content. Every non-structural, non-class key becomes a nested aspect with its own identity.

**Key semantics** declare, per aspect key, a `category ∈ { class, channel, facet }` through `cnf.keySemantics`. `aspectSubmodule` builds each declared key's option generically from this one surface:

- `class` (e.g. `nixos`, `homeManager`, `darwin`) → an explicit `nullOr deferredModule` option defaulting to `null` — clean content buckets with no structural keys injected. A class DECLARED but never given content reads `null`, so absence is representable rather than fabricated: a `{ }` default merges to `{ imports = [ { } ]; }`, shape-indistinguishable from real content, and a consumer projecting classes by shape would realize the mere declaration.
- `channel` → a raw passthrough (`mkOption { type = raw; }`); the value rides verbatim, and is *not* turned into a nested aspect. A channel may supply its own `option` to override the raw default.
- `facet` → the entry's own `option` (a bare `mkOption`) or a full `module` (mounted via `imports`) — for typed instance fields like `neededBy` / `settings` / `id`.

An **undeclared** key falls through the freeform fallback to a nested aspect (it gets identity). This is the module system's own option/freeform separation driven by one declared map, not a custom dispatch mechanism — the bounded category set and its meaning live in gen-aspects; gen-schema records `category` opaquely. There is no hardcoded `classes` arm: a class is simply a `keySemantics` entry with `category = "class"`. The category is validated eagerly (an unknown category throws a named error at construction).

**Guard functions** like `{ host, ... }: { nixos = ...; }` are context-dependent aspects that should not be evaluated eagerly. They're detected via `canTake` (all required args must be known module args) and wrapped via `functionTo` for pipeline resolution later.

**Module functions** like `{ config, ... }: { ... }` or `{ aspect, ... }: { ... }` are evaluated immediately by the submodule — they have access to `_module.args.aspect` (self-reference) and standard module args.

## Aspect identity (A-IDENT)

Every aspect carries an **intrinsic path identity** — its `.key` is a function of *where it sits in the aspect tree*, computed at merge and never reconstructed downstream. The top aspect container (`aspectsRoot`) re-roots its children so that below it the `prefix` gen-merge threads into every module body is **container-relative** (the module-system mount segment is dropped); `aspectSubmodule` reads that `prefix` and stamps `meta.aspect-chain`; `key` then computes `pathKey(meta.aspect-chain ++ [name]) = pathKey(prefix)`.

The rule (VERBATIM):

> **A-IDENT (intrinsic path identity).** Let an aspect container hold a tree of nested aspects. For every nested aspect `a` at container-relative path `p = [k₀ … kₙ]` (the sequence of freeform keys from the container root down to `a`, EXCLUDING the module-system mount prefix and EXCLUDING registered class/structural keys), gen-aspects stamps, intrinsically on the value: `a.name = kₙ` and `a.meta.aspect-chain = [k₀ … kₙ₋₁]`. Its identity key is `key(a) = pathKey(a.meta.aspect-chain ++ [a.name]) = pathKey(p)`.
> **Collision law:** two aspects share a key **iff** they occupy the same container-relative path.
> **Corollary (no name-only collapse):** distinct paths ⇒ distinct keys; in particular `key(hardware.cpu.intel) = "hardware/cpu/intel" ≠ "hardware/gpu/intel" = key(hardware.gpu.intel)`.
> **Parametric exception (unchanged):** a wrapped closure include (`__isWrappedFn`, and guard functions/records) is identified by its definition site `meta.loc` (already path-bearing) plus its arguments — its identity is parametric but KNOWN; A-IDENT unifies plain aspects to the SAME path-bearing key discipline, it does not alter the wrapped/guard branches.

**Key form — container-RELATIVE.** The stamped `prefix` is the merge `loc` *re-rooted at the aspect container*: the top container `aspectsRoot` merges each first-level aspect at `prefix = [key]` (dropping the module-system mount segment the container is mounted under — `aspects` in these tests, `den/aspects` in [den](https://github.com/sini/den)), and descendants accumulate relative from there. So `key(apps.media.spicetify) = "apps/media/spicetify"`, no mount. This form was chosen (over mount-absolute) because:

- **It is origin-invariant.** An aspect's key is a function of its position *within its aspect tree*, independent of where the consumer mounts that tree. This is the property the future aspect-registry / cross-flake origin work needs (an imported aspect keys by its definition origin, not the consumer's mount point — spec §3a north-star): the container root IS the proto-namespace root, and an origin qualifier prepends *additively* (`pathKey(origin ++ path)`).
- **It matches den-hoag's identity form.** den-hoag's `__provider` reconstruction is already root-relative (`apps/media/spicetify`), so consuming the native relative `.key` is byte-for-byte the same key — the lowest-churn path to retiring the shadow layer.
- **It keeps plain and guard unified.** The re-root is a *uniform* reset applied to every value the container merges (not a depth-based strip), so the guard branch (keyed off `meta.loc`, also re-rooted) lands in the SAME relative namespace as plain aspects — a plain aspect and a guard function at the same path key identically and dedup, as the collision law requires.

**One identity, two views — modulo the origin qualifier, and for plain aspects only.** For a plain aspect under an empty origin, `flatten`'s walk key and `.key` are literally equal: both are container-relative (`flatten` walks from the container root; `.key` is re-rooted there), so `key(a) == flattenKey(a)` (e.g. both `"apps/media/spicetify"`). Two scopes on that, both load-bearing:

- **The origin qualifier moves one side and not the other.** A published node id is `pathKey(origin ++ path)`, while `.key` takes no origin at all — its three arms are `guardKey`, `pathKey(meta.loc)` and `pathKey(aspectPath)`, none of which sees one. The two agree only after the qualifier is stripped, and coincide exactly when `cnf.providerPrefix` is `[ ]`.
- **Guard records and wrapped fns are outside the claim.** They are bare records rather than submodule instances, so they carry no `key` option at all — and a guard record's `.key` is `guardKey`, which content-addresses a bodied guard (`"guard:<pred>:<hash>"`) instead of rendering its position. Their positions are answered by the published `parentOf` (see [Flat Registry](#flat-registry)), never by `.key`.

Unit-tested in `flat-registry` `test-node-id-agrees-with-key-modulo-origin`, which enumerates over the published `nodes`, names those two exclusions rather than filtering them away, and asserts the fixture actually carried one of each.

## Schema Integration

gen-aspects depends on [gen-schema](https://github.com/sini/gen-schema) and provides `mkAspectSchema` to bridge aspect types with gen-schema's kind-level infrastructure (collections, introspection, schema extensions).

```nix
aspects = gen-aspects.lib;
schema = aspects.mkAspectSchema cnf;
```

`mkAspectSchema cnf` returns:

| Field | Description |
|-------|-------------|
| `schemaOption` | gen-schema option wrapping `aspectType` as the custom entry type |
| `mkAspectOption { providerPrefix? }` | Declares `options.aspects` with `lazyAttrsOf aspectType` |
| `mkAspectModule { providerPrefix? }` | NixOS module declaring both `options.aspects` and `options.schema`, lazily threading schema-declared options into every aspect instance |
| `mkNamespaceType { }` | Submodule type for namespace composition — includes `schema`, `classes`, and freeform aspect content |
| `aspectType` | Re-exported aspect type |
| `identity` | Bundled identity functions (`aspectPath`, `pathKey`, `key`, `isMeaningfulName`) |
| `canTake` | Re-exported function arg introspection |
| `mkIsModuleFn` | Re-exported module function predicate |

### Schema extensions

Schema-declared options propagate to aspect instances via `mkAspectModule`. When a schema kind entry declares options (e.g., `priority`, `tier`), those options become available on every aspect:

```nix
{ config, ... }:
{
  imports = [ (schema.mkAspectModule { }) ];

  # Collections and extensions declared on the schema kind
  schema.aspect = {
    settings = { };  # collection
    tags = { };      # collection
    # options.priority = lib.mkOption { ... };  # schema extension
  };

  # Every aspect now has access to schema-declared options
  aspects.networking.priority = 10;
}
```

`mkAspectModule` lazily injects `config.schema.aspect.__defsModule` into each aspect's `aspectModules`, so schema extensions are available without manual wiring. This `__defsModule` seam is why `aspectSubmodule` mounts `imports = facetModules ++ cnf.aspectModules` — `aspectModules` must stay live even though per-key channels are now declared through `keySemantics` rather than injected as modules.

## Flat Registry

The `flatten` function walks the recursive aspect tree and produces a flat attrset keyed by path identity:

```nix
aspects = gen-aspects.lib;

flat = aspects.flatten eval.config.aspects;
# => { "networking" = ...; "networking/firewall" = ...; }
```

Entries are the aspect values unchanged — `flatten` does not inject any fields. Guard functions (`__isWrappedFn`) and guard records (`__guard`) are included as entries but never recursed into.

**The path key is a RENDERING of a parent edge, not the edge. Do not split it.** `"networking/firewall"` looks like it says its parent is `"networking"`, and for a plain aspect it happens to agree — but a nested guard leaf is in the registry carrying no `meta.aspect-chain` at all, so the two derivations a consumer might reach for disagree on it, and the `meta.aspect-chain or [ ]` one answers *root* for a node whose parent is its container. Worse, that wrong answer is indistinguishable from a right one: a genuine root aspect yields `[ ]` through the same accessor, so absence and root are the same value. Read `graphFacts` instead.

Detection is structural rather than relying on a hardcoded key list:

- Nested aspects are attrsets with a `name` field (from `aspectSubmodule`)
- Class content (`deferredModule`) lacks `name` and is skipped
- Primitives (strings, lists) are skipped

### Published facts

`graphFacts` publishes what a graph is built FROM — the node set, the two edge relations and the node values — as plain data. gen-aspects imports no query library for this: the query libraries are needed to *query* a graph, never to *state* one, and every fact here is an attrset, a list or a string.

```nix
facts = aspects.graphFacts cnf eval.config.aspects;
# => { nodes                = [ "networking" "networking/firewall" … ];
#      parentOf             = { "networking" = null; "networking/firewall" = "networking"; … };
#      includesOf           = { "networking" = [ ]; … };
#      unresolvedIncludesOf = { "networking" = [ ]; … };
#      nodeData             = { "networking" = <the aspect value, unchanged>; … }; }
```

- **A node id is `pathKey(cnf.providerPrefix ++ walkPath)`** — the walk position the registry already keys on, qualified by origin. It is deliberately *not* `identity.key`: that function content-addresses a guard record, which would move every guard node's name off its position.
- **`parentOf` is the node's own WALK POSITION, and the id and the parent come from one source.** A framework holding only the registry and the values would have to join on `meta`, and that join is wrong rather than merely redundant — a nested guard leaf carries no `meta.aspect-chain` at all, so `meta.aspect-chain or [ ]` answers root for it, indistinguishably from a genuine root. That is why the relation is published here. It is *not* why it should be computed from `meta` here: this library holds the walk, and reading a position out of `meta` instead is wrong on its own public constructors — `wrapFn` stamps `meta.loc` from the siting name its caller passes, and `wrapGatedFn` defaults `meta` to `{ }`.
- **`parentOf` is total, and `null` means root and only root.** Every node has an answer. Totality holds *by construction* rather than by a check: the walk descends only into values it also emits, so a non-root node's parent is necessarily already a node — there is no dangling case for a refusal to guard.
- **`includesOf` resolves the include elements that REFERENCE a node**, taking a `keyRef`'s own origin for a cross-source reference. Every *locally-qualified* target it emits is in `nodes`. A **foreign** `keyRef` is the deliberate exception: its target names a node in a fixpoint gen-aspects does not hold, so it is emitted unresolved and unrefused, and the framework — which unions providers — is what resolves it. That is what `keyRef` is for.
- **`unresolvedIncludesOf` names the declared positions that reference no node.** An `includes` list holds two kinds of thing, and only one is an edge: a *reference* (a `keyRef`, or a by-value aspect whose key is a node), and *inline content* written at the include position (a wrapped fn, a guard record, a deferred closure or policy record, an aspect literal). The walk never descends into `includes`, so inline content has no node for an edge to reach. Its position is published rather than dropped — index back into `nodeData.<id>.includes` for the element itself.
- **One refusal, and it fires only where the input is unambiguously broken:** a `keyRef` carrying *this* tree's own origin, and so naming a local node, when no such node exists. A genuinely foreign origin names a node in a fixpoint this library does not hold and is not checkable here.

A framework builds the graph from these with `gen-graph.labeledFrom` / `fromRegistry` and expresses its named views over `gen-select`'s algebra; the registry above is one such view.

## API Reference

The `.lib` value exposes the five aspect types (incl. `aspectsRoot`, the re-rooting container), the value-shape constructors (`wrapFn`, `wrapGatedFn`, `canTake`), the identity/introspection utilities plus `guardKey` and `keyRef`, the schema-and-registry entry points (`mkAspectSchema`, `flatten`, `graphFacts`, `keyCategory`, `structuralKeys`, `cnfKeys`), and the guard-predicate vocabulary (`mkGuardVocab`, `applyGuard`, `toArgData`, `pred`, `guard`). The roster itself is the binding, not a count restated in prose — read `lib/default.nix`.

```nix
aspects = gen-aspects.lib;
```

### Types

- **`aspectsType cnf`** — top-level container. Submodule with `freeformType = lazyAttrsOf (aspectType cnf)` and fixpoint (`_module.args.aspects = config`).

- **`aspectSubmodule cnf`** — aspect entry. Submodule with structural options (`name`, `description`, `key`, `meta`, `includes`), one option per declared `cnf.keySemantics` key built generically from its category (class → `nullOr deferredModule` defaulting to `null`, channel → `raw`, facet → the entry's `option`/`module`), and freeform for undeclared (nested) aspects.

- **`aspectType cnf`** — Palmer flat dispatch. One type, dispatch in merge. Attrsets and module functions → `aspectSubmodule`. Guard functions → `functionTo` wrapper. Primitives → passthrough.

- **`aspectOrFn cnf`** — `either aspectType aspectSubmodule`. Recursion-safe binding for `includes` and nested aspect positions.

- **`wrapFn cnf name fn`** — wrap a single raw closure `ctx: <aspect>` as an inspectable `__isWrappedFn` functor: the API sibling of the guard-function wrap that `aspectType` applies automatically. A native bare-fn include rides the option-type merge; a **programmatically generated** include (built off the type, e.g. a bridge that raw-absorbs a foreign surface) bypasses that merge and must call `wrapFn` explicitly — the same rationale (Palmer's three eliminators over a value the type never intercepted) that makes a generated guard record first-order data. A `wrapFn`'d include is equivalent to a type-merge-wrapped bare fn (same formals; same merged content per context).

### Configuration (`cnf`)

`cnf` is a **closed vocabulary**, not an open attrset. Every entry point that takes one constructs it
through a single `checkedCnf`, so a key outside the recognised set is **refused by name** — the
refusal lists the offending keys, renders the recognised set, and, for a key the library retired,
names its replacement. The refusal is a `throw`, catchable with `tryEval`, and reachable by forcing
the entry point's own result. The recognised set is `aspects.cnfKeys`; read it from there rather than
restating it. The default behind each key stays internal — the question a consumer asks of this
surface is whether a key is recognised, not what it falls back to.

This closes a silent failure mode rather than adding a strictness. Under the previous `cnf.<key> or <default>` reads nothing ever inspected the key SET, so an unrecognised key was not reinterpreted —
it was **inert**, and whatever it meant to declare stayed undeclared and fell through the aspect
submodule's freeform fallback into a nested aspect tree. `mkAspectSchema { classes = …; }` computed
exactly `mkAspectSchema { }`.

```nix
aspectsType {
  # Per-key semantics — one surface for class/channel/facet dispatch.
  # class  → nullOr deferredModule, default null (clean content buckets; unset reads null)
  # channel → raw passthrough (value rides verbatim; may carry its own `option`)
  # facet  → the entry's `option` (bare mkOption) or `module` (mounted via imports)
  keySemantics = {
    nixos    = { category = "class"; };
    firewall = { category = "channel"; };
    neededBy = { category = "facet"; option = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; }; };
  };

  # Known module args for module/guard function detection
  # Default: { lib, config, options, pkgs, modulesPath, aspect }
  moduleArgs = { lib = true; config = true; /* ... */ };

  # Additional NixOS modules imported into every aspect entry.
  # Use for pipeline-specific options (excludes, policies, etc.).
  # ALSO the `__defsModule` seam: mkAspectModule injects
  # config.schema.aspect.__defsModule here, so schema-declared instance
  # options propagate — keep aspectModules mounted (see Schema extensions).
  aspectModules = [
    ({ config, ... }: {
      options.excludes = lib.mkOption { default = []; type = lib.types.listOf lib.types.str; };
    })
  ];

  # List of NixOS modules imported into each aspect's `meta` submodule.
  # Allows consumers to declare typed meta options (e.g., `meta.guard`,
  # `meta.priority`) alongside the freeform attrs.
  metaModules = [ ];
}
```

### Utilities

- **`canTake`** — function arg introspection. `canTake.upTo params fn` checks if all required args of `fn` are satisfiable by `params`.
- **`mkIsModuleFn cnf`** — `canTake.upTo cnf.moduleArgs`. Returns a predicate that classifies functions as module fns or guard fns.
- **`key`**, **`aspectPath`**, **`pathKey`**, **`isMeaningfulName`**, **`guardKey`** — identity computation from `meta` + `name`. `key` routes three ways: static aspects (via `meta.aspect-chain`, stamped intrinsically at merge from the option path — [A-IDENT](#aspect-identity-a-ident)), wrapped guard functions (via `meta.loc`), and defunctionalized guard records (`__guard` → `guardKey`, a site-independent structural key over the predicate + first-order body). All three are container-relative (re-rooted by `aspectsRoot`), so plain and guard keys share one namespace.

### Schema & Registry

- **`mkAspectSchema cnf`** — bridges aspect types to gen-schema kind-level infrastructure. Returns `schemaOption`, `mkAspectOption`, `mkAspectModule`, `mkNamespaceType`, plus re-exports (`aspectType`, `identity`, `canTake`, `mkIsModuleFn`). See [Schema Integration](#schema-integration).
- **`flatten aspects`** — walks the recursive aspect tree into a flat attrset keyed by `path` identity (`"parent/child"`), structurally detecting nested aspects vs class content. The key is a rendering of a parent edge, never the edge; read `graphFacts` for parenthood. See [Flat Registry](#flat-registry).
- **`graphFacts cnf aspects`** — the aspect graph's facts as plain data: `{ nodes; parentOf; includesOf; unresolvedIncludesOf; nodeData; }`, keyed by origin-qualified node id. `parentOf` is the walk position and is total by construction; include elements that reference no node are published as positions rather than refused. See [Published facts](#published-facts).

## Demo

The `examples/demo/` directory exercises eight gen libraries together: gen-algebra, gen-schema, gen-aspects, gen-graph, gen-scope, gen-select, gen-bind, and gen-dispatch. It demonstrates entities, aspects, namespaces, policies, queries, bindings, composition, and settings in a single integrated flake.

## Testing

```bash
nix shell nixpkgs#nix-unit -c nix-unit \
  --override-input target . \
  --flake './ci#.tests'
```

115 tests across 17 suites (verified `115/115 successful` via nix-unit): `can-take`, `class-content`, `extensions`, `flat-registry`, `freeform-dispatch`, `guard`, `guard-identity`, `identity`, `includes`, `lazy-classification`, `meta-modules`, `multi-def`, `multi-def-identity`, `nested-aspects`, `parametric`, `reserved-keys`, and `schema-integration` — covering class content cleanliness, nested aspect identity, includes fixpoint, module vs guard function dispatch, the guard predicate vocabulary + defunctionalized identity (`mkGuardVocab`/`applyGuard`/`guardKey`), lazy classification, parametric aspects, multi-def merging, reserved keys, primitive passthrough, deep nesting, extensions, `meta` modules, `canTake` introspection, schema integration, and the flat registry.

## Theoretical Foundations

| Paper | Relationship | Mechanism |
|-------|-------------|-----------|
| Palmer et al. (2024) "Intensional Functions" | Implements | Flat dispatch via one type in merge §2, identity §2.2; identity keys enable consumer-side dedup |
| Lorenzen et al. (2025) "First-Order Laziness" | Informed by | `deferredModule` inspectable before forcing (via Nix native laziness, not Lorenzen's mechanism) §1-2.3 |
| Reynolds (1972) "Definitional Interpreters" · Danvy & Nielsen (2001) "Defunctionalization at Work" | Implements | §6 "Elimination of Higher-Order Functions" for the guard **predicate vocabulary** (`mkGuardVocab`/`pred`/`applyGuard`/`guardKey`, obligations O1–O7): predicates are first-order data dispatched by one global `applyGuard`, keyed by a site-independent `guardKey`. Raw `{ host, … }:` closures remain the non-defunctionalized escape hatch (`functionTo`) |

**Palmer et al. (2024) "Intensional Functions"** — One type dispatches by value shape in merge (§2). Guard functions are defunctionalized as callable first-order data with inspectable args (§5.1). Identity keys enable consumer-side diamond dedup (Lemma 5.12 + Theorem 1, closure consistency); gen-aspects supplies the keys, the dedup lives in the consumer.

**Lorenzen et al. (2025) "First-Order Laziness"** (informed by) — Class content as `deferredModule` is inspectable before forcing, evaluated only when the consuming NixOS evaluation imports it (§1-2.3). This property comes from Nix native laziness plus nixpkgs `deferredModule`, NOT from Lorenzen's mechanism (first-order named constructors, defunctionalized deferred operations, in-place memoization). The citation is provenance for the laziness idea, not an implementation of the paper.

**Reynolds (1972) "Definitional Interpreters" + Danvy & Nielsen (2001) "Defunctionalization at Work"** — gen-aspects ships a closed guard-**predicate vocabulary** (`lib/guard.nix`) that is a genuine §6 defunctionalization for the guard function-space: a guard is a `{ __guard; pred; body }` record whose *predicate* is pure first-order data (`pred.host`/`class`/`user`/`tagEq`/`eq`/`all`/`any`/`always`, type-tagged via `toArgData`), dispatched by a single global `applyGuard` (case-analysis on the predicate tag — Reynolds' `apply`), and identified by a **site-independent** `guardKey = H(pred, bodyKey)` (the constructor tag replaces source position). The O1–O8 obligation checklist is Danvy & Nielsen's formalization of Reynolds §6. **Honest boundary:** arbitrary `{ host, … }: { … }` closures cannot be auto-defunctionalized in pure Nix (function equality is undecidable — the closure wall), so they remain a *non-defunctionalized escape hatch* via `functionTo` (a tagged, still-callable functor with a source-position key); `applyGuard` handles both. `guardKey` content-hashes a first-order body (enabling dedup); an opaque body falls back to source position — sound (no false merge), just no cross-site dedup. Three bodies are opaque: a closure, a `deferredModule`, and one the structural function-scan behind `bodyKey` REFUSED as cyclic or nested past that scan's depth budget. The scan must be bounded because it runs over caller-supplied values, and an unbounded structural recursion over a cyclic one aborts the evaluator **uncatchably**; a refusal by name is catchable and lands in the same source-position branch the other two opaque bodies already take. A derivation is answered by type test before any descent (its `out` attribute is self-referential) — exactness rather than safety, since `builtins.toJSON` renders a derivation as its `outPath` string without descending either, so a derivation-valued body keeps a content key instead of spending the budget.

## License

MIT — see `LICENSE`.
