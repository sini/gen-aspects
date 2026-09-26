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
#   * `wrapFn cnf name fn` stamps `meta.loc = [ name ]` from the SITING NAME its caller passes, not
#     from a tree position. Read as a position it is one segment long, so `top/wf` and
#     `top/deeper/wf2` both reported parent `null` — a non-root node spelled as a ROOT, silently:
#     the exact defect above, reproduced inside the fix for it.
#   * `wrapGatedFn` defaults `meta ? { }`, so its record carries no `meta.loc` at all and the read
#     THREW on the output of a shipped, tested public constructor.
#   * A hand-set `meta.aspect-chain` (it is `mkDefault`) was honoured over the walk, yielding a node
#     whose parent contradicts its own id.
#
# The control in the same run — a bare fn wrapped by the type-merge path, which does carry a real
# `meta.loc` — answered correctly, so those were the shapes failing and not the instrument.
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
{ prelude }:
let
  inherit (import ./cnf.nix) checkedEntry;
  inherit (import ./walk.nix) walk isGuardLeaf;

  render = prelude.concatStringsSep "/";

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

  # The same split for a DECLARATION value: an aspect value, carrying a key, that denotes a node —
  # but not one of this tree. It carries no origin, so no framework downstream could resolve it
  # later either; published, it would be a fact with no possible resolver.
  danglingDeclarationRefusal =
    id: i: key:
    "gen-aspects: aspect '${id}' declares at include position ${toString i} an aspect value whose "
    + "key '${key}' names no node of this tree. The value was declared as a node (its key and its "
    + "`meta.aspect-chain` do not both place it at an include position), so it is a reference whose "
    + "target is missing — a value taken from another tree, or one whose key was set by hand. "
    + "Include a declared aspect of this tree, or reference another tree's with `keyRef`.";
