# Graph traversals and pattern matching over the combined aspect registry.
# Demonstrates gen-graph and gen-select on a flattened aspect tree.
{
  config,
  lib,
  genAspects,
  genGraph,
  genSelect,
  ...
}:
let
  # --- Flatten main + namespace aspects into a unified registry ---

  mainFlat = genAspects.flatten config.aspects;

  nsFlat = lib.concatMapAttrs (
    nsName: ns:
    let
      raw = genAspects.flatten ns;
    in
    lib.mapAttrs' (k: v: {
      name = "${nsName}/${k}";
      value = v;
    }) raw
  ) config.namespaces;

  flat = mainFlat // nsFlat;
  flatKeys = builtins.attrNames flat;

  # --- Build gen-graph accessor ---

  # Map includes (evaluated aspect values) to their flat registry keys.
  # Accessing .key on includes can trigger submodule merge conflicts when the
  # same aspect is included from multiple files. Use .name (always safe) and
  # resolve to the flat registry key via reverse lookup.
  nameToKey = builtins.listToAttrs (
    map (k: {
      name = flat.${k}.name;
      value = k;
    }) flatKeys
  );

  includeEdges =
    id:
    let
      aspect = flat.${id};
      rawIncludes = aspect.includes or [ ];
      includeKeys = map (i: nameToKey.${i.name or "unknown"} or null) rawIncludes;
    in
    builtins.filter (k: k != null && flat ? ${k}) includeKeys;

  # Parent derived from path key: "a/b/c" → "a/b"
  parentOf =
    id:
    let
      parts = lib.splitString "/" id;
    in
    if builtins.length parts <= 1 then null else lib.concatStringsSep "/" (lib.init parts);

  g = {
    nodes = flatKeys;
    edges = includeEdges;
    parent = parentOf;
    nodeData = id: flat.${id};
  };

  # --- Build gen-select context ---

  walkParents =
    visited: id:
    let
      p = parentOf id;
    in
    if p == null then
      [ ]
    else if visited ? ${p} then
      [ ]
    else
      [ p ] ++ walkParents (visited // { ${p} = true; }) p;

  ctx = {
    data = id: flat.${id};
    parent = parentOf;
    children = id: builtins.filter (k: parentOf k == id) flatKeys;
    ancestors = id: walkParents { ${id} = true; } id;
    siblings =
      id:
      let
        p = parentOf id;
      in
      if p == null then
        [ ]
      else
        builtins.filter (k: k != id && parentOf k == p) flatKeys;
  };

  # --- Selector helpers ---

  hasTag = tag: genSelect.when (id: _ctx: builtins.elem tag ((flat.${id}).tags or [ ]));

  hasTier = tier: genSelect.when (id: _ctx: (flat.${id}).tier or "unspecified" == tier);

  selectWhere =
    sel: builtins.sort builtins.lessThan (builtins.filter (id: genSelect.matches sel id ctx) flatKeys);

  # --- Graph queries ---

  webDeps = builtins.sort builtins.lessThan (genGraph.reachableFrom g "services/nginx");
  dbImpact = builtins.sort builtins.lessThan (genGraph.dependentsOf g "services/postgres");
  allRoots = genGraph.roots g;
  allLeaves = genGraph.leaves g;
  hasCycles = genGraph.cycles g != [ ];

  # --- Selector queries ---

  publicFacing = selectWhere (hasTag "public-facing");
  statefulAspects = selectWhere (hasTag "stateful");
  securityAspects = selectWhere (hasTag "security");
  frontendTier = selectWhere (hasTier "frontend");
  dataTier = selectWhere (hasTier "data");

  # Observability aspects inside the namespace (prefix + tag)
  observabilityInNamespace = selectWhere (
    genSelect.and [
      (hasTag "observability")
      (genSelect.when (id: _ctx: lib.hasPrefix "observability/" id))
    ]
  );

  # Children of any aspect tagged "core"
  childrenOfCore = selectWhere (genSelect.within (hasTag "core"));

  queryResults = {
    inherit
      webDeps
      dbImpact
      allRoots
      allLeaves
      hasCycles
      publicFacing
      statefulAspects
      securityAspects
      frontendTier
      dataTier
      observabilityInNamespace
      childrenOfCore
      ;
  };
in
{
  config._module.args = {
    inherit
      flat
      g
      ctx
      queryResults
      ;
  };
}
