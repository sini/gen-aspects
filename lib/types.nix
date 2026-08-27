# gen-aspects type system — re-hosted on gen-merge (was nixpkgs lib.types/evalModules).
#
# Palmer et al. (2024) "Intensional Functions" §2: one type, dispatch in merge.
# aspectType dispatches by value shape — attrsets and module functions to
# aspectSubmodule, guard functions to a functor wrap (deferred for pipeline resolution),
# primitives pass through.
#
# Each declared aspect key's option is built generically from cnf.keySemantics (class →
# deferredModule, channel → raw, facet → the entry's option/module). The module system's own
# option/freeform separation routes declared keys cleanly — undeclared keys become nested aspects.
#
# Lorenzen et al. (2025) "First-Order Laziness" §1-2.3: class content is a lazy
# constructor (deferredModule) — inspectable before forcing, evaluated only when
# the consuming NixOS/homeManager evaluation imports it.
#
# Guard functions ({ host, ... }: { ... }) are preserved via a functor wrap
# (inspectable `__functor` wrapping; cf. Reynolds 1972 defunctionalization by ANALOGY —
# the closure is preserved inside __functor, not eliminated; there is no per-form
# constructor and no single global apply, so this is not the literal §6 transform).
# Re-host note: the wrap is now a hand-built functor (gen-merge has no `functionTo`);
# it reproduces the old `(lib.types.functionTo aspectSubmodule).merge … // { __isWrappedFn; … }`
# functor byte-for-byte (isAttrs + callable via __functor, tagged __isWrappedFn/name/meta).
# The pipeline resolves them when context is available — they are NOT evaluated by
# the type system.
#
# Defunctionalized guard records (guard.nix, __guard) are passed through as first-order
# data by the __guard branch below — THAT path IS the Reynolds §6 transform (closed
# predicate vocabulary + one applyGuard); the functor wrap is the non-defunctionalized
# escape hatch for raw closures.
{
  prelude,
  merge,
  hashIdentity,
}:
let
  identity = import ./identity.nix { inherit prelude; };
  canTake = import ./can-take.nix { inherit prelude; };
  inherit (import ./cnf.nix) extendCnf checkedEntry;
  t = merge.types;

  # The set of known module args is `cnf.moduleArgs`, declared with its default in lib/cnf.nix.
  mkIsModuleFn = cnf: canTake.upTo cnf.moduleArgs;

  # The `__isWrappedFn` functor record — ONE construction site for the inspectable raw-closure wrap
  # (Reynolds 1972 by analogy, per the header: the closure is preserved inside `__functor`, not
  # eliminated). Both callers below build THIS record; they differ only in the APPLICATOR (how the
  # context args become a merged aspect) and in the formals/name/meta sources. Keeping the shape in
  # one place is the R11 no-drift argument: constructor and readers (flatten/identity/guard,
  # resolved-aspects) live in one lib, so the tag's shape can never skew across callers.
  mkWrapped =
    {
      apply,
      functionArgs,
      name,
      meta,
    }:
    {
      __functor = _: fnArgs: apply fnArgs;
      # nixpkgs `functionTo` sets `__functionArgs` (via setFunctionArgs) so downstream
      # `functionArgs`/`lib.isFunction` see the closure's arg shape; reproduced here.
      __functionArgs = functionArgs;
      __isWrappedFn = true;
      inherit name meta;
    };

  # Raw-closure guard wrap — a hand-built functor reproducing nixpkgs `functionTo`'s merge result
  # tagged as a wrapped fn. The DEF-LIST caller: invoked by the aspect TYPE's merge, so it wraps the
  # module system's def-list (a guard fn defined possibly across several files). When the pipeline
  # applies it to a context, each def's guard closure is applied and the results merge through the
  # aspectSubmodule (deferred resolution).
  wrapGuardFn =
    cnf: loc: defs:
    mkWrapped {
      apply =
        fnArgs:
        (aspectSubmodule cnf).merge (loc ++ [ "<function body>" ]) (
          map (d: {
            inherit (d) file;
            value = d.value fnArgs;
          }) defs
        );
      functionArgs = prelude.foldl' (acc: d: acc // builtins.functionArgs d.value) { } defs;
      name = prelude.last loc;
      meta = {
        inherit loc;
        file = (builtins.head defs).file or "<unknown>";
      };
    };

  # PUBLIC: wrap a SINGLE raw closure `ctx: <aspect>` as an inspectable aspect include — the
  # single-closure sibling of `wrapGuardFn`. A NATIVE author never needs it: a bare guard fn written
  # into an aspect rides the option-type merge (aspectType below), which applies `wrapGuardFn` for
  # them. But a PROGRAMMATICALLY-GENERATED include (constructed off the option type, e.g. a bridge
  # that raw-absorbs a foreign surface) bypasses that merge, so the wrap must be callable as API —
  # the same rationale that makes a generated guard record a first-order value rather than a closure
  # the type must intercept. The applied closure's result merges through the aspectSubmodule exactly
  # as `wrapGuardFn`'s def-list path does, so a `wrapFn`'d include is byte-equivalent to a
  # type-merge-wrapped bare fn (ci/tests/wrap-fn.nix). `name` sites the wrap for tracing (Palmer §5.1).
  wrapFn =
    cnf: name: fn:
    mkWrapped {
      apply =
        fnArgs:
        (aspectSubmodule cnf).merge
          [ name "<function body>" ]
          [
            {
              file = "<wrapFn>";
              value = fn fnArgs;
            }
          ];
      functionArgs = builtins.functionArgs fn;
      inherit name;
      meta = {
        loc = [ name ];
        file = "<wrapFn>";
      };
    };

  # PUBLIC (N-GATE): the OPT-IN self-gating wrapped fn. Distinct from `mkWrapped`/`wrapGuardFn` — the
  # native guard path applies UNCONDITIONALLY and THROWS on a missing required coord (its contract, pinned
  # by ci/tests/gated-wrap.nix test-native-guard-not-gated); `wrapGatedFn`'s applicator SELF-GATES:
  # every required coord (a no-default formal — the same predicate `lib/can-take.nix`'s `canTake` builds
  # as its `required` binding) present ⇒ `onResult (fn (intersectAttrs
  # functionArgs fnArgs))`; a required coord MISSING ⇒ `{ }` (INERT, no throw — merges harmlessly through
  # `aspectSubmodule`). Params: `functionArgs` — the EXPLICIT formals of the INNER fire fn (load-bearing: a
  # consumer's fire path is a closure whose own `builtins.functionArgs` is `{ fnArgs = false; }`, so the
  # gate must read the inner fn's real formals — the override); `onResult` — a result hook (DEFAULT
  # identity) a consumer threads its post-fire processing through (den-hoag's class-key grounding rides
  # here, keeping den vocab OUT of gen-aspects). SELF-CONTAINED — built directly (NOT via `mkWrapped`,
  # whose required `name`/`meta` formals a param-less call would trip), mirroring `mkWrapped`'s tag field
  # set EXACTLY — `__functor`, `__functionArgs`, `__isWrappedFn`, `name`, `meta` — so a `__isWrappedFn`
  # reader cannot tell a gated record from a plain one.
  wrapGatedFn =
    {
      functionArgs,
      name ? "<gated>",
      meta ? { },
      onResult ? (x: x),
    }:
    fn:
    let
      required = builtins.filter (n: !functionArgs.${n}) (builtins.attrNames functionArgs);
    in
    {
      __functor =
        _: fnArgs:
        if builtins.all (a: fnArgs ? ${a}) required then
          onResult (fn (builtins.intersectAttrs functionArgs fnArgs))
        else
          { };
      __functionArgs = functionArgs;
      __isWrappedFn = true;
      inherit name meta;
    };

  # Palmer's flat type. One type, dispatch in merge, no recursive type construction.
  aspectType =
    cnf:
    let
      isModuleFn = mkIsModuleFn cnf;
    in
    merge.mkOptionType {
      name = "aspect";
      check = _: true;
      merge =
        loc: defs:
        if builtins.length defs != 1 then
          if builtins.all (d: !(builtins.isAttrs d.value) && !(builtins.isFunction d.value)) defs then
            merge.mkMerge (map (d: d.value) defs)
          else
            (aspectSubmodule cnf).merge loc (
              map (
                d:
                if builtins.isFunction d.value then
                  d
                  // {
                    value = {
                      includes = [ d.value ];
                    };
                  }
                else
                  d
              ) defs
            )
        else
          let
            v = (builtins.head defs).value;
          in
          if builtins.isAttrs v && (v.__isWrappedFn or false) then
            v
          # TODO(guard): multi-def guard records not supported (single-def only) — a guard
          # record defined twice under one key loses guard-record shape (multi-def folds via
          # the `length defs != 1` path above; see ci/tests/guard.nix multidef limitation).
          else if builtins.isAttrs v && (v.__guard or false) then
            # Guard record (guard.nix) — guard PAYLOAD (pred/body) untouched; only tracing
            # name/meta attached (meta.loc gives an opaque-body guard a site-distinguished key;
            # not hashed by guardKey).
            v
            // {
              name = prelude.last loc;
              meta = (v.meta or { }) // {
                inherit loc;
                file = (builtins.head defs).file or "<unknown>";
              };
            }
          else if builtins.isFunction v && isModuleFn v then
            (aspectSubmodule cnf).merge loc defs
          else if builtins.isFunction v then
            # Guard function — wrap as inspectable functor for pipeline resolution
            # (analogy to Reynolds defunctionalization, not the literal transform).
            # Palmer §5.1: name + meta from loc for tracing/diagramming.
            wrapGuardFn cnf loc defs
          else if builtins.isAttrs v then
            (aspectSubmodule cnf).merge loc defs
          else
            (prelude.last defs).value;
    };

  # THE canonical content-address for an aspect of ANY kind — plain, wrapped-fn (__isWrappedFn), or
  # guard (__guard). Routed through the ecosystem's ONE hashIdentity formula (`gen-identity/lib/default.nix`,
  # binding `hashIdentity`, injected above); origin is just another identity key (design §Identity).
  # `key` = identity.key (the 3-way dispatch in `identity.nix`), so a wrapped-fn / guard record — NOT
  # a submodule instance, carries no `id_hash` option — gets the SAME id as a plain aspect via the
  # SAME formula, and it is an IDENTITY, not a vertex name: gen-link NAMES a federation node by its
  # origin-qualified `aspects.key`, never this. Consumers (the `id_hash` default; den-hoag, which retired
  # `sha256 "den-aspect:${key}"`) call THIS, never re-derive the preimage. `origin` is the source label as
  # a path list (concatStringsSep "/"); default [] ⇒ "" ⇒ today's `.key` partition preserved.
  aspectId =
    origin: aspect:
    hashIdentity "aspect" [ "origin" "key" ] (
      k:
      {
        origin = prelude.concatStringsSep "/" origin;
        key = identity.key aspect;
      }
      .${k}
    );

  # Recursion-safe binding: either doesn't force subtypes during construction.
  aspectOrFn = cnf: merge.either (aspectType cnf) (aspectSubmodule cnf);

  # Closed-key typo-gate (design decision 2, opt-in). With `cnf.closedKeys` on, an UNDECLARED aspect key
  # (declared class/channel/facet/structural keys are handled by the submodule `options` and never reach
  # the freeform elem type) is rejected with a NAMED throw unless it is listed in `cnf.freeformKeys`. A
  # listed key opens an UNGATED subtree (closedKeys=false for descendants) so legitimate nested aspects
  # still nest freely. `prelude.last loc` is the undeclared key name (lazyAttrsOf merges each attr at
  # `loc ++ [key]`).
  gatedFreeformElem =
    cnf:
    merge.mkOptionType {
      name = "gatedFreeformKey";
      check = _: true;
      merge =
        loc: defs:
        let
          k = prelude.last loc;
          # den feeds ONE pre-merged config def per freeform child, so `head defs` is THE value; the all-defs
          # form generalises for a native multi-def author (recurse iff SOME def is an attrset namespace; an
          # all-primitive undeclared multi-def key is not a namespace → throw). Decides on WHNF
          # (`isAttrs d.value`) — no deep forcing, strictly less than a spine-walk.
          anyAttrs = builtins.any (d: builtins.isAttrs d.value) defs;
        in
        if cnf.recursiveClosed then
          if anyAttrs then
            # a namespace node — recurse as a nested aspect, gate RETAINED (recursive-closed).
            (aspectType cnf).merge loc defs
          else
            throw "gen-aspects: undeclared aspect key '${k}' (value is not a nested aspect — a closed "
            + "aspect vocabulary admits an undeclared key only as a namespace attrset that recurses to a "
            + "declared class/channel/facet; a primitive/function/list value here is a typo or misplaced "
            + "content). Declare it in keySemantics, or nest it under a declared key."
        else if builtins.elem k cnf.freeformKeys then
          (aspectType (extendCnf cnf { closedKeys = false; })).merge loc defs
        else
          throw "gen-aspects: undeclared aspect key '${k}' (closed-key gate on; declare it in keySemantics or list it in freeformKeys)";
    };

  # The closed keySemantics category vocabulary (ADR-0027 ruling 2). ONE binding so the eager
  # aspectSubmodule check and the standalone `keyCategory` read below can never drift apart.
  validCategories = [
    "class"
    "channel"
    "facet"
  ];

  # checkCategory k e -> e.category — the ONE validation a keySemantics entry must pass before its
  # category is trusted anywhere: `e` must be an attrset carrying a `category` from the closed
  # vocabulary. A malformed entry refuses BY NAME here, naming both the offending key and (where
  # present) its bogus category value, rather than surfacing as a generic Nix type error several
  # layers downstream (den-hoag-7cya: a bare-string entry, or an unrecognised category string, was
  # reaching `aspects.keyCategory` — the documented "single classification surface" — silently,
  # because that read path never went through aspectSubmodule's eager check at all).
  checkCategory =
    k: e:
    if !(builtins.isAttrs e) then
      throw "gen-aspects: keySemantics key '${k}' must be an attrset with a 'category' field (got ${builtins.typeOf e}); expected { category = \"class\" | \"channel\" | \"facet\"; … }"
    else if !(e ? category) then
      throw "gen-aspects: keySemantics key '${k}' is missing its 'category' field (expected class|channel|facet)"
    else if !(builtins.elem e.category validCategories) then
      throw "gen-aspects: keySemantics key '${k}' has unknown category '${e.category}' (expected class|channel|facet)"
    else
      e.category;

  # An `includes` element is EITHER a by-value aspect (aspectOrFn — unchanged) OR a keyRef (an
  # origin-qualified reference to a node possibly outside the local fixpoint, §Kernel fixes / decision
  # 6). keyRef is detected by its `__keyRef` marker and passed through opaquely (gen-link resolves it
  # against the merged graph); everything else routes through aspectOrFn EXACTLY as before, so by-value
  # includes are byte-unchanged.
  includesElemType =
    cnf:
    merge.mkOptionType {
      name = "includesElem";
      check = _: true;
      merge =
        loc: defs:
        let
          v = (builtins.head defs).value;
          # A DEFERRED-RESOLUTION include element (opt-in `cnf.deferIncludeResolution`): a raw guard
          # closure, a `{ __fn; … }` battery record, or a defunctionalised policy record
          # (`__isPolicy`/`__denCanTake`). Like `__keyRef`, its resolution must NOT be forced by the type —
          # the consumer wraps/dispatches it registry-aware (den-hoag compile `normalize`; gen-dispatch
          # `deriveGroup` for a policy record). First-Order Laziness (Lorenzen et al. 2025): a
          # deferred-resolution include passes the type unforced. Default off ⇒ native guard-wrapping.
          isDeferredInclude =
            builtins.isFunction v
            || (
              builtins.isAttrs v
              && ((v.__fn or null) != null || (v.__isPolicy or false) || (v.__denCanTake or null) != null)
            );
          # a bare MODULE at the include position — an attrset with a non-empty top-level `imports` list (the
          # deferredModule merge slot, UNIQUELY the class-content collapse artifact; `imports` is never a valid
          # aspect content key). This is a class-named node mis-included AS an aspect. Structural, not a heuristic.
          isBareModuleInclude =
            builtins.isAttrs v && (v ? imports) && builtins.isList v.imports && v.imports != [ ];
        in
        if builtins.length defs == 1 && builtins.isAttrs v && (v.__keyRef or false) then
          v
        else if cnf.deferIncludeResolution && builtins.length defs == 1 && isDeferredInclude then
          v
        else if cnf.rejectBareModuleInclude && builtins.length defs == 1 && isBareModuleInclude then
          throw "gen-aspects: includes element is a bare module ({ imports = [ … ]; }) with no aspect identity — "
          + "a class-content node included AS an aspect? An include must be an aspect (by value or fixpoint "
          + "ref), a keyRef, or a deferred fn/policy; `imports` is the module merge slot, never an aspect "
          + "content key."
        else
          (aspectOrFn cnf).merge loc defs;
    };

  # The native structural option SET — the six options every aspect submodule hardwires
  # (name/description/key/id_hash/meta/includes, below). ONE binding, so keyCategory and the submodule option
  # names cannot drift (a ci drift-pin asserts equality). Everything else is a declared keySemantics
  # class/channel/facet, or unregistered.
  nativeStructuralKeys = [
    "name"
    "description"
    "key"
    "id_hash"
    "meta"
    "includes"
  ];
  # keyCategory cnf key : "structural" | "class" | "channel" | "facet" | null. The single classification
  # surface — a consumer reads a key's category from HERE, never a parallel membership list. null = the key is
  # neither native-structural nor a declared keySemantics key (a typo, or a freeform nested-aspect child; the
  # closed gate distinguishes them). A key that IS declared but malformed (not an attrset, or an
  # attrset with an unrecognised category) refuses BY NAME via checkCategory — this is the read site
  # den-hoag-7cya measured as a silent pass-through (it never went through aspectSubmodule's own eager
  # check, so a bad entry rode all the way to a consumer as an unvalidated string, or an attribute
  # lookup on a non-attrset that threw a generic, unnamed Nix error).
  # The membership test on `cnf.keySemantics` (not `or null` on the dynamic lookup) is what makes
  # "key absent from keySemantics" (→ null, unchanged) and "key present but malformed" (→ throw, new)
  # two different outcomes instead of one `or` collapsing them.
  keyCategory =
    cnf: key:
    if builtins.elem key nativeStructuralKeys then
      "structural"
    else if cnf.keySemantics ? ${key} then
      checkCategory key cnf.keySemantics.${key}
    else
      null;

  # Aspect entry submodule.
  # Structural options (name, includes, meta) give each aspect identity.
  # Each DECLARED aspect key gets its option built generically FROM cnf.keySemantics:
  #   class   → deferredModule option (lazy class content; inspectable before forcing)
  #   channel → raw passthrough (mkOption { type = raw; default = null; }); value rides verbatim
  #   facet   → the entry's own bare `option`, or a full `module` mounted via imports
  # A key that isn't declared and isn't structural falls through the freeform fallback → a nested
  # aspect (gets identity). No hardcoded class arm: a class is just a keySemantics category.
  # cnf.aspectModules still extends with pipeline-specific options AND carries gen-schema's
  # __defsModule seam (schema.nix injects config.schema.aspect.__defsModule into it), so it MUST
  # stay live in `imports` even though per-key channels no longer ride it.
  aspectSubmodule =
    cnf:
    let
      rawKs = cnf.keySemantics;
      # Force category validation eagerly (a bad entry must throw at construction, not silently
      # never-match a keyOf filter). deepSeq forces checkCategory over every entry; ks is the
      # validated passthrough (checkCategory's own return value is discarded — downstream needs the
      # full entry, `.option`/`.module` included, not just the extracted category string).
      ks = builtins.deepSeq (prelude.mapAttrs checkCategory rawKs) rawKs;
      keyOf = category: builtins.attrNames (prelude.filterAttrs (_: e: e.category == category) ks);
      # A declared class with no content reads `null`, never an empty deferredModule. Absence must be
      # REPRESENTABLE in the value: a `{ }` default merges to `{ imports = [ { } ]; }`, which is
      # shape-indistinguishable from real content, so a delivery class would realize on the mere
      # DECLARATION (ADR-0028's Rider: a delivery class realizes only on declared content, never on
      # structural shape). The distinction does survive in the deferredModule's `_file` marker, but
      # recovering it there is a repair that sniffs a fabricated intermediate and binds a consumer to
      # merge-internal diagnostic text — `null` is the construction in which the intermediate never
      # forms. `channelOptions` below already represents absence this way.
      classOptions = prelude.genAttrs (keyOf "class") (
        _:
        merge.mkOption {
          description = "Class content (deferred module); `null` when the class is declared but never given content";
          default = null;
          type = t.nullOr t.deferredModule;
        }
      );
      channelOptions = prelude.genAttrs (keyOf "channel") (
        name:
        ks.${name}.option or (merge.mkOption {
          description = "Channel `${name}` (default raw passthrough)";
          default = null;
          type = t.raw;
        })
      );
      facetOptions = prelude.mapAttrs (_: e: e.option) (
        prelude.filterAttrs (_: e: e.category == "facet" && e ? option) ks
      );
      facetModules = prelude.mapAttrsToList (_: e: e.module) (
        prelude.filterAttrs (_: e: e.category == "facet" && e ? module) ks
      );
    in
    merge.submodule (
      {
        name,
        config,
        prefix ? [ ],
        ...
      }:
      {
        freeformType = t.lazyAttrsOf (if cnf.closedKeys then gatedFreeformElem cnf else aspectType cnf);
        config._module.args.aspect = config;
        # __defsModule seam: facet modules first, then aspectModules (which gen-schema's
        # mkAspectModule appends config.schema.aspect.__defsModule into). Dropping the tail breaks
        # schema-declared instance-option propagation.
        imports = facetModules ++ cnf.aspectModules;

        # A-IDENT (intrinsic path identity): the aspect's option path — the eval `prefix`
        # gen-merge threads into every module body (= the merge `loc`) — IS the identity. The
        # top container (`aspectsRoot`) re-roots the mount away, so `prefix` here is
        # CONTAINER-RELATIVE (2b, owner ruling): `[ apps media spicetify ]`, no mount segment.
        # `name` is already `last prefix`; the chain is everything above it. Stamped here so `key`
        # (= pathKey(chain ++ [name]) = pathKey(prefix), identity.nix `key`'s plain branch
        # `pathKey (aspectPath a)`) is path-bearing AT MERGE, born in the type — never
        # reconstructed downstream. Distinct paths ⇒ distinct keys (fixes the name-only collapse:
        # hardware.cpu.intel ≠ hardware.gpu.intel). The relative chain UNIFIES with the guard
        # branch (also loc-keyed and re-rooted, `aspectType`'s `__guard` branch),
        # is origin-invariant (§3a: the container root is the proto-namespace root; an origin
        # qualifier prepends additively), and byte-matches den-hoag's root-relative `__provider`.
        # mkDefault so a user-set meta.aspect-chain still wins.
        config.meta.aspect-chain = merge.mkDefault (if prefix == [ ] then [ ] else prelude.init prefix);

        options = {
          name = merge.mkOption {
            description = "Aspect name";
            default = name;
            type = t.str;
          };

          description = merge.mkOption {
            description = "Aspect description";
            default = "Aspect ${name}";
            type = t.str;
          };

          key = merge.mkOption {
            internal = true;
            readOnly = true;
            type = t.str;
            default = identity.key config;
          };

          # Convenience content-address on plain submodules, mirroring gen-schema's `id_hash` — computed
          # via the SAME exported `aspectId` (no second formula). Wrapped-fn / guard aspects are bare
          # records (no submodule, no option); consumers id them uniformly via `aspects.aspectId`.
          id_hash = merge.mkOption {
            internal = true;
            readOnly = true;
            type = t.str;
            default = aspectId cnf.providerPrefix config;
          };

          meta = merge.mkOption {
            description = "Aspect metadata";
            default = { };
            type = merge.submodule {
              freeformType = t.lazyAttrsOf t.raw;
              imports = cnf.metaModules;
            };
          };

          includes = merge.mkOption {
            description = "Aspects to include";
            type = t.listOf (includesElemType cnf);
            default = [ ];
          };
        }
        // classOptions
        // channelOptions
        // facetOptions;
      }
    );

  # aspectsRoot — the top aspect-container element type. A `lazyAttrsOf aspectType` that
  # RE-ROOTS: each first-level aspect is merged at `prefix = [ key ]` (NOT `containerLoc ++
  # [ key ]`), so the module-system mount segment (the option this container is mounted under —
  # `aspects`, or `den/aspects` in den) is dropped and A-IDENT identity is CONTAINER-RELATIVE
  # (2b, owner ruling 2026-07-13). Descendants keep accumulating relative through
  # `aspectSubmodule`'s own freeform (`lazyAttrsOf (aspectType cnf)`, still additive), so a deep
  # aspect keys as `apps/media/spicetify` — origin-invariant (§3a north-star: the container root
  # IS the proto-namespace root; an origin qualifier prepends additively) and byte-matching
  # den-hoag's root-relative `__provider` reconstruction. The reset is a per-container `mergeDefs
  # [ key ]` — no mount-depth arithmetic (portable across consumers), a uniform reset that keeps
  # plain and guard aspects in ONE relative namespace (collision law: plain+guard at the same
  # path dedup). MUST wrap only the TOP container, never `aspectSubmodule`'s nested freeform
  # (which must stay additive, else every level would reset to `[ ]` → name-only collapse).
  #
  # Element-parameterised, like gen-merge's own `attrsOfWith` (lib/types.nix, `attrsOf`/`lazyAttrsOf`):
  # a container that CARRIES an element type owes the nixpkgs sub-protocol over that element
  # (getSubOptions/getSubModules/substSubModules), and `substSubModules` can only answer by rebuilding
  # ITSELF over the substituted element — so the constructor has to take the element, not `cnf`.
  # `completeType`'s defaults (`{ }` / null / `_m: null`) are a LEAF's answers: on a wrapper they report
  # "declares nothing" indistinguishably from "protocol unimplemented here", which is the ambiguity a
  # supplied field cannot fall into.
  #
  # `getSubOptions` threads the caller's prefix (`prefix ++ [ "<name>" ]`, the per-key placeholder
  # segment) rather than re-rooting the way `merge` does. The two are not in tension: this type keeps
  # two distinct path notions, and each half reports the one it owns. `getSubOptions` is the ADDRESS —
  # where a consumer writes the value, which is still under the mount (`den.aspects.<name>.…`); the
  # re-rooting governs the merged aspect's IDENTITY (`key`, `meta.aspect-chain`), which `merge` derives
  # from its own re-rooted loc and which no introspection answer reports. Dropping the mount here would
  # hand an introspecting consumer an address that resolves nowhere.
  #
  # `getSubModules`/`substSubModules` propagate whatever the element answers. With `aspectType` as the
  # element that is `null` / a rebuild over `null`: `aspectType` is Palmer's flat dispatching type and
  # carries no module set, so `null` is its correct answer and propagating it is correct too. nixpkgs
  # calls `substSubModules` only where `getSubModules != null` (`fixupOptionType`, lib/modules.nix), so
  # the rebuild is live exactly when the element really does carry modules.
  #
  # Both propagations are guarded the way `attrsOfWith`/`listOf` guard theirs: an element that carries
  # no protocol AT ALL — a gen-types PARAMETRIC leaf (`enum`/`struct`/`union`) reaches the unified
  # namespace as a bare constructor and is never protocol-completed — must answer "nothing to
  # substitute" rather than abort on a missing attribute. `or null` covers the read; the `?` test
  # covers the rebuild, which falls back to the element unchanged.
  aspectsRootWith =
    elemType:
    merge.mkOptionType {
      name = "aspectsRoot";
      inherit elemType;
      nestedTypes = { inherit elemType; };
      getSubOptions = prefix: elemType.getSubOptions (prefix ++ [ "<name>" ]);
      getSubModules = elemType.getSubModules or null;
      substSubModules =
        m: aspectsRootWith (if elemType ? substSubModules then elemType.substSubModules m else elemType);
      merge =
        loc: defs:
        let
          keys = builtins.attrNames (prelude.foldl' (acc: d: acc // d.value) { } defs);
        in
        builtins.listToAttrs (
          map (k: {
            name = k;
            # re-root at [ k ]: drop the container `loc` (the mount) so children are relative.
            value = merge.mergeDefs [ k ] elemType (
              builtins.concatMap (
                d:
                prelude.optional (d.value ? ${k}) {
                  inherit (d) file;
                  value = d.value.${k};
                }
              ) defs
            );
          }) keys
        );
    };
  aspectsRoot = cnf: aspectsRootWith (aspectType cnf);

  # Top-level aspect container. Provides fixpoint: aspects can reference siblings.
  # Freeform is `aspectsRoot` (re-rooting) so nested identity is container-relative (A-IDENT 2b).
  aspectsType =
    cnf:
    merge.submodule (
      { config, ... }:
      {
        freeformType = aspectsRoot cnf;
        config._module.args.aspects = config;
      }
    );

in
{
  # PUBLIC entry points — every export whose first argument is a `cnf` constructs it through
  # `checkedEntry`, so a key outside the vocabulary refuses BY NAME here instead of being silently
  # inert. The recursion above (aspectType ↔ aspectSubmodule, gatedFreeformElem, includesElemType,
  # aspectsRoot's per-key mergeDefs) refers to the LOCAL bindings, which already hold a constructed
  # record: the check runs once per consumer call, not once per aspect node.
  aspectType = checkedEntry aspectType;
  aspectSubmodule = checkedEntry aspectSubmodule;
  aspectsType = checkedEntry aspectsType;
  aspectsRoot = checkedEntry aspectsRoot;
  aspectOrFn = checkedEntry aspectOrFn;
  mkIsModuleFn = checkedEntry mkIsModuleFn;
  wrapFn = checkedEntry wrapFn;
  keyCategory = checkedEntry keyCategory;
  # Not entry points, and the reason is structural rather than per-name: `canTake` carries no
  # configuration at all, `wrapGatedFn`'s first argument is a `{ functionArgs; … }` spec, `aspectId`
  # takes an origin path, and `structuralKeys` is a value.
  inherit
    canTake
    wrapGatedFn
    aspectId
    ;
  structuralKeys = nativeStructuralKeys;
}