in
{
  # Exported for the CI's message assertions, NOT re-exported from `lib/default.nix`: a consumer
  # reads a refusal, never renders one.
  inherit danglingIncludeRefusal danglingDeclarationRefusal;

  # `graphFacts cnf aspects` →
  #   { nodes; parentOf; includesOf; foreignIncludesOf; unresolvedIncludesOf; nodeData; }
  #
  # `nodes` is the membership predicate's answer as a list of ids; the rest are attrsets keyed by
  # that same id, so `attrNames` over any of them IS the node set — totality, asserted in
  # `ci/tests/graph-facts.nix`.
  graphFacts = checkedEntry (
    cnf: aspects:
    let
      # THE NODE ID IS THE ORIGIN-QUALIFIED WALK KEY. The origin qualifier is just another identity
      # key (ADR-0016), which is why `aspectId` already mints over `[ "origin" "key" ]`; the
      # container-relative half is the walk position the registry already keys on.
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
      # the shape is what produces a refusal on three shapes this library ships and tests — a raw
      # closure and an `__isPolicy` record under `cnf.deferIncludeResolution`, plus a bare closure
      # wrapped by the DEFAULT path — and a fabricated id for the inline `{ … }` aspect literal
      # (any record that is not a policy record is one), whose `.key` is its MERGE
      # position under `includes` rather than a walk position. An `includes` list holds two
      # different kinds of thing and only one of them is an edge:
      #
      #   REFERENCE — a `keyRef`, or a by-value aspect whose key IS a node. It has a target.
      #   INLINE    — content written AT the include position: a wrapped fn, a guard record, a
      #               deferred closure or policy record, an aspect literal. The walk never descends
      #               into `includes`, so no node exists for an edge to reach. This is not a broken
      #               reference; it is not a reference at all.
      #
      # An inline element is neither refused nor dropped: its POSITION is published in
      # `unresolvedIncludesOf`, so a consumer needing the element indexes back into
      # `nodeData.<id>.includes` and nothing about the declaration goes unsaid.
      #
      # TWO REFUSALS, each on a reference whose target is missing: a keyRef carrying THIS tree's
      # origin, and a KEYED by-value element that names no node and is not include content (below).
      # A KEY-LESS value is still read as content whatever it is: a guard-leaf or wrapped-fn node
      # of another tree carries no `.key` to test, and telling it from content needs a resolver that
      # checks the canonical entry rather than a key field (open under den-hoag-7gp66, den-hoag-lwbb1).
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
          else if nodeSet ? ${target} then
            {
              kind = "local";
              inherit target;
            }
          else
            throw (danglingIncludeRefusal id i target)
        else if builtins.isAttrs elem && elem ? key then
          if nodeSet ? ${qualify elem.key} then
            {
              kind = "local";
              target = qualify elem.key;
            }
          else if isIncludeContent elem then
            { kind = "inline"; }
          else
            throw (danglingDeclarationRefusal id i elem.key)
        else
          { kind = "inline"; };

      # A KEYED value is include content exactly when it was WRITTEN at an include position, and
      # the test is that its stamped `meta.aspect-chain` has an `includes` segment past the first.
      # `includes` is a native structural key, never a child aspect, and the walk never descends
      # into it: so no NODE's chain carries that segment past index 0 (a root aspect named
      # `includes` has it at index 0 only), while every element merged into an `includes` option
      # has a chain `<owner path> ++ [ "includes" … ]`. The chain is stamped from the merge prefix
      # and does not move with `name`; the `.key` does (`pathKey (chain ++ [ name ])`), so a node
      # named `includes` keys `…/includes` and the key alone cannot decide. The key is tested too:
      # its merge position under `includes` is PER DEFINITION (see AGENTS.md, "An `includes` list
      # holds REFERENCES and INLINE CONTENT"), so the test reads which key SPACE it is in and never
      # compares an index; a key set by hand outside that space is a claim to name a node, and it
      # refuses when none exists. Content copied from another aspect or another tree keeps the
      # chain and key of where it was written, so it stays content: it denotes no node anywhere.
      isIncludeContent =
        elem:
        let
          pastFirst = xs: builtins.elem "includes" (builtins.tail xs);
        in
        pastFirst (builtins.filter builtins.isString (builtins.split "/" elem.key))
        && pastFirst (elem.meta.aspect-chain or [ null ]);

      indexed =
        e:
        prelude.imap0 (i: elem: { inherit i elem; }) (
          if isGuardLeaf e.value then [ ] else e.value.includes
        );
      resolved = e: map (x: x // { r = resolve (idOf e.path) x.i x.elem; }) (indexed e);
      ofKind = k: e: builtins.filter (x: x.r.kind == k) (resolved e);

      includesOf = builtins.listToAttrs (
        map (e: {
          name = idOf e.path;
          value = map (x: x.r.target) (ofKind "local" e);
        }) entries
      );

      # THE REFERENCES THIS LIBRARY COULD NOT CHECK, published apart from the ones it could. A
      # foreign keyRef names a node in a fixpoint gen-aspects does not hold, so its target is not a
      # node here and never becomes one; left in `includesOf` it is an UNCHECKED edge spelled
      # exactly like a checked one, and a consumer unioning edge targets into a node set widens the
      # graph past the membership predicate on a value nothing refused. The reference is published
      # in the declaration's own `{ origin; path; key; }` shape rather than rendered to a string:
      # a rendering has to be re-split downstream to recover the qualifier, and that re-split is a
      # second source for a fact the declaration already stated.
      foreignIncludesOf = builtins.listToAttrs (
        map (e: {
          name = idOf e.path;
          value = map (x: x.r.ref) (ofKind "foreign" e);
        }) entries
      );

      # The declared include positions that name no node, PUBLISHED rather than dropped: an aspect's
      # inline include content is a fact the substrate holds, and a relation that simply omitted it
      # would be the "something vanishes and nothing says so" shape this whole design exists to
      # retire. Positions rather than elements, so reading the relation forces no element body.
      unresolvedIncludesOf = builtins.listToAttrs (
        map (e: {
          name = idOf e.path;
          value = map (x: x.i) (ofKind "inline" e);
        }) entries
      );
    in
    {
      inherit
        nodes
        parentOf
        includesOf
        foreignIncludesOf
        unresolvedIncludesOf
        nodeData
        ;
    }
  );
}
