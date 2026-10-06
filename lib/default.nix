# gen-aspects — ported to the pure-gen stack (gen-prelude + gen-merge), bypassing nixpkgs.
#   prelude : gen-prelude.lib (pure utility base)
#   merge   : gen-merge.lib (evalModuleTree + structural types + mkOption/mkMerge/… ; the lib.types
#             + lib.evalModules replacement — leaf checkers come from gen-types via merge.types)
#   schema  : the (ported, pure) gen-schema.lib — mkAspectSchema wraps aspectType for its
#             kind-level infrastructure.
# The grammar (types.nix) produces the aspect node set WITHOUT evalModules; nixpkgs.lib-free.
{
  prelude,
  merge,
  schema,
  identity,
  algebra,
}:
let
  # The one first-order term algebra, minted by the ecosystem's one formula (den-hoag-lwbb1).
  T = algebra.term identity.hashIdentity;
  types = import ./types.nix {
    inherit
      prelude
      merge
      schema
      T
      ;
    inherit (identity) hashIdentity;
  };
  # ★ RENAMED FROM `identity` TO AVOID SHADOWING THE INJECTED MINT. gen-identity arrives as
  # `identity` on the ecosystem's convention — the library name minus `gen-`, as prelude, merge
  # and schema all do — and a file-local binding of the same name silently captured it for the
  # whole `let` body. The parameter is interface and the let-binding is private, so the private
  # one yields. This module is gen-aspects' own aspect-KEY derivation (paths, keys, guard keys),
  # which is a different concern from the mint and now reads as one.
  aspectIdentity = import ./identity.nix { inherit prelude; };
  cnfModule = import ./cnf.nix;
  canTakeModule = import ./can-take.nix { inherit prelude; };
  flatten = import ./flatten.nix; # dep-free bare value
  factsModule = import ./facts.nix {
    inherit prelude T;
    inherit (types)
      includesDefault
      keyCategory
      hasClassContent
      GT
      ;
  };
  guardModule = import ./guard.nix {
    inherit prelude merge T;
    inherit (types) GT;
  };
  instanceModule = import ./instance.nix {
    inherit prelude;
    inherit (identity) hashIdentity;
    inherit (guardModule) mkGuardVocab;
    inherit (types) GT;
    inherit (factsModule) graphCore;
    inherit (types) aspectId;
  };
  schemaModule = import ./schema.nix {
    inherit prelude merge;
    genSchema = schema;
    inherit (types)
      aspectType
      aspectsRoot
      mkIsModuleFn
      keyCategory
      ;
    inherit (aspectIdentity)
      aspectPath
      pathKey
      key
      isMeaningfulName
      ;
    canTake = canTakeModule;
  };
