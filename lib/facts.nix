# THE ASPECT GRAPH'S FACTS. gen-aspects publishes them; the framework assembles the graph.
#
# ADR-0012 rules that the flat registry is a PROJECTION OF THE GRAPH, NEVER A SOURCE FOR IT, and
# that an aspect's slash-joined path key is a RENDERING of a parent edge rather than the edge.
# `flatten` was every structural consumer's only source for the node set, so the edges were
# recoverable from it only by parsing that rendering. This file ends that: the node set, the edge
# relations and the node values are published as plain data, and nothing downstream re-derives
# an edge from a string.
#
# ★ WHY THE RELATION MUST BE PUBLISHED HERE AND CANNOT BE RE-DERIVED BY A FRAMEWORK. A framework
# holding only `flatten`'s output and the node values would have to join on `meta`, and that join is
# WRONG rather than merely redundant: the position a node holds is recorded under a different
# attribute by shape, a nested guard leaf carries no `meta.aspect-chain` at all, and
# `meta.aspect-chain or [ ]` therefore answers ROOT for it while its true parent is its container.
# Worse, that wrong answer is INDISTINGUISHABLE from a right one, because a genuine root yields the
# same `[ ]`: absence and root are the same value. gen-aspects owns the node shapes, so gen-aspects
# answers.
#
# ★★ AND THE ANSWER IS THE WALK, NOT A DISPATCH OVER `meta`. This library HOLDS the walk — the
# framework's handicap is not ours — and every entry carries its own position (`walk.nix`), for
# every shape. Deriving the parent from `meta` instead was measurably wrong on this library's own
# public constructors, three ways in one run:
#
#   * A `meta.loc` stamped from a SITING NAME rather than a tree position reads as one segment, so
#     `top/wf` and `top/deeper/wf2` both reported parent `null` — a non-root node spelled as a ROOT,
#     silently: the exact defect above, reproduced inside the fix for it.
#   * A record carrying no `meta.loc` at all made the read THROW.
#   * A hand-set `meta.aspect-chain` was honoured over the walk, yielding a node whose parent
#     contradicts its own id. (It now refuses by name at `identity.key`: the chain is a rendering of
#     the declared path, never an input.)
#
# ⇒ THE ID AND THE PARENT NOW COME FROM ONE SOURCE, and that is the property rather than an
# optimisation: the id IS the origin-qualified walk key, so any second source for the parent makes
# their DISAGREEMENT expressible, and every such disagreement is a silent wrong. It also makes
# totality a CONSTRUCTION rather than a check — `walk.nix` descends only into values it also emits,
# so a non-root node's parent is necessarily already a node, and no refusal is needed to say so.
#
# NO QUERY LIBRARY IS IMPORTED, AND THAT IS THE DESIGN RATHER THAN AN OMISSION. Every fact here is
# plain data — an attrset, a list, a string, an int — so ADR-0014's "only plain data crosses" holds
# by construction, and the query libraries are needed to QUERY the graph, never to STATE it. Routing
# one through gen-aspects would additionally hand the substrate a second route to the evaluator,
# which is the engine drift one gen-scope exists to prevent (ADR-0006, ADR-0008).
{
  prelude,
  T,
  GT,
  includesDefault,
  keyCategory,
  hasClassContent,
}:
let
  inherit (import ./cnf.nix) checkedEntry;
  inherit (import ./walk.nix) walk isGuardLeaf;

  inherit (import ./path.nix) render;
  # `builtins.warn` where the evaluator has it (it honours `abort-on-warn`), a trace otherwise
  # (gen-schema `lib/entry-type.nix`, the same binding).
  warn = builtins.warn or (msg: v: builtins.trace "evaluation warning: ${msg}" v);

  # The refusal renders from a NAMED binding rather than being spelled at its `throw`. Nix cannot
  # recover a thrown message through `tryEval`, so the CI asserts catchability on the real path and
  # message CONTENT on this renderer — the same split `cnf.nix` uses for `cnfRefusal`. A message
  # that exists only inside a `throw` is one nothing can hold to naming its subject.
  danglingIncludeRefusal =
    id: i: target:
    "gen-aspects: aspect '${id}' declares at include position ${toString i} a keyRef to '${target}', "
    + "which carries THIS tree's own origin and so names a local node — but no such node exists. "
    + "Nothing downstream can name the aspect at fault once this edge leaves the library, so it is "
    + "refused here rather than passed on: `gen-graph.mkGraph` unions edge targets into its node "
    + "set, which would admit the typo AS a node and widen the graph past the membership predicate. "
    + "Correct the path, or give the keyRef the origin the target actually belongs to.";

  # The door a declaration or a bare identifier is resolved at, named first (R6) with the aspect and
  # the include position at fault, since nothing downstream can name them once the edge leaves.
  includesDoor = id: i: "gen-aspects.includes (aspect '${id}', include position ${toString i})";
  # The same door for the aspect's own `includes`, which has no position.
  memberDoor = id: "gen-aspects.includes (aspect '${id}')";

  # memberKeyRefusal / expect: a directly-supplied registry bypasses the aspect type, so a key this
  # file reads can carry the wrong type, and the builtin the read feeds (`imap0`, `split`, `tail`)
  # then aborts past `tryEval` with an interpreter type error naming neither the aspect nor the key,
  # in a class the evaluators do not agree on. Each read is checked first and refuses by name at its
  # door: `prelude.checkOptions`' "must be an attrset, not a …" form, for a field.
  memberKeyRefusal =
    door: key: want: v:
    "${door}: '${key}' must be ${want}, not a ${builtins.typeOf v}";

  expect =
    door: key: want: pred: v:
    if pred v then v else throw (memberKeyRefusal door key want v);
  expectList = door: key: expect door key "a list" builtins.isList;

  # includeSitesMaxDepth / includeSitesDepthRefusal: `includeSitesOf` recurses into inline content's
  # own `includes`, and inline content can be NON-WELL-FOUNDED (`let s = { includes = [ s ]; }`). Its
  # positions then grow without end, and a reader walking them (a delivery closure) runs until memory
  # is exhausted, killed with no message. The recursion therefore spends from a depth budget and
  # refuses by name, catchably, past it: the `hasFnMaxDepth` pattern (`identity.nix`). The limit here
  # is memory, not the evaluator stack, so no moving ceiling sits under the constant; the budget only
  # has to be far above any include nesting written as configuration.
  includeSitesMaxDepth = 256;

  # A parametric declaration's context-free include element is resolved once, at the declaration
  # (`declSites` below), so a refusal there is the declaration's: it names the aspect and the
  # include position, in guard-term's form, and refuses wherever the declaration's sites are read,
  # whether or not anything instantiates it.
  # `where` is `include position <i>`, or `includes` for a whole member.
  declarationMemberRefusal =
    id: where: left:
    GT.render "aspect `${id}`, ${where}, a declaration member resolved once at the declaration" left;

  includeSitesDepthRefusal =
    id: pos:
    "gen-aspects: aspect '${id}' nests inline include content deeper than the budget of "
    + "${toString includeSitesMaxDepth} levels (at include position ${pos}). Content nested that deeply is "
    + "almost always CYCLIC, a literal that includes itself, and a reader following it would never "
    + "finish, so the include sites refuse by name here instead. Name the repeated content as an "
    + "aspect and include it by reference: a cycle between named aspects is well defined.";
