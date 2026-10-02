# Guard-function defunctionalization — closed predicate vocabulary + global applyGuard.
# Theory: Reynolds 1972 "Elimination of Higher-Order Functions" (md:718; FUNVAL->ENV->CONT at
# md:874/1318) as formalized by Danvy & Nielsen 2001 (obligations O1-O7). A guard = predicate +
# body; the predicate is pure first-order data, so identity (identity.nix guardKey) never hashes a
# closure. Raw closures remain the non-defunctionalized escape hatch (functionTo, see types.nix).
{
  prelude,
  merge,
  T,
  GT,
}:
let
  inherit (import ./cnf.nix) checkedEntry entityKindsOf;
  doors = import ./require-wrapped-closure.nix;
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
      throw "gen-aspects.pred.custom was RETIRED by den-hoag-lwbb1: a custom condition is a term built from `pred.has`, `pred.eq`, `pred.all`, `pred.any` and `pred.not`; one no term can state is written as a guard function (`{ <coordinate>, ... }: <aspect>`) at the aspect position.";
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
      # The context door at this vocabulary's entity kinds, for the closure arms that remain until the
      # gen-rules door lands (the carrier's function fragment and the escape hatch; design Section 5
      # build order: retirements last).
      contextOf = doors.requireContextOf (entityKindsOf cnf);
      at = loc: "aspect `${prelude.concatStringsSep "." loc}`";
      checked = loc: GT.checkGuard cnf (at loc);
      fireAt =
        args: loc: g:
        GT.fire cnf (at loc) args (checked loc g);
      fires = ctx: g: GT.holds cnf ctx (checked (g.meta.loc or [ "<guard>" ]) g);
      # Multi-def guard carrier discharge (den-hoag-sezf Arm B): one fragment per definition. A record
      # fragment is a first-order guard, fired as one; a function fragment applies its closure (retired
      # with the hatch); an unconditional fragment always survives.
      dischargeFragment =
        args: loc: f:
        if f.kind == "record" then
          fireAt args loc f.guard
        else if f.kind == "fn" then
          f.fn (contextOf "guard" (at loc) f.fn args.context)
        else
          f.body;
      applyGuardWith =
        args: g:
        if g ? fragments then
          let
            loc = g.meta.loc or [ "<guard-carrier>" ];
            survivors = builtins.filter (v: v != null) (map (dischargeFragment args loc) g.fragments);
          in
          if survivors == [ ] then
            null
          else
            merge.mergeDefaultOption loc (
              map (v: {
                file = g.meta.file or "<unknown>";
                value = v;
              }) survivors
            )
        else if g.__guard or false then
          fireAt args (g.meta.loc or [ "<guard>" ]) g
        # A wrap record carries its own doors; the escape hatch applies a caller-supplied closure through
        # the context door. Both retire with the hatch (den-hoag-lwbb1).
        else if g.__isWrappedFn or false then
          g args.context
        else if prelude.isFunction g then
          g (contextOf "guard" "`applyGuard`" g args.context)
        else
          throw "gen-aspects.guard: applyGuard: not a guard record or callable";
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
