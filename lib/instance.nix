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
# - a source is the identity of a node of a kind that supplies no argument: `aspect-instance`,
#   `aspect`, `include-site`, `named-value`. The reaching instance is an edge, never a formal's
#   source (design §3), and an instance id as a source is a same-pass relatum, which r7 forbids.
# ITS BOUND, enumerated (ADR-0025 item 1). A source that is the instance's OWN id is a let-bound
# fixpoint: no door can read it before forcing it, so it aborts with `infinite recursion`,
# uncatchably.
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
  # The kinds gen mints for nodes that supply no argument (spec §2.9's tags beside the two aspect tags).
  nonSupplier = [
    "aspect-instance"
    "aspect"
    "include-site"
    "named-value"
  ];
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
      foreign = builtins.filter (
        k: builtins.elem (builtins.head (kindOf sources.${k})) nonSupplier
      ) received;
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
    else if foreign != [ ] then
      refuse "was handed, for formal(s) ${
        names (map (k: "`${k}`") foreign)
      }, the identity of a node of kind ${
        names (map (k: "`${builtins.head (kindOf sources.${k})}`") foreign)
      }, which supplies no argument; hand the identity of the entity or argument binding that supplied it. An instance's reaching node is an edge, never a formal's source."
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

  # THE INSTANCE RELATION (den-hoag-0cmbt spec §2.6, owner-ruled C1): `instancesFor cnf aspects
  # { suppliers; scopes; }`,
  #   suppliers = { <source identity> = { <key> = <value>; … }; … }
  #   scopes    = { <node> = { members; sources; descendants ? [ { sources; } … ]; }; }
  #   ⇒ { vertices.<iid> = { formals; entry; scope; };          one content cell per instance id
  #       instantiates.<iid> = [ <aspect> ];               instance → declaration, exactly one
  #       reaches.<node>.<aspect> = [ <iid> … ];           scope → instance edges
  #       nested.<iid>.<aspect>   = [ <iid> … ];           reaching edges FROM vertices
  #       declined = { reaches.<node> = [ <aspect> … ];    the walked guards decided FALSE, per
  #                    nested.<iid>   = [ <aspect> … ]; }; } handed scope and per vertex, ascending
  # the materialised view (ADR-0012 clause 2) htfv3's `project` reads. Instances are nodes: the
  # reaching node is an edge, never a field of a vertex (ADR-0010 §4(a)). `<aspect>` is the facts id of
  # the parametric node. `instantiates` is an adjacency map (`id → [ids]`, the adjacency shape
  # gen-graph's classical doors read); `reaches` and `nested` are grouped by `<aspect>` (`id → aspect → [ids]`), their ids
  # in minting order, each at its first occurrence, so a scope's fan-out siblings follow its
  # `descendants` list. Never by id: ADR-0016 r5 lets nothing durable depend on an `id_hash`, and an
  # instance id moves when its aspect is renamed. Under 0cmbt O3 (OQ1 arm (a), still the owner's) a
  # nested instance does not fan out, so a `nested` list holds one id.
  # ORDER IS IMPORTED, NOT DISCHARGED (den-hoag-qvgob's scope gate). ADR-0029 asks for a DECLARED total
  # order invariant under presentation order. `instancesFor` is HANDED its order, so what it owes is
  # order-faithfulness: each list is a total function of the caller's `descendants`, and no site here
  # introduces an order the caller did not supply. That the list is a declaration, invariant under
  # presentation, is the obligation of whoever builds `scopes`; this function cannot observe it.
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
  # instance's σ restricts its parent's (`mintOne`'s `tuple`), and the one place a path could carry two
  # substitutions for one key, a nested door rebinding an outer source, is refused (gen-rules
  # `mkApply`). Cells `instance-scope.test-rebound-refused-whichever-scope` and the path-consistency
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
  # `declined.nested.<iid>`), iff its condition was decided FALSE at every tuple tried: the scope's
  # and each descendant's at node scope (the static targets of vertices included, htfv3 Open 4), the
  # vertex's own tuple when nested. The third outcome is the evaluator's REFUSAL R (quf7g OQ1, design
  # Section 2): under the open world `has` over a coordinate the scope lacks is refused by name, and
  # `GT.decide` carries that refusal as `null`, which is neither TRUE nor FALSE, so the guard is in
  # neither set and the consumer refuses the reach. Under a declared coordinate set the same absence
  # is FALSE (Clark completion), and `eq` over an absent coordinate does not fire, FALSE in both
  # worlds. A carrier admits every tuple, so it is never declined. A guard never walked at a scope is
  # in neither set too. `declined` selects only between "no edge" and "refuse" for an empty reach:
  # a declined reach is no edge (ADR-0019), so a reader never folds, counts or orders over it. Each
  # entry reads only its own scope's or vertex's tuples, so the restriction property below holds.
  #
  # FAN-OUT (design §3). `admits` decides whether a tuple can mint at all: a first-order guard where
  # its condition holds at the tuple's context (`GT.holds`), a carrier always. At node scope: the
  # scope's tuple when it admits; otherwise each descendant tuple that does; otherwise no edge, and the
  # consumer's door names it.
  #
  # THE PASSES (spec §2.5's depth passes). Pass d+1 reads only the MEMBERS of pass-d vertices, through
  # each vertex's `instantiates` edge: its declaration's published sites (`graphCore`'s
  # `instanceSites`, the classification `project` descends, inline `content` included), each `deferred`
  # one classified at its own position of the vertex's fired `includes` and no other field read. Its
  # parametric targets are minted at the
  # vertex's own tuple (its context and sources narrowed to its formals) as `nested` edges, so a
  # vertex two nodes reach is applied once and its nested instances minted once. A nested instance
  # does not fan out (its site is `mintOne`'s `children`, ground design §3, never O3): a vertex is
  # shared, so it sees no scope's descendants, and a nested aspect its vertex's tuple does not
  # `admit` has no edge. Its STATIC targets resolve at NODE
  # scope (htfv3 Open 4): their parametric includes become `reaches.<node>` edges for every node
  # reaching the vertex, never `nested` ones. One vertex index over all depths at once diverges
  # (ADR-0033 clause 1), so each pass's index is built from the previous pass's alone.
  #
  # TERMINATION. Every vertex's aspect is a node of this finite tree, and its formals are a sub-map
  # of some scope's or descendant's sources (a nested vertex's are a sub-map of its parent's), so the
  # id space is finite. A pass that mints no new id and reaches no new (node, vertex) pair ends the
  # loop, and every other pass adds one of the two. A self-including aspect re-mints its own id.
  #
  # WHAT IS MINTED WHERE. A first-order guard is minted where its condition holds at the tuple's
  # context (`GT.holds`), keyed on its derived reads (den-hoag-lwbb1). A sealed or foreign include site
  # is not walked.
  #
  # WHAT IT FORCES. Reading any field forces every pass: each reached instance is applied once (its
  # body decides the next pass) and hashed once, so a mint refusal (a non-identity source, a
  # non-supplier kind) or the supplier door fires on any read, shared by every node, as `realize`'s
  # `_contentCheck` already shares it.
  #
  # ONE ID, SEVERAL CONTRIBUTIONS. Equal ids from several reaching identifiers (nodes, or parent
  # vertices) are one vertex, whose content is the contribution of the earliest pass and, within a
  # pass, of the least reaching identifier under string order (spec §2.5, obligation 2). Equal ids
  # mean equal formals, so the same source per received key, so the same `suppliers` value: the
  # contributions are one declaration applied to one input, identical by construction, and the order
  # picks among identical values. No content rule is exercised (ADR-0016 OPEN 2.C is not reached).
  #
  # THE DOORS, each a catchable `throw` naming the node (and the descendant's index): the input is not
  # `{ suppliers; scopes; }`; `suppliers` or `scopes` is not an attrset; a scope is not the record
  # above (an unknown field, the retired `context` among them, a missing `members` or `sources`);
  # `members` is not a list or names an id that is not a node of this tree; `sources` is not an
  # attrset; `descendants` is not a list of `{ sources; }` records; a tuple key whose source is not a
  # string, is not a name in `suppliers`, or names an entry that is not an attrset holding that key.
  # The supplier door reads key names only, so no supplied value is forced.
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
          ];
        in
        prelude.checkOptions rdoor fields (prelude.checkRequired rdoor fields input);
      inherit (top) suppliers scopes;
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
                "descendants"
              ]
              (
                prelude.checkRequired door [
                  "members"
                  "sources"
                ] s
              );
          ds = r.descendants or [ ];
          # Checked whether or not a fan-out reads them, so a malformed tuple refuses at every call.
          dts = prelude.imap0 (i: tupleOf "${door}, descendant ${toString i}") ds;
          unknown = builtins.filter (m: !(builtins.isString m && nodeData ? ${m})) r.members;
          m = builtins.head unknown;
        in
        if !(builtins.isList r.members) then
          throw "${door}: `members` must be a list of facts ids, not a ${builtins.typeOf r.members}."
        else if unknown != [ ] then
          throw "${door}: member ${
            if builtins.isString m then "'${m}'" else "of type ${builtins.typeOf m}"
          } is not a node of this tree; a member is a `graphFacts` node id (resolve a local key through `nodeIdOf`)."
        else if !(builtins.isList ds) then
          throw "${door}: `descendants` must be a list of { sources; } records, not a ${builtins.typeOf ds}."
        else
          builtins.seq (builtins.foldl' (_: t: builtins.seq t null) null dts) (
            tupleOf door { inherit (r) sources; }
            // {
              inherit (r) members;
              descendants = dts;
            }
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
          inherit tuple;
          aspect = a;
          # nested: parametric targets at the vertex's own tuple, never fanned out (design §3; not O3)
          children = builtins.concatMap (r: if admits tuple r then [ (mintOne r tuple) ] else [ ]) params;
          # the parametric targets this vertex's tuple decided, admitted or not
          walked = unique params;
          # static targets: their parametric reach, resolved at node scope
          statics = paramsFrom (builtins.filter (r: !(isGuardLeaf nodeData.${r})) targets);
        };
      atNode =
        n: a:
        let
          s = sc.${n};
        in
        map (mintOne a) (if admits s a then [ s ] else builtins.filter (t: admits t a) s.descendants);

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
            in
            {
              inherit ms newParams;
              frontier = builtins.filter (id: !(st.reached.${n} ? ${id})) (
                unique (ids ms ++ builtins.concatMap (v: ids v.children) vs)
              );
            }
          ) st.frontier;
          fresh = removeAttrs (index (
            builtins.concatMap (n: by n perNode.${n}.ms) nodeNames
            ++ builtins.concatMap (id: by id st.seen.${id}.children) st.fresh
          )) (builtins.attrNames st.seen);
          next = {
            seen = st.seen // fresh;
            fresh = builtins.attrNames fresh;
            frontier = builtins.mapAttrs (_: p: p.frontier) perNode;
            reached = builtins.mapAttrs (n: r: r // set perNode.${n}.frontier) st.reached;
            handled = builtins.mapAttrs (n: h: h // set perNode.${n}.newParams) st.handled;
            edges = builtins.mapAttrs (n: e: e ++ perNode.${n}.ms) st.edges;
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
        };
      final = step start;
      # Each id at its first occurrence, in minting order: `listToAttrs` keeps a name's first index, as
      # in `index`. At a node scope one `atNode` call mints a (node, aspect) list, in `descendants` order.
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
      nested = builtins.mapAttrs (_: m: groupIds m.children) final.seen;
      # A walked first-order guard with no edge whose condition was decided FALSE at every tuple it was
      # tried at (lib/guard-term.nix `decide`); a refused condition is in neither set (THE DECISION).
      falseAt = t: a: termGuard nodeData.${a} && GT.decide cnf t.context nodeData.${a} == false;
      declinedOf =
        edges: tuples: walked:
        builtins.filter (a: !(edges ? ${a}) && builtins.all (t: falseAt t a) tuples) walked;
    in
    {
      vertices = builtins.mapAttrs (_: m: {
        inherit (m)
          formals
          entry
          scope
          ;
      }) final.seen;
      instantiates = builtins.mapAttrs (_: m: [ m.aspect ]) final.seen;
      inherit reaches nested;
      declined = {
        reaches = builtins.mapAttrs (
          n: h: declinedOf reaches.${n} ([ sc.${n} ] ++ sc.${n}.descendants) (builtins.attrNames h)
        ) final.handled;
        nested = builtins.mapAttrs (id: m: declinedOf nested.${id} [ m.tuple ] m.walked) final.seen;
      };
    }
  );
}