in
rec {
  # Exported for the CI's message assertions, NOT re-exported from `lib/default.nix`: a consumer
  # reads a refusal, never renders one. The budget travels with them so a cell straddling it reads
  # the number from here.
  inherit
    danglingIncludeRefusal
    declarationMemberRefusal
    includeSitesDepthRefusal
    includeSitesMaxDepth
    memberKeyRefusal
    ;

  # `graphFacts cnf aspects` →
  #   { nodes; parentOf; includeSitesOf; includesOf; foreignIncludesOf; unresolvedIncludesOf;
  #     nodeIdOf; nodeData; }
  #
  # `nodes` is the membership predicate's answer as a list of ids; the rest are attrsets keyed by
  # that same id, so `attrNames` over any of them IS the node set — totality, asserted in
  # `ci/tests/graph-facts.nix`. The one exception is `nodeIdOf`, keyed by the LOCAL key a member is
  # named by, whose values are those ids.
  #
  # `graphCore` takes a constructed `cnf` (behind `checkedEntry`) and is shared with `instancesFor`
  # (lib/instance.nix), so the relation reads the one classification rather than a second one.
  graphCore =
    cnf: aspects:
    let
      # THE NODE ID IS THE ORIGIN-QUALIFIED WALK KEY. The origin qualifier is just another identity
      # key (ADR-0016), which is why `aspectId` already mints over `[ "origin" "key" ]`; the
      # container-relative half is the walk position the registry already keys on.
      #
      # ★ THE ID IS DELIBERATELY NOT `identity.key`. For a placed guard the two render alike
      # (`identity.key` is its declared path, `meta.loc`, identity design §1), and so does a static
      # aspect's, but `meta.loc` rides with a value carried by value (an alias at another tree
      # position keeps the one it was declared with), while the walk position cannot be moved; and `guardKey`, the guard TERM's identity (`"guard:<hash>"`, the mint over
      # condition and body), is never a position at all. ADR-0016 ruling 5 rules the separation
      # directly: an identifier is not an identity, and `id_hash` — which for this library IS
      # `aspectId` — is internal addressing only, so the minted hash may never be the durable
      # vertex name.
      origin = cnf.providerPrefix;
      idOf = path: render (origin ++ path);
      # An already-rendered container-relative key (an include element's `.key`) qualified the same
      # way: the origin is rendered and the key, already a rendering, is joined as is (rendering it as
      # one segment would escape its own separators).
      qualify = key: if origin == [ ] then key else render origin + "/" + key;

      entries = walk aspects;

      nodes = map (e: idOf e.path) entries;
      # The registry the include references resolve against: the tree's own nodes by their
      # container-relative walk key, which is what a by-value element's `.key` and a bare identifier
      # spell. Local-only by construction: the origin qualifies the id afterwards (`qualify`).
      localNodes = builtins.listToAttrs (
        map (e: {
          name = render e.path;
          inherit (e) value;
        }) entries
      );

      # (d): a declaration IS the canonical entry `k` when it carries that entry's stamp and its
      # identity-key values. The stamp is `id_hash`, which `aspectId` mints over origin and key, so
      # the origin half rides in the stamp and `key` is the one identity key to compare. Nothing is
      # minted (ADR-0034). Both stamp reads are guarded: a stampless value (or a stampless guard-leaf
      # entry) is "not this member", an ordinary verdict `prelude.resolve` refuses by name, where an
      # unguarded read aborts past `tryEval`. A conjunction of `?` and primitive `==`, so a bool.
      isCanonical =
        v: k:
        let
          c = localNodes.${k};
        in
        c ? id_hash && (v.id_hash or null) == c.id_hash && (v.key or null) == c.key;

      resolveRef =
        prelude.resolve
          {
            hint = "key";
            form = "an aspect value carrying its string 'key'";
          }
          {
            entries = localNodes;
            inherit isCanonical;
          };
      # A reference that resolved: the registry answers the local key, the edge names the node id.
      # Forced before the record is built, so a refusal reaches every relation that reads the kind,
      # not only the one that reads the target.
      local =
        door: ref:
        let
          k = resolveRef door ref;
        in
        builtins.seq k {
          kind = "local";
          target = qualify k;
        };
      nodeData = builtins.listToAttrs (
        map (e: {
          name = idOf e.path;
          inherit (e) value;
        }) entries
      );

      # THE PARENT EDGE, taken from the walk position the entry already carries. `null` means ROOT
      # and nothing else: a one-segment walk path IS a root of this container, so the value cannot
      # stand in for an absence the way a `meta` read could. Totality holds by construction, which
      # is why no refusal guards this — `test-parent-closure-is-a-construction` pins the walk
      # property the construction rests on instead.
      parentOf = builtins.listToAttrs (
        map (e: {
          name = idOf e.path;
          value = if builtins.length e.path <= 1 then null else idOf (prelude.init e.path);
        }) entries
      );

      # ── the INCLUDE edges ──────────────────────────────────────────────────────────────────────
      #
      # ★ THE DISPATCH IS ON WHETHER THE ELEMENT NAMES A NODE, NOT ON THE ELEMENT'S SHAPE. Reading
      # the shape is what produces a refusal on shapes this library ships and tests — a guard
      # record at an include position — and a fabricated id for the inline `{ … }` aspect literal,
      # whose `.key` is its MERGE position under `includes` rather than a walk position. An `includes` list holds two
      # different kinds of thing and only one of them is an edge:
      #
      #   REFERENCE — a `keyRef`, or a by-value aspect whose key IS a node. It has a target.
      #   INLINE    — content written AT the include position: a guard record, an aspect literal. The walk never descends
      #               into `includes`, so no node exists for an edge to reach. This is not a broken
      #               reference; it is not a reference at all.
      #
      # An inline element is neither refused nor dropped: its POSITION is published in
      # `unresolvedIncludesOf`, so a consumer needing the element indexes back into
      # `nodeData.<id>.includes` and nothing about the declaration goes unsaid. Inline elements are
      # of two kinds, and `includeSitesOf` publishes which: CONTENT, a keyed aspect literal that
      # passes `isIncludeContent` or a KEY-LESS attrset that is not a guard leaf (static, so its own
      # `includes` classify by this same rule), and SEALED, everything else (a guard record, a
      # function), whose content exists only once a context is supplied. A key-less attrset is
      # content by meaning, not by provenance: it cannot be a reference (a reference is located by
      # `key`, `__keyRef` or a string), and only a guard leaf still awaits a context. One rule for a
      # node's value and an applied body alike (den-hoag-lwbb1 OQ-U2.9 arm (B), uniform): the fired
      # body of a first-order guard is data the aspect type never merged, so its literals carry no
      # stamp, and this is what classifies them.
      #
      # A keyRef carrying THIS tree's origin is checked here. A KEYED by-value element that is not
      # include content (below), and a bare identifier, are REFERENCES resolved by `prelude.resolve`
      # over `localNodes` with this library's `isCanonical`: a member by identifier or by value
      # resolves, and anything else is refused by name at `includesDoor` — a key naming no node, a
      # member re-keyed or otherwise edited off its canonical entry, a value carrying no stamp.
      # ★ ONE ADMISSION IS NOT A REFUSAL, and it is the identity law's: another tree's value with the
      # same origin and the same key carries the same stamp and resolves to the LOCAL node, whose
      # content is served and the foreign content dropped (README, "References resolve by identity").
      # A KEY-LESS attrset is content unless it is a guard leaf, which stays sealed: a guard-leaf
      # node of another tree carries no `.key` to locate it by, and its content awaits a firing.
      resolve =
        id: i: elem:
        if builtins.isAttrs elem && (elem.__keyRef or false) then
          # A keyRef is a REFERENCE by construction, so a bad one is an error and not an ambiguity.
          # It is checkable exactly when its origin is ours; a genuinely foreign origin names a node
          # in a fixpoint this library does not hold and cannot be checked here at all.
          let
            target = render (elem.origin ++ elem.path);
          in
          if elem.origin != origin then
            {
              kind = "foreign";
              ref = { inherit (elem) origin path key; };
            }
          else if localNodes ? ${render elem.path} then
            {
              kind = "local";
              inherit target;
            }
          else
            throw (danglingIncludeRefusal id i target)
        else if builtins.isAttrs elem && elem ? key then
          if isIncludeContent (includesDoor id i) elem then
            { kind = "content"; }
          else
            local (includesDoor id i) elem
        else if builtins.isString elem then
          # A bare string is unconditionally a REFERENCE (den-hoag-2zjg1 rulings B / TERM "i") —
          # content is never string-shaped — so it has no `isIncludeContent` escape hatch. It
          # resolves LOCALLY ONLY, like a by-value element's `.key`: the string-sugar `keyRef`'s
          # origin is always its FIRST segment, so under most origins it would name a foreign node
          # nothing checks, instead of the local sibling the writer named.
          local (includesDoor id i) elem
        else if T.isTerm elem then
          # A context-dependent element of a parametric declaration (`declSites`): its target is
          # known only per instance, where it is classified at its position of the fired body.
          { kind = "deferred"; }
        else if builtins.isAttrs elem && !(isGuardLeaf elem) then
          # Key-less inline content (above): an applied body's literal, or a raw tree's.
          { kind = "content"; }
        else
          { kind = "sealed"; };

      # A KEYED value is include content exactly when it was WRITTEN at an include position, and
      # the test is that its stamped `meta.aspect-chain` has an `includes` segment past the first.
      # `includes` is a native structural key, never a child aspect, and the walk never descends
      # into it: so no NODE's chain carries that segment past index 0 (a root aspect named
      # `includes` has it at index 0 only), while every element merged into an `includes` option
      # has a chain `<owner path> ++ [ "includes" … ]`. Such an element carries no `meta.loc`, so its
      # `.key` is the rendering of its own fields (`pathKey (chain ++ [ name ])`), and both are read so
      # that neither field alone decides. The key is tested too:
      # its merge position under `includes` is PER DEFINITION (see AGENTS.md, "An `includes` list
      # holds REFERENCES and INLINE CONTENT"), so the test reads which key SPACE it is in and never
      # compares an index; a key set by hand outside that space is a claim to name a node, and it
      # refuses when none exists. Content copied from another aspect or another tree keeps the
      # chain and key of where it was written, so it stays content: it denotes no node anywhere.
      isIncludeContent =
        door: elem:
        let
          pastFirst = xs: builtins.elem "includes" (builtins.tail xs);
          key = expect door "key" "a string" builtins.isString elem.key;
        in
        pastFirst (builtins.filter builtins.isString (builtins.split "/" key))
        && pastFirst (expectList door "meta.aspect-chain" (elem.meta.aspect-chain or [ null ]));

      # A member with no `includes` (a hand-built or direct registry never passed the aspect type) reads
      # as the type's declared default, so the typed and untyped paths answer alike.
      # One whose `includes` is not a list refuses by name instead of aborting in `imap0`.
      includesOfValue =
        id: v:
        if isGuardLeaf v then
          [ ]
        else
          expectList (memberDoor id) "includes" (v.includes or includesDefault);

      # ★ THE ONE CLASSIFICATION PASS. Every include position of a node, in declared order, classified
      # by `resolve`:
      #
      #   { kind = "local";   target = <id>; }
      #   { kind = "foreign"; ref = { origin; path; key; }; }
      #   { kind = "content"; sites = [ site … ]; }   the element's OWN includes, by this same rule
      #   { kind = "sealed"; }
      #   { kind = "deferred"; }                          a parametric declaration's context-dependent
      #                                                    element (`declSites`), classified per instance
      #
      # The three relations below are PROJECTIONS of this one, not a second pass beside it, so they
      # cannot disagree with it or with each other. A position is a list index (at depth, a path of
      # them); nothing is minted, and a nested position renders only inside a refusal. A `content`
      # site's `sites` is a thunk: a dangling reference inside inline content refuses only for a
      # reader that descends into it, and the depth budget above bounds that descent.
      siteAt =
        id: p: elem:
        let
          at = prelude.concatStringsSep "." (map toString p);
          r = resolve id at elem;
        in
        if r.kind == "content" then
          {
            kind = "content";
            sites =
              if builtins.length p >= includeSitesMaxDepth then
                throw (includeSitesDepthRefusal id at)
              else
                sitesOf id p (expectList (includesDoor id at) "includes" (elem.includes or includesDefault));
          }
        else
          r;
      sitesOf = id: pos: prelude.imap0 (i: siteAt id (pos ++ [ i ]));

      # ── a PARAMETRIC DECLARATION'S MEMBERS, published without firing it (ADR-0010 §4(a) clause 2) ──
      #
      # van Antwerpen 2018 §2.5: an instantiation's members stay reachable through its `I` edge to
      # the declaration, whose members are static. A placed guard is CHECKED, so its body is an
      # `Attrs` term and its `includes` a `List` term: the members are that term's structure, which
      # does not depend on the substitution. An element with no context reader and no door `Ref` is
      # CONTEXT-FREE: it has one value under every substitution, so it is resolved once, here, under
      # an empty context and the guard's own nested map, and classified by `resolve`. Any other
      # element is `deferred`: its target exists only per instance (ADR-0010 §4(b)'s σ-dependent
      # edge target, admitted), and the instance classifies it at its own position.
      #
      # `whole` marks a declaration whose `includes` cannot be split by position: a context-dependent
      # `includes` member (an `If`, a `ReadCtx`), a door body, a body that is not an `Attrs` term, or
      # a carrier whose record fragments carry sites (they exist only where that fragment fires). It
      # publishes one `deferred`, and each instance classifies its whole fired `includes`.
      dependent =
        x:
        T.isTerm x
        && (
          T.readCtxHeads x != [ ] || builtins.any (n: n.__bodyTerm == "Ref" && GT.isDoorId n.id) (termNodes x)
        );
      termNodes = x: [ x ] ++ builtins.concatMap termNodes (T.children x);
      declValue =
        id: v: where: x:
        let
          r = T.resolveTerm {
            context = { };
            ref = rid: { right = (v.__nested or { }).${rid} or rid; };
          } x;
        in
        if !(T.isTerm x) then
          x
        else if r ? left then
          throw (declarationMemberRefusal id where r.left)
        else
          r.right;
      wholeDeferred = {
        whole = true;
        sites = [ { kind = "deferred"; } ];
      };
      declInfo =
        id: v:
        let
          b = v.body or null;
          inc = b.attrs.includes or null;
          split = sites: {
            whole = false;
            inherit sites;
          };
        in
        if v ? fragments then
          let
            records = builtins.filter (f: f.kind == "record") v.fragments;
          in
          if builtins.any (f: (declInfo id f.guard).sites != [ ]) records then
            wholeDeferred
          else
            split (
              sitesOf id [ ] (
                builtins.concatMap (f: if builtins.isAttrs f.body then f.body.includes or [ ] else [ ]) (
                  builtins.filter (f: f.kind != "record") v.fragments
                )
              )
            )
        else if !(T.isTerm b) || b.__bodyTerm != "Attrs" then
          wholeDeferred
        else if inc == null then
          split [ ]
        else if T.isTerm inc && inc.__bodyTerm == "List" then
          split (
            prelude.imap0 (
              i: x: siteAt id [ i ] (if dependent x then x else declValue id v "include position ${toString i}" x)
            ) inc.items
          )
        else if dependent inc then
          wholeDeferred
        else
          split (sitesOf id [ ] (expectList (memberDoor id) "includes" (declValue id v "`includes`" inc)));
      declOf = builtins.mapAttrs declInfo (prelude.filterAttrs (_: isGuardLeaf) nodeData);

      # A whole value's include sites: a node's, or an applied instance body's (`includeSitesOfEntry`).
      # `id` names the value in a refusal only. A guard leaf's are its declaration's members.
      sitesOfEntry =
        id: v: if isGuardLeaf v then (declInfo id v).sites else sitesOf id [ ] (includesOfValue id v);

      # AN INSTANCE'S SITES, read through its `instantiates` edge: the declaration's members, with each
      # `deferred` one classified at its own position of the instance's fired `includes` (only that
      # element is forced), or the whole fired `includes` where the declaration is `whole`.
      instanceSites =
        a: entry:
        let
          d = declOf.${a};
          key = entry.key or a;
        in
        if d.whole then
          sitesOf key [ ] (includesOfValue key entry)
        else
          prelude.imap0 (
            i: s:
            if s.kind == "deferred" then siteAt key [ i ] (builtins.elemAt (includesOfValue key entry) i) else s
          ) d.sites;

      includeSitesOf = builtins.listToAttrs (
        map (
          e:
          let
            id = idOf e.path;
          in
          {
            name = id;
            value = if declOf ? ${id} then declOf.${id}.sites else sitesOfEntry id e.value;
          }
        ) entries
      );

      # The top-level sites with their positions, which is what each projection selects over.
      topSites =
        kinds: id:
        builtins.filter (x: builtins.elem x.s.kind kinds) (
          prelude.imap0 (i: s: { inherit i s; }) includeSitesOf.${id}
        );
      project = f: builtins.mapAttrs (id: _: f id) includeSitesOf;

      includesOf = project (id: map (x: x.s.target) (topSites [ "local" ] id));

      # THE REFERENCES THIS LIBRARY COULD NOT CHECK, published apart from the ones it could. A
      # foreign keyRef names a node in a fixpoint gen-aspects does not hold, so its target is not a
      # node here and never becomes one; left in `includesOf` it is an UNCHECKED edge spelled
      # exactly like a checked one, and a consumer unioning edge targets into a node set widens the
      # graph past the membership predicate on a value nothing refused. The reference is published
      # in the declaration's own `{ origin; path; key; }` shape rather than rendered to a string:
      # a rendering has to be re-split downstream to recover the qualifier, and that re-split is a
      # second source for a fact the declaration already stated.
      foreignIncludesOf = project (id: map (x: x.s.ref) (topSites [ "foreign" ] id));

      # The declared include positions that name no node, PUBLISHED rather than dropped: an aspect's
      # inline include content is a fact the substrate holds, and a relation that simply omitted it
      # would be the "something vanishes and nothing says so" shape this whole design exists to
      # retire. Positions rather than elements, so reading the relation forces no element body.
      unresolvedIncludesOf = project (
        id:
        map (x: x.i) (
          topSites [
            "content"
            "sealed"
            "deferred"
          ] id
        )
      );

      # THE KEY → ID RELATION: the local key a member is named by (what a bare-string include
      # spells) to its origin-qualified node id. A consumer resolving a member by name reads it here
      # instead of re-rendering `origin ++ [ key ]`, which would be a second source for the id.
      nodeIdOf = builtins.mapAttrs (k: _: qualify k) localNodes;

      # THE DELIVERY RELATION (den-hoag-ouuwg): does a node's SUBTREE deliver? A node delivers when it
      # carries content on a DECLARED class key (`keyCategory` + `hasClassContent`, ADR-0028's Rider:
      # declared content, never shape), a non-empty `includes`, or a guard leaf (opaque until
      # discharged, so it may deliver), or when a child delivers. Total over `nodes`. `graphFacts`
      # forces `deadNested`, and through it the entry of every nested node, when its record is forced
      # (below); `graphCore`'s other reader, `instancesFor`, never reads either and pays nothing.
      childrenOf = builtins.groupBy (id: parentOf.${id}) (
        builtins.filter (id: parentOf.${id} != null) nodes
      );
      ownDelivers =
        v:
        isGuardLeaf v
        || (v.includes or includesDefault) != [ ]
        || builtins.any (k: keyCategory cnf k == "class" && hasClassContent v.${k}) (builtins.attrNames v);
      deliversOf = builtins.mapAttrs (
        id: v: ownDelivers v || builtins.any (c: deliversOf.${c}) (childrenOf.${id} or [ ])
      ) nodeData;
      # The dead-nested view (ADR-0012 clause 2: a view has a name and a defining query): the nested
      # aspects whose subtree delivers nothing.
      deadNested = builtins.filter (id: parentOf.${id} != null && !deliversOf.${id}) nodes;
    in
    {
      facts = {
        inherit
          nodes
          parentOf
          includeSitesOf
          includesOf
          foreignIncludesOf
          unresolvedIncludesOf
          nodeIdOf
          nodeData
          deliversOf
          deadNested
          ;
      };
      inherit sitesOfEntry instanceSites;
    };

  # A non-empty dead-nested view is SAID, not only published (ADR-0025 item 1): the record warns once
  # each time it is forced, so every reader of `graphFacts` sees it. `flatten` and `instancesFor` do
  # not read this record and do not warn.
  graphFacts = checkedEntry (
    cnf: aspects:
    let
      inherit (graphCore cnf aspects) facts;
    in
    if facts.deadNested == [ ] then
      facts
    else
      warn (
        "gen-aspects: nested aspect(s) ${
          prelude.concatStringsSep ", " (map (id: "`${id}`") facts.deadNested)
        } deliver nothing (no declared class content, no includes, no delivering child). A misspelt "
        + "class key is corrected at its spelling. Intended placeholder taxonomy has no silencing "
        + "remedy, and the warning is expected for it: declaring the key would make it an option, "
        + "not a node."
      ) facts
  );

  # `includeSitesOfEntry cnf aspects entry` → the include sites of any aspect value against this
  # tree, by the classification `graphFacts` publishes as `includeSitesOf` (one function, two
  # callers): a node's value gives its `includeSitesOf` entry, and an applied instance body gives
  # the sites its consumer descends (htfv3 spec gate K1, arm (A)). Partially applied to `cnf` and
  # `aspects`, the registry it resolves against is built once.
  includeSitesOfEntry = checkedEntry (
    cnf: aspects:
    let
      inherit (graphCore cnf aspects) sitesOfEntry;
    in
    entry: sitesOfEntry (entry.key or "<entry>") entry
  );
}
