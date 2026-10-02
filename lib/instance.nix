# THE INSTANCE MINT (den-hoag-0cmbt spec §2.5): `instanceOf cnf { aspect; value; context; sources; }`
# → `{ id; entry; formals; }`. A parametric aspect applied to a context is a node of its own, the
# instance, whose identity is its declaration and what it was handed (design §3): two contexts that
# hand it different values are two instances, and two that differ only in keys it never receives are
# one.
#
#   formals = { <k> = sources.<k>; } for every key k the definitions are handed at `context`
#   id      = hashIdentity "aspect-instance" [ "aspect" "formals" ] { aspect; formals; }
#   entry   = the aspect applied to `context`
#
# `formals` nests under its own label, so a formal named `aspect` does not clash with the relatum.
# A `{ }:` aspect receives nothing: `formals = { }`, one id for every context.
#
# THE RECEIVED KEYS. A wrap record (`__isWrappedFn`) publishes them as `__receives context`, the union
# over its definitions of what the context door hands each one (lib/types.nix `mkWrapped`), so the
# wrap's own cnf decides them. A guard carrier (`__guard` with `fragments`: a guard function defined
# more than once under one key, the K2 site) unions its `fn` fragments' door keys, read through the
# SAME door `dischargeFragment` applies them through, at this cnf's entity kinds; an `unconditional`
# fragment reads no context. `__receives` stays a closure, as spec §2.4 states it: it is a record
# marker this library both writes and reads, never an interface a consumer resolves.
#
# THE SOURCES (design K3). `sources` maps each context key to the identity of what supplied it, an
# entity's identity or a K1 argument binding's (gen-scope `argumentBinding`), so the binding ids reach
# the mint by the same call that carries the context. This is K3's "(or hands over an instance it
# minted)" arm: the applicator's functor keeps its arity (`w ctx`), and the sources travel here.
#
# THE DOORS, each a catchable `throw` naming this entry:
# - the argument is not the closed record `{ aspect; value; context; sources; }`, or `aspect` is not a
#   string, or `context` or `sources` is not an attrset;
# - the value is not parametric (neither a wrap record nor a carrier);
# - the value is a guard record, or a carrier holding a `record` fragment: a first-order guard reads
#   context through its predicate, and its instance identity is not defined yet (spec §4.1 O1);
# - a received key has no source (design §3, "a formal with no known supplier refuses by name");
# - a source is not identity-shaped (`<kind>:<64 hex>`): the honest mistake of handing the context
#   VALUE where its supplier's identity belongs (ADR-0016 r7, "a relatum must already be a minted
#   node"; the minter holds no registry, so it checks the shape);
# - a source is the identity of a node of a kind that supplies no argument: `aspect-instance`,
#   `aspect`, `include-site`, `named-value`. The reaching instance is an edge, never a formal's
#   source (design §3), and an instance id as a source is a same-pass relatum, which r7 forbids.
# ITS BOUND, enumerated (ADR-0025 item 1). A source that is the instance's OWN id is a let-bound
# fixpoint: no door can read it before forcing it, so it aborts with `infinite recursion`,
# uncatchably. And the received keys inherit the context door's bound (lib/require-wrapped-closure.nix):
# a forwarding wrapper around `{ }:` classifies as a context shape, so its instance is keyed on the
# context it is handed rather than on `{ }`.
# THE CALLER'S OBLIGATION. Each source must be the supplier of the value the context carries under its
# key. The id reads only the sources, and the minter holds no registry to check them against the
# context, so a mismatch is not refused: two contexts with one source and different values mint ONE id
# carrying two different entries. `instancesFor` (below) cannot be handed that input: it derives each
# context from its sources through one `suppliers` map (spec §2.6, gate C-1).
#
# COST: O(definitions × formals) for the received keys, one `hashIdentity` over O(formals) labelled
# entries, and one application. A wrap record's doors are classified once per definition when it is
# built; a carrier's `fn` fragments are classified at every call, as `dischargeFragment` classifies
# them at every discharge. The guard vocabulary that discharges a carrier is built once per
# `instanceOf cnf`. Nothing scans another instance.
{
  prelude,
  hashIdentity,
  mkGuardVocab,
  graphCore,
  aspectId,
}:
let
  inherit (import ./cnf.nix) checkedEntry;
  inherit (import ./walk.nix) isGuardLeaf;
  doors = import ./require-wrapped-closure.nix;
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
      contextOf = doors.requireContextOf cnf.entityKinds;
      inherit (mkGuardVocab cnf) applyGuard;
    in
    args:
    let
      a = prelude.checkOptions door fields (prelude.checkRequired door fields args);
      inherit (a)
        aspect
        value
        context
        sources
        ;
      wrapped = builtins.isAttrs value && (value.__isWrappedFn or false);
      guarded = builtins.isAttrs value && (value.__guard or false);
      carrier = guarded && value ? fragments;
      fragments = if carrier then value.fragments else [ ];
      at = "aspect `${prelude.concatStringsSep "." (value.meta.loc or [ "<guard-carrier>" ])}`";
      received =
        if wrapped then
          value.__receives context
        else
          builtins.attrNames (
            prelude.foldl' (acc: f: acc // contextOf "guard" at f.fn context) { } (
              builtins.filter (f: f.kind == "fn") fragments
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
    else if !(wrapped || guarded) then
      refuse "is not parametric: it is neither a wrap record (`__isWrappedFn`) nor a guard carrier, so it has no instances."
    else if guarded && (!carrier || builtins.any (f: f.kind == "record") fragments) then
      refuse "carries a guard record, whose instance identity is not defined yet: a first-order guard reads its context through its predicate (den-hoag-0cmbt spec §4.1 O1)."
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
      {
        id = hashIdentity "aspect-instance" [ "aspect" "formals" ] (l: { inherit aspect formals; }.${l});
        entry = if carrier then applyGuard context value else value context;
        inherit formals;
      };
in
{
  instanceOf = checkedEntry mint;

  # THE INSTANCE RELATION (den-hoag-0cmbt spec §2.6, owner-ruled C1): `instancesFor cnf aspects
  # { suppliers; scopes; }`,
  #   suppliers = { <source identity> = { <key> = <value>; … }; … }
  #   scopes    = { <node> = { members; sources; descendants ? [ { sources; } … ]; }; }
  #   ⇒ { vertices.<iid> = { aspect; formals; entry; };   one content cell per instance id
  #       reaches.<node>.<aspect> = [ <iid> … ];           scope → instance edges
  #       nested.<iid>.<aspect>   = [ <iid> … ]; }         reaching edges FROM vertices
  # the materialised view (ADR-0012 clause 2) htfv3's `project` reads. Instances are nodes: the
  # reaching node is an edge, never a field of a vertex (ADR-0010 §4(a)). `aspect` is the facts id of
  # the parametric node, and every edge list is grouped by it, its ids ascending (a function of the set).
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
  # FAN-OUT (design §3). Two key sets, each with one site:
  # - `fanOutKeys` (O3, spec §4.1; defaulted, reversible: the REQUIRED formals) decides whether the
  #   scope's own tuple mints, or each descendant tuple that carries them does;
  # - `admits` (every required formal is supplied) decides whether a tuple can mint at all.
  # At node scope: the scope's tuple when it carries `fanOutKeys` and `admits`; otherwise each
  # descendant tuple that does; otherwise the scope's tuple when it `admits`; otherwise no edge, and the
  # consumer's door names it. Every branch requires `admits`, so under any `fanOutKeys` an edge comes
  # only from a tuple that can mint. A context shape requires nothing and never fans out. Under the
  # default the third branch adds nothing; fanning out on defaulted formals too is the one edit
  # `fanOutKeys = formalsWhere (_: true)`, and the third branch then keeps a host's defaulted edge.
  #
  # THE PASSES (spec §2.5's depth passes). Pass d+1 reads only the CONTENT of pass-d vertices: each
  # vertex's applied body is classified by `includeSitesOfEntry`'s classification (the one `project`
  # descends, inline `content` included), once per vertex. Its parametric targets are minted at the
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
  # WHAT IS NOT MINTED. A guard record, and a carrier holding a `record` fragment, has no instance
  # identity yet (spec §4.1 O1): it is a leaf with no edge, and the consumer's door refuses it where
  # it reaches it. A sealed or foreign include site is not walked.
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
  # instance, one attribute lookup per (tuple, key), the static walk per node, and the body
  # classification per vertex. Two routes: the whole relation is O(Σ reach) over every handed scope,
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
      # A wrap record, or a carrier of function fragments: the shapes `instanceOf` mints.
      mintable =
        v:
        (v.__isWrappedFn or false)
        || (v.__guard or false) && v ? fragments && builtins.all (f: f.kind != "record") v.fragments;
      # Per node, the formals of its definitions (unioned over a carrier's `fn` fragments) whose
      # `functionArgs` flag (true = defaulted) passes `keep`.
      formalsWhere =
        keep:
        builtins.mapAttrs (
          _: v:
          let
            fas =
              if v ? fragments then
                map (f: builtins.functionArgs f.fn) (builtins.filter (f: f.kind == "fn") v.fragments)
              else
                [ v.__functionArgs ];
          in
          if mintable v then
            unique (builtins.concatMap (fa: builtins.filter (k: keep fa.${k}) (builtins.attrNames fa)) fas)
          else
            [ ]
        ) nodeData;
      requiredOf = formalsWhere (defaulted: !defaulted);
      # O3 (spec §4.1; defaulted, reversible), its ONE site: the formals whose absence from the scope's
      # tuple sends the mint to the descendant tuples. Required only, since a default declares that the
      # aspect runs without the formal; fanning out on defaulted formals too is
      # `fanOutKeys = formalsWhere (_: true)`.
      fanOutKeys = requiredOf;
      carriesAll = ks: t: builtins.all (k: t.sources ? ${k}) ks;
      # Whether a tuple can mint the aspect at all: it supplies every required formal.
      admits = t: a: carriesAll requiredOf.${a} t;
      # Whether a tuple both carries `fanOutKeys` and admits: one test over the union, built once per
      # aspect, so a tuple costs the single test the unsplit binding paid. It equals `fanOutKeys` under
      # either O3 arm (both are supersets of the required formals); under any other `fanOutKeys` it still
      # keeps an edge from a tuple that cannot mint.
      fansAndAdmits = builtins.mapAttrs (a: ks: unique (ks ++ requiredOf.${a})) fanOutKeys;
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
          targets = locals (core.sitesOfEntry (i.entry.key or a) i.entry);
        in
        {
          inherit (i) id formals entry;
          aspect = a;
          # nested: parametric targets at the vertex's own tuple, never fanned out (design §3; not O3)
          children = builtins.concatMap (r: if admits tuple r then [ (mintOne r tuple) ] else [ ]) (
            builtins.filter (r: mintable nodeData.${r}) targets
          );
          # static targets: their parametric reach, resolved at node scope
          statics = paramsFrom (builtins.filter (r: !(isGuardLeaf nodeData.${r})) targets);
        };
      atNode =
        n: a:
        let
          s = sc.${n};
        in
        map (mintOne a) (
          if carriesAll fansAndAdmits.${a} s then
            [ s ]
          else
            let
              ds = builtins.filter (carriesAll fansAndAdmits.${a}) s.descendants;
            in
            if ds != [ ] then
              ds
            else if admits s a then
              [ s ]
            else
              [ ]
        );

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
      groupIds = ms: builtins.mapAttrs (_: xs: unique (ids xs)) (builtins.groupBy (m: m.aspect) ms);
    in
    {
      vertices = builtins.mapAttrs (_: m: { inherit (m) aspect formals entry; }) final.seen;
      reaches = builtins.mapAttrs (_: groupIds) final.edges;
      nested = builtins.mapAttrs (_: m: groupIds m.children) final.seen;
    }
  );
}
