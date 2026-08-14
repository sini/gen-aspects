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
# nothing deep-seq'd. It inspects names, never contents, so it cannot become a second instance of the
# eager keySemantics category validation, where a bad value throws while reading an unrelated
# aspect's `name`. It runs once per public entry call, not once per aspect node: the internals
# receive an already-constructed record and are never re-checked.
let
  # Module functions take known module args — evaluated by the submodule. Guard functions take
  # context args (host/user/etc.) — wrapped for later. The default set is the standard NixOS args
  # plus `aspect`, which gen-aspects provides.
  defaultModuleArgs = {
    lib = true;
    config = true;
    options = true;
    pkgs = true;
    modulesPath = true;
    aspect = true;
  };

  cnfDefaults = {
    aspectModules = [ ];
    closedKeys = false;
    collections = { };
    deferIncludeResolution = false;
    freeformKeys = [ ];
    guardForms = { };
    keySemantics = { };
    metaModules = [ ];
    moduleArgs = defaultModuleArgs;
    providerPrefix = [ ];
    recursiveClosed = false;
    rejectBareModuleInclude = false;
  };

  cnfKeys = builtins.attrNames cnfDefaults;

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
  checkedEntry =
    f: cnf:
    let
      c = checkedCnf cnf;
    in
    builtins.seq c (f c);
in
{
  inherit
    cnfDefaults
    cnfKeys
    cnfRefusal
    checkedCnf
    extendCnf
    checkedEntry
    ;
}
