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
# `children cnf aspects path` → the named include value `{ name; includes = childrenOf …; }`: a raw
# named value (identity design §2), so it is ONE node wherever it is included, keyed by the position of
# its `name` (this file) and the name, its sightings decided same-or-distinct by `==` over the whole value.
# The name is `toJSON` of the origin and the path, which is injective over the pair (a plain rendering
# of `origin ++ path` would join the two), so two parents never share a name; the value also carries the
# children's references, so two trees with one origin and one parent path but different children are two
# classes. Nothing is minted (ADR-0034; 7gp66 OQ4 (b′)).
#
# Only the walk's predicate is read: the node's attribute names and each value's shape. A child's content,
# and every `includes`, stay unforced, so a bundle may be written inside the tree it enumerates.
{
  prelude,
  cnfDoor,
  keyRef,
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
  nodeAt =
    door: aspects: path:
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

  childrenOfAt =
    door: cnf: aspects: path:
    let
      node = nodeAt door aspects path;
    in
    map (
      k:
      keyRef {
        origin = cnf.providerPrefix;
        path = path ++ [ k ];
      }
    ) (builtins.filter (k: isChild node.${k}) (builtins.attrNames node));
in
{
  childrenOf = cnfDoor prelude "gen-aspects.childrenOf" (childrenOfAt "gen-aspects.childrenOf");
  children = cnfDoor prelude "gen-aspects.children" (
    cnf: aspects: path: {
      name = builtins.toJSON {
        origin = cnf.providerPrefix;
        inherit path;
      };
      includes = childrenOfAt "gen-aspects.children" cnf aspects path;
    }
  );
}
