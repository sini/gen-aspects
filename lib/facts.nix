# THE ASPECT GRAPH'S FACTS. gen-aspects publishes them; the framework assembles the graph.
#
# ADR-0012 rules that the flat registry is a PROJECTION OF THE GRAPH, NEVER A SOURCE FOR IT, and
# that an aspect's slash-joined path key is a RENDERING of a parent edge rather than the edge.
# `flatten` was every structural consumer's only source for the node set, so the edges were
# recoverable from it only by parsing that rendering. This file ends that: the node set, the two
# edge relations and the node values are published as plain data, and nothing downstream re-derives
# an edge from a string.
#
# ★ THE PARENT RELATION IS NOT A JOIN — IT IS A DISPATCH, AND THE DISPATCH IS DOMAIN KNOWLEDGE.
# The position a node holds is recorded under a DIFFERENT ATTRIBUTE BY SHAPE: a plain aspect's
# under `meta.aspect-chain` (stamped at merge by `types.nix`), a wrapped-fn's or guard record's
# under `meta.loc`, and neither shape carries the other's. A framework joining `meta.aspect-chain`
# with the registry key would get a WRONG graph, not merely a re-derived one — measured: a nested
# guard leaf is in the registry, carries no `aspect-chain` at all, and `meta.aspect-chain or [ ]`
# answers ROOT for it while its true parent is its container. Worse, that wrong answer is
# INDISTINGUISHABLE from a right one, because a genuine root aspect yields `[ ]` through the same
# accessor: absence and root are the same value. So the relation is published ONCE, by the library
# that owns the node shapes.
#
# NO QUERY LIBRARY IS IMPORTED, AND THAT IS THE DESIGN RATHER THAN AN OMISSION. Every fact here is
# plain data — an attrset, a list, a string — so ADR-0014's "only plain data crosses" holds by
# construction, and the query libraries are needed to QUERY the graph, never to STATE it. Routing
# one through gen-aspects would additionally hand the substrate a second route to the evaluator,
# which is the engine drift one gen-scope exists to prevent (ADR-0006, ADR-0008).
{ prelude }:
let
  inherit (import ./cnf.nix) checkedEntry;
  inherit (import ./walk.nix) walk isGuardLeaf;

  render = prelude.concatStringsSep "/";

  # Every refusal below is rendered from a NAMED binding rather than spelled at its `throw`. Nix
  # cannot recover a thrown message through `tryEval`, so the CI asserts catchability on the real
  # path and message CONTENT on these renderers — the same split `cnf.nix` uses for `cnfRefusal`.
  # A message that only exists inside a `throw` is a message nothing can hold to naming its subject.
  positionRefusal =
    id: what:
    "gen-aspects: aspect '${id}' records no position in the tree (`${what}` is absent), so its parent "
    + "cannot be answered. Reading the position as `or [ ]` would report this node as a ROOT, which is "
    + "the absence-as-root collapse the published relation exists to retire.";

  danglingParentRefusal =
    id: position: parent:
    "gen-aspects: aspect '${id}' holds the position '${position}', whose parent '${parent}' is not a "
    + "node in this aspect tree. Nothing downstream can name the aspect at fault once this edge leaves "
    + "the library, so it is refused here. Either the parent is missing from the tree, or "
    + "`meta.aspect-chain` was set by hand to a path the tree does not contain.";

  unresolvableIncludeRefusal =
    id: i:
    "gen-aspects: aspect '${id}' declares an include at position ${toString i} that references no node "
    + "— an inline guard record or a deferred closure, not an aspect and not a keyRef. The walk never "
    + "descends into `includes`, so no node exists for the edge to reach. Give the include an aspect "
    + "(by value or as a `keyRef`), or declare the inline content at a position of its own, where it "
    + "becomes a node.";
