# The nixpkgs sub-protocol on `aspectsRoot` — the three answers a type owes about WHAT IT WRAPS,
# as opposed to about its values: what it declares (`getSubOptions`), the module set it carries
# (`getSubModules`), and how it rebuilds itself over a replacement one (`substSubModules`).
#
# `aspectsRoot` carries an element type, so it owes all three. Left on gen-merge `completeType`'s
# defaults (`_prefix: { }` / `null` / `_m: null`) it would report a LEAF's answers — "declares
# nothing" indistinguishable from "protocol unimplemented here" — and a consumer reflecting a
# declared surface off the type fails closed and silently.
#
# ★ THE ORACLE IS SHAPE-AND-LENGTH, NEVER `isNull`. `isNull` cannot separate `LIST[0]` from
# `LIST[1]`, nor a rebuilt type from a stub's `null`; reading that predicate on this very surface is
# what produced two withdrawn measurements upstream. Every row below reports a shape, and every
# absence claim is armed with a live positive control on the SAME predicate in the SAME run.
{
  aspects,
  genMerge,
  ...
}:
let
  t = genMerge.types;
  cnf = {
    keySemantics = { };
  };
  root = aspects.aspectsRoot cnf;
  elem = aspects.aspectType cnf;

  probeMod = {
    options.y = genMerge.mkOption { type = t.str; };
  };
  # POSITIVE CONTROL for the module-set predicates: a type that really does carry a module set.
  sub = t.submodule probeMod;
  # POSITIVE CONTROL for the getSubOptions read path: a type that really does declare a sub-option.
  # It carries neither an element type nor a module set, so it is outside the construction rule's
  # domain and is completed, not refused.
  #
  # ★ WHY THIS AND NOT `sub`. The obvious control is `sub.getSubOptions [ ]`, and it is ARM-VARIANT:
  # it reads ATTRS{0} against the gen-merge this repo's ci lock pins (`2701d8b`) and ATTRS{1} against
  # any gen-merge from `8daa25d` on, which is where `getSubOptions` for submodule/attrsOf/listOf
  # landed — AFTER the lock. Pinning that row would red whichever arm it was not measured on, so it
  # is deliberately left unpinned. `declaring` replaces it because it is both constructible under the
  # construction rule and arm-stable: it supplies its own `getSubOptions`, so it reads ATTRS{1} on
  # both arms and does not depend on which gen-merge answers. Recorded here rather than dropped — an
  # exclusion that leaves no trace gets re-proposed, and re-proposing this one breaks an arm.
  declaring = genMerge.mkOptionType {
    name = "declaring";
    getSubOptions = _prefix: {
      z = { };
    };
    merge = _loc: defs: (builtins.head defs).value;
  };

  shape =
    v:
    if v == null then
      "NULL"
    else if builtins.isList v then
      "LIST[${toString (builtins.length v)}]"
    else if builtins.isFunction v then
      "FN"
    else if builtins.isAttrs v then
      (
        if v._type or null == "option-type" then
          "TYPE<${v.name}>"
        else
          "ATTRS{${toString (builtins.length (builtins.attrNames v))}}"
      )
    else
      builtins.typeOf v;
