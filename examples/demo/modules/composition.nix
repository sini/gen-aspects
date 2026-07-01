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
  genDispatch,
  genGraph,
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

      # Parallel to raw-settings: the node ID of each contributing layer, so
      # composeForHost can label layers (env vs host) without guessing. Same
      # neron traverse + same null-drop, so it stays length-aligned with raw-settings.
      raw-settings-ids = genScope.collectionAttr {
        traverse = "neron";
        extract =
          _self: id:
          let
            nodeSettings = (roots.${id} or { decls.settings = { }; }).decls.settings;
          in
          if nodeSettings == { } then null else id;
      };
    };
  };

  # --- 4. Compose settings per host ---

  # Policy layer: per-host fixpoint dispatch produces `configure` actions that
  # become the FINAL cascade layer (wins by position over env/host settings).
  policyRules = import ./_policy-rules.nix { inherit lib genDispatch genGraph; };
  inherit (policyRules)
    act
    phaseOrder
    rules
    extract
    fromFunctionMatch
    ;

  # The convergence LOOP is gen-resolve's / gen-scope.circular's (Kleene ascent);
  # gen-dispatch supplies only the STEP (dispatchStep). Pair them: dispatchInit seeds
  # the circular value { context; fired; accActions; ... }, dispatchStep is one pass.
  policyCfg = {
    inherit rules extract phaseOrder;
    id = null;
    match = fromFunctionMatch;
    classify = act.classify;
    combine = ctx: ext: ctx // ext;
  };
  policyStep = genDispatch.dispatchStep { inherit (genDispatch) dispatch; } policyCfg;

  dispatchForHost =
    hostName:
    let
      h = config.fleet.hosts.${hostName};
      context = {
        env = config.fleet.environments.${h.env};
        host = h // {
          name = hostName;
        };
      };
    in
    (genScope.circular {
      init = genDispatch.dispatchInit context;
      # Convergence by top-level context key-set: sound here because the only feedback
      # is enrich (via extract), which only ever ADDS top-level keys — never changes a
      # value in place. A ruleset that mutated a value without adding a key would need a
      # value-aware eq.
      eq = a: b: builtins.attrNames a.context == builtins.attrNames b.context;
    } policyStep)
      { }
      null;
  policyResultsByHost = lib.genAttrs hostNames dispatchForHost;

  # Collapse one host's configure actions into ONE aspect-namespaced patch:
  #   [ {aspect="postgres";settings={...};} {aspect="firewall";settings={...};} ]
  #   => { postgres = {...}; firewall = {...}; }
  # The inner `//` is a SHALLOW merge at the aspect's top level: safe because each
  # rule targets a distinct aspect (or disjoint keys). Two configure actions on the
  # same aspect with overlapping top-level keys would clobber — use recursiveUpdate
  # if that becomes possible.
  policyPatchForHost =
    hostName:
    builtins.foldl' (
      acc: a:
      acc
      // {
        ${a.aspect} = (acc.${a.aspect} or { }) // a.settings;
      }
    ) { } (policyResultsByHost.${hostName}.accActions.configuration or [ ]);

  composeForHost =
    hostName:
    let
      nodeId = "host:${hostName}";
      rawLayers = scopeResult.get nodeId "raw-settings"; # most-specific first
      rawIds = scopeResult.get nodeId "raw-settings-ids"; # parallel ids, identical null-drop
      entityLayers = map (l: flattenAttrs "" l) (lib.reverseList rawLayers); # least-specific first
      entityNames = map (id: lib.head (lib.splitString ":" id)) (lib.reverseList rawIds); # "env" | "host"
      policyLayer = flattenAttrs "" (policyPatchForHost hostName);
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

  composedResults = lib.genAttrs hostNames composeForHost;
  composedSettings = lib.mapAttrs (_: r: r.value) composedResults;
  settingsProvenance = lib.mapAttrs (_: r: r.provenance) composedResults;

in
{
  config._module.args = {
    inherit
      composedSettings
      settingsProvenance
      scopeResult
      policyResultsByHost
      ;
  };
  # Interim flake outputs so the cascade is verifiable now; a later task adds the
  # named proof outputs on top. These raw exposures may remain.
  config.flake = {
    inherit composedSettings settingsProvenance;
  };
}
