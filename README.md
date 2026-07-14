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

One flat type (`aspectType`) dispatches by value shape at merge time (Palmer 2024): attrsets and module functions become aspect submodules, context-dependent guard functions are wrapped as inspectable, tagged functors, and primitives pass through unchanged. The library computes stable identity keys and, via `flatten`, a flat path-keyed registry suitable for graph queries.

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
| [gen-rebuild](https://github.com/sini/gen-rebuild) | Pure-Nix incremental rebuilder (change propagation, AFFECTED set) |
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
          classes = { nixos = {}; homeManager = {}; };
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

**Classes** are registered content buckets (`nixos`, `homeManager`, `darwin`). When registered via `cnf.classes`, class keys become explicit `deferredModule` options — clean content with no structural keys injected. This is the module system's own option/freeform separation, not a custom dispatch mechanism.

**Guard functions** like `{ host, ... }: { nixos = ...; }` are context-dependent aspects that should not be evaluated eagerly. They're detected via `canTake` (all required args must be known module args) and wrapped via `functionTo` for pipeline resolution later.

**Module functions** like `{ config, ... }: { ... }` or `{ aspect, ... }: { ... }` are evaluated immediately by the submodule — they have access to `_module.args.aspect` (self-reference) and standard module args.

## Aspect identity (A-IDENT)

Every aspect carries an **intrinsic path identity** — its `.key` is a function of *where it sits in the aspect tree*, computed at merge and never reconstructed downstream. `aspectSubmodule` reads its own option path (the `prefix` gen-merge threads into every module body, equal to the merge `loc`) and stamps `meta.aspect-chain`; `key` then computes `pathKey(meta.aspect-chain ++ [name]) = pathKey(prefix)`.

The rule (VERBATIM):

> **A-IDENT (intrinsic path identity).** Let an aspect container hold a tree of nested aspects. For every nested aspect `a` at container-relative path `p = [k₀ … kₙ]` (the sequence of freeform keys from the container root down to `a`, EXCLUDING the module-system mount prefix and EXCLUDING registered class/structural keys), gen-aspects stamps, intrinsically on the value: `a.name = kₙ` and `a.meta.aspect-chain = [k₀ … kₙ₋₁]`. Its identity key is `key(a) = pathKey(a.meta.aspect-chain ++ [a.name]) = pathKey(p)`.
> **Collision law:** two aspects share a key **iff** they occupy the same container-relative path.
> **Corollary (no name-only collapse):** distinct paths ⇒ distinct keys; in particular `key(hardware.cpu.intel) = "hardware/cpu/intel" ≠ "hardware/gpu/intel" = key(hardware.gpu.intel)`.
> **Parametric exception (unchanged):** a wrapped closure include (`__isWrappedFn`, and guard functions/records) is identified by its definition site `meta.loc` (already path-bearing) plus its arguments — its identity is parametric but KNOWN; A-IDENT unifies plain aspects to the SAME path-bearing key discipline, it does not alter the wrapped/guard branches.

**Key form — mount-ABSOLUTE.** The stamped `prefix` is the module-system `loc`, which *includes* the mount segment the aspects container is mounted under (`aspects/…` in these tests, `den/aspects/…` in [den](https://github.com/sini/den)). So `key` carries that mount segment. This form was chosen deliberately (over a container-relative one) because:

- **It unifies the plain and guard namespaces.** The guard branch already keys off `meta.loc` (mount-absolute, e.g. `aspects/theme/fonts`). Making plain aspects mount-absolute too puts *both* in ONE namespace, so a plain aspect and a guard function at the same path key identically and dedup — exactly what the collision law requires.
- **It avoids mount-strip fragility.** A container-relative key would have to subtract the mount depth, which differs per consumer (den mounts deeper) — mount-dependent and brittle.
- **It is registry/namespace-ready.** The mount prefix is a proto-namespace; when the future aspect-registry / cross-flake origin qualifier lands, the key becomes `pathKey(origin ++ path)` — the qualifier extends the key *additively*, no re-key churn.

**One identity, two views.** `flatten`'s walk key is the SAME identity, expressed container-relative (no mount): `key(a) == mount ++ flattenKey(a)` (e.g. `.key = "aspects/apps/media/spicetify"` vs flatten key `"apps/media/spicetify"`). A constant mount prefix shifts every key equally, so the dedup equivalence classes coincide — `flatten` and `.key` are two surfaces of one path identity, not two divergent surfaces.

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

`mkAspectModule` lazily injects `config.schema.aspect.__defsModule` into each aspect's `aspectModules`, so schema extensions are available without manual wiring.

## Flat Registry

The `flatten` function walks the recursive aspect tree and produces a flat attrset keyed by path identity:

```nix
aspects = gen-aspects.lib;

flat = aspects.flatten eval.config.aspects;
# => { "networking" = ...; "networking/firewall" = ...; }
```

Entries are the aspect values unchanged — `flatten` does not inject any fields. Parent relationships are implicit in the path key: `"networking/firewall"` → parent is `"networking"`. Guard functions (`__isWrappedFn`) are included as entries but not recursed into.

Detection is structural rather than relying on a hardcoded key list:

- Nested aspects are attrsets with a `name` field (from `aspectSubmodule`)
- Class content (`deferredModule`) lacks `name` and is skipped
- Primitives (strings, lists) are skipped

The flat registry enables gen-graph and gen-select queries over the aspect tree. Parent accessors derive from the key:

```nix
parentOf = id:
  let parts = lib.splitString "/" id;
  in if builtins.length parts <= 1 then null
  else lib.concatStringsSep "/" (lib.init parts);
```

## API Reference

The `.lib` value exposes nineteen top-level names: the four aspect types, `wrapFn`, the four identity/introspection utilities plus `guardKey`, the four schema-and-registry entry points, and the five-name guard-predicate vocabulary (`mkGuardVocab`, `applyGuard`, `toArgData`, `pred`, `guard`).

```nix
aspects = gen-aspects.lib;
```

### Types

- **`aspectsType cnf`** — top-level container. Submodule with `freeformType = lazyAttrsOf (aspectType cnf)` and fixpoint (`_module.args.aspects = config`).

- **`aspectSubmodule cnf`** — aspect entry. Submodule with structural options (`name`, `description`, `key`, `meta`, `includes`), explicit `deferredModule` options per registered class, and freeform for nested aspects.

- **`aspectType cnf`** — Palmer flat dispatch. One type, dispatch in merge. Attrsets and module functions → `aspectSubmodule`. Guard functions → `functionTo` wrapper. Primitives → passthrough.

- **`aspectOrFn cnf`** — `either aspectType aspectSubmodule`. Recursion-safe binding for `includes` and nested aspect positions.

- **`wrapFn cnf name fn`** — wrap a single raw closure `ctx: <aspect>` as an inspectable `__isWrappedFn` functor: the API sibling of the guard-function wrap that `aspectType` applies automatically. A native bare-fn include rides the option-type merge; a **programmatically generated** include (built off the type, e.g. a bridge that raw-absorbs a foreign surface) bypasses that merge and must call `wrapFn` explicitly — the same rationale (Palmer's three eliminators over a value the type never intercepted) that makes a generated guard record first-order data. A `wrapFn`'d include is equivalent to a type-merge-wrapped bare fn (same formals; same merged content per context).

### Configuration (`cnf`)

```nix
aspectsType {
  # Registered class names → explicit deferredModule options (clean content)
  classes = { nixos = {}; homeManager = {}; };

  # Known module args for module/guard function detection
  # Default: { lib, config, options, pkgs, modulesPath, aspect }
  moduleArgs = { lib = true; config = true; /* ... */ };

  # Additional NixOS modules imported into every aspect entry
  # Use for pipeline-specific options (excludes, policies, etc.)
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
- **`mkIsModuleFn cnf`** — `canTake.upTo (cnf.moduleArgs or defaults)`. Returns a predicate that classifies functions as module fns or guard fns.
- **`key`**, **`aspectPath`**, **`pathKey`**, **`isMeaningfulName`**, **`guardKey`** — identity computation from `meta` + `name`. `key` routes three ways: static aspects (via `meta.aspect-chain`, stamped intrinsically at merge from the option path — [A-IDENT](#aspect-identity-a-ident)), wrapped guard functions (via `meta.loc`), and defunctionalized guard records (`__guard` → `guardKey`, a site-independent structural key over the predicate + first-order body). All three are mount-absolute, so plain and guard keys share one namespace.

### Schema & Registry

- **`mkAspectSchema cnf`** — bridges aspect types to gen-schema kind-level infrastructure. Returns `schemaOption`, `mkAspectOption`, `mkAspectModule`, `mkNamespaceType`, plus re-exports (`aspectType`, `identity`, `canTake`, `mkIsModuleFn`). See [Schema Integration](#schema-integration).
- **`flatten aspects`** — walks the recursive aspect tree into a flat attrset keyed by `path` identity (`"parent/child"`), structurally detecting nested aspects vs class content. See [Flat Registry](#flat-registry).

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

**Reynolds (1972) "Definitional Interpreters" + Danvy & Nielsen (2001) "Defunctionalization at Work"** — gen-aspects ships a closed guard-**predicate vocabulary** (`lib/guard.nix`) that is a genuine §6 defunctionalization for the guard function-space: a guard is a `{ __guard; pred; body }` record whose *predicate* is pure first-order data (`pred.host`/`class`/`user`/`tagEq`/`eq`/`all`/`any`/`always`, type-tagged via `toArgData`), dispatched by a single global `applyGuard` (case-analysis on the predicate tag — Reynolds' `apply`), and identified by a **site-independent** `guardKey = H(pred, bodyKey)` (the constructor tag replaces source position). The O1–O8 obligation checklist is Danvy & Nielsen's formalization of Reynolds §6. **Honest boundary:** arbitrary `{ host, … }: { … }` closures cannot be auto-defunctionalized in pure Nix (function equality is undecidable — the closure wall), so they remain a *non-defunctionalized escape hatch* via `functionTo` (a tagged, still-callable functor with a source-position key); `applyGuard` handles both. `guardKey` content-hashes a first-order body (enabling dedup); an opaque body (a closure / `deferredModule`) falls back to source position — sound (no false merge), just no cross-site dedup.

## License

MIT — see `LICENSE`.