in
{
  # `getSubModules` is the element's own answer, propagated. With `aspectType` as the element that
  # answer is NULL — and NULL is CORRECT here, not a stub: `aspectType` is Palmer's flat dispatching
  # type (one type, dispatch in merge), so it carries no module set to report. The two controls make
  # the NULL a measurement rather than a blind spot: the same predicate reads `LIST[1]` off a type
  # that does carry a module set, and `NULL` off a leaf.
  flake.tests.sub-protocol.test-getsubmodules-propagates-the-element = {
    expr = {
      root = shape root.getSubModules;
      element = shape elem.getSubModules;
      ctlCarriesModuleSet = shape sub.getSubModules;
      ctlLeaf = shape t.str.getSubModules;
    };
    expected = {
      root = "NULL";
      element = "NULL";
      ctlCarriesModuleSet = "LIST[1]";
      ctlLeaf = "NULL";
    };
  };

  # `substSubModules` rebuilds THIS container over the substituted element. The rebuild is what the
  # stub cannot fake: `completeType`'s default answers `null`, so `TYPE<aspectsRoot>` is reachable
  # only from a supplied field. The element it rebuilds over is the element's OWN answer — NULL for
  # `aspectType`, which is why `rootElement` is NULL rather than a type: nixpkgs calls
  # `substSubModules` only where `getSubModules != null` (`fixupOptionType`), so that rebuild is live
  # exactly when the element really does carry modules. Controls: a module-set carrier rebuilds to
  # `TYPE<submodule>`, a leaf still answers NULL.
  flake.tests.sub-protocol.test-substsubmodules-rebuilds-the-container = {
    expr = {
      root = shape (root.substSubModules [ ]);
      # `or null` keeps the row TOTAL: a stubbed `substSubModules` answers `null`, and selecting
      # through it would abort the whole cell instead of reporting a shape. The discrimination lives
      # in `root` above; this row reports what the rebuild rebuilt over.
      rootElement = shape ((root.substSubModules [ ]).elemType or null);
      element = shape (elem.substSubModules [ ]);
      ctlCarriesModuleSet = shape (sub.substSubModules [ probeMod ]);
      ctlLeaf = shape (t.str.substSubModules [ ]);
    };
    expected = {
      root = "TYPE<aspectsRoot>";
      rootElement = "NULL";
      element = "NULL";
      ctlCarriesModuleSet = "TYPE<submodule>";
      ctlLeaf = "NULL";
    };
  };

  # `getSubOptions` descends to the element under the per-key placeholder segment, threading the
  # caller's prefix (`prefix ++ [ "<name>" ]`) — the ADDRESS a consumer writes the value at, which is
  # still under the mount. The container-relative re-rooting `merge` performs governs the merged
  # aspect's IDENTITY (`key`, `meta.aspect-chain`) and is not what an introspection answer reports.
  #
  # ★ HONEST SCOPE: over `aspectType` this is not value-discriminating. `aspectType` declares no
  # static options, so `root` and the element agree at ATTRS{0} whether the field is supplied or left
  # on the stub — the pin here is that the answer IS the element's, at the threaded prefix. The
  # control proves only that the read path can see a declared surface (ATTRS{1}), not the descent.
  # What makes the supplied field non-vacuous is the construction rule, which refuses the type
  # outright when it is absent; that refusal is exercised by this suite evaluating at all.
  flake.tests.sub-protocol.test-getsuboptions-is-the-elements-answer = {
    expr = {
      root = shape (
        root.getSubOptions [
          "den"
          "aspects"
        ]
      );
      elementAtThreadedPrefix = shape (
        elem.getSubOptions [
          "den"
          "aspects"
          "<name>"
        ]
      );
      ctlDeclares = shape (declaring.getSubOptions [ ]);
      ctlLeaf = shape (t.str.getSubOptions [ ]);
    };
    expected = {
      root = "ATTRS{0}";
      elementAtThreadedPrefix = "ATTRS{0}";
      ctlDeclares = "ATTRS{1}";
      ctlLeaf = "ATTRS{0}";
    };
  };

  # Each answer is STORED, not absent — a NULL that is stored is a supplied answer ("no module set
  # here"), where a missing field is the protocol left unimplemented.
  #
  # ★ WHAT THIS CELL CANNOT SEPARATE, MEASURED BOTH ARMS WITH THE FIX ARCHIVED OUT. On the current
  # lock (pre-W4a gen-merge) it stays GREEN without the fix: `completeType` stamps all three fields
  # onto every type it completes, so the stubbed `aspectsRoot` answers "stored" too. On the W4a arm it
  # never evaluates — construction refuses `aspectsRoot` by name first and all four cells in this file
  # abort together. Neither arm discriminates the fix, so what this cell documents is STORAGE: that
  # the NULLs above are supplied answers rather than gaps, which the shape rows alone cannot say. The
  # discrimination lives in cells 1-3 — `substSubModules` reads TYPE<aspectsRoot> where a stub reads
  # NULL — and in the archived-fix control run that reds exactly that row.
  flake.tests.sub-protocol.test-answers-are-stored-not-absent = {
    expr = {
      getSubOptions = root ? getSubOptions;
      getSubModules = root ? getSubModules;
      substSubModules = root ? substSubModules;
    };
    expected = {
      getSubOptions = true;
      getSubModules = true;
      substSubModules = true;
    };
  };
}
