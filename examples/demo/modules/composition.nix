# Settings composition: gen-scope neron traverse + gen-algebra foldLayers.
#
# Pipeline:
# 1. Extract settings schemas from all aspects (defaults + merge strategies)
# 2. Build scope graph: env nodes as roots, host nodes with P-edges to env
# 3. Neron traverse collects settings layers ordered D > I > P (host > env)
# 4. foldLayers merges with per-field strategies; result unflattened to nested attrsets
{
  config,
  lib,
  genAspects,
  genAlgebra,
  genScope,
  ...
}:
let
  inherit (genAlgebra) record;

  # --- 1. Extract settings schemas from all aspects ---

  flat = genAspects.flatten config.aspects;

  # Detect a settings leaf: an attrset with a `default` field.
  isSettingsLeaf = v: builtins.isAttrs v && v ? default;

  # Recursively walk a settings tree, producing flat dot-separated keys.
  # Returns { "path.to.field" = { default, merge }; }
  flattenSchema =
    prefix: settings:
    builtins.foldl' (
      acc: k:
      let
        v = settings.${k};
        key = if prefix == "" then k else "${prefix}.${k}";
      in
      if isSettingsLeaf v then
        acc // { ${key} = v; }
      else if builtins.isAttrs v then
        acc // flattenSchema key v
      else
        acc
    ) { } (builtins.attrNames settings);

  # Walk all flattened aspects, namespace settings under the aspect's leaf name.
  # e.g. "services/nginx" → namespace "nginx", "define-user" → namespace "define-user"
  allSchemas =
    let
      leafName =
        path:
        let
          parts = lib.splitString "/" path;
        in
        lib.last parts;
    in
    builtins.foldl' (
      acc: path:
      let
        aspect = flat.${path};
        settings = aspect.settings or { };
        ns = leafName path;
        prefixed = flattenSchema ns settings;
      in
      acc // prefixed
    ) { } (builtins.attrNames flat);

  # Build strategies and defaults maps from schemas.
  strategies = lib.mapAttrs (_: schema: schema.merge or "replace") allSchemas;
  defaults = lib.mapAttrs (_: schema: schema.default) allSchemas;

  # --- 2. Build scope graph ---

  envNames = builtins.attrNames config.fleet.environments;
  hostNames = builtins.attrNames config.fleet.hosts;

  envNodeIds = map (e: "env:${e}") envNames;
  hostNodeIds = map (h: "host:${h}") hostNames;

  # P-edges: host:<name> → env:<envName>
  parentEdges = map (h: genScope.edge "host:${h}" "env:${config.fleet.hosts.${h}.env}") hostNames;

  roots = genScope.buildNodes {
    parentGraph = genScope.overlays parentEdges;
    decls =
      # Env nodes carry their settings overrides
      lib.listToAttrs (
        map (e: {
          name = "env:${e}";
          value = {
            settings = config.scopeSettings.${"env:${e}"} or { };
            tier = config.fleet.environments.${e}.tier;
          };
        }) envNames
      )
      //
        # Host nodes carry their settings overrides
        lib.listToAttrs (
          map (h: {
            name = "host:${h}";
            value = {
              settings = config.scopeSettings.${"host:${h}"} or { };
              role = config.fleet.hosts.${h}.role;
              env = config.fleet.hosts.${h}.env;
            };
          }) hostNames
        );
  };

  # --- 3. Gen-scope eval with neron traverse ---

  # Flatten a nested attrset to dot-separated keys.
  # { a.b = 1; a.c = 2; } → { "a.b" = 1; "a.c" = 2; }
  flattenAttrs =
    prefix: attrs:
    builtins.foldl' (
      acc: k:
      let
        v = attrs.${k};
        key = if prefix == "" then k else "${prefix}.${k}";
      in
      if builtins.isAttrs v && v != { } && !(v ? __toString) then
        # Only recurse if the key has a known "replace" or no strategy.
        # For "recursive" strategy fields, keep the attrset as-is (it's the value).
        let
          strat = strategies.${key} or null;
        in
        if strat == "recursive" then acc // { ${key} = v; } else acc // flattenAttrs key v
      else
        acc // { ${key} = v; }
    ) { } (builtins.attrNames attrs);

  # Unflatten dot-separated keys back to nested attrsets.
  unflattenAttrs =
    flat':
    builtins.foldl' (
      acc: key:
      let
        parts = lib.splitString "." key;
        value = flat'.${key};
      in
      lib.recursiveUpdate acc (lib.setAttrByPath parts value)
    ) { } (builtins.attrNames flat');

  scopeResult = genScope.eval {
    inherit roots;
    parseParent = id: (roots.${id} or { parent = null; }).parent;

    attributes = {
      # Children: host nodes whose parent is this env node.
      children = _self: id: lib.filterAttrs (_: n: n.parent == id) roots;

      # No import edges in this graph.
      imports = _self: _id: [ ];

      # Neron traverse: collect settings layers D > I > P (most-specific first).
      raw-settings = genScope.collectionAttr {
        traverse = "neron";
        extract =
          _self: id:
          let
            nodeSettings = (roots.${id} or { decls.settings = { }; }).decls.settings;
          in
          if nodeSettings == { } then null else nodeSettings;
      };
    };
  };

  # --- 4. Compose settings per host ---

  composeForHost =
    hostName:
    let
      nodeId = "host:${hostName}";
      # Neron gives us [self-settings, parent-settings, ...] ordered D > I > P (most-specific first).
      # foldLayers expects least-specific first (CSS cascade), so reverse.
      rawLayers = scopeResult.get nodeId "raw-settings";
      flatLayers = map (layer: flattenAttrs "" layer) (lib.reverseList rawLayers);
      composed = record.foldLayers {
        inherit strategies defaults;
        layers = flatLayers;
      };
    in
    unflattenAttrs composed;

  composedSettings = lib.genAttrs hostNames composeForHost;

in
{
  config._module.args = {
    inherit composedSettings scopeResult;
  };
}