in
{
  # Legacy API preserved for backward compat
  inherit (types)
    aspectType
    aspectSubmodule
    aspectsType
    aspectsRoot
    aspectOrFn
    mkIsModuleFn
    canTake
    ;
  # `wrapFn` and `wrapGatedFn` are RETIRED (den-hoag-lwbb1 stage 2b): refused-by-name aliases naming
  # the gen-rules door, which a context closure crosses. See lib/types.nix.
  inherit (types) wrapFn wrapGatedFn;
  # THE canonical, uniform aspect content-address (all three kinds). den-hoag retired its
  # `sha256 "den-aspect:${key}"` hand-roll onto it. `aspectId origin aspect`. See lib/types.nix.
  inherit (types) aspectId;
  # `instanceOf cnf { aspect; value; context; sources; }` → `{ id; entry; formals; }` — the instance
  # mint: a guard record or carrier applied to a context is a node of its own, identified by
  # its aspect and by the sources of the keys it receives there (0cmbt spec §2.5). See lib/instance.nix.
  inherit (instanceModule) instanceOf;
  # `instancesFor cnf aspects { suppliers; scopes; containment; }` → `{ vertices; instantiates;
  # reaches; nestedAt; declined; }` — the instance relation: one vertex per minted instance, its
  # `instantiates` edge to its declaration, scope → instance edges and, per reading node, nested edges
  # from vertices, each fanning out over the containment descendants derived from `containment`
  # (den-hoag-8g2rn), minted in depth passes over reached pairs only (0cmbt spec §2.6), with the walked
  # guards whose condition was decided FALSE (`declined`, den-hoag-n8wb5). The materialised view
  # gen-delivery's `project` reads. See lib/instance.nix.
  inherit (instanceModule) instancesFor;
  # `structuralKeys` (the six native structural option names as ONE binding) + `keyCategory cnf key` — the
  # single aspect-key classification surface a consumer reads a key's category from. See lib/types.nix.
  # `hasClassContent v` is its companion over the class VALUE: the has-content fact this library's
  # `null` class default makes representable, named at its source so a consumer composes with it
  # instead of privately re-deriving it (ADR-0012 clause 2). A key is a class carrying content when
  # `keyCategory cnf k == "class" && hasClassContent entry.${k}`. Both of its clauses are
  # load-bearing — it also excludes the FABRICATED EMPTY deferredModule this library never emits but
  # a directly-supplied registry can — and it answers "was this key given a defining module", never
  # "does that module carry non-vacuous fields", which would force the deferred body. See lib/types.nix.
  inherit (types) structuralKeys keyCategory hasClassContent;
  # `isGuardLeaf v` — whether an aspect value is a guard leaf (a `__guard` record): a node whose content exists only once a context is supplied. It is the membership
  # predicate `flatten` and `graphFacts` already stop at (`lib/walk.nix`), named here so a consumer
  # reading `graphFacts`' `nodeData` asks this library rather than re-deriving the shape test.
  inherit (import ./walk.nix) isGuardLeaf;
  inherit (aspectIdentity)
    aspectPath
    pathKey
    parsePath
    key
    isMeaningfulName
    guardKey
    keyRef
    ;
  # New API
  inherit (schemaModule) mkAspectSchema;
  inherit flatten;
  # `graphFacts cnf aspects` →
  # `{ nodes; parentOf; includeSitesOf; includesOf; foreignIncludesOf; unresolvedIncludesOf;
  #   nodeIdOf; nodeData; }` —
  # THE aspect graph's facts as plain data. The node set, the edge relations and the node values,
  # published so a framework assembles the graph from them instead of parsing `flatten`'s key for
  # parenthood (ADR-0012: the flat registry is a projection, never a source). The id and the parent
  # are BOTH the node's walk position, so a disagreement between them is inexpressible — see
  # lib/facts.nix for the measurement that makes one source a correctness requirement.
  inherit (factsModule) graphFacts;
  # `includeSitesOfInstance cnf aspects iid entry` — `graphFacts`' include-site classification over
  # any aspect value, its anonymous content keyed under `iid`: an applied instance body gives the
  # sites its consumer descends, and a node's value under its own id its `includeSitesOf`. One
  # function for both, so the relation and its reader cannot disagree.
  inherit (factsModule) includeSitesOfInstance;
  inherit (guardModule)
    mkGuardVocab
    pred
    guard
    ;
  # the base vocab (open world, no door); a consumer with a declared set or a door uses
  # (mkGuardVocab cnf).applyGuard
  applyGuard = (guardModule.mkGuardVocab { }).applyGuard;
  # The recognised `cnf` key set as data. Every entry point above whose first argument is a `cnf`
  # constructs it through this vocabulary and refuses an off-domain key by name; `cnfKeys` is the set
  # the refusal renders, exported so a consumer — and the drift pin that checks it against the
  # library's own reads — reads it from here rather than restating it. The defaults behind it stay
  # internal: a consumer asks whether a key is RECOGNISED, and nothing outside this library needs the
  # value each key falls back to.
  inherit (cnfModule) cnfKeys;
}
