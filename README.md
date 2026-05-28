# gen-aspects

[![CI](https://github.com/sini/gen-aspects/actions/workflows/ci.yml/badge.svg)](https://github.com/sini/gen-aspects/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT) [![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/sini)

Aspect-oriented composition types for Nix module systems.

A pure type library: no resolve, no pipeline, no framework. Provides the structural types for defining aspects — composable configuration units with identity, includes, and class-separated content. Consumers (like [den](https://github.com/sini/den)) bring their own evaluation pipeline.

## Table of Contents

- [Terminology](#terminology)
- [Gen Ecosystem](#gen-ecosystem)
- [Usage](#usage)
- [Core Concepts](#core-concepts)
- [API](#api)
  - [Types](#types)
  - [Configuration](#configuration-cnf)
  - [Utilities](#utilities)
- [Schema Integration](#schema-integration)
- [Flat Registry](#flat-registry)
- [Demo](#demo)
- [Testing](#testing)
- [Theoretical Foundations](#theoretical-foundations)

## Terminology

| Term | Definition |
|------|-----------|
| Traits | The aspect type — one type, dispatch in merge (Palmer 2024) |
| Classes | Output targets (NixOS, darwin, homeManager module systems) |
| Collections | Named data aggregation (aspect keys matching registered collection names) |
| Edges | Composition relationships: includes (forward I), neededBy (reverse I) |
| Constraints | Pruning rules: meta.guard, meta.drop, meta.substitute |

## Gen Ecosystem

| Library | Role |
|---------|------|
| [gen-algebra](https://github.com/sini/gen-algebra) | Pure primitives (search, record, identity) |
| [gen-schema](https://github.com/sini/gen-schema) | Typed registries (kinds, instances, collections, refs) |
| [gen-aspects](https://github.com/sini/gen-aspects) | Aspect types (traits, classification, dispatch, schema integration) |
| [gen-graph](https://github.com/sini/gen-graph) | Graph queries (combinators, traversals, fixpoint) |
| [gen-scope](https://github.com/sini/gen-scope) | Scope graphs (construction, evaluation, resolution) |
| [gen-select](https://github.com/sini/gen-select) | Selector algebra (pattern matching over graph positions) |
| [gen-bind](https://github.com/sini/gen-bind) | Module binding (inject args into NixOS modules) |
| [gen-derive](https://github.com/sini/gen-derive) | Rule dispatch (stratified phases, fixpoint, conflict resolution) |

## Usage

```nix
let
  aspects = import gen-aspects { inherit lib; };
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

## API

```nix
aspects = import gen-aspects { inherit lib; };
```

### Types

- **`aspectsType cnf`** — top-level container. Submodule with `freeformType = lazyAttrsOf (aspectType cnf)` and fixpoint (`_module.args.aspects = config`).

- **`aspectSubmodule cnf`** — aspect entry. Submodule with structural options (`name`, `description`, `key`, `meta`, `includes`), explicit `deferredModule` options per registered class, and freeform for nested aspects.

- **`aspectType cnf`** — Palmer flat dispatch. One type, dispatch in merge. Attrsets and module functions → `aspectSubmodule`. Guard functions → `functionTo` wrapper. Primitives → passthrough.

- **`aspectOrFn cnf`** — `either aspectType aspectSubmodule`. Recursion-safe binding for `includes` and nested aspect positions.

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
- **`key`**, **`aspectPath`**, **`pathKey`**, **`isMeaningfulName`** — identity computation from `meta` + `name`. `key` handles both static aspects (via `meta.aspect-chain`) and wrapped guard functions (via `meta.loc`).

## Schema Integration

gen-aspects depends on [gen-schema](https://github.com/sini/gen-schema) and provides `mkAspectSchema` to bridge aspect types with gen-schema's kind-level infrastructure (collections, introspection, schema extensions).

```nix
aspects = import gen-aspects { inherit lib; };
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
aspects = import gen-aspects { inherit lib; };

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

## Demo

The `examples/demo/` directory exercises all 8 gen libraries together: gen-algebra, gen-schema, gen-aspects, gen-graph, gen-scope, gen-select, gen-bind, and gen-derive. It demonstrates entities, aspects, namespaces, policies, queries, bindings, composition, and settings in a single integrated flake.

## Testing

```bash
nix shell nixpkgs#nix-unit -c nix-unit \
  --override-input target . \
  --flake './ci#.tests'
```

67 tests covering: class content cleanliness, nested aspect identity, includes/fixpoint, module vs guard function dispatch, multi-def merging, primitive passthrough, deep nesting, extensions, `canTake` introspection, schema integration, and flat registry.

## Theoretical Foundations

| Paper | Relationship | Mechanism |
|-------|-------------|-----------|
| Palmer et al. (2024) "Intensional Functions" | Implements | Flat dispatch via one type in merge §2, identity §2.2, fold-based dedup |
| Lorenzen et al. (2025) "First-Order Laziness" | Implements | `deferredModule` as lazy constructor §1-2.3 |
| Reynolds (1972) "Definitional Interpreters" | Implements | Guard function defunctionalization — closures become tagged data |

**Palmer et al. (2024) "Intensional Functions"** — One type dispatches by value shape in merge (§2). Guard functions are defunctionalized as callable first-order data with inspectable args (§5.1). Identity keys enable diamond dedup in fold-based collect (§5.3, Lemma 5.12).

**Lorenzen et al. (2025) "First-Order Laziness"** — Class content as `deferredModule` is a lazy constructor: inspectable before forcing, evaluated only when the consuming NixOS evaluation imports it (§1-2.3).

**Reynolds (1972) "Definitional Interpreters"** — Guard functions wrapped via `functionTo` are Reynolds defunctionalization: closures become tagged data (`__isWrappedFn`, `__functionArgs`) with explicit dispatch (`__functor`).
