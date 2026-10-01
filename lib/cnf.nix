# The `cnf` vocabulary — ONE binding naming every recognised key with its default, and ONE
# constructor that is the sole producer of a `cnf` the library's internals accept.
#
# WHY A CONSTRUCTED TOTAL RECORD RATHER THAN AN ATTRSET READ WITH `or` DEFAULTS. Under `or` defaults
# nothing ever looks at the key SET, so a key the library does not recognise is not reinterpreted —
# it is INERT: `mkAspectSchema { someKey = …; }` computes exactly `mkAspectSchema { }`. Whatever that
# key meant to declare is then undeclared, so its content meets the aspect submodule's freeform
# fallback and becomes a nested aspect tree instead. Refusing off-domain keys where the record is
# BUILT makes that reinterpretation inexpressible: nothing downstream has a bad intermediate to
# filter, normalise or guard, because none forms.
#
# NAME → DEFAULT, never a bare name list: a key set and its defaults held apart are two copies that
# drift. Because the constructed record is total, every read is `cnf.<key>` with no fallback, so a
# read of a key absent from `cnfDefaults` is an eval abort — adding a read forces adding a
# declaration, in the same commit. That guarantee is LAZY, not static: an unexercised read path can
# ship with an undeclared key and abort only for the consumer who reaches it. The reverse direction —
# a key declared here that nothing reads, which would be inert in exactly the way the defect was — is
# pinned in CI against the read set derived from `lib/` itself, since Nix offers no static reflection
# over reads.
#
# THE CHECK IS SHALLOW AND MUST STAY SHALLOW: `attrNames` plus a membership filter, no value forced,
# nothing deep-seq'd. It inspects names, never contents, so it cannot make one bad value throw while
# reading an unrelated aspect's `name` — the defect keySemantics category validation had while it was
# eager (den-hoag-2ejx; it now refuses per key, lib/types.nix `refusedOptions`). It runs once per public entry call, not once per aspect node: the internals
# receive an already-constructed record and are never re-checked.
let
  genAttrs =
    names: f:
    builtins.listToAttrs (
      map (n: {
        name = n;
        value = f n;
      }) names
    );
  # Module functions take known module args — evaluated by the submodule. Guard functions take
  # context args (whatever the caller's context carries) — wrapped for later. The default set is the standard NixOS args
  # plus `aspect`, which gen-aspects provides.
  defaultModuleArgs = {
    lib = true;
    config = true;
    options = true;
    pkgs = true;
    modulesPath = true;
    aspect = true;
  };

  # Each key's DEFAULT and its identity REGIME, in one binding (ADR-0034: the regime is decided at
  # the declaration, never by inspecting a value). `minted` content is inert by construction and
  # enters the one mint; `compared` content is caller-supplied collections or option declarations,
  # sealed until its vocabulary migrates, and is decided by the reified value under Nix `==`.
  # `keySemantics` is split per entry: its `category` is inert, the rest of an entry (a facet's
  # `option`/`module`) is not. A `merged` key is a module list, and like the `modules` of a nixpkgs
  # submodule (`types.submoduleWith`'s `binOp`) it is payload, never identity: two declarations
  # concatenate theirs, a monoid with identity `[ ]`: the lists are joined unread, never compared,
  # so one read from `config` is not forced while declarations fold (ADR-0033). An `excluded`
  # key is read by no type (`guardForms` reaches only `mkGuardVocab`), so it distinguishes nothing.
  cnfVocabulary = {
    aspectModules = {
      default = [ ];
      regime = "merged";
    };
    closedKeys = {
      default = false;
      regime = "minted";
    };
    collections = {
      default = { };
      regime = "compared";
    };
    deferIncludeResolution = {
      default = false;
      regime = "minted";
    };
    # The framework's entity kinds, as the context keys that carry them (ADR-0027: entity kinds are
    # the framework's to declare). At an instance-producing applicator, a context shape is handed the
    # context narrowed to them; `null` hands it whole (lib/require-wrapped-closure.nix
    # `requireContextOf`). A guard predicate's evaluation is never narrowed.
    entityKinds = {
      default = null;
      regime = "minted";
    };
    freeformKeys = {
      default = [ ];
      regime = "minted";
    };
    guardForms = {
      default = { };
      regime = "excluded";
    };
    keySemantics = {
      default = { };
      regime = "split";
    };
    metaModules = {
      default = [ ];
      regime = "merged";
    };
    moduleArgs = {
      default = defaultModuleArgs;
      regime = "minted";
    };
    providerPrefix = {
      default = [ ];
      regime = "minted";
    };
    recursiveClosed = {
      default = false;
      regime = "minted";
    };
    rejectBareModuleInclude = {
      default = false;
      regime = "minted";
    };
    # A module the type reads out of the enclosing evaluation's `config` (mkAspectModule's
    # schema-declared instance options). Its content is value-stratum output, which a type
    # relation decided while declarations fold may not read (ADR-0033), so it is stated as a
    # first-order `term` naming where it is read from, and that term is what is minted. Within one
    # evaluation the term determines the module, because there is one `config`.
    schemaDefs = {
      default = null;
      regime = "term";
    };
  };

  cnfDefaults = builtins.mapAttrs (_: e: e.default) cnfVocabulary;

  keysIn =
    regime: builtins.filter (k: cnfVocabulary.${k}.regime == regime) (builtins.attrNames cnfVocabulary);
  categoryOf = e: if builtins.isAttrs e then e.category or null else e;
  entryRest = e: if builtins.isAttrs e then removeAttrs e [ "category" ] else null;

  # A checked cnf's construction, by regime, in gen-schema `constructionRelation`'s grammar
  # (den-hoag-bfc0k): the inert keys, the `term` keys' terms and each keySemantics entry's
  # category are minted; the sealed keys and the rest of each entry are compared as values, each
  # stating the type records its grammar places in it. Only an entry's `option.type` is such a
  # position; the collections are open caller content. That content is outside `records`, and it is
  # ordinary: a module in `collections`, or a facet entry's `module`, declaring an option typed by a per-call
  # `mkOptionType` aborts when two constructions are compared in the order that interns `functor`
  # first, and in every order when that type has a `description` back-edge (gen-merge
  # `closuresFirst`'s enumerated exception). `records = [ ]` is an unchecked assertion that no
  # grammar-fixed record position exists in the component, not a check that none is present.
  cnfConstruction = keySemanticsRecords: cnf: {
    minted =
      genAttrs (keysIn "minted") (k: cnf.${k})
      // genAttrs (keysIn "term") (k: if cnf.${k} == null then null else cnf.${k}.term)
      // {
        keySemanticsCategories = builtins.mapAttrs (_: categoryOf) cnf.keySemantics;
      };
    compared =
      genAttrs (keysIn "compared") (k: {
        records = [ ];
        value = cnf.${k};
      })
      // {
        keySemantics = {
          records = keySemanticsRecords cnf.keySemantics;
          value = builtins.mapAttrs (_: entryRest) cnf.keySemantics;
        };
      };
  };

  cnfKeys = builtins.attrNames cnfDefaults;

  # The keys a construction's relation concatenates rather than compares; outside `cnfConstruction`,
  # whose grammar is gen-schema's and has no union.
  mergedKeys = keysIn "merged";

  # A key the library RETIRED names its replacement in the refusal, and does so from a binding rather
  # than from an `if`: a future retirement adds an entry, and the message construction does not
  # change. An unrecognised key with no entry gets the same message minus this paragraph.
  #
  # Each sentence is stored WITHOUT its leading `cnf.<key>` — `cnfRefusal` renders that from the key.
  # Spelling it here would put the literal token `cnf.classes` in `lib/`, where the CI guard that
  # derives the vocabulary from the reads themselves would pick it up as a phantom member of the
  # recognised set — the retirement record manufacturing its own false evidence.
  retiredCnfKeys = {
    classes =
      "was RETIRED at gen-aspects 9a855c9 (2026-07-15): a class is now a keySemantics entry. "
      + "Replace `classes = { nixos = { }; }` with `keySemantics = { nixos = { category = \"class\"; }; }`.";
  };

  # ALL offending keys are named, never just the first: otherwise a three-typo migration is three
  # round trips. The recognised set is rendered from `cnfDefaults` and never restated, because a
  # literal list inside a message string is one more copy that drifts silently. No edit-distance
  # "did you mean" — that adds a similarity heuristic and a tuning parameter to a refusal path, where
  # printing the recognised set in full answers the same question exactly rather than probabilistically.
  cnfRefusal =
    unknown:
    let
      noun = if builtins.length unknown == 1 then "key" else "keys";
      named = builtins.concatStringsSep ", " (map (k: "'${k}'") unknown);
      retired = map (k: "  `cnf.${k}` ${retiredCnfKeys.${k}}\n") (
        builtins.filter (k: retiredCnfKeys ? ${k}) unknown
      );
    in
    "gen-aspects: unrecognised cnf ${noun} ${named}.\n"
    + builtins.concatStringsSep "" retired
    + "  Recognised cnf keys: ${builtins.concatStringsSep ", " cnfKeys} "
    + "(also exported as `aspects.cnfKeys`).";

  checkedCnf =
    cnf:
    let
      unknown = builtins.filter (k: !(cnfDefaults ? ${k})) (builtins.attrNames cnf);
    in
    if unknown == [ ] then cnfDefaults // cnf else throw (cnfRefusal unknown);

  # An internal site that extends a checked record with further keys is refused at its OWN call, so
  # the "internals hold a checked record" invariant has a single enforcement point rather than one
  # honour-system point per extension site.
  extendCnf = c: overrides: checkedCnf (c // overrides);

  # A PUBLIC entry point: construct the record, and put that construction on the STRICT path of the
  # result, so the refusal is reachable by forcing the result to WHNF rather than only by evaluating
  # a configuration through it. This placement is load-bearing: forcing a returned option DECLARATION
  # does not force validation buried inside its type, so a check placed there would be a landmine
  # firing at whatever unrelated read first happens to build the submodule.
  #
  # `entityKinds` is the one VALUE checked here, beside the key set: a framework whose closures all
  # declare formals never reads a narrowed context, so a shape check at the first read would never
  # fire for it. `[ ]` is refused with the off-shape values: it would hand every context shape `{ }`.
  # `null` does not declare "no kinds": it leaves the kinds UNDECLARED and hands the whole context.
  # Whether a declared empty set differs from undeclared, and whether a kind NAME is one the
  # framework has, wait on a declared vocabulary (den-hoag-closed-world-guards-uir7d).
  checkedEntry =
    f: cnf:
    let
      c = checkedCnf cnf;
    in
    builtins.seq c (builtins.seq (checkEntityKinds c.entityKinds) (f c));

  # `kinds` itself when it is `null` or a non-empty list of strings, a refusal by name otherwise.
  # Also read by `requireContextOf`, for a record extended past `checkedEntry` (`extendCnf`).
  checkEntityKinds =
    kinds:
    let
      received =
        if !builtins.isList kinds then
          builtins.typeOf kinds
        else if kinds == [ ] then
          "[ ]"
        else
          "a list holding a value of type ${
            builtins.typeOf (builtins.head (builtins.filter (k: !builtins.isString k) kinds))
          }";
    in
    if
      kinds == null || builtins.isList kinds && kinds != [ ] && builtins.all builtins.isString kinds
    then
      kinds
    else
      throw "gen-aspects: cnf.entityKinds must be null or a non-empty list of context keys (strings); received: ${received}.";
in
{
  inherit
    checkEntityKinds
    cnfConstruction
    cnfDefaults
    cnfKeys
    mergedKeys
    cnfRefusal
    checkedCnf
    extendCnf
    checkedEntry
    ;
}
