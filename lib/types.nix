# gen-aspects type system — ported to gen-merge (was nixpkgs lib.types/evalModules).
#
# Palmer et al. (2024) "Intensional Functions" §2: one type, dispatch in merge.
# aspectType dispatches by value shape — attrsets and module functions to
# aspectSubmodule, guard records (guard.nix) to their checked term, primitives pass through; a
# context closure is refused by name (design Section 3: closures cross the gen-rules door).
#
# Each declared aspect key's option is built generically from cnf.keySemantics (class →
# deferredModule, channel → raw, facet → the entry's option/module). The module system's own
# option/freeform separation routes declared keys cleanly — undeclared keys become nested aspects.
#
# Lorenzen et al. (2025) "First-Order Laziness" §1-2.3: class content is a lazy
# constructor (deferredModule) — inspectable before forcing, evaluated only when
# the consuming NixOS/homeManager evaluation imports it.
#
# Guard records (guard.nix, __guard) are first-order data, checked here against their cnf
# (lib/guard-term.nix) — the Reynolds §6 transform (closed condition vocabulary + one applyGuard). A
# context closure handed to gen-aspects is refused by name, naming the gen-rules door
# (den-hoag-lwbb1 stage 2b): gen-aspects holds terms only.
{
  prelude,
  merge,
  schema,
  hashIdentity,
  T,
}:
let
  identity = import ./identity.nix { inherit prelude; };
  canTake = import ./can-take.nix { inherit prelude; };

  # The identity inputs are written by the type and by nothing else (ADR-0016 r5: one minting
  # authority). `key` and `id_hash` are the type's computed values, and a write that differs from
  # them refuses by name at the option's `apply`; `meta.loc` is a plain type definition, so a
  # caller's unequal write conflicts with it at merge, and one that wins by priority refuses at
  # `locChecked` (`aspectSubmodule`). A write EQUAL to the type's own value is accepted: it mints
  # nothing. An already-typed value placed at a second position is a reference and is passed through
  # unmerged (`isTypedAspect`), so carriage never meets the refusal.
  isTypedAspect = v: builtins.isAttrs v && v ? id_hash && v ? key && !(v.__guard or false);

  # An inline element's declaring SITE (identity design §2, a raw named value: the position of its
  # `name` attribute and the name). A named attrset element is declared at
  # `<owner> includes <name>@<line>:<column>:<file>`, so two elements sharing a name at two positions
  # are two declarations, and module order moves neither (ADR-0034's rider: the declaring position,
  # never the merged one). An element with no positioned string `name` keeps its merge position
  # (`[definition N-entry M]`), the §1 anonymous rule's remaining gap: its module and definition
  # ordinal need gen-merge. `@` is escaped in the name, so the segment is injective, and `path.nix`
  # escapes the file's `/` where the path is rendered.
  includeSite =
    v: prefix:
    let
      pos = if v ? name && builtins.isString v.name then builtins.unsafeGetAttrPos "name" v else null;
    in
    if pos == null then
      prefix
    else
      prelude.init prefix
      ++ [
        "${
          builtins.replaceStrings [ "%" "@" ] [ "%25" "%40" ] v.name
        }@${toString pos.line}:${toString pos.column}:${pos.file}"
      ];
  # The element, read as a module that also DEFINES its declared path, from the module argument
  # `prefix` (its merge position) and its own authored value. An authored `key`, `id_hash` or
  # `meta.loc` refuses by name BEFORE the wrap: inside `imports` the attrset is a module, and its
  # top-level `key` would be the module key, dropped silently or deduplicating the element away.
  stampIncludeSite =
    d:
    let
      written =
        builtins.filter (k: d.value ? ${k}) [
          "key"
          "id_hash"
        ]
        ++ prelude.optional (builtins.isAttrs (d.value.meta or null) && d.value.meta ? loc) "meta.loc";
    in
    if written != [ ] then
      throw "gen-aspects: an include element named `${d.value.name}' writes `${builtins.head written}', which the aspect type writes; remove the definition."
    else
      d
      // {
        value =
          {
            prefix ? [ ],
            ...
          }:
          {
            imports = [ d.value ];
            config.meta.loc = includeSite d.value prefix;
          };
      };
  inherit (import ./cnf.nix)
    extendCnf
    checkedEntry
    mergedKeys
    ;
  cnfConstruction = (import ./cnf.nix).cnfConstruction schema.keySemanticsRecords;

  # The merge relation of a type built per `cnf` (`aspectType`, `gatedFreeformElem`,
  # `includesElemType`; den-hoag-bfc0k, the half of den-hoag-a0gc its tripwire left open). The
  # type's distinguishing content is its cnf, so two are one type exactly when their cnfs are one
  # construction, and every other same-named pair is refused rather than merged on the NAME
  # (ADR-0034; ADR-0025 item 1). gen-schema's `constructionRelation` decides that, per component,
  # over the cnf's construction (lib/cnf.nix `cnfConstruction`): the one implementation gen-schema's
  # own per-construction types use.
  # `minted` adds components beside the cnf's: a freeform position's `nesting` (below), which a type
  # at a declaration site does not state, so that type's construction is the cnf's alone.
  cnfFunctor =
    name: cnf: minted: self:
    let
      c = cnfConstruction cnf;
    in
    schema.constructionRelation (c // { minted = c.minted // minted; }) name self;
  t = merge.types;

  # The set of known module args is `cnf.moduleArgs`, declared with its default in lib/cnf.nix.
  mkIsModuleFn = cnf: canTake.upTo cnf.moduleArgs;

  # gen-aspects' instance of the one term algebra (lib/guard-term.nix), over this file's own
  # classification surface, so a guard's module slots are exactly the keys `keyCategory` calls classes.
  GT = import ./guard-term.nix {
    inherit
      T
      hashIdentity
      keyCategory
      mkIsModuleFn
      ;
  };

  # The retired closure wraps (den-hoag-lwbb1 stage 2b): refused-by-name aliases naming the door.
  retiredWrap =
    name:
    throw "gen-aspects.${name} was RETIRED by den-hoag-lwbb1: gen-aspects holds first-order guards only, and a context closure crosses the gen-rules door. Declare the aspect through the framework's surface, so that gen-rules' lowering turns the closure into a door node, or write it as a guard term (`guard (pred.has <coordinate>) <body>`).";
  wrapFn = _: retiredWrap "wrapFn";
  wrapGatedFn = _: retiredWrap "wrapGatedFn";

  # ── THE PORTS: gen-native types, stated in gen's vocabulary (den-hoag-n6dh7 item 5; gate C4) ──
  # `aspectType`, `gatedFreeformElem`, `includesElemType` and `aspectsRootWith` are built through
  # gen-merge's `defineType`, the library's one crossing site for a type stated in gen's words, and
  # not through `mkOptionType`: that is the door for a descriptor written in the FOREIGN protocol,
  # whose import wraps a fold stating `check` in a bare lambda and so erases the fold's threaded
  # sibling. Each states the sibling (`mergeDefs.threaded`, the same fold reading a nested tree
  # through the evaluation's accessor `ev` instead of evaluating it here), what it carries (so
  # `canNest` sees the nesting members), `recarry`, and `substructure` answering the sub-option
  # protocol exactly as it answered before the port. The dropped `check = _: true` stated no domain,
  # which a gen type says by stating no `admits`/`verify`.

  # A relation its author STATES as a functor, in both vocabularies from that one functor. The
  # functor and the foreign `typeMerge` over it are published as stated (`retainedRelation`, gen's
  # word for a relation stated rather than derived from `carries`), and gen's own relation asks the
  # same `typeMerge` about the partner's functor, so the two vocabularies cannot answer differently
  # and a refusal reads as it did when the relation crossed through the foreign import.
  statedRelation = name: functor: typeMerge: {
    retainedRelation = { inherit functor typeMerge; };
    typeMergeRel =
      other:
      let
        merged = if builtins.isAttrs other then typeMerge (other.functor or null) else null;
        # A per-cnf type at a freeform position states it in its payload (`cnfRelation`); two operands
        # of one name that differ only there are told apart by it.
        positionOf =
          f:
          if builtins.isAttrs f && builtins.isAttrs (f.payload or null) then
            f.payload.position or null
          else
            null;
        mine = positionOf functor;
        theirs = if builtins.isAttrs other then positionOf (other.functor or null) else null;
        at =
          p:
          if mine == null && theirs == null then
            ""
          else
            " at ${if p == null then "a declared position" else p}";
      in
      if merged == null then
        {
          refused = "`${name}'${at mine} and `${
            if builtins.isAttrs other then other.name or "<unnamed>" else builtins.typeOf other
          }'${at theirs}, which the first type's own `functor' does not reconcile";
        }
      else
        { inherit merged; };
  };

  # A per-cnf type's relation (`cnfFunctor`, gen-schema's construction relation): two such types
  # merge exactly when their cnfs are one construction. The cnf's module lists (`mergedKeys`) are
  # not part of it: they ride the payload and concatenate, as a nixpkgs submodule's `modules` do
  # (`submoduleWith`'s `binOp`), so the merge is `rebuild` over the joined cnf. It always joins:
  # telling an empty partner list apart would force it, and a list read from `config` may not be
  # forced while declarations fold (ADR-0033).
  cnfRelation =
    name: cnf: minted: rebuild: self:
    let
      construction = cnfFunctor name cnf minted self;
      functor = construction // {
        payload = construction.payload // {
          modules = prelude.genAttrs mergedKeys (k: cnf.${k});
          position =
            if minted ? nesting then
              "the freeform slot ${
                if minted.nesting.deep then "nested below" else "of"
              } `${merge.showOption minted.nesting.anchor}`"
            else
              null;
        };
        binOp =
          a: b:
          if construction.binOp a b == null then
            null
          else
            a
            // {
              modules = builtins.mapAttrs (k: l: l ++ b.modules.${k}) a.modules;
            };
        type = p: rebuild (extendCnf cnf p.modules);
      };
    in
    statedRelation name functor (
      f:
      let
        joined =
          if !(builtins.isAttrs f) || (f.name or null) != name || (f.payload or null) == null then
            null
          else
            functor.binOp functor.payload f.payload;
      in
      if joined == null then null else functor.type joined
    );

  # A per-cnf UNION: a type whose fold picks one of its members by the definitions' shape, or answers
  # without one. `dispatch loc defs` is that shape dispatch, stated ONCE: `{ member = <type>; }` where
  # a nesting-capable member folds the definitions, `{ value = …; }` where the type answers itself
  # (a guard record, a wrapped fn, a pass-through, a refusal). `choose` is its member half, `null`
  # where no member is chosen, and the called and threaded folds both dispatch on it, so a key walk
  # reading `choose` and the fold reading `dispatch` cannot disagree about the member. A union adds
  # no position step, so the accessor reaches the member unchanged.
  #
  # ★ THE CALLED FOLD FORWARDS TO THE MEMBER'S CALLED FOLD, as gen-merge's own `either` does. Once
  # the engine dispatches the threaded sibling, a nesting member's called fold refuses, so a path
  # that did not thread reaches that refusal, never a silent evaluation of its own.
  mkUnion =
    name: cnf:
    {
      alternatives,
      recarry,
      rebuild,
      dispatch,
      declares ? _prefix: { },
      minted ? { },
    }:
    let
      rel = cnfRelation name cnf minted rebuild self;
      choose = loc: defs: (dispatch loc defs).member or null;
      foldWith =
        foldMember: loc: defs:
        let
          r = dispatch loc defs;
        in
        if r ? member then foldMember r.member loc defs else r.value;
      self = merge.types.defineType {
        inherit name recarry choose;
        inherit (rel) typeMergeRel retainedRelation;
        carries.alternatives = alternatives;
        substructure = {
          inherit declares;
          modules = null;
          rebuild = _m: null;
        };
        # One member position, adding no step, under the member `choose` picks (gen-merge `either`).
        split = loc: defs: [
          {
            step = [ ];
            inherit loc defs;
            type = choose loc defs;
          }
        ];
        mergeDefs = {
          __functor = _: foldWith (m: m.mergeDefs);
          threaded = ev: foldWith (m: m.mergeDefs.threaded ev);
        };
      };
    in
    self;

  # A nesting member that reads each definition through `coerce` first. The transform lives in its
  # nested tree's `entry` (`nests.entry`), so the definitions its tree is seeded from are the
  # addresses the fold was handed, never values built from them: a threaded fold names its tree by
  # position and the tree reads its own definitions. The called fold is the submodule's own over the
  # coerced definitions, as the union's fold made it before the port.
  entryCoerced =
    sub: coerce:
    let
      n = sub.nests;
      nests = n // {
        entry = d: n.entry (coerce d);
      };
    in
    merge.types.defineType (
      sub
      // {
        inherit nests;
        mergeDefs = {
          __functor =
            _: loc: defs:
            sub.mergeDefs loc (map coerce defs);
          # A definition outside the submodule's domain is refused by the submodule's own fold, by
          # name, before any tree is read (`coerce` preserves the domain on both callers).
          threaded =
            ev: loc: defs:
            if builtins.all (d: sub.admits d.value) defs then
              (ev.child {
                inherit (ev) position;
                inherit nests loc defs;
              }).config
            else
              sub.mergeDefs.threaded ev loc defs;
        };
      }
    );

  # Palmer's flat type. One type, dispatch in merge, no recursive type construction.
  # A union (above) over its two nesting members: the plain aspect submodule, and the element that
  # coerces a function definition among several to `{ includes = [ f ]; }`.
  #
  # `nesting` is the position's relation to its nearest DECLARATION SITE, carried by the type rather
  # than read off the path (den-hoag-nwshf). `null`: the position is itself declared, which is every
  # aspect-typed position a caller writes (the container root, an `includes` element, an option or
  # facet typed `aspectType`). `{ anchor; deep; }`: the position is an element of an aspect
  # submodule's FREEFORM slot, the one place an undeclared key nests (`aspectSubmoduleAt`), where
  # `anchor` is the declared aspect's own loc and `deep` says the enclosing aspect was itself reached
  # through the freeform slot. A scalar or list at a `deep` position is the orphan leaf `orphanLeaf`
  # refuses; how the key is spelled plays no part.
  aspectType = cnf: aspectTypeAt cnf null;
  aspectTypeAt =
    cnf: nesting:
    let
      sub = aspectSubmoduleAt cnf nesting;
    in
    aspectTypeOver cnf nesting [
      sub
      (entryCoerced sub (
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
      ))
    ];
  aspectTypeOver =
    cnf: nesting: alternatives:
    let
      sub = builtins.elemAt alternatives 0;
      coerced = builtins.elemAt alternatives 1;
      isModuleFn = mkIsModuleFn cnf;
      # Arm B (witness 2, den-hoag-sezf §2): a def at a multi-def key is guard-shaped as a guard
      # RECORD (guard.nix, `__guard`). A CONTEXT CLOSURE (a function that is not a module fn) is
      # refused by name at any arity (`bareClosureRefusal`, below).
      isGuardRecordDef = d: builtins.isAttrs d.value && (d.value.__guard or false);
      # A carrier carried by value: an aspect's merged carrier, placed at another aspect position
      # (den-hoag-dmdou). It is already checked; it passes through, re-stamped, or splices its fragments.
      isCarrierValue = v: builtins.isAttrs v && (v.__guard or false) && v ? fragments;
      isClosureDef = d: builtins.isFunction d.value && !(isModuleFn d.value);
      # A FUNCTOR-FORM MODULE FUNCTION (an attrset with `__functor`, as `lib.setFunctionArgs` builds it,
      # whose formals are satisfiable by `cnf.moduleArgs`). The submodule reads an attrset def as CONFIG,
      # so a functor's `__functor`/`__functionArgs` land in the freeform slot and the class value stays
      # null. Told from den v1's `__functor` aspect form (a context closure, carried unlowered by
      # gen-rules) by `isModuleFn`, exactly as a lambda module function is told from a closure.
      # A malformed `__functionArgs` is not a formals declaration: `isModuleFn` is total on it (false), so
      # it is left to the freeform read as before.
      isFunctorModuleDef = d: builtins.isAttrs d.value && d.value ? __functor && isModuleFn d.value;
      functorModuleRefusal =
        loc:
        "gen-aspects: aspect `${prelude.concatStringsSep "." loc}`: a functor-form module function (an attrset with "
        + "`__functor`, as `setFunctionArgs` builds) reached an aspect position. A submodule reads an attrset "
        + "definition as config, never as a module, so its `__functor` key would be kept as an aspect attribute and "
        + "nothing would be delivered. Write it as a lambda: `{ config, ... }: { ... }`.";
      # Every definition at a guard-bearing multi-def key becomes a FRAGMENT — nothing rejected,
      # nothing shredded (spec §2 Arm B, table). `__guard = true` here is a literal Boolean, not
      # the unresolved gen-merge marker witness 1 produces, so `walk.nix`'s `isGuardLeaf` already
      # admits this carrier as a leaf with no edit of its own.
      toFragment =
        d:
        if isGuardRecordDef d then
          (
            let
              g = GT.checkGuard cnf "aspect `${
                prelude.concatStringsSep "." (d.loc or [ "<guard-carrier>" ])
              }`" d.value;
            in
            {
              kind = "record";
              guard = g;
              inherit (g) condition body __mint;
            }
          )
        else
          # Plain attrset or primitive def alongside a guard-shaped sibling: an UNCONDITIONAL
          # fragment, condition ≡ true, riding beside the guarded ones (F4(a)'s dissolution made
          # mechanism — the heterogeneous list has defined semantics, no refusal owed).
          {
            kind = "unconditional";
            body = d.value;
          };
      # A module function among guard-shaped siblings keeps today's `includes` coercion (F4(b): guard
      # functions join the carrier, module functions do not), and is applied once, in this evaluation,
      # as `coerced` applies it beside a plain second definition: each in its own element of the
      # carrier's `includes`, so its tables are that element's and the root reaches them (S1;
      # den-hoag-cgobz). A plain definition contributes its POSITIONS (`positionsOf`, den-hoag-3849t):
      # the `includes` list at each of its aspect positions, and a module function at a nested key in
      # the same coercion, one level down. A guard record contributes nothing here.
      carrierCoerced = entryCoerced carrierSub (
        d:
        d
        // {
          value =
            if builtins.isFunction d.value then
              { includes = [ d.value ]; }
            else if isGuardRecordDef d || !(builtins.isAttrs d.value) then
              { }
            else
              positionsOf d.value;
        }
      );
      # ROUTE (a) (den-hoag-3849t): of a plain definition beside a guard, only its `includes` lists are
      # typed, at every aspect position, and a module function at a nested key is coerced into one.
      # F4(a)'s content law (`types.anything`) merges attrsets per key and scalars by agreement, and
      # concatenates lists without entering their elements; so the typed contribution adds nothing a
      # definition did not write, apart from an empty `includes` at a nested position, and no typed
      # default can meet a fired value. Every other value stays its raw fragment (`remainderOf`).
      declaredKeys = sub.getSubOptions [ ];
      # an undeclared key of an aspect: a nested aspect position (the freeform slot)
      isNestedKey = k: k != "includes" && !(declaredKeys ? ${k});
      # a value the projection enters: a plain attrset, not a property, a guard record or a functor
      isPlainNode = v: builtins.isAttrs v && !(v ? _type) && !(v.__guard or false) && !(v ? __functor);
      # a functor-form module function: coerced as a lambda is, so the typed element refuses it by name
      # (`functorModuleRefusal`), as T4's does; any other functor is held raw
      isFunctorModule = v: builtins.isAttrs v && v ? __functor && isModuleFn v;
      isCoercible = v: builtins.isFunction v || isFunctorModule v;
      # a property wrapper is projected through and kept, so the typed child discharges it as T4 would
      isContentV =
        v:
        builtins.isAttrs v
        && builtins.elem (v._type or null) [
          "if"
          "override"
          "order"
        ];
      isMergeV = v: builtins.isAttrs v && (v._type or null) == "merge";
      # a nested value's positions: a module function is coerced, a property is projected through
      # keeping its wrapper, a plain node recurses, and anything else has none
      posVal =
        x:
        if isCoercible x then
          { includes = [ x ]; }
        else if isContentV x then
          (
            let
              c = posVal x.content;
            in
            if c == { } then { } else x // { content = c; }
          )
        else if isMergeV x then
          (
            let
              cs = builtins.filter (c: c != { }) (map posVal x.contents);
            in
            if cs == [ ] then { } else x // { contents = cs; }
          )
        else if isPlainNode x then
          positionsOf x
        else
          { };
      remVal =
        x:
        if isContentV x then
          x // { content = remVal x.content; }
        else if isMergeV x then
          x // { contents = map remVal x.contents; }
        else if isCoercible x then
          { }
        else if isPlainNode x then
          remainderOf x
        else
          x;
      # the `includes` lists of a plain value's aspect positions, and its nested module functions coerced
      positionsOf =
        v:
        prelude.optionalAttrs (v ? includes) { inherit (v) includes; }
        // prelude.filterAttrs (_: x: x != { }) (
          prelude.mapAttrs (_: posVal) (prelude.filterAttrs (k: _: isNestedKey k) v)
        );
      # the rest of it, held raw: every declared key and every value that is not a position
      remainderOf =
        v:
        prelude.mapAttrs (k: x: if isNestedKey k then remVal x else x) (
          prelude.filterAttrs (k: x: k != "includes" && !(isNestedKey k && isCoercible x)) v
        );
      # The position its module functions are applied at declares `includes` alone, typed as every
      # aspect's is, and imports no aspect module, so the coerced definitions are the list's only
      # contributors and each adds exactly one element, in definition order (den-hoag-cgobz C1). A
      # carrier is not an aspect submodule (F4(a): its fragments' bodies are held raw), so an aspect
      # module's content reaches no carrier, as before; each element is a full include element, so
      # the aspect modules apply inside it, as they do to T4's.
      carrierSub = merge.submodule {
        # a nested key is a position of the same shape, an `includes` list and nested keys, and nothing else
        freeformType = t.lazyAttrsOf carrierSub;
        options.includes = merge.mkOption {
          type = t.listOf (includesElemType cnf);
          default = includesDefault;
        };
      };
      # the child's value as data: `_module` dropped at every level
      positionsData =
        v:
        prelude.mapAttrs (k: x: if k == "includes" then x else positionsData x) (
          removeAttrs v [ "_module" ]
        );
      # The carrier's member. Its one position, adding no step, holds its module functions under
      # `carrierCoerced`, so gen-merge evaluates their elements in this evaluation (a nested tree is a
      # child of the one evaluation that holds it, selected by its fold's split).
      carrierType = merge.types.defineType {
        name = "aspectGuardCarrier";
        split = loc: defs: [
          {
            step = [ ];
            inherit loc defs;
            type = carrierCoerced;
          }
        ];
        mergeDefs = {
          __functor =
            _: loc: defs:
            mkGuardCarrier (m: m.mergeDefs loc) loc defs;
          threaded =
            ev: loc: defs:
            mkGuardCarrier (m: m.mergeDefs.threaded ev loc) loc defs;
        };
      };
      # Each definition becomes a fragment, in order. The typed positions of every module function and
      # plain definition form ONE unconditional `coerced` fragment, placed at the first definition that
      # is not a guard record, and only when there is a position; each plain definition also keeps its
      # remainder as an unconditional fragment, minted over the definition as written (`decl`). A carrier
      # carried by value splices its own fragments.
      mkGuardCarrier = fold: loc: defs: {
        __guard = true;
        fragments =
          let
            typed = {
              kind = "unconditional";
              coerced = true;
              # identity: a typed fragment of plain definitions alone repeats what their `decl`s mint, so
              # only one holding a module function's element is opaque
              ofFunctions = builtins.any (d: builtins.isFunction d.value) defs;
              body = positionsData (fold carrierCoerced defs);
            };
            isPlainDef = d: !(isGuardRecordDef d) && builtins.isAttrs d.value;
            hasTyped = builtins.any (
              d: builtins.isFunction d.value || (isPlainDef d && positionsOf d.value != { })
            ) defs;
          in
          (builtins.foldl'
            (
              acc: d:
              if isGuardRecordDef d then
                acc
                // {
                  fs = acc.fs ++ (if isCarrierValue d.value then d.value.fragments else [ (toFragment d) ]);
                }
              else
                {
                  placed = true;
                  fs =
                    acc.fs
                    ++ (if acc.placed || !hasTyped then [ ] else [ typed ])
                    ++ (
                      if builtins.isFunction d.value then
                        [ ]
                      else if isPlainDef d then
                        [
                          {
                            kind = "unconditional";
                            body = remainderOf d.value;
                            decl = d.value;
                          }
                        ]
                      else
                        [ (toFragment d) ]
                    );
                }
            )
            {
              placed = false;
              fs = [ ];
            }
            defs
          ).fs;
        name = prelude.last loc;
        meta = {
          inherit loc;
          file = (builtins.head defs).file or "<unknown>";
        };
      };
      # Design Section 3: a context closure handed to gen-aspects is refused by name, naming the gen-rules
      # door and the remedy (ADR-0025). gen-aspects holds terms only. The last sentences state when a
      # closure inside an aspect-position module function's result is lowered: only where the framework
      # mounts gen-rules' registration table in the aspect submodule (S1 arm (a), den-hoag-lwbb1). The
      # text names the mount by gen-aspects' own vocabulary, never by a gen-rules parameter.
      bareClosureRefusal =
        loc:
        "gen-aspects: aspect `${prelude.concatStringsSep "." loc}`: a context closure reached a gen-aspects-typed "
        + "position. gen-aspects holds first-order guards only; a closure crosses the gen-rules door. Declare the "
        + "aspect through the framework's surface, so that gen-rules' lowering turns the closure into a door node, "
        + "or write it as a guard term (`guard (pred.has <coordinate>) <body>`). If the closure sits in the result "
        + "of a module function written at an aspect position (`{ config, ... }: { includes = [ ({ host, ... }: …) ]; }`), "
        + "the lowering reaches it only where the framework mounts gen-rules' registration table inside the aspect "
        + "submodule (`cnf.aspectModules`); "
        + "without that mount the closure arrives here unlowered. A closure that reads none of the module function's "
        + "arguments can also be written beside the function instead of inside it.";
      # A refusal VALUE of a value-regime library (ADR-0025 item 1), forwarded unread to an aspect
      # position (den-hoag-3sk7j). Recognised by each live encoding's EXACT shape, never by a mark: a
      # refusal mints nothing (ADR-0034). `null`, or `{ kind; code; message; }`. Each test leads with
      # one `?` probe, so an aspect costs at most three. An encoding whose keys this aspect type DECLARES
      # is not recognised: a declared key is the author's, and the value is that author's aspect. The declared
      # set is read only once a shape matched, inline, so an aspect pays no binding for it (§2.3's bound).
      refusalOf =
        v:
        if !(builtins.isAttrs v) then
          null
        else if v ? left && builtins.attrNames v == [ "left" ] && !((sub.getSubOptions [ ]) ? left) then
          if builtins.isAttrs v.left && builtins.isString (v.left.code or null) then
            {
              kind = "an Either refusal (`{ left = { code; witness; }; }`, gen-algebra / gen-rules)";
              inherit (v.left) code;
              message = v.left.witness.message or null;
            }
          else if builtins.isList v.left && v.left != [ ] then
            {
              kind = "an Either refusal carrying a failure list (`{ left = [ failure … ]; }`, gen-types / gen-schema `runValidators`, gen-algebra `collectErrors`)";
              code = null;
              message =
                let
                  f = builtins.head v.left;
                in
                if builtins.isAttrs f then f.message or null else null;
            }
          else
            null
        else if
          v ? refused
          &&
            builtins.attrNames v == [
              "blamed"
              "code"
              "message"
              "refused"
              "witness"
            ]
          && v.refused == true
          && builtins.isString v.code
          && !(builtins.any (k: (sub.getSubOptions [ ]) ? ${k}) (builtins.attrNames v))
        then
          {
            kind = "a refusal record (`{ refused = true; code; … }`, gen-program)";
            inherit (v) code message;
          }
        else if
          v ? __crossingResult
          &&
            builtins.attrNames v == [
              "__crossingResult"
              "refusal"
            ]
          && v.__crossingResult == "refusal"
          && builtins.isAttrs v.refusal
          && !(builtins.any (k: (sub.getSubOptions [ ]) ? ${k}) (builtins.attrNames v))
        then
          {
            kind = "a crossing refusal (`__crossingResult = \"refusal\"`, gen-bind)";
            code = v.refusal.code or null;
            message = null;
          }
        else
          null;
      refusalRefusal =
        loc: r:
        "gen-aspects: aspect `${prelude.concatStringsSep "." loc}`: a refusal value reached an aspect position: "
        + r.kind
        + (if builtins.isString r.code then " with code `${r.code}`" else "")
        + ", not an aspect. A call that returns its refusals as values refused, and its result was placed "
        + "here unread; read the refusal where it was returned."
        + (
          if builtins.isString r.message && r.message != "" then
            " Its message: ${r.message}"
            + (if builtins.substring (builtins.stringLength r.message - 1) 1 r.message == "." then "" else ".")
          else
            ""
        )
        + " A context closure crosses the gen-rules door: declare the aspect through the framework's surface, "
        + "so that gen-rules' lowering turns the closure into a door node, or write it as a guard term.";
      dispatch =
        loc: defs:
        if builtins.any isFunctorModuleDef defs then
          { value = throw (functorModuleRefusal loc); }
        else if builtins.any isClosureDef defs then
          { value = throw (bareClosureRefusal loc); }
        else if builtins.any (d: refusalOf d.value != null) defs then
          {
            value = throw (
              refusalRefusal loc (
                refusalOf (builtins.head (builtins.filter (d: refusalOf d.value != null) defs)).value
              )
            );
          }
        else if builtins.length defs != 1 then
          if builtins.all (d: !(builtins.isAttrs d.value) && !(builtins.isFunction d.value)) defs then
            { value = orphanLeaf loc (merge.mergeDefaultOption loc defs); }
          else if builtins.any isGuardRecordDef defs then
            { member = carrierType; }
          else
            { member = coerced; }
        else
          let
            v = (builtins.head defs).value;
          in
          # Single-def guard record: dispatched here directly (never reaches the multi-def
          # branch above, whose `mkGuardCarrier` is what supports a guard record defined more
          # than once under one key; den-hoag-sezf Arm B).
          if isCarrierValue v then
            {
              value = v // {
                name = prelude.last loc;
                meta = (v.meta or { }) // {
                  inherit loc;
                  file = (builtins.head defs).file or "<unknown>";
                };
              };
            }
          else if builtins.isAttrs v && (v.__guard or false) then
            # Guard record (guard.nix) — guard PAYLOAD (pred/body) untouched; only tracing
            # name/meta attached (meta.loc gives an opaque-body guard a site-distinguished key;
            # not hashed by guardKey).
            {
              value = GT.checkGuard cnf "aspect `${prelude.concatStringsSep "." loc}`" v // {
                name = prelude.last loc;
                meta = (v.meta or { }) // {
                  inherit loc;
                  file = (builtins.head defs).file or "<unknown>";
                };
              };
            }
          else if isTypedAspect v then
            { value = v; }
          else if builtins.isFunction v then
            { member = sub; }
          else if builtins.isAttrs v then
            { member = sub; }
          else
            { value = orphanLeaf loc (prelude.last defs).value; };
      # A scalar or list at a `deep` freeform position (above) is neither class content (no class key
      # declared it) nor an aspect (it has no body), and nothing gave it a meaning: refused by name,
      # catchably (ADR-0025 item 1). `null` passes: it is this library's representation of absence.
      orphanLeaf =
        loc: v:
        if nesting == null || !nesting.deep || v == null then v else throw (orphanLeafRefusal loc v);
      orphanLeafRefusal =
        loc: v:
        let
          inherit (nesting) anchor;
          # The undeclared keys between the declared aspect and the leaf: each one nested an aspect.
          run = builtins.genList (i: builtins.elemAt loc (builtins.length anchor + i)) (
            builtins.length loc - builtins.length anchor - 1
          );
          # The declared class keys in full, rendered from `keySemantics` and never restated: no
          # edit-distance "did you mean" (`lib/cnf.nix` `cnfRefusal`, the same reasoning).
          classKeys = builtins.attrNames (
            prelude.filterAttrs (_: e: builtins.isAttrs e && (e.category or null) == "class") cnf.keySemantics
          );
          # The extension route is named only where this type reads extensions (`cnf.schemaDefs`).
          remedy =
            if cnf.schemaDefs != null then
              "Declare the key — a keySemantics class/channel/facet, or a schema extension "
              + "`schema.aspect.options.<key>` — or correct its spelling."
            else
              "Declare the key as a keySemantics class/channel/facet (this aspect type reads no schema "
              + "extension; `mkAspectModule` threads them), or correct its spelling.";
        in
        "gen-aspects: aspect `${merge.showOption anchor}`: orphan leaf at `${merge.showOption loc}` "
        + "(a value of type ${builtins.typeOf v} below the undeclared key path `${merge.showOption run}` "
        + "is neither class content nor an aspect). "
        + remedy
        + " Declared class keys: ${
           if classKeys == [ ] then "none" else builtins.concatStringsSep ", " classKeys
         }.";
    in
    mkUnion "aspect" cnf {
      inherit alternatives dispatch;
      # A freeform position's nesting is distinguishing content (it decides `orphanLeaf`), so it
      # enters the construction; a declared position states none, and its construction is the cnf's.
      minted = if nesting == null then { } else { inherit nesting; };
      recarry = c: aspectTypeOver cnf nesting c.alternatives;
      rebuild = c: aspectTypeAt c nesting;
      # The sub-option protocol is answered by the branch that declares options: every attrset and
      # module-function aspect merges through `aspectSubmodule`, so its option set IS this type's.
      # The guard branch declares none. Left on the protocol's `{ }` default this type would read as a
      # leaf.
      # A published channel for foreign tools only: gen introspects aspects by graph query
      # (`graphFacts`), never through this function (ADR-0012 clause 3).
      declares = prefix: sub.getSubOptions prefix;
    };

  # THE canonical content-address for an aspect of ANY kind — plain or guard (__guard). Routed through the ecosystem's ONE hashIdentity formula (`gen-identity/lib/default.nix`,
  # binding `hashIdentity`, injected above); origin is just another identity key (design §Identity).
  # `key` = identity.key (the dispatch in `identity.nix`), so a guard record — NOT
  # a submodule instance, carries no `id_hash` option — gets the SAME id as a plain aspect via the
  # SAME formula, over its declared path (identity design §1; its term's mint, `guardKey`, is not
  # the declaration's identity), and it is an IDENTITY, not a vertex name: gen-link NAMES a federation node by its
  # origin-qualified `aspects.key`, never this. Consumers (the `id_hash` default; den-hoag, which retired
  # `sha256 "den-aspect:${key}"`) call THIS, never re-derive the preimage. `origin` is the source label as
  # a path list, entering the preimage as the list; default [] is the local partition.
  # A DECLARATION mints over its declared path as a LIST, never its rendering (identity design §1:
  # "no preimage is a rendered string"), so `[ "f/x" ]` and `[ "f" "x" ]` mint apart by construction.
  # A record with no declared path keeps the key-labelled shape, a disjoint key space.
  aspectId = origin: aspect: builtins.seq (aspect.key or null) (mintAspectId origin aspect);
  mintAspectId =
    origin: aspect:
    if identity.isDeclared aspect then
      hashIdentity "aspect" [ "origin" "path" ] (
        k:
        {
          inherit origin;
          path = identity.checkedPath aspect;
        }
        .${k}
      )
    else
      hashIdentity "aspect" [ "origin" "key" ] (
        k:
        {
          inherit origin;
          key = identity.rawKey aspect;
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
  # A union (above) over the two aspect types it can pick: this cnf's on the recursive-closed arm, and
  # the ungated one on a listed freeform key. The pick reads `loc`, so the same definitions give
  # different members by key.
  # Always a freeform position, so it carries its members' `nesting` (`aspectType`, above).
  gatedFreeformElem =
    cnf: nesting:
    gatedFreeformElemOver cnf nesting [
      (aspectTypeAt cnf nesting)
      (aspectTypeAt (extendCnf cnf { closedKeys = false; }) nesting)
    ];
  gatedFreeformElemOver =
    cnf: nesting: alternatives:
    mkUnion "gatedFreeformKey" cnf {
      inherit alternatives;
      minted = { inherit nesting; };
      recarry = c: gatedFreeformElemOver cnf nesting c.alternatives;
      rebuild = c: gatedFreeformElem c nesting;
      dispatch =
        loc: defs:
        let
          k = prelude.last loc;
          at = "aspect `${prelude.concatStringsSep "." (prelude.init loc)}`";
          # den feeds ONE pre-merged config def per freeform child, so `head defs` is THE value; the all-defs
          # form generalises for a native multi-def author (recurse iff SOME def is an attrset namespace; an
          # all-primitive undeclared multi-def key is not a namespace → throw). Decides on WHNF
          # (`isAttrs d.value`) — no deep forcing, strictly less than a spine-walk.
          anyAttrs = builtins.any (d: builtins.isAttrs d.value) defs;
        in
        if cnf.recursiveClosed then
          if anyAttrs then
            # a namespace node — recurse as a nested aspect, gate RETAINED (recursive-closed).
            { member = builtins.elemAt alternatives 0; }
          else
            {
              value = throw (
                "gen-aspects: ${at}: undeclared aspect key '${k}' (value is not a nested aspect — a closed "
                + "aspect vocabulary admits an undeclared key only as a namespace attrset that recurses to a "
                + "declared class/channel/facet; a primitive/function/list value here is a typo or misplaced "
                + "content). Declare it in keySemantics, or nest it under a declared key."
              );
            }
        else if builtins.elem k cnf.freeformKeys then
          { member = builtins.elemAt alternatives 1; }
        else
          {
            value = throw "gen-aspects: ${at}: undeclared aspect key '${k}' (closed-key gate on; declare it in keySemantics or list it in freeformKeys)";
          };
    };

  # The closed keySemantics category vocabulary (ADR-0027 ruling 2). ONE binding so aspectSubmodule's
  # per-key refusal and the standalone `keyCategory` read below can never drift apart.
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
  # because that read path never went through aspectSubmodule's check at all).
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
  # A union (above) over its two nesting-capable members: the element reading a bare module AS a
  # module, and `aspectOrFn`. A keyRef passes through as itself.
  includesElemType =
    cnf:
    includesElemTypeOver cnf [
      # Default OFF: the bare module is absorbed AS A MODULE. The aspect submodule reads an
      # attrset def as config (gen-merge `types.submodule`, as nixpkgs), which would make
      # `imports` a freeform key and drop the imported content, so the def is handed over as a
      # function module, which the submodule reads as a module.
      (entryCoerced (aspectSubmodule cnf) (d: d // { value = _: d.value; }))
      (aspectOrFn cnf)
      (entryCoerced (aspectSubmodule cnf) stampIncludeSite)
    ];
  includesElemTypeOver =
    cnf: alternatives:
    mkUnion "includesElem" cnf {
      inherit alternatives;
      recarry = c: includesElemTypeOver cnf c.alternatives;
      rebuild = includesElemType;
      dispatch =
        loc: defs:
        let
          v = (builtins.head defs).value;
          # a bare MODULE at the include position — an attrset with a non-empty top-level `imports` list (the
          # deferredModule merge slot, UNIQUELY the class-content collapse artifact; `imports` is never a valid
          # aspect content key). This is a class-named node mis-included AS an aspect. Structural, not a heuristic.
          isBareModuleInclude =
            builtins.isAttrs v && (v ? imports) && builtins.isList v.imports && v.imports != [ ];
        in
        if builtins.length defs == 1 && builtins.isAttrs v && (v.__keyRef or false) then
          { value = v; }
        else if cnf.rejectBareModuleInclude && builtins.length defs == 1 && isBareModuleInclude then
          {
            value = throw (
              "gen-aspects: includes element is a bare module ({ imports = [ … ]; }) with no aspect identity — "
              + "a class-content node included AS an aspect? An include must be an aspect (by value or fixpoint "
              + "ref), a keyRef, or a deferred fn/policy; `imports` is the module merge slot, never an aspect "
              + "content key."
            );
          }
        else if builtins.length defs == 1 && isBareModuleInclude then
          { member = builtins.elemAt alternatives 0; }
        else if
          builtins.length defs == 1
          && builtins.isAttrs v
          && v ? name
          && !(v.__guard or false)
          && !(v ? _type)
          && !(isTypedAspect v)
        then
          { member = builtins.elemAt alternatives 2; }
        else
          { member = builtins.elemAt alternatives 1; };
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
  # neither native-structural nor a declared keySemantics key (a typo, a freeform nested-aspect child, or an
  # option declared by a schema extension or `aspectModules`; the closed gate distinguishes the first
  # two). A key that IS declared but malformed (not an attrset, or an
  # attrset with an unrecognised category) refuses BY NAME via checkCategory — this is the read site
  # den-hoag-7cya measured as a silent pass-through (it never went through aspectSubmodule's own
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

  # hasClassContent v : does this class VALUE carry a definition. The has-content fact `classOptions`
  # below makes representable, NAMED here so a consumer composes with it instead of re-deriving it
  # privately — ADR-0012 clause 2: every derived view has a name and a defining query at its source,
  # or it is not a view. The companion of `keyCategory`, and deliberately the same thin shape: a key
  # is a class WITH content when `keyCategory cnf k == "class" && hasClassContent entry.${k}`, two
  # composable primitives rather than one composite that also takes the cnf and the entry.
  #
  # BOTH CLAUSES ARE LOAD-BEARING, and the second is not incidental to the first.
  #   `v != null` is this library's own representation of absence (`classOptions`, below).
  #   The attrset arm is the FABRICATED EMPTY deferredModule — a module carrying nothing, the state
  #   ADR-0028's Rider hazard turns on. This library never PRODUCES it (that is the whole point of
  #   the `null` default), but the predicate is exported, so it answers for values it did not build:
  #   a registry handed in directly, or another representation of emptiness arriving from a
  #   framework. A consumer that realizes on the mere DECLARATION is the defect, whichever way the
  #   emptiness was spelled, so the exported predicate excludes both spellings rather than only the
  #   one this library happens to emit. The test is on the WHOLE key set, not on `imports` alone, so
  #   a module carrying a definition beside an empty `imports` still counts as content.
  #
  # DOMAIN: class VALUES only. An undeclared key never reaches here — it falls through to the
  # freeform fallback and becomes a nested aspect (it has a `name`), a different node kind entirely.
  #
  # WHAT IT DOES NOT ANSWER: whether the merged module carries non-vacuous FIELDS. A class declared
  # with an empty def (`aspects.x.classKey = { }`) reads `true`, identically to real content, because
  # the deferredModule merge wraps any non-null def into a one-entry `imports` list regardless of
  # that def's own contents. Telling those two apart would mean forcing the deferred body, which is
  # exactly the invariant `test-inspection-does-not-force-class-body` holds. The question this
  # predicate answers is "was this class key given a defining module", and that is the question a
  # delivery projection needs.
  #
  # LAZINESS: forces the value's own outermost tag, its top-level key set, and (on the fabricated
  # shape alone) one list's spine. Never the deferred body.
  hasClassContent =
    v: v != null && !(builtins.isAttrs v && builtins.attrNames v == [ "imports" ] && v.imports == [ ]);

  # The `includes` option's declared default, ONE binding: `graphFacts` reads it for a member of a
  # directly-supplied registry, which bypasses this type and so lacks the key the type always supplies.
  includesDefault = [ ];

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
  # `nesting` is the aspect's own position (`aspectType`, above): its freeform slot's elements are
  # anchored at this aspect's loc when it is declared, and inherit its anchor, `deep`, when it is not.
  aspectSubmodule = cnf: aspectSubmoduleAt cnf null;
  aspectSubmoduleAt =
    cnf: nesting:
    let
      ks = cnf.keySemantics;
      # categoryOf e : "class" | "channel" | "facet" | null — the TOTAL classifier the option
      # construction partitions on; null = malformed. Validation is LAZY and PER KEY (den-hoag-2ejx):
      # a malformed entry must refuse where its key is read, never while reading an unrelated
      # aspect's `name` — a deepSeq of checkCategory over every entry made one bad declaration poison
      # every read of every aspect. It also must not silently never-match a keyOf filter, so a
      # malformed key is not dropped: it gets `refusedOptions` below.
      categoryOf =
        e:
        if builtins.isAttrs e && e ? category && builtins.elem e.category validCategories then
          e.category
        else
          null;
      keyOf = category: builtins.attrNames (prelude.filterAttrs (_: e: categoryOf e == category) ks);
      # A malformed key stays DECLARED (so it neither falls through to the freeform fallback nor
      # trips the closed-key gate) and its value is checkCategory's named refusal: reading or
      # forcing that key on any aspect throws it, catchably, and nothing else does.
      refusedOptions = prelude.genAttrs (keyOf null) (
        k:
        merge.mkOption {
          description = "Malformed keySemantics key `${k}` (refuses by name when read)";
          default = null;
          type = t.raw;
          apply = _: checkCategory k ks.${k};
        }
      );
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
        prelude.filterAttrs (_: e: categoryOf e == "facet" && e ? option) ks
      );
      facetModules = prelude.mapAttrsToList (_: e: e.module) (
        prelude.filterAttrs (_: e: categoryOf e == "facet" && e ? module) ks
      );
    in
    merge.submodule (
      {
        name,
        config,
        prefix ? [ ],
        ...
      }:
      let
        # The type's identity values, computed once: the option's default and its write check share them.
        # A tree position's declared path is `prefix`; a `meta.loc` that says otherwise (an mkForce'd
        # write) is refused here, where key and id read it.
        treeLoc =
          if prefix != [ ] && !(builtins.elem "includes" (builtins.tail prefix)) then prefix else null;
        locChecked =
          treeLoc == null
          || (config.meta.loc or null) == treeLoc
          || throw "gen-aspects: the option `${
            merge.showOption (
              prefix
              ++ [
                "meta"
                "loc"
              ]
            )
          }' is written by the aspect type; remove the definition.";
        stampedKey = builtins.seq locChecked (identity.rawKey config);
        stampedId = builtins.seq locChecked (mintAspectId cnf.providerPrefix config);
      in
      {
        freeformType =
          let
            below =
              if nesting == null then
                {
                  anchor = prefix;
                  deep = false;
                }
              else
                {
                  inherit (nesting) anchor;
                  deep = true;
                };
          in
          t.lazyAttrsOf (if cnf.closedKeys then gatedFreeformElem cnf below else aspectTypeAt cnf below);
        config._module.args.aspect = config;
        # __defsModule seam: facet modules first, then aspectModules (which gen-schema's
        # mkAspectModule appends config.schema.aspect.__defsModule into). Dropping the tail breaks
        # schema-declared instance-option propagation.
        imports =
          facetModules
          ++ cnf.aspectModules
          ++ prelude.optional (cnf.schemaDefs != null) cnf.schemaDefs.module;

        # A-IDENT (intrinsic path identity): the aspect's option path — the eval `prefix`
        # gen-merge threads into every module body (= the merge `loc`) — IS the identity. The
        # top container (`aspectsRoot`) re-roots the mount away, so `prefix` here is
        # CONTAINER-RELATIVE (2b, owner ruling): `[ apps media spicetify ]`, no mount segment.
        # Stamped here as `meta.loc`, the DECLARED PATH and the one identity input (identity
        # design §1): `identity.key` reads `pathKey meta.loc`, never `name` or `meta.aspect-chain`,
        # so the key is path-bearing AT MERGE, born in the type and never reconstructed downstream.
        # Distinct paths ⇒ distinct keys (fixes the name-only collapse: hardware.cpu.intel ≠
        # hardware.gpu.intel). The relative path UNIFIES with the guard branch (also loc-keyed and
        # re-rooted, `aspectType`'s `__guard` branch), is origin-invariant (§3a: the container root
        # is the proto-namespace root; an origin qualifier prepends additively), and byte-matches
        # den-hoag's root-relative `__provider`. `name` (`last prefix` by default) and
        # `meta.aspect-chain` (`init prefix`) are its RENDERINGS: a caller may set `name`, which moves
        # no identity, and a chain that contradicts the declared path refuses by name at `key`
        # (identity design Q4). The type is the one writer of `meta.loc`, `key` and `id_hash` (see
        # `isTypedAspect`): a typed value carried by value (an include, an alias at a tree position)
        # is passed through as a reference and never re-merged against these definitions.
        #
        # No `meta.loc` at the container root (`prefix == [ ]`), which declares nothing, nor on an
        # element written in an `includes` list: its prefix is its MERGE position
        # (`[definition N-entry M]`), which moves with module order, while identity is the DECLARING
        # position and reordering includes changes nothing (ADR-0034's den-module rider). Such an
        # element keeps its field-keyed identity, the same `includes`-past-the-first test
        # `facts.nix`' `isIncludeContent` reads.
        config.meta = {
          aspect-chain = merge.mkDefault (if prefix == [ ] then [ ] else prelude.init prefix);
        }
        // prelude.optionalAttrs (treeLoc != null) { loc = treeLoc; };

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
            default = stampedKey;
            apply =
              v:
              if v == stampedKey then
                v
              else
                throw "gen-aspects: the option `${
                  merge.showOption (prefix ++ [ "key" ])
                }' is written by the aspect type; remove the definition.";
          };

          # Convenience content-address on plain submodules, mirroring gen-schema's `id_hash` — computed
          # via the SAME exported `aspectId` (no second formula). Wrapped-fn / guard aspects are bare
          # records (no submodule, no option); consumers id them uniformly via `aspects.aspectId`.
          id_hash = merge.mkOption {
            internal = true;
            readOnly = true;
            type = t.str;
            default = stampedId;
            apply =
              v:
              if v == stampedId then
                v
              else
                throw "gen-aspects: the option `${
                  merge.showOption (prefix ++ [ "id_hash" ])
                }' is written by the aspect type; remove the definition.";
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
            default = includesDefault;
          };
        }
        // classOptions
        // channelOptions
        // facetOptions
        // refusedOptions;
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
  # The protocol's own defaults for those three (`{ }` / null / `_m: null`) are a LEAF's answers: on a
  # wrapper they report "declares nothing" indistinguishably from "protocol unimplemented here", which
  # is the ambiguity a supplied field cannot fall into.
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
  # element that is `null` / a rebuild over `null`. That is not because a dispatcher cannot name a
  # module set: nixpkgs' `attrTag` dispatches and names one, rebuilding itself. `aspectType` is Palmer's
  # flat dispatching type, whose `aspectSubmodule` branch carries a module set while its guard and
  # wrapped-fn branches do not, and `null` is ITS answer for what a non-null one would set off: gen-merge
  # derives `carries.moduleSet` from `getSubModules` alone, so the element would cross the carries
  # boundary; gen-merge's identity walk stops at an element carrying no element and no module set, and
  # would otherwise descend into aspects and read them as `id_hash` instances; and nixpkgs'
  # `fixupOptionType` would `substSubModules` the type, which delegated to the branch swaps the
  # dispatcher for a bare submodule and drops the guard and wrapped-fn branches. (Its `getSubOptions`
  # does answer, with that branch's options: that field sets off none of the three.) nixpkgs
  # calls `substSubModules` only where `getSubModules != null` (`fixupOptionType`, lib/modules.nix), so
  # the rebuild is live exactly when the element really does carry modules.
  #
  # Both propagations are guarded the way `attrsOfWith`/`listOf` guard theirs: an element that carries
  # no protocol AT ALL — a gen-types PARAMETRIC leaf (`enum`/`struct`/`union`) reaches the unified
  # namespace as a bare constructor and is never protocol-completed — must answer "nothing to
  # substitute" rather than abort on a missing attribute. `or null` covers the read; the `?` test
  # covers the rebuild, which falls back to the element unchanged.
  # Merges two ELEMENT types for `aspectsRootWith`'s own functor below. `mergeElemTypes` IS that
  # functor's `binOp`, and it is gen-merge's own `mergeTypes` (ADR-0008: one engine), never the
  # element's own foreign `typeMerge`. The difference is the check-family witness: asked directly, a
  # foreign `port`'s `typeMerge` joins `port ∥ int` to bare `int` and nothing sees the dropped check,
  # so `aspectsRoot(port) ∥ aspectsRoot(int)` accepted 70000 (den-hoag-plm1h). Through `mergeTypes`
  # the join is judged and that drop is refused by name (ADR-0025 item 1). gen-schema's `refined`
  # joins its base the same way.
  #
  # ★ IT IS TOTAL ON WHAT IT IS CALLED WITH, and that is a property of the caller, not a guard here:
  # `protoTypeMerge` (gen-merge `lib/interface.nix`) reaches `binOp` only once it has established
  # both operands carry a non-null payload, so a null second operand is a state this function is
  # never handed.
  mergeElemTypes = merge.mergeTypes;

  aspectsRootWith =
    elemType:
    let
      # The container's element positions, stated ONCE (gen-merge's `split`): one per key, each
      # re-rooted at `[ k ]` — drop the container `loc` (the mount) so children are relative — with
      # the position extended by that key.
      split =
        _loc: defs:
        map (k: {
          step = [ k ];
          loc = [ k ];
          defs = builtins.concatMap (
            d:
            prelude.optional (d.value ? ${k}) {
              inherit (d) file;
              value = d.value.${k};
            }
          ) defs;
          type = elemType;
        }) (builtins.attrNames (prelude.foldl' (acc: d: acc // d.value) { } defs));
      foldWith =
        foldElement: loc: defs:
        builtins.listToAttrs (
          map (e: {
            name = builtins.head e.step;
            value = foldElement e;
          }) (split loc defs)
        );
      functor = {
        name = "aspectsRoot";
        payload = elemType;
        binOp = mergeElemTypes;
        type = aspectsRootWith;
      };
      # The protocol's reading of that functor against a partner's (gen-merge `protoTypeMerge`, over
      # this one functor): two roots merge when their elements do, rebuilt over the merged element.
      typeMerge =
        f:
        let
          merged =
            if !(builtins.isAttrs f) || (f.name or null) != "aspectsRoot" || (f.payload or null) == null then
              null
            else
              mergeElemTypes elemType f.payload;
        in
        if merged == null then null else aspectsRootWith merged;
    in
    merge.types.defineType {
      name = "aspectsRoot";
      inherit elemType split;
      carries.element = elemType;
      recarry = c: aspectsRootWith c.element;
      # THE FIX (den-hoag-a0gc): a descriptor that states NO relation of its own gets the protocol's
      # nullary one, which merges ANY two same-named operands unconditionally — two `aspectsRoot`
      # declarations typeMerged on the CONTAINER'S NAME ALONE, blind to their elements, the
      # silent-collision shape den-hoag-k1uv named one layer down. Stating `functor` here is the
      # elemTypeFunctor pattern: `payload` carries the element type, `binOp` decides whether two
      # elements merge (via `mergeElemTypes`, recursively), and `type` rebuilds this same container
      # over the merged element on success.
      #
      # ★★ WHY STATING IT IS ENOUGH: gen-merge's export publishes a relation its author STATED
      # (`retainedRelation`, the owner's 2026-09-08 fork-1 ruling) rather than deriving one from
      # `carries`, so what is stated here is what a foreign engine reads back, and gen's own relation
      # is the same functor read against the partner's (`statedRelation`). ⇒ THAT RULING IS WHAT
      # A FUTURE PIN BUMP MUST BE CHECKED AGAINST. The revision itself belongs to the lock, which is
      # the coordinate; a rev written into this comment is a figure that decays the moment the relock
      # runs.
      inherit (statedRelation "aspectsRoot" functor typeMerge) typeMergeRel retainedRelation;
      substructure = {
        declares = prefix: elemType.getSubOptions (prefix ++ [ "<name>" ]);
        modules = elemType.getSubModules or null;
        rebuild =
          m: aspectsRootWith (if elemType ? substSubModules then elemType.substSubModules m else elemType);
      };
      # Each element folds through the engine's fold, called or threaded. The threaded one is the
      # engine's threaded twin composed from its published halves: the called spine (`mergeDefs`)
      # over the element whose fold is its threaded form, with the position extended by the key.
      mergeDefs = {
        __functor = _: foldWith (e: merge.mergeDefs e.loc e.type e.defs);
        threaded =
          ev:
          foldWith (
            e:
            merge.mergeDefs e.loc (
              if builtins.isAttrs e.type && e.type ? mergeDefs.threaded then
                e.type // { mergeDefs = e.type.mergeDefs.threaded (ev // { position = ev.position ++ e.step; }); }
              else
                e.type
            ) e.defs
          );
      };
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
  keyCategory = checkedEntry keyCategory;
  # Not entry points, and the reason is structural rather than per-name: `canTake` carries no
  # configuration at all, `aspectId` takes an origin path, `hasClassContent`'s is a class value, and
  # `structuralKeys` is a value. `wrapFn` and `wrapGatedFn` are retired aliases that refuse at once.
  inherit
    canTake
    wrapFn
    wrapGatedFn
    aspectId
    hasClassContent
    includesDefault
    GT
    ;
  structuralKeys = nativeStructuralKeys;
}
