# THE INSTANCE MINT (den-hoag-0cmbt spec §2.5): `instanceOf cnf { aspect; value; context; sources; }`
# → `{ id; entry; formals; }`. A parametric aspect applied to a context is a node of its own, the
# instance, whose identity is its declaration and what it was handed (design §3): two contexts that
# hand it different values are two instances, and two that differ only in keys it never receives are
# one.
#
#   formals = { <k> = sources.<k>; } for every key k the definitions are handed at `context`
#   id      = hashIdentity "aspect-instance" [ "aspect" "formals" ] { aspect; formals; }
#   entry   = the aspect applied to `context`
#
# `formals` nests under its own label, so a formal named `aspect` does not clash with the relatum.
# A `{ }:` aspect receives nothing: `formals = { }`, one id for every context.
#
# THE RECEIVED KEYS. A wrap record (`__isWrappedFn`) publishes them as `__receives context`, the union
# over its definitions of what the context door hands each one (lib/types.nix `mkWrapped`), so the
# wrap's own cnf decides them. A guard carrier (`__guard` with `fragments`: a guard function defined
# more than once under one key, the K2 site) unions its `fn` fragments' door keys, read through the
# SAME door `dischargeFragment` applies them through, at this cnf's entity kinds; an `unconditional`
# fragment reads no context. `__receives` stays a closure, as spec §2.4 states it: it is a record
# marker this library both writes and reads, never an interface a consumer resolves.
#
# THE SOURCES (design K3). `sources` maps each context key to the identity of what supplied it, an
# entity's identity or a K1 argument binding's (gen-scope `argumentBinding`), so the binding ids reach
# the mint by the same call that carries the context. This is K3's "(or hands over an instance it
# minted)" arm: the applicator's functor keeps its arity (`w ctx`), and the sources travel here.
#
# THE DOORS, each a catchable `throw` naming this entry:
# - the argument is not the closed record `{ aspect; value; context; sources; }`, or `aspect` is not a
#   string, or `context` or `sources` is not an attrset;
# - the value is not parametric (neither a wrap record nor a carrier);
# - the value is a guard record, or a carrier holding a `record` fragment: a first-order guard reads
#   context through its predicate, and its instance identity is not defined yet (spec §4.1 O1);
# - a received key has no source (design §3, "a formal with no known supplier refuses by name");
# - a source is not identity-shaped (`<kind>:<64 hex>`): the honest mistake of handing the context
#   VALUE where its supplier's identity belongs (ADR-0016 r7, "a relatum must already be a minted
#   node"; the minter holds no registry, so it checks the shape);
# - a source is the identity of a node of a kind that supplies no argument: `aspect-instance`,
#   `aspect`, `include-site`, `named-value`. The reaching instance is an edge, never a formal's
#   source (design §3), and an instance id as a source is a same-pass relatum, which r7 forbids.
# ITS BOUND, enumerated (ADR-0025 item 1). A source that is the instance's OWN id is a let-bound
# fixpoint: no door can read it before forcing it, so it aborts with `infinite recursion`,
# uncatchably. And the received keys inherit the context door's bound (lib/require-wrapped-closure.nix):
# a forwarding wrapper around `{ }:` classifies as a context shape, so its instance is keyed on the
# context it is handed rather than on `{ }`.
#
# COST: O(definitions × formals) for the received keys, one `hashIdentity` over O(formals) labelled
# entries, and one application. A wrap record's doors are classified once per definition when it is
# built; a carrier's `fn` fragments are classified at every call, as `dischargeFragment` classifies
# them at every discharge. The guard vocabulary that discharges a carrier is built once per
# `instanceOf cnf`. Nothing scans another instance.
{
  prelude,
  hashIdentity,
  mkGuardVocab,
}:
let
  inherit (import ./cnf.nix) checkedEntry;
  doors = import ./require-wrapped-closure.nix;
  door = "gen-aspects.instanceOf";
  fields = [
    "aspect"
    "value"
    "context"
    "sources"
  ];
  names = prelude.concatStringsSep ", ";
  # The kinds gen mints for nodes that supply no argument (spec §2.9's tags beside the two aspect tags).
  nonSupplier = [
    "aspect-instance"
    "aspect"
    "include-site"
    "named-value"
  ];
  kindOf = s: if builtins.isString s then builtins.match "([^:]+):[0-9a-f]{64}" s else null;
in
{
  instanceOf = checkedEntry (
    cnf:
    let
      contextOf = doors.requireContextOf cnf.entityKinds;
      inherit (mkGuardVocab cnf) applyGuard;
    in
    args:
    let
      a = prelude.checkOptions door fields (prelude.checkRequired door fields args);
      inherit (a)
        aspect
        value
        context
        sources
        ;
      wrapped = builtins.isAttrs value && (value.__isWrappedFn or false);
      guarded = builtins.isAttrs value && (value.__guard or false);
      carrier = guarded && value ? fragments;
      fragments = if carrier then value.fragments else [ ];
      at = "aspect `${prelude.concatStringsSep "." (value.meta.loc or [ "<guard-carrier>" ])}`";
      received =
        if wrapped then
          value.__receives context
        else
          builtins.attrNames (
            prelude.foldl' (acc: f: acc // contextOf "guard" at f.fn context) { } (
              builtins.filter (f: f.kind == "fn") fragments
            )
          );
      missing = builtins.filter (k: !(sources ? ${k})) received;
      notIdentity = builtins.filter (k: kindOf sources.${k} == null) received;
      foreign = builtins.filter (
        k: builtins.elem (builtins.head (kindOf sources.${k})) nonSupplier
      ) received;
      formals = prelude.genAttrs received (k: sources.${k});
      refuse = msg: throw "${door}: aspect `${aspect}` ${msg}";
    in
    if !(builtins.isString aspect) then
      throw "${door}: `aspect` must be the aspect's identity, a string; received: ${builtins.typeOf aspect}."
    else if !(builtins.isAttrs context) then
      refuse "was handed a context of type ${builtins.typeOf context}; a context is an attrset of coords."
    else if !(builtins.isAttrs sources) then
      refuse "was handed sources of type ${builtins.typeOf sources}; sources map each context key to the identity that supplied it."
    else if !(wrapped || guarded) then
      refuse "is not parametric: it is neither a wrap record (`__isWrappedFn`) nor a guard carrier, so it has no instances."
    else if guarded && (!carrier || builtins.any (f: f.kind == "record") fragments) then
      refuse "carries a guard record, whose instance identity is not defined yet: a first-order guard reads its context through its predicate (den-hoag-0cmbt spec §4.1 O1)."
    else if missing != [ ] then
      refuse "reads formal(s) `${names missing}` with no known supplier; the sources map carries: ${names (builtins.attrNames sources)}."
    else if notIdentity != [ ] then
      refuse "was handed a source for formal(s) `${names notIdentity}` that is not an identity (`<kind>:<sha256>`); hand the identity of the entity or argument binding that supplied it, never its value."
    else if foreign != [ ] then
      refuse "was handed, for formal(s) ${
        names (map (k: "`${k}`") foreign)
      }, the identity of a node of kind ${
        names (map (k: "`${builtins.head (kindOf sources.${k})}`") foreign)
      }, which supplies no argument; hand the identity of the entity or argument binding that supplied it. An instance's reaching node is an edge, never a formal's source."
    else
      {
        id = hashIdentity "aspect-instance" [ "aspect" "formals" ] (l: { inherit aspect formals; }.${l});
        entry = if carrier then applyGuard context value else value context;
        inherit formals;
      }
  );
}
