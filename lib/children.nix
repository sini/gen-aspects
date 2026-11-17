# A node's CHILDREN, as include elements: the view of the parent edge read downward (ADR-0012 clause 2:
# a derived view has a name and a defining query). The defining query is the walk's own membership
# predicate (`walk.nix`): a child is a nested aspect or a guard leaf directly below the node, and class
# content, structural options and primitives are not. `graphFacts`' `parentOf` is the same predicate read
# upward, so a child here is exactly a node whose `parentOf` is the parent.
#
# `childrenOf cnf aspects path` → [ keyRef … ], one per child in `attrNames` order. Each reference is
# structured, `{ origin = cnf.providerPrefix; path = path ++ [ child ]; }`, so an include site under the
# same origin CHECKS it (a dangling one refuses by name there) and one under another origin publishes it
# as a foreign reference, never as a local node of a same-spelled path.
#
# THE ORIGIN IS THE TREE'S, CHECKED, NEVER THE CALLER'S CLAIM. A tree's origin is minted into every
# node's `id_hash` (`aspectId origin node`, the stamp the aspect type writes) and is held nowhere else, so
# the parent's stamp is re-derived under `cnf.providerPrefix` through the one authority and compared,
# as `facts.nix` `isCanonical` compares a by-value element's: a tree stamped under another origin, or a
# stampless one, refuses by name, so a reference never carries an origin its targets were not built
# under. Nothing new is minted or keyed by the comparison.
#
# THE COORDINATE IS THE NODE'S OWN, CHECKED, NEVER THE CALLER'S CLAIM. The stamp re-derives over the
# node's own declared path (`meta.loc`), so it decides the origin and says nothing about the `path` the
# caller walked: a hand-built container can hold a correctly stamped node at a coordinate that is not
# its own. The references and the name are built from the walked `path`, so a node whose declared path
# is not that path refuses by name, as a claimed origin does.
#
# `childBundle cnf aspects path` → the named include value `{ name; includes = childrenOf …; }`: a raw
# named value (identity design §2), so it is ONE node wherever it is included from one gen-aspects
# source, keyed by the position of its `name` (this file) and the name, its sightings decided
# same-or-distinct by `==` over the whole value. The name is `toJSON` of the origin and the CHECKED path,
# which is injective over the pair (a plain rendering of `origin ++ path` would join the two), so two
# parents never share a name; the value also carries the children's references, so two trees with one
# origin and one parent path but different children are two classes.
#
# Only the walk's predicate and the parent's stamp are read: the node's attribute names, each value's
# shape and the parent's `id_hash`. A child's content, and every `includes`, stay unforced, so a bundle
# may be written inside the tree it enumerates.
{
  prelude,
  cnfDoor,
  keyRef,
  aspectId,
}:
let
  inherit (import ./walk.nix) isNestedAspect isGuardLeaf;
  inherit (import ./path.nix) render;
  isChild = v: isNestedAspect v || isGuardLeaf v;

  # A parent that is no node of the tree refuses by name rather than reading as a node with no children:
  # an absent parent and a childless one are different answers. A guard leaf has no children until its
  # body is fired, and the walk never descends into one, so it refuses too.
  parentRefusal =
    door: path: what:
    "${door}: the parent `${render path}' is ${what}; name an aspect of this tree by its container-relative path (a list of segments).";
  originRefusal =
    door: path:
    "${door}: the parent `${render path}' was not built under this cnf's `providerPrefix` (its stamp is another origin's, or it carries none); read the tree with the cnf it was evaluated under.";
  coordinateRefusal =
    door: path: loc:
    let
      declared =
        if builtins.isList loc && builtins.all builtins.isString loc then
          "at `${render loc}'"
        else
          "at no path";
    in
    "${door}: the parent reached at `${render path}' was declared ${declared}; a node's coordinate is its own declared path, so name the parent by that path in the tree it was declared in.";
  nodeAt =
    door: cnf: aspects: path:
    let
      node =
        if !(builtins.isList path && builtins.all builtins.isString path) then
          throw "${door}: takes the parent's container-relative path as a list of strings, not a ${builtins.typeOf path}."
        else if path == [ ] then
          throw (parentRefusal door path "the container, which is no node")
        else
          builtins.foldl' (
            node: i:
            let
              seg = builtins.elemAt path i;
              at = builtins.genList (builtins.elemAt path) (i + 1);
              v = node.${seg};
            in
            if !(node ? ${seg}) then
              throw (parentRefusal door at "absent")
            else if isGuardLeaf v then
              throw (parentRefusal door at "a guard leaf, whose content exists only once a context is supplied")
            else if !(isNestedAspect v) then
              throw (parentRefusal door at "no aspect (class content, a structural option or a primitive)")
            else
              v
          ) aspects (builtins.genList (i: i) (builtins.length path));
    in
    # A stampless record refuses on its missing stamp before any mint is attempted.
    if !(node ? id_hash) || node.id_hash != aspectId cnf.providerPrefix node then
      throw (originRefusal door path)
    # The declared path the mint just read (identity.nix `checkedPath`); a key-labelled stamp has none.
    else if (node.meta.loc or null) != path then
      throw (coordinateRefusal door path (node.meta.loc or null))
    else
      node;

  childrenOfAt =
    door: cnf: aspects: path:
    let
      node = nodeAt door cnf aspects path;
      origin = cnf.providerPrefix;
    in
    {
      inherit node;
      refs = map (
        k:
        keyRef {
          inherit origin;
          path = path ++ [ k ];
        }
      ) (builtins.filter (k: isChild node.${k}) (builtins.attrNames node));
    };
in
{
  childrenOf = cnfDoor prelude "gen-aspects.childrenOf" (
    cnf: aspects: path:
    (childrenOfAt "gen-aspects.childrenOf" cnf aspects path).refs
  );
  childBundle = cnfDoor prelude "gen-aspects.childBundle" (
    cnf: aspects: path:
    let
      c = childrenOfAt "gen-aspects.childBundle" cnf aspects path;
    in
    {
      # The path is checked (through the node) before it is rendered, so a bad one gets its named refusal.
      name = builtins.seq c.node (
        builtins.toJSON {
          origin = cnf.providerPrefix;
          inherit path;
        }
      );
      includes = c.refs;
    }
  );
}
