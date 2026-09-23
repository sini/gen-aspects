# Settings composition: gen-scope neron traverse + gen-algebra foldLayers.
#
# READER side of the value-injection split: the aspect/haberdashery/scopeSettings definitions are
# composed PURELY in the gen tree (./gen-modules) and injected here as `genValues`. This module reads
# `genValues.{aspects,haberdashery,scopeSettings}` (was `config.*`) and runs the settings cascade on the
# flake-parts side, threading the results to sibling reader modules via `config._module.args`.
#
# Pipeline:
# 1. Extract settings schemas from all aspects (defaults + merge strategies)
# 2. Build scope graph: env nodes as roots, thimble nodes with P-edges to env
# 3. Neron traverse collects settings layers ordered D > I > P (thimble > env)
# 4. foldLayers merges with per-field strategies; result unflattened to nested attrsets
{
  lib,
  genValues,
  genAspects,
  genAlgebra,
  genScope,
  genDispatch,
  genGraph,
  ...
}:
let
  inherit (genAlgebra) record;

  # --- 1. Extract settings schemas from all aspects ---

  flat = genAspects.flatten genValues.aspects;

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
  # e.g. "services/nginx" → namespace "nginx", "define-basting" → namespace "define-basting"
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

  envNames = builtins.attrNames genValues.haberdashery.environments;
  thimbleNames = builtins.attrNames genValues.haberdashery.thimbles;

  envNodeIds = map (e: "env:${e}") envNames;
  thimbleNodeIds = map (h: "thimble:${h}") thimbleNames;

  # P-edges: thimble:<name> → env:<envName>
  parentEdges = map (
    h: genScope.edge "thimble:${h}" "env:${genValues.haberdashery.thimbles.${h}.env}"
  ) thimbleNames;

  scope = genScope.buildRoots {
    parentGraph = genScope.overlays parentEdges;
    decls =
      # Env nodes carry their settings overrides
      lib.listToAttrs (
        map (e: {
          name = "env:${e}";
          value = {
            settings = genValues.scopeSettings.${"env:${e}"} or { };
            tier = genValues.haberdashery.environments.${e}.tier;
          };
        }) envNames
      )
      //
        # Thimble nodes carry their settings overrides
        lib.listToAttrs (
          map (h: {
            name = "thimble:${h}";
            value = {
              settings = genValues.scopeSettings.${"thimble:${h}"} or { };
              role = genValues.haberdashery.thimbles.${h}.role;
              env = genValues.haberdashery.thimbles.${h}.env;
            };
          }) thimbleNames
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
    inherit scope;
    parseParent = id: (scope.nodes.${id} or { parent = null; }).parent;

    attributes = {
      # Children: thimble nodes whose parent is this env node.
      children = _self: id: lib.filterAttrs (_: n: n.parent == id) scope.nodes;

      # No import edges in this graph.
      imports = _self: _id: [ ];

      # Neron traverse: collect settings layers D > I > P (most-specific first).
      raw-settings = genScope.collectionAttr {
        traverse = "neron";
        extract =
          _self: id:
          let
            nodeSettings = (scope.nodes.${id} or { decls.settings = { }; }).decls.settings;
          in
          if nodeSettings == { } then null else nodeSettings;
      };

      # Parallel to raw-settings: the node ID of each contributing layer, so
      # composeForThimble can label layers (env vs thimble) without guessing. Same
      # neron traverse + same null-drop, so it stays length-aligned with raw-settings.
      raw-settings-ids = genScope.collectionAttr {
        traverse = "neron";
        extract =
          _self: id:
          let
            nodeSettings = (scope.nodes.${id} or { decls.settings = { }; }).decls.settings;
          in
          if nodeSettings == { } then null else id;
      };
    };
  };

  # --- 4. Compose settings per thimble ---

  # Policy layer: per-thimble fixpoint dispatch produces `configure` actions that
  # become the FINAL cascade layer (wins by position over env/thimble settings). The
  # convergence LOOP is gen-resolve's / gen-scope.circular's (Kleene ascent); gen-dispatch
  # supplies only the pure STEP. `_policy-rules.resolve` threads the plain domain state
  # (context) through repeated one-shot dispatch and reads the policy actions off the
  # fixpoint — see the "Convergence" section of gen-dispatch's README.
  policyRules = import ./_policy-rules.nix {
    inherit
      lib
      genDispatch
      genGraph
      genScope
      ;
  };
  inherit (policyRules) resolve;

  dispatchForThimble =
    thimbleName:
    let
      h = genValues.haberdashery.thimbles.${thimbleName};
    in
    resolve {
      env = genValues.haberdashery.environments.${h.env};
      thimble = h // {
        name = thimbleName;
      };
    };
  policyResultsByThimble = lib.genAttrs thimbleNames dispatchForThimble;

  # Collapse one thimble's configure actions into ONE aspect-namespaced patch:
  #   [ {aspect="postgres";settings={...};} {aspect="firewall";settings={...};} ]
  #   => { postgres = {...}; firewall = {...}; }
  # The inner `//` is a SHALLOW merge at the aspect's top level: safe because each
  # rule targets a distinct aspect (or disjoint keys). Two configure actions on the
  # same aspect with overlapping top-level keys would clobber — use recursiveUpdate
  # if that becomes possible.
  policyPatchForThimble =
    thimbleName:
    builtins.foldl' (
      acc: a:
      acc
      // {
        ${a.aspect} = (acc.${a.aspect} or { }) // a.settings;
      }
    ) { } (policyResultsByThimble.${thimbleName}.actions.configuration or [ ]);

  composeForThimble =
    thimbleName:
    let
      nodeId = "thimble:${thimbleName}";
      rawLayers = scopeResult.get nodeId "raw-settings"; # most-specific first
      rawIds = scopeResult.get nodeId "raw-settings-ids"; # parallel ids, identical null-drop
      entityLayers = map (l: flattenAttrs "" l) (lib.reverseList rawLayers); # least-specific first
      entityNames = map (id: lib.head (lib.splitString ":" id)) (lib.reverseList rawIds); # "env" | "thimble"
      policyLayer = flattenAttrs "" (policyPatchForThimble thimbleName);
      traced = record.foldLayersTraced {
        inherit strategies defaults;
        layers = entityLayers ++ [ policyLayer ]; # policy appended LAST → wins by position
        layerNames = entityNames ++ [ "policy" ]; # length-aligned with layers
        defaultLabel = "default";
      };
    in
    {
      value = unflattenAttrs traced.value;
      provenance = traced.provenance;
    };

  composedResults = lib.genAttrs thimbleNames composeForThimble;
  composedSettings = lib.mapAttrs (_: r: r.value) composedResults;
  settingsProvenance = lib.mapAttrs (_: r: r.provenance) composedResults;

in
{
  config._module.args = {
    inherit
      composedSettings
      settingsProvenance
      scopeResult
      policyResultsByThimble
      ;
  };
  # Interim flake outputs so the cascade is verifiable now; a later task adds the
  # named proof outputs on top. These raw exposures may remain.
  config.flake = {
    inherit composedSettings settingsProvenance;
  };
}
