# gen-aspects — aspect type system (traits, classification, dispatch)

[![CI](https://github.com/sini/gen-aspects/actions/workflows/ci.yml/badge.svg)](https://github.com/sini/gen-aspects/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT) [![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/sini)

Aspect-oriented composition types for Nix module systems.

A pure type library: no resolve, no pipeline, no framework. It provides the structural types for defining aspects — composable configuration units with identity, includes, and class-separated content. Consumers (like [den](https://github.com/sini/den)) bring their own evaluation pipeline.

**nixpkgs-lib-free.** The type system is re-hosted on [gen-merge](https://github.com/sini/gen-merge): `evalModuleTree`, the structural types and `mkOption`/`mkMerge` stand in for `lib.types` and `lib.evalModules`, with leaf checkers arriving from [gen-types](https://github.com/sini/gen-types) through merge. The grammar in `lib/types.nix` produces the aspect node set without `evalModules` at all, and nixpkgs is pulled only in `ci/`, for the harness. Enforced by `ci/tests/purity.nix` rather than by convention.

Sibling dependencies: [gen-identity](https://github.com/sini/gen-identity), [gen-merge](https://github.com/sini/gen-merge), [gen-prelude](https://github.com/sini/gen-prelude) and [gen-schema](https://github.com/sini/gen-schema).

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

| Term        | Definition                                                                                                                                                                                                                                         |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Traits      | The aspect type — one type, dispatch in merge (Palmer 2024)                                                                                                                                                                                        |
| Classes     | Output targets (NixOS, darwin, homeManager module systems)                                                                                                                                                                                         |
| Collections | Named data aggregation (aspect keys matching registered collection names)                                                                                                                                                                          |
| Edges       | `includes` (forward I) — the one core structural edge, declared inline on each aspect. `neededBy` (reverse I) — a *consumer-declared, predicate-based* reverse reference; its semantics live in the consumer's dispatch layer, not in these types. |
| Constraints | Pruning rules: meta.guard, meta.drop, meta.substitute                                                                                                                                                                                              |

## Overview

gen-aspects gives you the *types*, not a framework. An **aspect** is a submodule carrying structural identity (`name`, `key`, `meta`, `includes`) plus freeform, class-separated content. You register your target module systems as **classes** (`nixos`, `homeManager`, `darwin`); each class becomes a clean `deferredModule` option so content stays free of the structural keys.

One flat type (`aspectType`) dispatches by value shape at merge time (Palmer 2024): attrsets and module functions become aspect submodules, guard records are checked against their `cnf`, a context closure is refused by name (it crosses the gen-rules door, the one closure crossing), and primitives pass through unchanged, except a scalar or list reached below an undeclared key's nested aspect: nothing gave it a meaning, so it is refused by name as an orphan leaf, naming its full key path and the declared class keys. The library computes stable identity keys, and via `graphFacts` publishes the aspect graph's facts — the node set, the parent and include relations, and the node values — for a framework to assemble a graph from. `flatten` renders the same walk as a flat path-keyed registry.

Everything downstream — evaluation, scheduling, conflict resolution, dispatch policy — is the consumer's job. gen-aspects supplies the type surface and the identity keys; the pipeline lives in [gen-resolve](https://github.com/sini/gen-resolve) / [gen-dispatch](https://github.com/sini/gen-dispatch) / [den](https://github.com/sini/den).

## Gen Ecosystem

| Library                                              | Role                                                                                                                                                                                                                                                                                                                                                       |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [gen-prelude](https://github.com/sini/gen-prelude)   | Pure nixpkgs-lib-free utility base (builtins re-exports + vendored lib utils)                                                                                                                                                                                                                                                                              |
| [gen-algebra](https://github.com/sini/gen-algebra)   | Pure primitives (record, either, intensional identity)                                                                                                                                                                                                                                                                                                     |
| [gen-types](https://github.com/sini/gen-types)       | Clean-room MIT structural type checker (leaf/poly checkers; `verify: v → null\|err`)                                                                                                                                                                                                                                                                       |
| [gen-merge](https://github.com/sini/gen-merge)       | Byte-mode module merge engine (`evalModuleTree`, byte-identical to nixpkgs `lib.evalModules` over the priority subset)                                                                                                                                                                                                                                     |
| [gen-schema](https://github.com/sini/gen-schema)     | Typed registries (kinds, instances, collections, refs); re-hosted on gen-merge                                                                                                                                                                                                                                                                             |
| [gen-aspects](https://github.com/sini/gen-aspects)   | **This lib** — Aspect type system (traits, classification, dispatch); re-hosted on gen-merge                                                                                                                                                                                                                                                               |
| [gen-scope](https://github.com/sini/gen-scope)       | HOAG scope-graph evaluator (demand-driven, \_eval memoization, circular attributes)                                                                                                                                                                                                                                                                        |
| [gen-graph](https://github.com/sini/gen-graph)       | Accessor-based graph query combinators (traversal, condensation, phaseOrder)                                                                                                                                                                                                                                                                               |
| [gen-select](https://github.com/sini/gen-select)     | Selector algebra (pattern matching over graph positions)                                                                                                                                                                                                                                                                                                   |
| [gen-bind](https://github.com/sini/gen-bind)         | Module binding (inject external args into NixOS modules)                                                                                                                                                                                                                                                                                                   |
| [gen-dispatch](https://github.com/sini/gen-dispatch) | Relational rule dispatch STEP (stratified phases, conflict resolution)                                                                                                                                                                                                                                                                                     |
| [gen-memo](https://github.com/sini/gen-memo)         | The incremental plane — decides reuse, never evaluates (change propagation, AFFECTED set)                                                                                                                                                                                                                                                                  |
| [gen-vars](https://github.com/sini/gen-vars)         | Pure-Nix vars/secrets (den-agnostic)                                                                                                                                                                                                                                                                                                                       |
| [gen-flake](https://github.com/sini/gen-flake)       | Orphaned as reference rather than deleted, so its record stays readable — dissolution complete. Was the nixpkgs boundary; successors: compose → hub `lib.compose`/flakeModule (INTERIM, not the settled framework interface), warm/override/trace → gen-memo, projection+realize → gen-delivery, inject/terminals → the crossing's Adapter set via the hub |

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

An **undeclared** key falls through the freeform fallback to a nested aspect (it gets identity). This is the module system's own option/freeform separation driven by one declared map, not a custom dispatch mechanism — the bounded category set and its meaning live in gen-aspects; gen-schema records `category` opaquely. There is no hardcoded `classes` arm: a class is simply a `keySemantics` entry with `category = "class"`. The category is validated per key, lazily: a malformed entry throws a named error where that key is read, and never while reading an unrelated aspect.

**Context closures** like `{ host, ... }: { nixos = ...; }` are told apart from module functions via `canTake` (a module function's required args are all known module args) and refused by name: a closure crosses the gen-rules door, which lowers it to a door node. A context-dependent aspect is written as a guard record, `guard (pred.has "host") { … }`, whose body reads the context through read terms.

**Module functions** like `{ config, ... }: { ... }` or `{ aspect, ... }: { ... }` are evaluated immediately by the submodule — they have access to `_module.args.aspect` (self-reference) and standard module args.

## Aspect identity (A-IDENT)

Every aspect carries an **intrinsic path identity** — its `.key` is a function of *where it sits in the aspect tree*, computed at merge and never reconstructed downstream. The top aspect container (`aspectsRoot`) re-roots its children so that below it the `prefix` gen-merge threads into every module body is **container-relative** (the module-system mount segment is dropped); `aspectSubmodule` reads that `prefix` and stamps `meta.aspect-chain`; `key` then computes `pathKey(meta.aspect-chain ++ [name]) = pathKey(prefix)`.

The rule (VERBATIM):

> **A-IDENT (intrinsic path identity).** Let an aspect container hold a tree of nested aspects. For every nested aspect `a` at container-relative path `p = [k₀ … kₙ]` (the sequence of freeform keys from the container root down to `a`, EXCLUDING the module-system mount prefix and EXCLUDING registered class/structural keys), gen-aspects stamps, intrinsically on the value: `a.name = kₙ` and `a.meta.aspect-chain = [k₀ … kₙ₋₁]`. Its identity key is `key(a) = pathKey(a.meta.aspect-chain ++ [a.name]) = pathKey(p)`.
> **Collision law:** two aspects share a key **iff** they occupy the same container-relative path.
> **Corollary (no name-only collapse):** distinct paths ⇒ distinct keys; in particular `key(hardware.cpu.intel) = "hardware/cpu/intel" ≠ "hardware/gpu/intel" = key(hardware.gpu.intel)`.
> **Parametric exception (unchanged):** a guard record is identified by the mint over its condition and body, never by a path; its instances add the sources of what it reads. A-IDENT unifies plain aspects to the path-bearing key discipline; it does not alter the guard branch.

**Key form — container-RELATIVE.** The stamped `prefix` is the merge `loc` *re-rooted at the aspect container*: the top container `aspectsRoot` merges each first-level aspect at `prefix = [key]` (dropping the module-system mount segment the container is mounted under — `aspects` in these tests, `den/aspects` in [den](https://github.com/sini/den)), and descendants accumulate relative from there. So `key(apps.media.spicetify) = "apps/media/spicetify"`, no mount. This form was chosen (over mount-absolute) because:

- **It is origin-invariant.** An aspect's key is a function of its position *within its aspect tree*, independent of where the consumer mounts that tree. This is the property the future aspect-registry / cross-flake origin work needs (an imported aspect keys by its definition origin, not the consumer's mount point — spec §3a north-star): the container root IS the proto-namespace root, and an origin qualifier prepends *additively* (`pathKey(origin ++ path)`).
- **It matches den-hoag's identity form.** den-hoag's `__provider` reconstruction is already root-relative (`apps/media/spicetify`), so consuming the native relative `.key` is byte-for-byte the same key — the lowest-churn path to retiring the shadow layer.
- **It keeps plain and guard unified.** The re-root is a *uniform* reset applied to every value the container merges (not a depth-based strip), so a guard record placed at a path (its `meta.loc`, also re-rooted) lands in the SAME relative namespace as plain aspects.

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

| Field                                | Description                                                                                                                                                                                                               |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `schemaOption`                       | gen-schema option wrapping `aspectType` as the custom entry type                                                                                                                                                          |
| `mkAspectOption { providerPrefix? }` | Declares `options.aspects` with `lazyAttrsOf aspectType`                                                                                                                                                                  |
| `mkAspectModule { providerPrefix? }` | NixOS module declaring both `options.aspects` and `options.schema`, lazily threading schema-declared options into every aspect instance                                                                                   |
| `mkNamespaceType { config }`         | Submodule type for namespace composition — includes `schema`, `classes`, and freeform aspect content. `config` (required) is the enclosing evaluation's config: a namespace's aspects read its `schema.aspect` extensions |
| `aspectType`                         | Re-exported aspect type                                                                                                                                                                                                   |
| `identity`                           | Bundled identity functions (`aspectPath`, `pathKey`, `key`, `isMeaningfulName`)                                                                                                                                           |
| `canTake`                            | Re-exported function arg introspection                                                                                                                                                                                    |
| `mkIsModuleFn`                       | Re-exported module function predicate                                                                                                                                                                                     |

The three constructors take a closed options set: a field outside the ones shown is refused by name, catchably, naming the constructor (`gen-aspects.mkAspectSchema.<name>`) and the accepted set.

**Redeclaration.** The per-cnf types are built per construction, so a container declared twice (two `mkAspectModule` calls, or `mkAspectModule` beside `mkAspectOption`) meets two records of one name. They state their merge relation through gen-schema's `constructionRelation`, read off `lib/cnf.nix` `cnfConstruction`, by each key's regime in `cnfVocabulary`: one construction (one cnf, reached through one slot) merges, and two are refused by name. The module lists `aspectModules` and `metaModules` are not identity: as a nixpkgs submodule's `modules` do, two declarations' lists concatenate and the merged type is built over both, so each side's options reach the aspect. `ref`, the framework's door, is read by no type and distinguishes nothing. Stated limits: module content is outside the relation's `records` — a module in `collections`, or a facet entry's `module`, declaring an option typed by a per-call `mkOptionType` aborts when two constructions are compared in the order that interns `functor` first, and in every order when that type has a `description` back-edge; a function in a compared key reached by a selection written at each site is two slots, refused on Nix and Determinate and merged on Lix; and a module list is concatenated, so an anonymous module in both declarations is never deduplicated and is imported twice (a list option it defines holds its definition twice), while a keyed or path module is imported once, as in nixpkgs.

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

A construction formal written at the kind entry's top level is refused by name, because there it
would land on every aspect as a nested aspect while the schema's own formal stayed what the
constructor fixed: `schema.aspect.keySemantics = …` (meant to widen the class vocabulary) or
`schema.aspect.providerPrefix = …`. The names are the `mkAspectSchema` cnf keys (`aspects.cnfKeys`)
and gen-schema's own formals, and a cnf collection named for a cnf key is refused the same way. Pass
a formal to `mkAspectSchema`; an aspect field of the same name is written on the aspect, or as
`schema.aspect.config.<name>` (under `closedKeys` it must be declared or listed in `freeformKeys`).
The refusal covers every route into the entry: a formal at the top level of a module the entry
imports (nested `imports`, `require`, a function or path module, a whole-module `mkIf`) is refused by
gen-merge's collector with the same text, saying it was written in a module the kind entry imports and
naming the module.

## Flat Registry

The `flatten` function walks the recursive aspect tree and produces a flat attrset keyed by path identity:

```nix
aspects = gen-aspects.lib;

flat = aspects.flatten eval.config.aspects;
# => { "networking" = ...; "networking/firewall" = ...; }
```

Entries are the aspect values unchanged — `flatten` does not inject any fields. Guard records (`__guard`) are included as entries but never recursed into.

**The path key is a RENDERING of a parent edge, not the edge. Do not split it.** `"networking/firewall"` looks like it says its parent is `"networking"`, and for a plain aspect it happens to agree — but a nested guard leaf is in the registry carrying no `meta.aspect-chain` at all, so the two derivations a consumer might reach for disagree on it, and the `meta.aspect-chain or [ ]` one answers *root* for a node whose parent is its container. Worse, that wrong answer is indistinguishable from a right one: a genuine root aspect yields `[ ]` through the same accessor, so absence and root are the same value. Read `graphFacts` instead.

Detection is structural rather than relying on a hardcoded key list:

- Nested aspects are attrsets with a `name` field (from `aspectSubmodule`)
- Class content (`deferredModule`) lacks `name` and is skipped
- Primitives (strings, lists) are skipped

### Published facts

`graphFacts` publishes what a graph is built FROM — the node set, the edge relations and the node values — as plain data. gen-aspects imports no query library for this: the query libraries are needed to *query* a graph, never to *state* one, and every fact here is an attrset, a list or a string.

```nix
facts = aspects.graphFacts cnf eval.config.aspects;
# => { nodes                = [ "networking" "networking/firewall" … ];
#      parentOf             = { "networking" = null; "networking/firewall" = "networking"; … };
#      includeSitesOf       = { "networking" = [ ]; … };
#      includesOf           = { "networking" = [ ]; … };
#      foreignIncludesOf    = { "networking" = [ ]; … };
#      unresolvedIncludesOf = { "networking" = [ ]; … };
#      nodeIdOf             = { "networking" = "networking"; … };
#      nodeData             = { "networking" = <the aspect value, unchanged>; … }; }
```

- **A node id is `pathKey(cnf.providerPrefix ++ walkPath)`** — the walk position the registry already keys on, qualified by origin. It is deliberately *not* `identity.key`: that function content-addresses a guard record, which would move every guard node's name off its position.
- **`parentOf` is the node's own WALK POSITION, and the id and the parent come from one source.** A framework holding only the registry and the values would have to join on `meta`, and that join is wrong rather than merely redundant — a nested guard leaf carries no `meta.aspect-chain` at all, so `meta.aspect-chain or [ ]` answers root for it, indistinguishably from a genuine root. That is why the relation is published here. It is *not* why it should be computed from `meta` here: this library holds the walk, and reading a position out of `meta` instead is wrong on values this library accepts — a guard built by the public `guard` in a tree no aspect type stamped carries no `meta.loc`, and a guard carried by value from another tree carries the `meta.loc` of where it was placed there.
- **`parentOf` is total, and `null` means root and only root.** Every node has an answer. Totality holds *by construction* rather than by a check: the walk descends only into values it also emits, so a non-root node's parent is necessarily already a node — there is no dangling case for a refusal to guard.
- **`includesOf` carries the edges this library CHECKED, and every target it emits is in `nodes`** — universally, with no exception and at every provider-prefix length. It resolves the include elements that reference a *local* node.
- **`foreignIncludesOf` carries the references it could NOT check.** A **foreign** `keyRef` names a node in a fixpoint gen-aspects does not hold, so it is not an edge of this graph; it is published as a reference in the declaration's own `{ origin; path; key; }` shape, and the framework — which unions providers — is what resolves it. That is what `keyRef` is for. **Which keyRefs are foreign is decided by the origin, and the string sugar takes its origin from the FIRST SEGMENT** — `keyRef "prov/a/b"` has origin `[ "prov" ]`, always exactly one element, by construction. So the sugar can name a local node only when `cnf.providerPrefix` is itself one segment long: under the default `[ ]` — gen-link's `self`, the state of a corpus whose origin is assigned at federation — **every** string-sugar keyRef is foreign and contributes no edge to `includesOf`. Use the structured form (`keyRef { origin = [ ]; path = [ … ]; }`) for a reference you want checked locally. The shape is structured rather than a rendered `"origin/path"` string on purpose: a rendering has to be re-split downstream to recover the qualifier, and that re-split is a second source for a fact the declaration already stated. The two relations are **exclusive**, which is the point — left together, an unchecked reference is spelled exactly like a checked edge, and a consumer unioning edge targets into a node set widens the graph past its own membership predicate on a value nothing refused.
- **`unresolvedIncludesOf` names the declared positions that reference no node.** An `includes` list holds two kinds of thing, and only one is an edge: a *reference* (a `keyRef`, a by-value aspect whose key is a node, or a bare string — never a bare string as content; see below), and *inline content* written at the include position (a wrapped fn, a guard record, a deferred closure or policy record, an aspect literal). The walk never descends into `includes`, so inline content has no node for an edge to reach. Its position is published rather than dropped — index back into `nodeData.<id>.includes` for the element itself. A *keyed* value is inline content only when it was written at an include position — its `.key` and its `meta.aspect-chain` both carry `includes` past their first segment; content copied from another aspect or another tree keeps where it was written and stays content. A bare string is always a reference (a use-site name is a reference, never a declaration), resolved locally against this tree's own registry exactly like a by-value element's `.key`; it is never published here as unresolved content, and one naming no node is refused by name, catchably.
- **`includeSitesOf` is every include position of a node, in declared order, classified — and the three relations above are its projections.** Each site is `{ kind = "local"; target; }`, `{ kind = "foreign"; ref; }`, `{ kind = "content"; sites; }` or `{ kind = "sealed"; }`. *Content* is a keyed aspect literal written at the include position (including the element `aspectType` coerces a function definition into when it is one of several definitions of an aspect), or a key-less attrset that is not a guard leaf — the literal in a guard's fired body, which the aspect type never merged — and its `sites` are that element's own includes, classified by the same rule. *Sealed* is every other inline element: a guard record, whose content exists only once a context is supplied, and a function (a module function in an applied body is sealed, a defaulted, reversible choice pending an owner reading). The rule is one for a node's value and an applied body (`includeSitesOfEntry`). `includesOf` is the top-level `local` targets, `foreignIncludesOf` the `foreign` refs, `unresolvedIncludesOf` the `content` and `sealed` positions: one classification pass feeds all four, so they cannot disagree. A position is a list index (at depth, a path of them); nothing is minted for inline content. A `content` site's `sites` is lazy, so a bad reference inside inline content refuses only for a reader that descends into it, and content nested past 256 levels (almost always a literal that includes itself) refuses by name there rather than growing without end.
- **`nodeIdOf` maps the local key a member is named by to its node id.** A consumer naming an aspect by its key reads the id here rather than re-rendering `providerPrefix ++ [ key ]`, which would be a second source for it.
- **`isGuardLeaf v`** (top level, beside `graphFacts`) answers whether a node value is a guard leaf — a `__guard` record, the node shape whose content exists only in a context. It is the predicate the walk itself stops at, so a consumer reading `nodeData` asks it here rather than re-deriving the shape test.
- **References resolve by identity, never by the key field alone.** A by-value element that is not inline content, and a bare string, resolve through `gen-prelude`'s `resolve` against this tree's nodes: a bare string must name a node by its local key, and a by-value element is the node whose stamp (`id_hash`) and `key` it carries — the key only *locates* the candidate, and the verdict compares the canonical entry, minting nothing. So a member resolves whether written by name or by value (including one whose `name` moved its key off its walk id), and each of these is refused by name, catchably, at `gen-aspects.includes (aspect '<id>', include position <i>)`: a key naming no node (a value from another tree, a key set by hand), a member edited off its canonical entry (`base // { key = "app"; }` keeps base's stamp and so is not `app`), a value carrying no stamp, and a bare string naming nothing. A `keyRef` carrying *this* tree's own origin is checked the same way against the walk and refused when it names no node; a genuinely foreign origin names a node in a fixpoint this library does not hold and is not checkable here. A refusal surfaces in every include relation of that node (`includesOf`, `foreignIncludesOf`, `unresolvedIncludesOf`) and in no other node's. The scope is keyed values: a *key-less* node value (a guard leaf, a wrapped fn) from another tree is still read as content.
- **★ The one admission that is not a refusal: another tree's value with the same origin and the same key IS the local node.** `id_hash` is minted over origin and key, so such a value carries the local node's stamp and key, and by the identity law it is that node: it resolves to the local id, and `nodeData` serves the LOCAL value — **the foreign value's content is dropped, and nothing says so.** No loud arm exists without either widening aspect identity to content (module functions refuse identity, so most aspects would have none) or giving each tree a distinct origin (every aspect id moves, and every tree at the default origin `[ ]` breaks). To keep two trees' aspects apart, give them distinct `providerPrefix`es — their stamps then differ, and the foreign value is refused by name — or reference the other tree's node with `keyRef`. Pinned by `test-references-resolve-by-identity`'s `otherTreeSameKey` rows.

A framework builds the graph from these with `gen-graph.labeledFrom` / `fromRegistry` and expresses its named views over `gen-select`'s algebra; the registry above is one such view.

## API Reference

The `.lib` value exposes the five aspect types (incl. `aspectsRoot`, the re-rooting container), the value-shape introspection (`canTake`), the retired `wrapFn` and `wrapGatedFn` (refused by name), the instance mint and relation (`instanceOf`, `instancesFor`), the identity/introspection utilities plus `guardKey` and `keyRef`, the schema-and-registry entry points (`mkAspectSchema`, `flatten`, `graphFacts`, `includeSitesOfEntry`, `isGuardLeaf`, `keyCategory`, `structuralKeys`, `cnfKeys`), and the guard vocabulary (`mkGuardVocab`, `applyGuard`, `pred`, `guard`). The roster itself is the binding, not a count restated in prose — read `lib/default.nix`.

```nix
aspects = gen-aspects.lib;
```

### Types

- **`aspectsType cnf`** — top-level container. Submodule with `freeformType = lazyAttrsOf (aspectType cnf)` and fixpoint (`_module.args.aspects = config`).

- **`aspectSubmodule cnf`** — aspect entry. Submodule with structural options (`name`, `description`, `key`, `meta`, `includes`), one option per declared `cnf.keySemantics` key built generically from its category (class → `nullOr deferredModule` defaulting to `null`, channel → `raw`, facet → the entry's `option`/`module`), and freeform for undeclared (nested) aspects.

- **`aspectType cnf`** — Palmer flat dispatch. One type, dispatch in merge. Attrsets and module functions → `aspectSubmodule`. Guard records → checked against the `cnf`. A context closure → refused by name, naming the gen-rules door. Primitives → passthrough.

- **`aspectOrFn cnf`** — `either aspectType aspectSubmodule`. Recursion-safe binding for `includes` and nested aspect positions.

- **`wrapFn`, `wrapGatedFn`** — RETIRED. Each refuses by name at its first application: a context closure crosses the gen-rules door, which lowers it to a door node, so declare the aspect through the framework's surface or write it as a guard term (`guard (pred.has <coordinate>) <body>`). The same refusal meets a context closure anywhere a gen-aspects type reads one (an aspect, an `includes` element, a definition beside others), and `applyGuard` handed a closure. A closure inside the result of a module function written at an aspect position is refused the same way; the message says the lowering does not enter that result.

  **The declared set and the entity kinds.** A framework declares its coordinates as `cnf.entityKinds`: `null`, the default, is the open world; a list declares its names, all of them entity kinds (`[ ]` is a closed world with no coordinates); an attrset `{ <name> = <bool>; }` declares its names and marks an entity kind `true`. Any other value is refused by name. A context key *is* the name of the entity kind whose value it carries (entity kinds are the framework's to declare). A guard's condition is a term, not an aspect: it reads the context unnarrowed, and a read of a coordinate outside the declared set (with this library's own `class` and `tags`) is refused when the guard is checked.

- **`instanceOf cnf { aspect; value; context; sources; scope ? { }; }`** — the instance mint. A parametric aspect (a first-order guard, or a guard carrier) applied to a context is a node of its own, the instance: `{ id; entry; formals; scope; }`. A first-order guard receives its DERIVED READS, the coordinates its condition and body terms read, so it is keyed on what it reads and not on the whole context. `formals` maps each key the aspect receives at `context` to its entry in `sources`, the identity of the entity or argument binding that supplied it, and `id` is `hashIdentity "aspect-instance"` over `{ aspect; formals; }`. So two contexts handing the aspect different values are two instances, two that differ only in keys it never reads are one, and a guard that reads nothing is one instance everywhere. `entry` is the guard fired at `context`, and `scope` its instantiation scope: the closures of the door nodes its firing left in `entry` unfired. Such a node fired later through `instanceOf` handed that `scope` reads its closure there; handed none, the door re-applies the outer to recover it, the same value at one outer application per firing. `scope` never enters the id, and it is the caller's to hand the right one: it is checked only by key. A key with no source, a source that is a value rather than an identity, and a source that is an aspect's or an instance's identity are each refused by name.

- **`instancesFor cnf aspects { suppliers; scopes; }`**: the instance relation, `{ vertices; reaches; nested; }`. Each node's scope is `{ members; sources; descendants ? [ { sources; } … ]; }`, and each tuple's context is derived from its sources through `suppliers.<source>.<key> = <value>`, so one scope never reads another's content. A node's members are walked through static aspects to the parametric ones they reach, and each is minted at the node's own tuple, or once per descendant tuple (a host's users) where the scope's own tuple does not satisfy its condition: `reaches.<node>.<aspect>` lists those instance ids. Every instance is one vertex, `vertices.<id> = { aspect; formals; entry; scope; }`, however many nodes reach it, and the parametric aspects its applied body includes are minted once at its own tuple as `nested.<id>.<aspect>`. A static aspect inside a body resolves at the reaching node's scope. A pair no tuple supplies has no edge. Malformed scopes refuse by name.

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
- **`key`**, **`aspectPath`**, **`pathKey`**, **`isMeaningfulName`**, **`guardKey`** — identity computation from `meta` + `name`. `key` routes two ways: static aspects (via `meta.aspect-chain`, stamped intrinsically at merge from the option path — [A-IDENT](#aspect-identity-a-ident)) and first-order guard records (`__guard` → `guardKey`, the mint over the condition and body terms, defined once the guard is checked against its cnf; a module function in the body is a slot keyed by its position, never its payload, and there is no source-position fallback). Both are container-relative (re-rooted by `aspectsRoot`), so plain and guard keys share one namespace.

### Schema & Registry

- **`mkAspectSchema cnf`** — bridges aspect types to gen-schema kind-level infrastructure. Returns `schemaOption`, `mkAspectOption`, `mkAspectModule`, `mkNamespaceType`, plus re-exports (`aspectType`, `identity`, `canTake`, `mkIsModuleFn`). See [Schema Integration](#schema-integration).
- **`flatten aspects`** — walks the recursive aspect tree into a flat attrset keyed by `path` identity (`"parent/child"`), structurally detecting nested aspects vs class content. The key is a rendering of a parent edge, never the edge; read `graphFacts` for parenthood. See [Flat Registry](#flat-registry).
- **`graphFacts cnf aspects`** — the aspect graph's facts as plain data: `{ nodes; parentOf; includeSitesOf; includesOf; foreignIncludesOf; unresolvedIncludesOf; nodeIdOf; nodeData; deliversOf; deadNested; }`, keyed by origin-qualified node id (`nodeIdOf` by local key). `parentOf` is the walk position and is total by construction; `includeSitesOf` classifies every include position in order and the three include relations project from it; inline include content is published as positions, and a reference whose target is missing refuses by name. `deliversOf` says whether a node's subtree delivers (declared class content, includes, a guard leaf, or a delivering child), and `deadNested` is the nested nodes whose subtree does not; the record warns once each time it is forced while `deadNested` is non-empty (a misspelt class key, or intended placeholder taxonomy, for which the warning is expected). See [Published facts](#published-facts).
- **`includeSitesOfEntry cnf aspects entry`**: the include-site classification `graphFacts` publishes as `includeSitesOf`, over any aspect value. A node's value gives its `includeSitesOf` entry, and an applied instance body gives the sites a consumer descends, so the relation and its reader classify a body with one function.
- **`isGuardLeaf v`** — whether an aspect value is a guard leaf (a wrapped fn or a guard record), the node shape `flatten` and `graphFacts` stop at.

## Demo

The `examples/demo/` directory exercises nine gen libraries together: gen-algebra, gen-schema, gen-aspects, gen-graph, gen-scope, gen-select, gen-bind, gen-dispatch, and gen-delivery. It demonstrates entities, aspects, namespaces, policies, queries, bindings, composition, settings, and delivery-class realization in a single integrated flake, over invented node kinds: gen names no domain entities, and a framework supplies its own names.

## Testing

```bash
nix develop ./ci --command ci
```

`ci` refuses when anything under a declared read root is unknown to git — any extension or name,
`_`-prefixed included — and the remedy is `git add` or a move. The bare `nix-unit --flake ./ci#tests`
and `nix flake check ./ci` are unguarded: they read a git-filtered copy of the tree, so an untracked
cell is silently absent and the run stays green.

381 cells on the value plane and 96 on the error plane (`nix develop ./ci --command ci` ⇒ `381/381 successful`, `ci --tests-error` ⇒ `96/96 successful`) — one file per suite under `ci/tests/`, which is the count's own source rather than a list restated here, since the last three restatements (`115/17`, `236/33`, then `247/34`) each went stale by the next landing. Coverage spans class content cleanliness, nested aspect identity, includes fixpoint, module vs guard function dispatch, first-order guards over gen-algebra's term algebra (`ci/tests/first-order-guards.nix`: the condition vocabulary, the declared set, identity, instance keys, the door and its totality, nested guards and the depth budget behind a cyclic body), lazy classification, parametric aspects, multi-def merging, reserved keys, primitive passthrough, deep nesting, extensions, `meta` modules, `canTake` introspection, schema integration, and the flat registry.

## Theoretical Foundations

| Paper                                                                                              | Relationship | Mechanism                                                                                                                                                                                                                                                                                                                                                                            |
| -------------------------------------------------------------------------------------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Palmer et al. (2024) "Intensional Functions"                                                       | Implements   | Flat dispatch via one type in merge §2, identity §2.2; identity keys enable consumer-side dedup                                                                                                                                                                                                                                                                                      |
| Lorenzen et al. (2025) "First-Order Laziness"                                                      | Informed by  | `deferredModule` inspectable before forcing (via Nix native laziness, not Lorenzen's mechanism) §1-2.3                                                                                                                                                                                                                                                                               |
| Reynolds (1972) "Definitional Interpreters" · Danvy & Nielsen (2001) "Defunctionalization at Work" | Implements   | §6 "Elimination of Higher-Order Functions" for guards (`mkGuardVocab`/`pred`/`applyGuard`/`guardKey`): a guard is a condition term and a body term of gen-algebra's one first-order algebra, interpreted by its one resolver through this library's read environment, keyed by the mint over the two. A raw `{ host, … }:` closure is refused by name: it crosses the gen-rules door |

**Palmer et al. (2024) "Intensional Functions"** — One type dispatches by value shape in merge (§2). Guard functions are defunctionalized as callable first-order data with inspectable args (§5.1). Identity keys enable consumer-side diamond dedup (Lemma 5.12 + Theorem 1, closure consistency); gen-aspects supplies the keys, the dedup lives in the consumer.

**Lorenzen et al. (2025) "First-Order Laziness"** (informed by) — Class content as `deferredModule` is inspectable before forcing, evaluated only when the consuming NixOS evaluation imports it (§1-2.3). This property comes from Nix native laziness plus nixpkgs `deferredModule`, NOT from Lorenzen's mechanism (first-order named constructors, defunctionalized deferred operations, in-place memoization). The citation is provenance for the laziness idea, not an implementation of the paper.

**Reynolds (1972) "Definitional Interpreters" + Danvy & Nielsen (2001) "Defunctionalization at Work"** — a guard is `{ __guard; condition; body; }`, a condition term and a body term of gen-algebra's ONE first-order algebra (`lib/guard-term.nix` is this library's instance of it). The condition vocabulary (`pred.class`/`tagEq`/`eq`/`has`/`all`/`any`/`always`/`not`) is constructors emitting core terms, so there is one interpreter, the core's resolver (Reynolds' `apply`), whose read environment gen-aspects supplies. A custom condition is a Nix function that builds a term at declaration: a new interpreted atom would need a case in the one apply function, a closure held beside it, which is what defunctionalization removes. A body is a term or first-order data, lifted to its term where the guard meets its `cnf` and checked there (shape, declared names, safety); a class key's value is a declared module slot, carried opaque, and a module function at another position of the body is a slot keyed by its position. A guard's identity is the mint over (condition, body), defined once it is checked, with no source-position fallback. A guard nested in a body stays a guard: it is checked as its own clause and fires at its own firing. The lift spends one depth budget, so a cyclic body is refused by name (`guard-depth`), catchably, rather than aborting the evaluator. **Honest boundary:** arbitrary `{ thimble, … }: { … }` closures cannot be auto-defunctionalized in pure Nix (function equality is undecidable — the closure wall), so gen-aspects holds none: a context closure is refused by name, naming the gen-rules door, the one closure crossing (design Q8 (c′)), which lowers it to a door node.

## License

MIT — see `LICENSE`.
