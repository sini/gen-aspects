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
  # key is read by no type (`ref` reaches only the guard resolver), so it distinguishes nothing.
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
    # The framework's entity kinds, as the context keys that carry them (ADR-0027: entity kinds are
    # the framework's to declare).
    # The DECLARED COORDINATE SET, with the entity kinds a marked subset (design Q5 (A): one set,
    # widening `entityKinds`). `null` is the open world. A list declares its names as coordinates that
    # are all entity kinds; an attrset `{ <name> = <bool>; }` declares its names, marking an entity kind
    # `true`. `[ ]` and `{ }` are the closed world with no coordinates.
    entityKinds = {
      default = null;
      regime = "minted";
    };
    freeformKeys = {
      default = [ ];
      regime = "minted";
    };
    # The door the framework supplies (unifying spec §2.8's door call): `null` resolves no
    # registration identifier. Read only by the guard resolver's read environment, so it is in no
    # construction.
    ref = {
      default = null;
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

  # The record the internals hold: every key, its default where the caller gave none. The key set
  # was checked at the door, so this is total by construction.
  constructed = cnf: cnfDefaults // cnf;

  # An internal site that extends a constructed record with further keys asserts they are keys of the
  # vocabulary: an internal invariant, not a caller's refusal, which the door owns.
  extendCnf =
    c: overrides:
    assert builtins.all (k: cnfDefaults ? ${k}) (builtins.attrNames overrides);
    c // overrides;

  # A PUBLIC entry point: the `cnf` step is a `prelude.door` (den-hoag-7gp66 P2 L5) — closed over
  # `cnfKeys`, refusing an unknown key by name with the recognised set (a key the library no longer
  # reads is an unknown key like any other, den-hoag-c54n4), its contract published as data — whose body constructs the record and puts that
  # construction on the STRICT path of the result, so the refusal is reachable by forcing the result to WHNF rather than only by evaluating
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
      c = constructed cnf;
    in
    builtins.seq c (
      builtins.seq (checkEntityKinds c.entityKinds) (builtins.seq (checkRef c.ref) (f c))
    );

  # `cnfDoor prelude name f` — the published door over `checkedEntry f`, named for the entry point
  # (R6). The spec is the same at every entry point, so each binds it once, where it is built.
  cnfDoor =
    prelude: name: f:
    prelude.door {
      inherit name;
      optional = cnfKeys;
    } (checkedEntry f);

  # `cnf.ref`, the framework's door: `null`, or a function the resolver can call with
  # `{ id; context; sources; captured; }` without aborting. A formals pattern is read through
  # `toXML` (the ellipsis is invisible to `functionArgs`): without `...` it must name all four
  # fields, and it may require no other. A functor is callable only when its `__functor` is a function
  # that, given the functor, returns one (`__functor = self: { right = …; }` forgot its argument).
  # Everything else refuses here, by name, before any firing.
  doorFields = [
    "id"
    "context"
    "sources"
    "captured"
  ];
  checkRef =
    door:
    let
      functor = builtins.isAttrs door && door ? __functor;
      callable = builtins.isFunction door || functor && builtins.isFunction door.__functor;
      raw = if functor then door.__functor door else door;
      formals = if builtins.isFunction raw then builtins.functionArgs raw else { };
      ellipsis = builtins.match ".*<attrspat[^>]*ellipsis=\"1\".*" (builtins.toXML raw) != null;
      required = builtins.filter (n: !formals.${n}) (builtins.attrNames formals);
      foreign = builtins.filter (n: !(builtins.elem n doorFields)) required;
      unnamed = builtins.filter (n: !(formals ? ${n})) doorFields;
      refuse =
        msg:
        throw "gen-aspects: cnf.ref must be null or the framework's door, a function of `{ id; context; sources; captured; }`; ${msg}.";
    in
    if door == null then
      door
    else if functor && !callable then
      refuse "received: a set whose `__functor` is of type ${builtins.typeOf door.__functor}, not a function"
    else if !callable then
      refuse "received: ${builtins.typeOf door}"
    else if !(builtins.isFunction raw) then
      refuse "received: a functor whose `__functor` returns a value of type ${builtins.typeOf raw}, not a function; a functor door is `self: { id, context, sources, captured, ... }: …`"
    else if formals == { } then
      door
    else if foreign != [ ] then
      refuse "it requires `${builtins.concatStringsSep "`, `" foreign}`, which the call never supplies"
    else if !ellipsis && unnamed != [ ] then
      refuse "its formals omit `${builtins.concatStringsSep "`, `" unnamed}` and take no `...`, so the call would be refused"
    else
      door;

  # `kinds` itself when it is `null` or a non-empty list of strings, a refusal by name otherwise.
  checkEntityKinds =
    kinds:
    if
      kinds == null
      || builtins.isList kinds && builtins.all builtins.isString kinds
      || builtins.isAttrs kinds && builtins.all builtins.isBool (builtins.attrValues kinds)
    then
      kinds
    else
      throw "gen-aspects: cnf.entityKinds must be null, a list of coordinate names (strings), or an attrset marking each declared coordinate `true` when it is an entity kind; received: ${
        if builtins.isList kinds then
          "a list holding a value of type ${
            builtins.typeOf (builtins.head (builtins.filter (k: !builtins.isString k) kinds))
          }"
        else if builtins.isAttrs kinds then
          "an attrset whose value at `${
            builtins.head (builtins.filter (n: !builtins.isBool kinds.${n}) (builtins.attrNames kinds))
          }` is of type ${
            builtins.typeOf
              kinds.${builtins.head (builtins.filter (n: !builtins.isBool kinds.${n}) (builtins.attrNames kinds))}
          }"
        else
          builtins.typeOf kinds
      }.";
  # D, the declared coordinate set, and E, the entity kinds (`null` both, in the open world).
  declaredOf =
    cnf:
    let
      k = checkEntityKinds cnf.entityKinds;
    in
    if builtins.isAttrs k then builtins.attrNames k else k;
  entityKindsOf =
    cnf:
    let
      k = checkEntityKinds cnf.entityKinds;
    in
    if builtins.isAttrs k then builtins.filter (n: k.${n}) (builtins.attrNames k) else k;
in
{
  inherit
    checkEntityKinds
    declaredOf
    entityKindsOf
    cnfConstruction
    cnfDefaults
    cnfKeys
    mergedKeys
    extendCnf
    checkedEntry
    cnfDoor
    ;
}
