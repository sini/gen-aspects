# gen-aspects demo: web deployment fleet

A single integrated flake exercising 9 gen libraries together. Models a web deployment fleet with environments (prod, staging, dev), hosts, services, and observability — demonstrating aspects, schema extensions, scope-based settings composition, graph queries, selector patterns, policy dispatch, module bindings, and delivery-class realization.

The gen definition tree (`gen-modules/`) is composed **purely** by the [gen hub](https://github.com/sini/gen)'s successor compose (`gen.lib.compose`) — gen-merge's byte-mode `evalModuleTree`, not flake-parts' nixpkgs `lib.evalModules`. The flake injects the resolved config **values** into the flake-parts eval as the `genValues` module arg; the readers (`modules/*`) run the settings cascade + graph/selector/policy/bind demos over those values. No gen *type* ever enters the flake-parts options tree — the value-injection invariant that lets a gen aspect schema coexist with flake-parts (the old `options.schema`/`options.aspects`/`options.namespaces` embeds threw under the pure re-host).

## Running

```bash
# --allow-dirty-locks is only needed while iterating with an uncommitted flake.lock:
nix eval --json .#aspectNames --allow-dirty-locks | jq   # list all aspects
nix eval --json .#aspectCount --allow-dirty-locks        # total aspect count
nix eval --json .#nginxWorkersProdWeb1 --allow-dirty-locks  # composed setting: 32
nix eval --json .#nginxWorkersDev --allow-dirty-locks       # composed setting: 1

# Full evaluation — proves no gen type enters the flake-parts options tree:
nix flake check --allow-dirty-locks
```

## Structure

```
flake.nix            — flake-parts + the hub's compose + gen-delivery project (DIRECT) + reader-side gen libs
gen-modules/         — the gen definition tree, composed PURELY by gen.lib.compose (evalModuleTree)
  setup.nix          — options.schema + options.aspects (the typed surface) + schema extensions
  _aspect-cnf.nix    — the mkAspectSchema ARGUMENT (one declaration: schema construction + gen-delivery's cnf)
  _aspect-schema.nix — shared mkAspectSchema construction (helper; _-prefixed, not a tree module)
  entities.nix       — fleet structure: environments + hosts (marked `pureModule` — warm-reusable)
  aspects/
    base.nix         — base-system, networking, monitoring-base
    web.nix          — services/nginx, services/app (nested)
    data.nix         — services/postgres, services/redis (nested)
    security.nix     — hardening (plain), firewall (parametric: static settings + settings-consuming nixos)
    users.nix        — define-user
  namespace.nix      — observability namespace: prometheus, grafana, loki
  settings.nix       — per-scope settings overrides (env-level, host-level)
modules/             — the flake-parts (reader) side; reads genValues, NOT composed into the tree
  composition.nix    — scope graph + neron traverse + foldLayers (over genValues)
  queries.nix        — gen-graph traversals + gen-select pattern matching (over genValues)
  policies.nix       — gen-dispatch step + gen-scope.circular loop with action vocabulary
  bindings.nix       — gen-bind signature/wrapped METADATA probe (bindResults)
  terminal.nix       — the nixos-class TERMINAL: gen-delivery realize + the refinements layer → realized (per-host systems)
  override-trace.nix — warm override showcase: composed.override → the memoization trace (pureModule fleet reused)
  _policy-rules.nix  — shared policy action vocabulary + rules (helper; _-prefixed, not a module)
  outputs.nix        — flake outputs for verification (reads genValues + reader results)
```

### Class-content terminal — gen-delivery's `project` + `realize`

The `nixos` class content is built by [gen-delivery](https://github.com/sini/gen-delivery) (`terminal.nix`): the projection discovers the **declared** delivery classes per node (the `cnf` — the demo's own `mkAspectSchema` argument, shared via `gen-modules/_aspect-cnf.nix`), and the fold hands each class's collected content to the target-owned terminal. Because the demo needs two knobs the hub's `flakeModules.default` ergonomics module does not surface, it drives the lower-level surfaces directly:

- `project { selectHosts; }` — the fleet lives under `fleet.hosts`, not the top-level `hosts` the default projection reads, and the projection needs each host tagged with the aspects its role runs (the fleet schema carries only env/role, so `selectHosts` synthesizes membership: web/all hosts run `firewall` + `services/nginx`, database hosts run `firewall` only).
- `realize { refinements; }` — the reader-computed per-`(host, aspect)` settings cascade (`composedSettings`) is passed as the per-node contribution layer (the declared layer order: projection < global < refinement). v0's `mkSystems` `wrapAll` bound only the resolved `host` instance, with no hook for that richer settings binding — so this demo used to hand-roll a "reader terminal" (per-aspect `genBind.wrap` + a stub `evalModules`). `realize`'s refinement layer lets the terminal itself wrap the class content.

The terminal here is a pure **DATA terminal** (the design's "attrset builder — no nixpkgs"): it wraps a host's class deferredModules with `genBind.wrapAll` and renders them through a bare `lib.evalModules` over stub options, so the demo asserts exact resolved values without a full NixOS eval. `realize` folds it per host into `realized.nixos.<host>` = the host's composed config.

**Intentional delta vs the reader terminal.** The reader terminal rendered each aspect in isolation; `realize` composes ALL of a host's aspects into ONE system. So `networking.firewall.allowedTCPPorts` on a web/all host now UNIONs the firewall cascade with nginx's public port (443) — the correct behaviour for a composed host system. The assertions moved from per-aspect equality to whole-system checks (cascade ports preserved as a subset; nginx contributes exactly its port; database hosts, running firewall only, carry no 443).

## What each library does here

| Library | Role in demo |
|---------|-------------|
| **gen-algebra** | `record.foldLayersTraced` merges settings layers (per-field replace/append/recursive) and returns a per-field provenance trace alongside the value |
| **gen-schema** | `mkAspectSchema` registers the aspect kind with collections (settings, tags) and schema extensions (priority, tier) |
| **gen-aspects** | `aspectsType` + `flatten` — type system for aspects with identity, classes, includes, parametric class content; flat registry for queries |
| **gen-scope** | Scope graph with env/host nodes, P-edges, neron traverse to collect settings in D > I > P order; `circular` (Kleene ascent) drives the policy dispatch convergence loop |
| **gen-graph** | `reachableFrom`, `dependentsOf`, `roots`, `leaves`, `cycles` over the aspect include graph; `phaseOrder` (over `entryAnywhere`/`entryAfter`) linearizes the policy dispatch groups |
| **gen-select** | `when`, `and`, `within` selectors — tag queries, tier filtering, namespace prefix matching |
| **gen-bind** | `wrapAll` binds the resolved per-host settings into the parametric NixOS modules at the terminal (via realize's `refinements` layer); `wrap`/`buildSignature` also drive the standalone binding-metadata probe (`bindings.nix`) with contract validation and provenance |
| **gen-delivery** | `project` discovers the DECLARED delivery classes per node (`cnf` + `selectHosts`) and reshapes the flat registry per host; `realize` folds each host's class content through the DATA terminal with the declared contribution-layer order |
| **gen-dispatch** | the pure dispatch STEP: `mkRule`/`mkActions` + `dispatch` fire policy rules (prod hardening, database backup, dev firewall) across ordered groups with context enrichment; the caller threads the domain state through repeated one-shot dispatch (the LOOP is gen-scope's, the ORDER is gen-graph's) |

## Key patterns demonstrated

### Aspect shapes

- **Static** — `base-system`, `networking`, `hardening`: plain attrset with tags, settings, nixos class content
- **Nested** — `services.nginx`, `services.postgres`: auto-nesting creates `services/nginx` identity
- **Parametric** — `firewall`, `services.nginx`: a STATIC settings schema (introspectable by `flatten`/cascade) plus class content written as `{ settings, host, lib, ... }: { ... }` that CONSUMES resolved per-host settings, injected at the terminal via realize's `refinements` layer

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

### Policy dispatch (step + loop)

Rules emit typed actions (`edge`, `enrich`, `configure`) over ordered groups. Group order comes from `gen-graph.phaseOrder` (`structural` before `configuration`); the pure dispatch STEP (`gen-dispatch.dispatch`) fires the matching rules for a pass, and `gen-scope.circular` (Kleene ascent) is the LOOP that drives it to a fixpoint — the step threads the plain domain state (context), each pass being one one-shot dispatch whose output context is the next iterate. `configure` carries an aspect target (`{ aspect; settings; }`) and folds into the cascade as the final layer; `enrich` actions feed back into context (via `extract`) so later passes see them. Convergence is reached when the context key-set stabilizes, and the policy actions are read off the converged context by one post-convergence dispatch (`result.actions.<group>`) — a function of the fixpoint, not the iteration path:

```nix
prodHardening = mkRule {
  condition.env = false;
  produce = _id: ctx:
    lib.optional (ctx.env.tier == "production") (act.edge { target = "hardening"; });
  identity = "prod-hardening";
  group = "structural";
};
```

### Settings injection via realize's `refinements` layer (full loop)

Parametric class content (`{ settings, host, lib, ... }: { ... }`) reads resolved
settings that don't exist until the cascade runs. `terminal.nix` closes the loop:
it passes the cascade's `composedSettings.<host>` (+ host) as realize's per-node
`refinements` layer, and `realize` folds each host's class deferredModules through
the DATA terminal (`genBind.wrapAll` + `lib.evalModules`) into `realized.nixos.<host>`.

`outputs.nix` exercises this end-to-end against the rendered, COMPOSED system:

```
fwCascadePortsPreserved    # firewall.allowed-tcp cascade survives (subset of) the composed ports
nginxPortAddDevAll         # [443] — nginx contributes exactly its public port to the union
dbHasNoNginxPort           # true — a database host runs firewall only (membership drives the build)
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

### Warm override + memoization trace

`composed.override edits` re-composes the tree. When `edits` carries ONLY `modules` (a modules-only
append), the successor compose fires gen-merge's WARM path: it SPLICES the previous eval's declared
leaves the edit provably cannot touch and re-merges only the rest, byte-identically to a cold
re-compose (the standing cold-parity oracle pins warm ≡ cold on both values and provenance). The
admission is gen-memo's `warmAdmits`; the trace record is gen-memo's `warmTrace` over the engine's
`warmDecision`. `override-trace.nix` overrides the composed tree by appending one host-level settings
layer and projects the result's `trace`, documented under
[gen-merge](https://github.com/sini/gen-merge#warm-re-eval-memoized-override) `Warm re-eval`.

The reuse turns on the `pureModule` marker: `gen-modules/entities.nix` wraps the fleet inventory in
`genMerge.pureModule` (it reads only `lib` from `specialArgs`, never `config`/`options` — the
[pureModule contract](https://github.com/sini/gen-merge#the-puremodule-contract)), so the engine may
splice its leaves unchanged. Every other tree module is a function reading `config` (dirty by default),
so it re-merges:

```
overrideTrace.mode        # "warm"
overrideTrace.reused      # ["fleet.environments" "fleet.hosts"] — the marked fleet, SPLICED
overrideTrace.remerged    # { aspects; namespaces; schema; scopeSettings; } — the dirty function modules (scopeSettings is dirty-decl settings.nix, not driven by the edit)
overrideModeWarm          # true  — a modules-only edit fires the warm path
overrideFleetReused       # true  — fleet.hosts ∈ reused (the pureModule's leaves)
overrideSettingsRemerged  # true  — scopeSettings re-merges as dirty-decl (settings.nix), regardless of the edit
overrideMarkedPureClean   # true  — the pureModule marking took effect (fleet is the sole clean entry)

overrideColdControlMode          # "cold" — RED control: the same edit + a second key (specialArgs) refuses warm
overrideColdControlFleetDropped  # true   — nothing spliced on the cold path (the invariants measure the warm path, not a constant)
```
