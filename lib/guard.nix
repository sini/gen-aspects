# Guard-function defunctionalization — closed predicate vocabulary + global applyGuard.
# Theory: Reynolds 1972 "Elimination of Higher-Order Functions" (md:718; FUNVAL->ENV->CONT at
# md:874/1318) as formalized by Danvy & Nielsen 2001 (obligations O1-O7). A guard = predicate +
# body; the predicate is pure first-order data, so identity (identity.nix guardKey) never hashes a
# closure. A context closure crosses the gen-rules door, never this one (den-hoag-lwbb1 stage 2b).
{
  prelude,
  merge,
  T,
  GT,
}:
let
  inherit (import ./cnf.nix) checkedEntry;
  tm = T.term;

  # The condition vocabulary (design Section 3): constructors emitting terms of the one algebra.
  # `class` and `tagEq` read this library's own context fields and lower to the core `eq`.
  pred = {
    class = v: tm.eq [ "class" ] v;
    tagEq = k: v: tm.eq [ "tags" k ] v;
    inherit (tm)
      eq
      has
      all
      any
      always
      not
      ;
    custom =
      _: _:
      throw "gen-aspects.pred.custom was RETIRED by den-hoag-lwbb1: a custom condition is a term built from `pred.has`, `pred.eq`, `pred.all`, `pred.any` and `pred.not`; one no term can state is a context closure, which crosses the gen-rules door: declare the aspect through the framework's surface.";
  };

  # A guard is a condition term and a body (design Section 3). The body is a term or first-order data,
  # lifted to its term where the guard meets its `cnf` (lib/guard-term.nix `checkGuard`).
  guard = condition: body: {
    __guard = true;
    inherit condition body;
  };
in
{
  inherit pred guard;

  mkGuardVocab = checkedEntry (
    cnf:
    let
      at = loc: "aspect `${prelude.concatStringsSep "." loc}`";
      checked = loc: GT.checkGuard cnf (at loc);
      fireAt =
        args: loc: g:
        GT.fire cnf (at loc) args (checked loc g);
      fires = ctx: g: GT.holds cnf ctx (checked (g.meta.loc or [ "<guard>" ]) g);
      # Multi-def guard carrier discharge (den-hoag-sezf Arm B): one fragment per definition. A record
      # fragment is a first-order guard, fired as one; an unconditional fragment always survives.
      dischargeFragment =
        args: loc: f:
        if f.kind == "record" then fireAt args loc f.guard else f.body;
      applyGuardWith =
        args: g:
        if g ? fragments then
          let
            loc = g.meta.loc or [ "<guard-carrier>" ];
            survivors = builtins.filter (v: v != null) (map (dischargeFragment args loc) g.fragments);
          in
          if survivors == [ ] then
            null
          else if builtins.length survivors == 1 then
            builtins.head survivors
          else
            # The module system's own law for untyped content (`types.anything`): lists concatenate,
            # attrsets merge per key, equal scalars agree, and a conflicting scalar is refused by name
            # (ADR-0025 item 1). `mergeDefaultOption` folds attrsets with `//`, which drops a
            # definition's keys without a message (den-hoag-ywlww).
            merge.types.anything.merge loc (
              map (v: {
                file = g.meta.file or "<unknown>";
                value = v;
              }) survivors
            )
        else if g.__guard or false then
          fireAt args (g.meta.loc or [ "<guard>" ]) g
        # A context closure has no arm here (den-hoag-lwbb1 stage 2b): it crosses the gen-rules door.
        else if prelude.isFunction g then
          throw "gen-aspects.guard: applyGuard: a context closure was handed where a guard record belongs. gen-aspects holds first-order guards only; a closure crosses the gen-rules door. Declare the aspect through the framework's surface, or write it as a guard term (`guard (pred.has <coordinate>) <body>`)."
        else
          throw "gen-aspects.guard: applyGuard: not a guard record";
    in
    {
      inherit
        pred
        guard
        fires
        applyGuardWith
        ;
      vocab = {
        whenClass = name: guard (pred.class name);
        whenTagEq = tag: value: guard (pred.tagEq tag value);
        whenEq = path: value: guard (pred.eq path value);
        whenAll = ps: guard (pred.all ps);
        whenAny = ps: guard (pred.any ps);
        always = body: guard pred.always body;
      };
      # The single firing entry, with no sources: a door node refuses here by name (it fires through
      # `instanceOf` / `instancesFor`, which carry them).
      applyGuard =
        ctx: g:
        applyGuardWith {
          context = ctx;
          sources = null;
          scope = { };
        } g;
    }
  );
}
