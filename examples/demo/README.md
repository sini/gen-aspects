# gen-aspects demo: web deployment fleet

A single integrated flake exercising all 8 gen libraries together. Models a web deployment fleet with environments (prod, staging, dev), hosts, services, and observability — demonstrating aspects, schema extensions, scope-based settings composition, graph queries, selector patterns, policy dispatch, and module bindings.

## Running

```bash
nix eval --json .#aspectNames | jq   # list all aspects
nix eval --json .#aspectCount        # total aspect count
nix eval --json .#nginxWorkersProdWeb1  # composed setting: 32
nix eval --json .#nginxWorkersDev       # composed setting: 1
```

## Structure

```
modules/
  setup.nix          — instantiate all 8 gen libraries, wire aspect schema
  entities.nix       — fleet structure: environments + hosts
  aspects/
    base.nix         — base-system, networking, monitoring-base
    web.nix          — services/nginx, services/app (nested)
    data.nix         — services/postgres, services/redis (nested)
    security.nix     — hardening (plain), firewall (parametric: static settings + settings-consuming nixos)
    users.nix        — define-user
  namespace.nix      — observability namespace: prometheus, grafana, loki
  settings.nix       — per-scope settings overrides (env-level, host-level)
  composition.nix    — scope graph + neron traverse + foldLayers
  queries.nix        — gen-graph traversals + gen-select pattern matching
  policies.nix       — gen-derive fixpoint dispatch with action vocabulary
  bindings.nix       — gen-bind module wrapping with contracts
  outputs.nix        — flake outputs for verification
```

## What each library does here

| Library | Role in demo |
|---------|-------------|
| **gen-algebra** | `record.foldLayersTraced` merges settings layers (per-field replace/append/recursive) and returns a per-field provenance trace alongside the value |
| **gen-schema** | `mkAspectSchema` registers the aspect kind with collections (settings, tags) and schema extensions (priority, tier) |
| **gen-aspects** | `aspectsType` + `flatten` — type system for aspects with identity, classes, includes, parametric class content; flat registry for queries |
| **gen-scope** | Scope graph with env/host nodes, P-edges, neron traverse to collect settings in D > I > P order |
| **gen-graph** | `reachableFrom`, `dependentsOf`, `roots`, `leaves`, `cycles` over the aspect include graph |
| **gen-select** | `when`, `and`, `within` selectors — tag queries, tier filtering, namespace prefix matching |
| **gen-bind** | `wrap` binds resolved per-host settings into a parametric NixOS module (the settings-injection construct) with contract validation and provenance |
| **gen-derive** | `fixpoint` dispatches policy rules (prod hardening, database backup, dev firewall) with context enrichment |

## Key patterns demonstrated

### Aspect shapes

- **Static** — `base-system`, `networking`, `hardening`: plain attrset with tags, settings, nixos class content
- **Nested** — `services.nginx`, `services.postgres`: auto-nesting creates `services/nginx` identity
- **Parametric** — `firewall`, `services.nginx`: a STATIC settings schema (introspectable by `flatten`/cascade) plus class content written as `{ settings, host, lib, ... }: { ... }` that CONSUMES resolved per-host settings, injected before `evalModules` via the settings-injection construct

### Settings cascade

Settings schemas declare defaults and merge strategies per field. Scope graph layers (host overrides > env overrides > aspect defaults) compose via `foldLayers`:

```
aspect default:  nginx.performance.workers = 4
env:prod:        nginx.performance.workers = 16
host:prod-web-1: nginx.performance.workers = 32   # ← wins
```

Append-strategy fields accumulate across layers:

```
aspect default:   nginx.upstream.servers = []
host:prod-web-1:  nginx.upstream.servers = ["app-1:3000", "app-2:3000", "app-3:3000"]
```

### Schema extensions

`schema.aspect.options.priority` and `schema.aspect.options.tier` are declared on the schema kind and automatically available on every aspect instance — no manual wiring.

### Graph + selector queries

```nix
# All aspects reachable from nginx via includes
webDeps = genGraph.reachableFrom g "services/nginx";

# Aspects tagged "public-facing"
publicFacing = selectWhere (hasTag "public-facing");

# Aspects inside a "core"-tagged parent
childrenOfCore = selectWhere (genSelect.within (hasTag "core"));
```

### Policy fixpoint

Rules emit typed actions (`edge`, `enrich`, `configure`). `configure` carries an aspect target (`{ aspect; settings; }`) and folds into the cascade as the final layer; `enrich` actions feed back into context for the next iteration. Fixpoint converges when context stabilizes:

```nix
prodHardening = mkRule {
  condition.env = false;
  produce = _id: ctx:
    lib.optional (ctx.env.tier == "production") (act.edge { target = "hardening"; });
  identity = "prod-hardening";
  phase = "structural";
};
```

### Settings-injection construct (full loop)

Parametric class content (`{ settings, host, lib, ... }: { ... }`) reads resolved
settings that don't exist until the cascade runs. The `injectAspectSettings`
construct (`injection.nix`) closes the loop: for each `(host, aspect)` it binds
the cascade's `composedSettings.<host>.<leaf>` (+ host) into the class content via
`genBind.wrap`, producing a ready-to-`evalModules` module (`assembledClasses`).

`outputs.nix` exercises this end-to-end against rendered module values:

```
fwInjectionMatchesCascade  # firewall.allowed-tcp cascade == rendered allowedTCPPorts
nginxInjectionResolved     # resolved workers=32 reaches nginx config (worker_processes 32)
```

### Cascade provenance + policy-overrides-host

`foldLayersTraced` records, per field, which layer contributed each value. The demo
turns that into discriminating proofs:

```
loggingLevelProdWeb1        # "error" — policy (folded LAST) beats env's "warn"
loggingLevelProdWeb1Winner  # "policy"  (replace winner = last contributor)
workersProdWeb1Winner       # "host"    — negative control: policy doesn't touch workers
dbBackupSubkeyProvenance    # per-subkey on a recursive field:
                            #   { schedule="policy"; retention="policy";
                            #     method="host"; destination="host"; }
```