in
{
  # Exported for the CI's message assertions, NOT re-exported from `lib/default.nix`: a consumer
  # reads the refusal, never renders it.
  inherit positionRefusal danglingParentRefusal unresolvableIncludeRefusal;

  # `graphFacts cnf aspects` → { nodes; parentOf; includesOf; nodeData; }
  #
  # `nodes` is the membership predicate's answer as a list of ids; the other three are attrsets
  # keyed by that same id, so `attrNames` over any of them IS the node set (the property O-row R3
  # names TOTALITY, asserted in `ci/tests/graph-facts.nix`).
  graphFacts = checkedEntry (
    cnf: aspects:
    let
      # R1 — THE NODE ID IS THE ORIGIN-QUALIFIED WALK KEY. The origin qualifier is just another
      # identity key (ADR-0016), which is why `aspectId` already mints over `[ "origin" "key" ]`;
      # the container-relative half is the walk position the registry already keys on.
      #
      # ★ THE ID IS DELIBERATELY NOT `identity.key`, AND THE DIFFERENCE IS NOT COSMETIC. That
      # function's `__guard` arm returns `guardKey`, which prefixes a located guard
      # (`"guard-loc:" + …`) or CONTENT-ADDRESSES a bodied one (`"guard:<pred>:<hash>"`) — so a
      # guard record's minted key is not its position at all, and building the id from it would
      # move every guard node's name off its walk position. ADR-0016 ruling 5 rules the separation
      # directly: an identifier is not an identity, and `id_hash` — which for this library IS
      # `aspectId` — is internal addressing only, so the minted hash may never be the durable
      # vertex name.
      origin = cnf.providerPrefix;
      idOf = path: render (origin ++ path);
      # An already-rendered container-relative key (an include element's `.key`) qualified the same
      # way. The key is slash-joined and the origin is a segment list, so one join spans both.
      qualify = key: render (origin ++ [ key ]);

      entries = walk aspects;

      nodes = map (e: idOf e.path) entries;
      nodeSet = builtins.listToAttrs (
        map (id: {
          name = id;
          value = true;
        }) nodes
      );
      nodeData = builtins.listToAttrs (
        map (e: {
          name = idOf e.path;
          inherit (e) value;
        }) entries
      );

      # R2 — the position a node HOLDS, dispatched on shape exactly as `identity.key` dispatches,
      # but resolving to the held position rather than to a minted key. Absence is never spelled as
      # a root: a shape whose position lives at an attribute that is missing REFUSES BY NAME, since
      # answering `[ ]` there is precisely the collapse this relation exists to retire.
      positionOf =
        id: v:
        if isGuardLeaf v then
          if (v.meta or { }) ? loc then v.meta.loc else throw (positionRefusal id "meta.loc")
        else if (v.meta or { }) ? aspect-chain then
          v.meta.aspect-chain ++ [ v.name ]
        else
          throw (positionRefusal id "meta.aspect-chain");

      # R3 — `parentOf` is TOTAL and REFUSES; it never defaults. Every node has an answer: an id, or
      # an explicit `null` meaning root. No node is silently absent from the relation.
      #
      # A parent naming a string that is not a node is a NAMED REFUSAL RAISED HERE, and THE GROUND
      # IS LOCALITY. Each alternative defers the objection to a site that cannot name the offending
      # aspect: passing the target through means the first objection arrives at an ordering call
      # holding a request and no idea whose chain was wrong; dropping the edge reports a node with
      # no parent while its own position says otherwise, which is silence about a fact the substrate
      # holds; and admitting the target as a node widens the node set past the membership predicate.
      parentOf = builtins.listToAttrs (
        map (
          e:
          let
            id = idOf e.path;
            position = positionOf id e.value;
          in
          {
            name = id;
            value =
              if builtins.length position <= 1 then
                null
              else
                let
                  parent = idOf (prelude.init position);
                in
                if nodeSet ? ${parent} then parent else throw (danglingParentRefusal id (render position) parent);
          }
        ) entries
      );

      # `includesOf` — the declared include edges, each element resolved to a node id.
      #
      # THE ELEMENT DISPATCH IS ON WHAT THE ELEMENT REFERENCES, and only two shapes reference a node.
      # A `keyRef` carries its own origin and path, so it qualifies with the REFERENT's origin rather
      # than this container's — that is what makes it a cross-source reference. A by-value aspect is a
      # submodule instance and its `.key` is the container-relative walk key, which qualifies here.
      #
      # ★ AN INLINE GUARD RECORD OR DEFERRED CLOSURE AT THE INCLUDE POSITION REFERENCES NOTHING, and
      # is refused by name rather than dropped. Measured: such an element's `meta.loc` is its MERGE
      # position (`app/includes/0`), not a walk position, and the walk never descends into `includes`
      # — so there is no node for the edge to land on, and minting one would widen the node set past
      # the membership predicate. Dropping it silently would lose a declaration the substrate holds,
      # which is the same defect on the includes side that R3 refuses on the parent side.
      includesOf = builtins.listToAttrs (
        map (
          e:
          let
            id = idOf e.path;
            declared = if isGuardLeaf e.value then [ ] else e.value.includes;
          in
          {
            name = id;
            value = prelude.imap0 (
              i: elem:
              if builtins.isAttrs elem && (elem.__keyRef or false) then
                render (elem.origin ++ elem.path)
              else if builtins.isAttrs elem && elem ? key then
                qualify elem.key
              else
                throw (unresolvableIncludeRefusal id i)
            ) declared;
          }
        ) entries
      );
    in
    {
      inherit
        nodes
        parentOf
        includesOf
        nodeData
        ;
    }
  );
}
