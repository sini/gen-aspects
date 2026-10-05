# THE INSTANCE MINT (den-hoag-0cmbt spec §2.5): `instanceOf cnf { aspect; value; context; sources;
# scope ? { }; }` → `{ id; entry; formals; scope; }`. A parametric aspect applied to a context is a
# node of its own, the instance, whose identity is its declaration and what it was handed (design
# §3): two contexts that hand it different values are two instances, and two that differ only in keys
# it never receives are one.
#
#   formals = { <k> = sources.<k>; } for every key k the definitions are handed at `context`
#   id      = hashIdentity "aspect-instance" [ "aspect" "formals" ] { aspect; formals; }
#   entry   = the aspect applied to `context`
#
#   scope   = the instance's instantiation scope: the scope it was handed, extended by every door
#             firing inside it (lib/guard-term.nix `fireScoped`)
#
# `formals` nests under its own label, so a formal named `aspect` does not clash with the relatum.
# A `{ }:` aspect receives nothing: `formals = { }`, one id for every context.
#
# THE RECEIVED KEYS. A first-order guard receives the coordinates it READS, derived from its terms,
# that the context supplies. A guard carrier (`__guard` with `fragments`: a guard defined more than
# once under one key, the K2 site) unions its record fragments' reads; an `unconditional` fragment
# reads no context.
#
# THE SOURCES (design K3). `sources` maps each context key to the identity of what supplied it, an
# entity's identity or a K1 argument binding's (gen-scope `argumentBinding`), so the binding ids reach
# the mint by the same call that carries the context. This is K3's "(or hands over an instance it
# minted)" arm: the applicator's functor keeps its arity (`w ctx`), and the sources travel here.
#
# THE DOORS, each a catchable `throw` naming this entry:
# - the argument is not the closed record `{ aspect; value; context; sources; }`, or `aspect` is not a
#   string, or `context`, `sources` or `scope` is not an attrset;
# - the value is not parametric (not a guard record or carrier);
# - a received key has no source (design §3, "a formal with no known supplier refuses by name");
# - a source is not identity-shaped (`<kind>:<64 hex>`): the honest mistake of handing the context
#   VALUE where its supplier's identity belongs (ADR-0016 r7, "a relatum must already be a minted
#   node"; the minter holds no registry, so it checks the shape);
# A source is never refused by its kind tag: a framework names its own entity kinds (ADR-0035), so a
# kind spelled `aspect` or `aspect-instance` supplies arguments like any other. Whether a source is a
# node that supplies no argument is decided by GRAPH MEMBERSHIP, and only `instancesFor` holds a graph
# (its door, below; den-hoag-fkkzk, owner-ruled arm (d)).
# ITS BOUNDS, enumerated (ADR-0025 item 1). A source that is the instance's OWN id is a let-bound
# fixpoint: no door can read it before forcing it, so it aborts with `infinite recursion`,
# uncatchably. Holding no registry, the mint refuses no identity-shaped source: an aspect's id or an
# instance's id handed here mints.
# THE CALLER'S OBLIGATION. Each source must be the supplier of the value the context carries under its
# key. The id reads only the sources, and the minter holds no registry to check them against the
# context, so a mismatch is not refused: two contexts with one source and different values mint ONE id
# carrying two different entries. `instancesFor` (below) cannot be handed that input: it derives each
# context from its sources through one `suppliers` map (spec §2.6, gate C-1).
#
# THE SCOPE (den-hoag-ohvjc). A door node left unfired in an instance's entry (its condition needs a
# key the instance's context lacks) is fired later as an instance of its own, and handed the scope of
# the instance whose entry holds it, it reads its closure there: the door is handed it as `captured`
# and applies it, once. `scope` is the door's closure environment passed explicitly (guard-term's G5
# scope ruling: a guard stores no closure), never an input to the id: it holds closures (ADR-0034's
# sealed limb), and the nested id it serves already names its outer and the outer's sources. `scope`
# JOINS THE CALLER'S OBLIGATION and is unchecked beyond the key lookup: a scope holding no key for the
# node's id is the fallback, silently and with the same value, and a scope of the same outer sources
# carrying other values is the mismatch above, undetected. The door's own source-rebound refusal
# (gen-rules `mkApply`) fires before `captured` is read, whichever scope is handed.
#
# COST: O(definitions × reads) for the received keys, one `hashIdentity` over O(formals) labelled
# entries, and one firing. The guard vocabulary that discharges a carrier is built once per
# `instanceOf cnf`. Nothing scans another instance. A deferred door node fired WITHOUT its outer's
# scope is the door's fallback, a correct degraded mode (ADR-0025 item 1: the value is returned): it
# re-applies the outer closure, and every closure between, to recover its own, so K such firings
# cost K outer applications where the scope costs none.
{
  prelude,
  hashIdentity,
  mkGuardVocab,
  GT,
  graphCore,
  aspectId,
}:
let
  inherit (import ./cnf.nix) checkedEntry;
  inherit (import ./walk.nix) isGuardLeaf;
  door = "gen-aspects.instanceOf";
  fields = [
    "aspect"
    "value"
    "context"
    "sources"
  ];
  names = prelude.concatStringsSep ", ";
  kindOf = s: if builtins.isString s then builtins.match "([^:]+):[0-9a-f]{64}" s else null;
  # The mint over a constructed `cnf`; `instanceOf` is it behind `checkedEntry`.
  mint =
    cnf:
    let
      inherit (mkGuardVocab cnf) applyGuardScoped;
    in
    args:
    let
      a = prelude.checkOptions door (fields ++ [ "scope" ]) (prelude.checkRequired door fields args);
      inherit (a)
        aspect
        value
        context
        sources
        ;
      scope = a.scope or { };
      guarded = builtins.isAttrs value && (value.__guard or false);
      carrier = guarded && value ? fragments;
      fragments = if carrier then value.fragments else [ ];
      at = "aspect `${prelude.concatStringsSep "." (value.meta.loc or [ "<guard-carrier>" ])}`";
      # A first-order guard (or a carrier's record fragment) receives the coordinates it READS, derived
      # from its terms (design Section 3, the instance rule), that the context supplies.
      readsOf =
        g:
        builtins.filter (k: context ? ${k}) (
          GT.derivedReads cnf context (GT.checkGuard cnf at (g // { __guard = true; }))
        );
      received =
        if !carrier then
          readsOf value
        else
          builtins.attrNames (
            prelude.genAttrs (builtins.concatMap readsOf (builtins.filter (f: f.kind == "record") fragments)) (
              _: null
            )
          );
      missing = builtins.filter (k: !(sources ? ${k})) received;
      notIdentity = builtins.filter (k: kindOf sources.${k} == null) received;
      formals = prelude.genAttrs received (k: sources.${k});
      refuse = msg: throw "${door}: aspect `${aspect}` ${msg}";
    in
    if !(builtins.isString aspect) then
      throw "${door}: `aspect` must be the aspect's identity, a string; received: ${builtins.typeOf aspect}."
    else if !(builtins.isAttrs context) then
      refuse "was handed a context of type ${builtins.typeOf context}; a context is an attrset of coords."
    else if !(builtins.isAttrs sources) then
      refuse "was handed sources of type ${builtins.typeOf sources}; sources map each context key to the identity that supplied it."
    else if !(builtins.isAttrs scope) then
      refuse "was handed a scope of type ${builtins.typeOf scope}; a scope is an instance's `scope`, closures keyed by nested registration identifiers."
    else if !guarded then
      refuse "is not parametric: it is not a guard record or carrier, so it has no instances."
    else if missing != [ ] then
      refuse "reads formal(s) `${names missing}` with no known supplier; the sources map carries: ${names (builtins.attrNames sources)}."
    else if notIdentity != [ ] then
      refuse "was handed a source for formal(s) `${names notIdentity}` that is not an identity (`<kind>:<sha256>`); hand the identity of the entity or argument binding that supplied it, never its value."
    else
      let
        fired = applyGuardScoped { inherit context sources scope; } value;
      in
      {
        id = hashIdentity "aspect-instance" [ "aspect" "formals" ] (l: { inherit aspect formals; }.${l});
        entry = fired.value;
        inherit (fired) scope;
        inherit formals;
      };
in
{
  instanceOf = checkedEntry mint;

  # THE INSTANCE RELATION (den-hoag-0cmbt spec §2.6, owner-ruled C1; den-hoag-8g2rn): `instancesFor cnf
  # aspects { suppliers; scopes; containment; }`,
  #   suppliers   = { <source identity> = { <key> = <value>; … }; … }
  #   scopes      = { <node> = { members; sources; }; }
  #   containment = { <identifier> = { parent; key; identity; marked; bindings; }; }
  #   ⇒ { vertices.<iid> = { formals; entry; scope; };          one content cell per instance id
  #       instantiates.<iid> = [ <aspect> ];               instance → declaration, exactly one
  #       reaches.<node>.<aspect> = [ <iid> … ];           scope → instance edges
  #       nestedAt.<node>.<iid>.<aspect> = [ <iid> … ];    reaching edges FROM vertices, per reading node
  #       declined = { reaches.<node> = [ <aspect> … ];    the walked guards decided FALSE, per
  #                    nestedAt.<node>.<iid> = [ … ]; }; } handed scope and per (node, vertex), ascending
  # the materialised view (ADR-0012 clause 2) gen-delivery's `project` reads. Instances are nodes: the
  # reaching node is an edge, never a field of a vertex (ADR-0010 §4(a)). `<aspect>` is the facts id of
  # the parametric node. `instantiates` is an adjacency map (`id → [ids]`, the adjacency shape
  # gen-graph's classical doors read); `reaches` and `nestedAt` are grouped by `<aspect>` (`id → aspect
  # → [ids]`), their ids in minting order, each at its first occurrence. Never by id: ADR-0016 r5 lets
  # nothing durable depend on an `id_hash`, and an instance id moves when its aspect is renamed. A
  # vertex is shared by every node reaching it (one id, one application); its nested EDGES are per
  # reading node, because a nested include fans out at the meet of the vertex and the node (S3c).
  # ORDER IS CANONICAL (ruling 13, den-hoag-8g2rn). A fan-out's siblings are the descendants in the
  # order of their IDENTIFIERS, `containment`'s attribute names (ADR-0016 r5's readable vertex names),
  # so ADR-0029's invariance under presentation is discharged here, by construction: the order reads
  # only the attribute names, never an identity and never an instance id.
  #
  # THE CONTAINMENT. `containment` is the entity graph's ONE-STEP containment, handed as data: one
  # record per entity under its identifier, its parent's identifier (null at a root), the key it
  # binds, its identity, whether its containment edge carries a boundary mark (ADR-0026), and the
  # argument bindings declared AT it. The closure is DERIVED, never handed (gate C1): an entity's
  # COORDINATE is its own key and bindings and every ancestor's; its descendants are every entity whose
  # upward walk reaches it without leaving a marked entity. An argument binding inherits down the
  # chain, and one re-declared below SHADOWS the ancestor's for the re-declaring entity and its
  # descendants, as a new binding id (owner-ruled 2026-10-05, gen-scope `argumentBinding` R10); an
  # ENTITY key is a level and is bound once along a chain.
  #
  # THE INSTANTIATION EDGE (ADR-0010 §4(a) clauses 1–3; van Antwerpen 2018 §2.5, (F-TApp), Fig. 11).
  # An instance is its own scope (one vertex per id); its `I` edge, `instantiates`, points at its
  # declaration, whose members stay reachable through it (`instantiates · includes`, the members
  # `graphFacts.includeSitesOf` publishes from the checked body term); the substitution σ is the
  # vertex's `formals`, a datum on the node and never a payload on the edge (ADR-0016 r3), applied to
  # each field where it is read (`entry` is resolved per field, gen-algebra `resolveFields`), so one
  # unsound member refuses at its own read and nothing else. The query returns the RESOLVED members
  # only: a context-dependent element is a `deferred` site (ADR-0010 §4(b)'s σ-dependent target), found
  # in `unresolvedIncludesOf` and, per instance, in `nested`.
  # Clause 4, reverse-order normalisation along a projection path, is VACUOUS by construction: no term
  # former binds a coordinate (gen-algebra cell `known-formers-bind-no-coordinate`), a nested
  # instance's σ restricts its parent's meet with the reading node, extended by one containment
  # descendant's coordinate whose crossed levels it takes; a descendant extends its ancestors'
  # coordinate (an entity key bound twice refuses), a node never binds against its entities'
  # coordinates, and a descendant rebinding an entity key a tuple binds refuses at a node and at a
  # meet; and the one place a path could carry two substitutions for one key, a nested door rebinding
  # an outer source, is refused (gen-rules `mkApply`). Cells `instance-scope.test-rebound-refused-whichever-scope` and the path-consistency
  # cells in `instances.nix` hold each premise.
  #
  # ONLY REACHED PAIRS ARE EDGES. A node's `members` (facts ids) are walked over `graphFacts`' local
  # include sites, through static nodes and inline `content`, stopping at parametric ones; those are
  # minted at the node's scope. A slot per (scope, parametric node) would be an edge where no scope
  # reaches, which a query following instance edges would deliver.
  #
  # A TUPLE'S CONTEXT IS DERIVED, never handed: `context = mapAttrs (k: src: suppliers.${src}.${k})
  # sources`. One source names one value per key by attrset construction, so two scopes sharing a
  # source cannot carry two values for it, and one scope never reads another's content (gate C-1). The
  # value lives on the node its source names (ADR-0016 r6); how several emissions of one supplier
  # compose is its assembler's, under the minting phase spec R§4.4 (spec §4.1 O4), never this relation's.
  #
  # THE DECISION (den-hoag-n8wb5). The edges are the reaches whose condition was decided TRUE. A
  # walked first-order guard with no edge is DECLINED, listed in `declined.reaches.<node>` (or
  # `declined.nestedAt.<node>.<iid>`), iff its condition was decided FALSE at every tuple tried: the
  # scope's and each descendant tried at node scope (the static targets of vertices included, htfv3
  # Open 4), the meet and each descendant tried there when nested. The third outcome is the evaluator's REFUSAL R (quf7g OQ1, design
  # Section 2): under the open world `has` over a coordinate the scope lacks is refused by name, and
  # `GT.decide` carries that refusal as `null`, which is neither TRUE nor FALSE, so the guard is in
  # neither set and the consumer refuses the reach. Under a declared coordinate set the same absence
  # is FALSE (Clark completion), and `eq` over an absent coordinate does not fire, FALSE in both
  # worlds. A carrier admits every tuple, so it is never declined. A guard never walked at a scope is
  # in neither set too. `declined` selects only between "no edge" and "refuse" for an empty reach:
  # a declined reach is no edge (ADR-0019), so a reader never folds, counts or orders over it. Each
  # entry reads only its own scope's or vertex's tuples, so the restriction property below holds.
  #
  # FAN-OUT (design §3; ruling 7, T1). `admits` decides whether a tuple can mint at all: a
  # first-order guard where its condition holds at the tuple's context (`GT.holds`), a carrier always.
  # At a tuple (a node's, or a meet): the tuple when it admits; otherwise each descendant of its
  # innermost held entities whose coordinate admits AND whose chain crosses, below the entities the
  # reading node binds, only levels whose key the minted instance takes (`crosses`); otherwise no edge,
  # and the consumer's door names it. A descendant's tuple is its coordinate, a function of the entity
  # alone, so a nested instance minted from it shares the direct instance's id.
  #
  # THE PASSES (spec §2.5's depth passes). Pass d+1 reads only the MEMBERS of pass-d vertices, through
  # each vertex's `instantiates` edge: its declaration's published sites (`graphCore`'s
  # `instanceSites`, the classification `project` descends, inline `content` included), each `deferred`
  # one classified at its own position of the vertex's fired `includes` and no other field read. Its
  # parametric targets are minted, per node reaching the vertex, at THE MEET of the vertex's tuple and
  # the node's (den-hoag-8g2rn S3c, den v1's binding order): what the node binds is bound before any
  # fan-out is tried, so an instance inconsistent with the node is never minted on its account, and the
  # levels already crossed are the node's, never the vertex's. The meet is built once per (node,
  # vertex), in the pass that reaches the pair, and the decision reads that stored meet. Its STATIC
  # targets resolve at NODE
  # scope (htfv3 Open 4): their parametric includes become `reaches.<node>` edges for every node
  # reaching the vertex, never `nested` ones. One vertex index over all depths at once diverges
  # (ADR-0033 clause 1), so each pass's index is built from the previous pass's alone.
  #
  # TERMINATION. Containment is a finite forest (a cycle refuses). Every vertex's aspect is a node of
  # this finite tree, and its formals are a sub-map of a node's tuple, a meet or a containment
  # coordinate, so the id space is finite. A pass that mints no new id and reaches no new (node, vertex) pair ends the
  # loop, and every other pass adds one of the two. A self-including aspect re-mints its own id.
  #
  # WHAT IS MINTED WHERE. A first-order guard is minted where its condition holds at the tuple's
  # context (`GT.holds`), keyed on its derived reads (den-hoag-lwbb1). A sealed or foreign include site
  # is not walked.
  #
  # THE SOURCE DOOR (den-hoag-fkkzk, owner-ruled 2026-10-05, arm (d)). A source is refused iff it is
  # a node id of THIS relation's own graph: an aspect node's id (`aspectIdOf`) or one of its vertices.
  # Such a node supplies no argument: the reaching instance is an edge, never a formal's source
  # (design §3), and a vertex id as a source is a same-pass relatum, which r7 forbids. Every other id is
  # admitted, whatever its kind tag spells (ADR-0035): membership is by the exact id string, so an
  # honest framework kind `aspect` is never taken for a node, and only an identical preimage, the
  # forger's case, matches. STATED DIVERGENCES (ADR-0025 item 1), the limbs the retired spelling list
  # covered and membership cannot: an instance id minted by an EARLIER relation, not a vertex of this
  # one, is admitted; and `instanceOf` alone holds no graph, so it refuses no source by kind.
  # Checked once over the final vertices, so a vertex is minted before its source is read against them.
  # The kind tag only EXCLUDES: `aspectId` mints every node id under the kind `aspect`, so a source of
  # another kind cannot be one and is admitted without reading the node ids, while a source of kind
  # `aspect` is admitted or refused by membership alone.
  #
  # WHAT IT FORCES. Reading any field forces every pass: each reached instance is applied once (its
  # body decides the next pass) and hashed once, so a mint refusal (a non-identity source), the source
  # door or the supplier door fires on any read, shared by every node, as `realize`'s `_contentCheck`
  # already shares it. The source door forces no unreached node unless a minted formal's source is
  # of kind `aspect` (den-hoag-biefe). Only then does it force every node's `aspectIdOf`, once per
  # relation, because a digest is one-way: a source can be shown to differ from a node's id only by
  # minting that id. ITS BOUND, enumerated (ADR-0025 item 1): with such a source, a node with no
  # identity (an unchecked first-order guard, never placed at an aspect position) refuses the
  # relation even where no scope reaches it.
  #
  # ONE ID, SEVERAL CONTRIBUTIONS. Equal ids from several reaching identifiers (nodes, or parent
  # vertices) are one vertex, whose content is the contribution of the earliest pass and, within a
  # pass, of the least reaching identifier under string order (spec §2.5, obligation 2). Equal ids
  # mean equal formals, so the same source per received key, so the same `suppliers` value: the
  # contributions are one declaration applied to one input, identical by construction, and the order
  # picks among identical values. No content rule is exercised (ADR-0016 OPEN 2.C is not reached).
  #
  # THE DOORS, each a catchable `throw` naming the node or the containment entity: the input is not
  # `{ suppliers; scopes; containment; }`; `suppliers`, `scopes` or `containment` is not an attrset; a
  # scope is not `{ members; sources; }` (the retired `context` and `descendants` are unknown fields);
  # `members` is not a list or names an id that is not a node of this tree; `sources` is not an
  # attrset; a containment record is not exactly `{ parent; key; identity; marked; bindings; }`, its
  # `parent` neither null nor an identifier, its `key` not a string, its `bindings` not an attrset, its
  # `marked` not a bool, or it is keyed by its own identity; two identifiers carry one identity; a
  # parent chain is a cycle; an entity key is bound twice along a chain; a node binds an entity under
  # another key than its own, or binds a key against the coordinate of an entity it binds (the
  # override belongs on a containment record, where it shadows); a descendant rebinds an entity key a
  # node or a meet binds; a tuple key whose source is not a string, is not a name in `suppliers`, or
  # names an entry that is not an attrset holding that key. The containment doors and the supplier
  # door over every coordinate refuse at every call, whichever nodes are read. The supplier door reads
  # key names only, so no supplied value is forced.
  #
  # COST (derived; spec §3b G1 measures it): one application and one hash per distinct reached
  # instance, one attribute lookup per (tuple, key), the static walk per node, the members'
  # classification once per DECLARATION, and per vertex only its `deferred` positions. Two routes: the whole relation is O(Σ reach) over every handed scope,
  # and a reader of one node pays all of it, the price of sharing a vertex across nodes; handed ONE
  # scope, it is O(reach(n)), constant in N. The RESTRICTION PROPERTY: the relation handed a subset of
  # the scopes equals the whole relation's slice for them, because a scope's values derive from its
  # own sources through `suppliers` and never from which other scopes are handed.
  instancesFor = checkedEntry (
    cnf: aspects: input:
    let
      core = graphCore cnf aspects;
      inherit (core.facts) nodeData includeSitesOf;
      origin = cnf.providerPrefix;
      mintAt = mint cnf;
      rdoor = "gen-aspects.instancesFor";
      set =
        xs:
        builtins.listToAttrs (
          map (x: {
            name = x;
            value = null;
          }) xs
        );
      unique = xs: builtins.attrNames (set xs);

      # ── the doors ──
      top =
        let
          fields = [
            "suppliers"
            "scopes"
            "containment"
          ];
        in
        prelude.checkOptions rdoor fields (prelude.checkRequired rdoor fields input);
      inherit (top) suppliers scopes containment;
      supplied =
        src: k:
        builtins.isString src
        && suppliers ? ${src}
        && builtins.isAttrs suppliers.${src}
        && suppliers.${src} ? ${k};
      tupleOf =
        door: t:
        let
          fields = [ "sources" ];
          r = prelude.checkOptions door fields (prelude.checkRequired door fields t);
          unsupplied = builtins.filter (k: !(supplied r.sources.${k} k)) (builtins.attrNames r.sources);
        in
        if !(builtins.isAttrs r.sources) then
          throw "${door}: `sources` must be an attrset mapping each context key to its supplier's identity, not a ${builtins.typeOf r.sources}."
        else if unsupplied != [ ] then
          throw "${door}: key(s) ${
            prelude.concatStringsSep ", " (map (k: "'${k}'") unsupplied)
          } name a source that `suppliers` holds no value for under that key; a context value is supplied as `suppliers.<source>.<key>`, never beside the scope."
        else
          {
            inherit (r) sources;
            # derived, never handed (gate C-1): one source names one value per key
            context = builtins.mapAttrs (k: src: suppliers.${src}.${k}) r.sources;
          };
      scopeOf =
        n: s:
        let
          door = "${rdoor} (node '${n}')";
          r =
            prelude.checkOptions door
              [
                "members"
                "sources"
              ]
              (
                prelude.checkRequired door [
                  "members"
                  "sources"
                ] s
              );
          unknown = builtins.filter (m: !(builtins.isString m && nodeData ? ${m})) r.members;
          m = builtins.head unknown;
        in
        if !(builtins.isList r.members) then
          throw "${door}: `members` must be a list of facts ids, not a ${builtins.typeOf r.members}."
        else if unknown != [ ] then
          throw "${door}: member ${
            if builtins.isString m then "'${m}'" else "of type ${builtins.typeOf m}"
          } is not a node of this tree; a member is a `graphFacts` node id (resolve a local key through `nodeIdOf`)."
        else
          let
            t = tupleOf door { inherit (r) sources; };
            bd = boundOf t.sources;
            ds = neighbourhood "${door}" t;
            clash = builtins.filter (k: t.sources ? ${k} && t.sources.${k} != bd.${k}) (builtins.attrNames bd);
          in
          # THE NODE DOOR: a node never binds a key against the coordinate of an entity it binds (an
          # override is written on a containment record, where it shadows), and its descendants are
          # checked whether or not a fan-out reads them. A miskeyed entity refuses first.
          if builtins.seq ds (clash != [ ]) then
            throw "${door}: binds `${builtins.head clash}` to another source than the containment coordinate of an entity it binds; a node reads its entities' coordinates, and a binding is overridden only on a containment record, where it shadows."
          else
            builtins.seq (builtins.foldl' (_: d: builtins.seq d null) null ds) (
              t
              // {
                inherit (r) members;
                bound = bd;
                descendants = ds;
              }
            );
      # THE CONTAINMENT (den-hoag-8g2rn). `containment.<identifier> = { parent; key; identity; marked; bindings; }`
      # is the entity graph's ONE-STEP containment, handed as data: each entity once, under its
      # IDENTIFIER (ADR-0016 r5's readable vertex name), with its parent's identifier (null at a root),
      # the key it binds, its minted identity, and whether its containment edge carries a boundary
      # mark (ADR-0026). The transitive view is DERIVED here, never handed.
      edoor = x: "${rdoor} (containment '${x}')";
      efields = [
        "parent"
        "key"
        "identity"
        "marked"
        "bindings"
      ];
      entities =
        if !(builtins.isAttrs containment) then
          throw "${rdoor}: `containment` must be an attrset `<identifier> = { parent; key; identity; marked; bindings; }`, not a ${builtins.typeOf containment}."
        else
          builtins.mapAttrs (
            x: e:
            let
              r = prelude.checkOptions (edoor x) efields (prelude.checkRequired (edoor x) efields e);
            in
            if !(r.parent == null || builtins.isString r.parent && containment ? ${r.parent}) then
              throw "${edoor x}: `parent` must be null (a root) or the identifier of an entity of `containment`."
            else if !(builtins.isString r.key) then
              throw "${edoor x}: `key` must be the coordinate the entity binds, a string, not a ${builtins.typeOf r.key}."
            else if !(builtins.isAttrs r.bindings) then
              throw "${edoor x}: `bindings` must be an attrset `<key> = <source>` of the argument bindings declared at this entity, not a ${builtins.typeOf r.bindings}."
            else if !(builtins.isBool r.marked) then
              throw "${edoor x}: `marked` must be a bool, not a ${builtins.typeOf r.marked}."
            else if r.identity == x then
              throw "${edoor x}: is keyed by its own identity; key it by the entity's identifier, which orders siblings (an identity is a hash, and no order may depend on it, ADR-0016 r5)."
            else
              r
          ) containment;
      # identity → identifier; one entity per identity
      byIdentity =
        let
          xs = builtins.attrNames entities;
          idx = builtins.groupBy (x: entities.${x}.identity) xs;
          dup = builtins.filter (i: builtins.length idx.${i} > 1) (builtins.attrNames idx);
        in
        if dup != [ ] then
          throw "${rdoor}: containment entities ${
            names (map (x: "'${x}'") idx.${builtins.head dup})
          } carry one identity; an entity has one identifier."
        else
          builtins.mapAttrs (_: builtins.head) idx;
      # the up-walk from x, x first; it ends at a root or, on a cycle, at a revisit
      upOf =
        x:
        builtins.genericClosure {
          startSet = [ { key = x; } ];
          operator =
            p: if entities.${p.key}.parent == null then [ ] else [ { key = entities.${p.key}.parent; } ];
        };
      # what an entity binds itself: its key, and the argument bindings declared at it
      ownOf = y: entities.${y}.bindings // { ${entities.${y}.key} = entities.${y}.identity; };
      chains = builtins.mapAttrs (
        x: _:
        let
          up = map (p: p.key) (upOf x);
          top = entities.${prelude.last up};
        in
        if top.parent != null then
          throw "${edoor x}: its parent chain is a cycle through '${top.parent}'; containment is a forest."
        else
          {
            inherit up;
            # the entity's coordinate: its own key and argument bindings and every ancestor's. An
            # argument binding inherits down containment, and one re-declared below SHADOWS the
            # ancestor's for the re-declaring entity and its descendants, as a new binding id (gen-scope
            # `argumentBinding`, R10). An ENTITY key is a level and is bound once: a key bound twice
            # along the chain refuses when either binding is an entity's key.
            inherit
              (builtins.foldl'
                (
                  acc: y:
                  let
                    below = acc.levels;
                    again = builtins.filter (
                      k: acc.sources ? ${k} && (k == entities.${y}.key || builtins.elem k below)
                    ) (builtins.attrNames (ownOf y));
                    k = builtins.head again;
                    z = prelude.findFirst (z: (ownOf z) ? ${k}) null up;
                  in
                  if again != [ ] then
                    throw "${edoor z}: entity key `${k}` is bound by '${z}' and again by its ancestor '${y}'; an entity key is bound once along containment (an argument binding re-declared there shadows)."
                  else
                    {
                      sources = ownOf y // acc.sources;
                      levels = below ++ [ entities.${y}.key ];
                    }
                )
                {
                  sources = { };
                  levels = [ ];
                }
                up
              )
              sources
              ;
            # the entity keys along the chain, the LEVELS a fan-out from an ancestor crosses
            levels = map (y: entities.${y}.key) up;
          }
      ) entities;
      # the ancestors x reaches walking up, never leaving a marked entity
      reachUp =
        x:
        let
          up = chains.${x}.up;
          go =
            i:
            if i >= builtins.length up || entities.${builtins.elemAt up (i - 1)}.marked then
              [ ]
            else
              [ (builtins.elemAt up i) ] ++ go (i + 1);
        in
        go 1;
      # a descendant's tuple carries its whole coordinate, and `own`, the key it binds itself
      dTuple = builtins.mapAttrs (
        x: _: tupleOf (edoor x) { inherit (chains.${x}) sources; } // { inherit (chains.${x}) levels; }
      ) entities;
      # THE DERIVED VIEW: identity of x → { <identifier of each descendant> = its tuple }, transitive
      # over `parent`, never entering a marked entity; siblings in identifier order by construction.
      dView =
        builtins.mapAttrs
          (
            _: ps:
            builtins.listToAttrs (
              map (p: {
                name = p.y;
                value = dTuple.${p.y};
              }) ps
            )
          )
          (
            builtins.groupBy (p: entities.${p.x}.identity) (
              builtins.concatMap (y: map (x: { inherit x y; }) (reachUp y)) (builtins.attrNames entities)
            )
          );
      # THE NEIGHBOURHOOD. A tuple's neighbourhood is the descendants of every INNERMOST bound entity
      # (one no other bound entity is contained in), intersected, in identifier order. An ancestor the
      # tuple also binds is implied by containment, so its view, which a mark below it narrows, does not
      # narrow its descendant's. A source that is no entity constrains nothing; a tuple binding none has
      # no neighbourhood. A descendant that rebinds a key the tuple binds refuses, and so does a tuple
      # binding an entity under another key than its own.
      neighbourhood =
        door: t:
        let
          held = builtins.filter (k: byIdentity ? ${t.sources.${k}}) (builtins.attrNames t.sources);
          miskeyed = builtins.filter (k: entities.${byIdentity.${t.sources.${k}}}.key != k) held;
          xOf = k: byIdentity.${t.sources.${k}};
          inner = builtins.filter (
            k: !(builtins.any (j: j != k && builtins.elem (xOf k) (builtins.tail chains.${xOf j}.up)) held)
          ) held;
          maps = map (k: dView.${t.sources.${k}} or { }) inner;
          cands = builtins.attrValues (
            builtins.foldl' (acc: m: builtins.intersectAttrs m acc) (builtins.head maps) (builtins.tail maps)
          );
          rebinds =
            d:
            builtins.filter (k: t.sources ? ${k} && t.sources.${k} != d.sources.${k}) (
              # only entity keys can be rebound; a shadowing argument binding is the descendant's own
              builtins.filter (k: builtins.elem k d.levels) (builtins.attrNames d.sources)
            );
          checked =
            d:
            if rebinds d == [ ] then
              d
            else
              throw "${door}: a descendant of the tuple binds `${builtins.head (rebinds d)}` to another source than the tuple does; a descendant extends its ancestor's bindings and never rebinds one.";
        in
        if miskeyed != [ ] then
          throw "${door}: binds `${builtins.head miskeyed}` to containment entity '${
            byIdentity.${t.sources.${builtins.head miskeyed}}
          }', whose key is `${entities.${byIdentity.${t.sources.${builtins.head miskeyed}}}.key}`."
        else if held == [ ] then
          [ ]
        else
          map checked cands;
      # What a reading node binds (T1's crossed levels): its sources and the coordinate of every entity
      # it holds, a deeper entity's over its ancestor's, so a shadowing binding reads as it shadows.
      boundOf =
        srcs:
        let
          held = map (k: byIdentity.${srcs.${k}}) (
            builtins.filter (k: byIdentity ? ${srcs.${k}}) (builtins.attrNames srcs)
          );
          depth = x: builtins.length chains.${x}.up;
        in
        builtins.foldl' (acc: x: acc // chains.${x}.sources) srcs (
          builtins.sort (x: y: depth x < depth y) held
        );
      sc =
        if !(builtins.isAttrs suppliers) then
          throw "${rdoor}: `suppliers` must be an attrset `<source identity>.<key> = <value>`, not a ${builtins.typeOf suppliers}."
        else if !(builtins.isAttrs scopes) then
          throw "${rdoor}: `scopes` must be an attrset of node scopes, not a ${builtins.typeOf scopes}."
        else
          builtins.mapAttrs scopeOf scopes;
      nodeNames = builtins.attrNames sc;

      # ── what a node is ──
      # A guard record or carrier: the shapes `instanceOf` mints.
      mintable = v: v.__guard or false;
      termGuard = v: (v.__guard or false) && v ? condition;
      # Whether a tuple can mint the aspect at all: a first-order guard where its condition holds
      # (lib/guard-term.nix `holds`); a carrier's fragments fire at the tuple and decide themselves.
      admits = t: a: !(termGuard nodeData.${a}) || GT.holds cnf t.context nodeData.${a};
      aspectIdOf = builtins.mapAttrs (_: aspectId origin) nodeData;

      locals =
        sites:
        builtins.concatMap (
          s:
          if s.kind == "local" then
            [ s.target ]
          else if s.kind == "content" then
            locals s.sites
          else
            [ ]
        ) sites;
      # The parametric nodes reached from `ids` through static nodes, never entering a parametric one.
      paramsFrom =
        ids:
        builtins.filter (a: mintable nodeData.${a}) (
          map (x: x.key) (
            builtins.genericClosure {
              startSet = map (k: { key = k; }) ids;
              operator =
                x:
                if isGuardLeaf nodeData.${x.key} then
                  [ ]
                else
                  map (k: { key = k; }) (locals includeSitesOf.${x.key});
            }
          )
        );

      # ── a vertex: one record per mint, whose body is classified once ──
      mintOne =
        a: t:
        let
          i = mintAt {
            aspect = aspectIdOf.${a};
            value = nodeData.${a};
            inherit (t) context sources;
          };
          tuple = {
            context = builtins.intersectAttrs i.formals t.context;
            sources = builtins.intersectAttrs i.formals t.sources;
          };
          targets = locals (core.instanceSites a i.entry);
          params = builtins.filter (r: mintable nodeData.${r}) targets;
        in
        {
          inherit (i)
            id
            formals
            entry
            scope
            ;
          inherit tuple params;
          aspect = a;
          # the parametric targets this vertex's tuple decided, admitted or not
          walked = unique params;
          # static targets: their parametric reach, resolved at node scope
          statics = paramsFrom (builtins.filter (r: !(isGuardLeaf nodeData.${r})) targets);
        };
      # A descendant is tried only when the aspect takes the coordinate of every LEVEL its chain crosses
      # below what the reading node binds (den-hoag-8g2rn T1, den v1's fan-out): a {dot} aspect does not
      # fan through the user level from a host node, a co-destructured {user, dot} one fans over pairs.
      crosses =
        s: t: m:
        !(t ? levels) || builtins.all (k: s.bound ? ${k} || m.formals ? ${k}) t.levels;
      triedAt = s: a: builtins.filter (t: crosses s t (mintOne a t)) s.descendants;
      # the scope's tuple when it admits, else each tried descendant that does (one mint per tuple)
      mintsAt =
        s: a:
        if admits s a then
          [ (mintOne a s) ]
        else
          builtins.concatMap (
            t:
            let
              m = mintOne a t;
            in
            if admits t a && crosses s t m then [ m ] else [ ]
          ) s.descendants;
      atNode = n: mintsAt sc.${n};
      # THE MEET (den-hoag-8g2rn, OQ1 ruled S3c). A vertex read at node n fans its nested parametric
      # targets out at the meet of its tuple and n's: what n binds is bound before any fan-out is tried,
      # so an instance inconsistent with n's coordinates is never minted on n's account. The vertex's
      # value is shared (one id, one application); its nested EDGES are per reading node.
      meetAt =
        n: v:
        let
          t = {
            sources = sc.${n}.sources // v.tuple.sources;
            context = sc.${n}.context // v.tuple.context;
          };
        in
        t
        // {
          # the levels already crossed are the reading node's, never the vertex's
          bound = sc.${n}.bound;
          descendants = neighbourhood "${rdoor} (vertex of '${v.aspect}' at node '${n}')" t;
        };
      childrenOf = s: v: builtins.concatMap (mintsAt s) v.params;

      # The canonical record per id: the least reaching identifier (`by`) wins, since `listToAttrs`
      # keeps a name's first occurrence.
      index =
        cands:
        builtins.listToAttrs (
          map (c: {
            name = c.m.id;
            value = c.m;
          }) (builtins.sort (x: y: x.by < y.by) cands)
        );
      by =
        r:
        map (m: {
          inherit m;
          by = r;
        });
      ids = map (m: m.id);

      step =
        st:
        let
          perNode = builtins.mapAttrs (
            n: fr:
            let
              vs = map (id: st.seen.${id}) fr;
              newParams = builtins.filter (a: !(st.handled.${n} ? ${a})) (
                unique (builtins.concatMap (v: v.statics) vs)
              );
              ms = builtins.concatMap (atNode n) newParams;
              # each (node, vertex) is in exactly one frontier, so its meet is built once, here
              kids = builtins.listToAttrs (
                map (v: {
                  name = v.id;
                  value =
                    let
                      s = meetAt n v;
                    in
                    {
                      meet = s;
                      children = childrenOf s v;
                    };
                }) vs
              );
              cs = builtins.concatMap (v: kids.${v.id}.children) vs;
            in
            {
              inherit
                ms
                cs
                kids
                newParams
                ;
              frontier = builtins.filter (id: !(st.reached.${n} ? ${id})) (unique (ids ms ++ ids cs));
            }
          ) st.frontier;
          fresh = removeAttrs (index (
            builtins.concatMap (n: by n (perNode.${n}.ms ++ perNode.${n}.cs)) nodeNames
          )) (builtins.attrNames st.seen);
          next = {
            seen = st.seen // fresh;
            fresh = builtins.attrNames fresh;
            frontier = builtins.mapAttrs (_: p: p.frontier) perNode;
            reached = builtins.mapAttrs (n: r: r // set perNode.${n}.frontier) st.reached;
            handled = builtins.mapAttrs (n: h: h // set perNode.${n}.newParams) st.handled;
            edges = builtins.mapAttrs (n: e: e ++ perNode.${n}.ms) st.edges;
            kids = builtins.mapAttrs (n: k: k // perNode.${n}.kids) st.kids;
          };
        in
        if builtins.all (n: next.frontier.${n} == [ ]) nodeNames then next else step next;

      start =
        let
          p0 = builtins.mapAttrs (_: s: paramsFrom s.members) sc;
          m0 = builtins.mapAttrs (n: builtins.concatMap (atNode n)) p0;
          seen = index (builtins.concatMap (n: by n m0.${n}) nodeNames);
          f0 = builtins.mapAttrs (_: ms: unique (ids ms)) m0;
        in
        {
          inherit seen;
          fresh = builtins.attrNames seen;
          frontier = f0;
          reached = builtins.mapAttrs (_: set) f0;
          handled = builtins.mapAttrs (_: set) p0;
          edges = m0;
          kids = builtins.mapAttrs (_: _: { }) m0;
        };
      final =
        let
          f = step start;
          own = set (builtins.attrValues aspectIdOf);
          # `aspectId` mints under the one kind `aspect`, so a source minted under any other kind is
          # no node id, and `own`, which forces every node's id, is read only for an `aspect` source.
          isOwn = s: f.seen ? ${s} || (builtins.head (kindOf s) == "aspect" && own ? ${s});
          bad = builtins.filter (id: builtins.any isOwn (builtins.attrValues f.seen.${id}.formals)) (
            builtins.attrNames f.seen
          );
          m = f.seen.${builtins.head bad};
          ks = builtins.filter (k: isOwn m.formals.${k}) (builtins.attrNames m.formals);
        in
        if bad == [ ] then
          f
        else
          throw "${rdoor}: aspect `${aspectIdOf.${m.aspect}}` was handed, for formal(s) ${names (map (k: "`${k}`") ks)}, the identity of a node of this relation's own graph, which supplies no argument; hand the identity of the entity or argument binding that supplied it. An instance's reaching node is an edge, never a formal's source.";
      # Each id at its first occurrence, in minting order: `listToAttrs` keeps a name's first index, as
      # in `index`. One `mintsAt` call mints a (tuple, aspect) list, its siblings in identifier order.
      firstOf =
        xs:
        let
          at = builtins.listToAttrs (
            prelude.imap0 (i: x: {
              name = x;
              value = i;
            }) xs
          );
        in
        builtins.concatLists (prelude.imap0 (i: x: if at.${x} == i then [ x ] else [ ]) xs);
      groupIds = ms: builtins.mapAttrs (_: xs: firstOf (ids xs)) (builtins.groupBy (m: m.aspect) ms);
      reaches = builtins.mapAttrs (_: groupIds) final.edges;
      # per reading node: the nested edges of every vertex it reaches, built at the meet
      nestedAt = builtins.mapAttrs (_: builtins.mapAttrs (_: k: groupIds k.children)) final.kids;
      # decided over the stored meet, never a rebuilt one
      declinedNestedAt = builtins.mapAttrs (
        n: builtins.mapAttrs (id: e: declinedOf e final.kids.${n}.${id}.meet final.seen.${id}.walked)
      ) nestedAt;
      # A walked first-order guard with no edge whose condition was decided FALSE at every tuple it was
      # tried at (lib/guard-term.nix `decide`); a refused condition is in neither set (THE DECISION).
      falseAt = t: a: termGuard nodeData.${a} && GT.decide cnf t.context nodeData.${a} == false;
      declinedOf =
        edges: s: walked:
        builtins.filter (a: !(edges ? ${a}) && builtins.all (t: falseAt t a) ([ s ] ++ triedAt s a)) walked;
      # every entity's record, identity, coordinate and descendant tuple is checked at every call,
      # reached or not, so a malformed record, an aliased identity, a repeated entity key or an
      # unsupplied coordinate refuses whichever nodes are read
      containmentChecked = builtins.seq byIdentity (
        builtins.foldl' (_: x: builtins.seq chains.${x}.sources (builtins.seq dTuple.${x} null)) null (
          builtins.attrNames chains
        )
      );
    in
    builtins.seq containmentChecked {
      vertices = builtins.mapAttrs (_: m: {
        inherit (m)
          formals
          entry
          scope
          ;
      }) final.seen;
      instantiates = builtins.mapAttrs (_: m: [ m.aspect ]) final.seen;
      inherit reaches nestedAt;
      declined = {
        reaches = builtins.mapAttrs (
          n: h: declinedOf reaches.${n} sc.${n} (builtins.attrNames h)
        ) final.handled;
        nestedAt = declinedNestedAt;
      };
    }
  );
}
