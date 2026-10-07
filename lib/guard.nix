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
        GT.fireScoped cnf (at loc) args (checked loc g);
      fires = ctx: g: GT.holds cnf ctx (checked (g.meta.loc or [ "<guard>" ]) g);
      # Multi-def guard carrier discharge (den-hoag-sezf Arm B): one fragment per definition. A record
      # fragment is a first-order guard, fired as one; an unconditional fragment always survives.
      dischargeFragment =
        args: loc: f:
        if f.kind == "record" then
          fireAt args loc f.guard
        else
          {
            value = f.body;
            inherit (args) scope;
          };
      # `{ value; scope; }`: the firing's value, and its instantiation scope (lib/guard-term.nix
      # `fireScoped`), a carrier's the union of its surviving fragments' scopes. Their keys are nested
      # identifiers, which name the registration and the position, so two fragments share a key only
      # where they share the closure.
      applyGuardScoped =
        let
          # A guard carrier's content law over its survivors. Plain attrsets fold as `lazyAttrsOf
          # anything`, bound once, where `applyGuardScoped` is first forced: not in a let the library's
          # load builds (a member-load cost), and not per firing (building the type cost more than the
          # fold it runs; den-hoag-15wnx, measured against nixpkgs' same fold). Every other survivor list
          # (a scalar or list body at a freeform field, a construction carrying `__mint`, a mix) takes
          # `anything`, whose own arms are the same law; the test is `anything`'s own attrset-arm test.
          fields = merge.types.lazyAttrsOf merge.types.anything;
          contentLaw =
            loc: defs:
            if
              builtins.all (d: builtins.isAttrs d.value) defs
              && !((builtins.head defs).value ? __mint && builtins.all (d: d.value ? __mint) defs)
            then
              fields.merge loc defs
            else
              merge.types.anything.merge loc defs;
        in
        args: g:
        if g ? fragments then
          let
            loc = g.meta.loc or [ "<guard-carrier>" ];
            survivors = builtins.filter (r: r.value != null) (map (dischargeFragment args loc) g.fragments);
            values = map (r: r.value) survivors;
          in
          {
            value =
              if survivors == [ ] then
                null
              else
                # The module system's own law for untyped content (`types.anything`): lists concatenate,
                # attrsets merge per key, equal scalars agree, and a conflicting scalar is refused by name
                # (ADR-0025 item 1). `mergeDefaultOption` folds attrsets with `//`, which drops a
                # definition's keys without a message (den-hoag-ywlww).
                #
                # Plain attrset survivors' fields fold as `lazyAttrsOf anything` (den-hoag-15wnx). Each
                # field's definitions take gen-merge's spine, so a property marker a raw fragment holds at a
                # nested key is discharged at fire time, where a fired record's content can meet its
                # priority; one survivor takes the law as several do, because the law is not the identity
                # on one definition. The field level is LAZY, as the aspect type's own freeform slot (T4)
                # is: a field whose every definition discharges to nothing is kept and refused by name
                # where it is read, and reading one field never forces another (ADR-0010 §4(a),
                # per-field substitution). Below the fields `anything` is nixpkgs' own, strict key set
                # and all. Survivors that are not plain attrsets take `anything` whole (`contentLaw`).
                contentLaw loc (
                  map (v: {
                    file = g.meta.file or "<unknown>";
                    value = v;
                  }) values
                );
            scope = builtins.foldl' (acc: r: acc // r.scope) args.scope survivors;
          }
        else if g.__guard or false then
          fireAt args (g.meta.loc or [ "<guard>" ]) g
        # A context closure has no arm here (den-hoag-lwbb1 stage 2b): it crosses the gen-rules door.
        else if prelude.isFunction g then
          throw "gen-aspects.guard: applyGuard: a context closure was handed where a guard record belongs. gen-aspects holds first-order guards only; a closure crosses the gen-rules door. Declare the aspect through the framework's surface, or write it as a guard term (`guard (pred.has <coordinate>) <body>`)."
        else
          throw "gen-aspects.guard: applyGuard: not a guard record";
      applyGuardWith = args: g: (applyGuardScoped args g).value;
    in
    {
      inherit
        pred
        guard
        fires
        applyGuardWith
        applyGuardScoped
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
