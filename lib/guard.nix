# Guard-function defunctionalization — closed predicate vocabulary + global applyGuard.
# Theory: Reynolds 1972 "Elimination of Higher-Order Functions" (md:718; FUNVAL->ENV->CONT at
# md:874/1318) as formalized by Danvy & Nielsen 2001 (obligations O1-O7). A guard = predicate +
# body; the predicate is pure first-order data, so identity (identity.nix guardKey) never hashes a
# closure. A context closure crosses the gen-rules door, never this one (den-hoag-lwbb1 stage 2b).
{
  prelude,
  cnfDoor,
  merge,
  T,
  GT,
  carrierLawOf,
}:
let
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

  # THE FIRING RECORD (den-hoag-7gp66 P2 L5): `applyGuardWith` / `applyGuardScoped` take `{ context;
  # sources; scope; }`, three configuration operands with no natural order, as one keyed open record
  # (R5: a missing field refused by name at its application, an extra one admitted), then the guard,
  # the subject, last. The spec is bound once; the library's own firing (`instanceOf`, `applyGuard`)
  # calls the unchecked core.
  firingRecord = prelude.door {
    name = "gen-aspects.applyGuardWith";
    required = [
      "context"
      "sources"
      "scope"
    ];
    open = true;
  };

  # The vocabulary over a CONSTRUCTED `cnf`, unchecked: `mkGuardVocab` is it behind the `cnf` door,
  # and `instanceOf` reads its core from it directly.
  guardVocabOf =
    cnf:
    let
      at = loc: "aspect `${prelude.concatStringsSep "." loc}`";
      # A guard carrier's content law, T4's at its top-level fields (lib/types.nix `carrierLawFor`),
      # bound here, where carriers are discharged, from the declarations this cnf's aspect submodule
      # makes; once per vocabulary and only where a carrier is first discharged. Never on the carrier,
      # which stays first-order data. It stands for the carrier's position only where the position's
      # declaration evidence, which the carrier holds, is this vocabulary's; elsewhere the carrier folds
      # by the law no declaration enters (`base`), so a vocabulary never folds a carrier by declarations
      # its position does not make (lib/types.nix `carrierEvidence`).
      carrierLaw = carrierLawOf cnf;
      lawFor = g: if (g.__evidence or null) == carrierLaw.evidence then carrierLaw else carrierLaw.base;
      checked = loc: GT.checkGuardIn null loc cnf (at loc);
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
        args: g:
        if g ? fragments then
          let
            loc = g.meta.loc or [ "<guard-carrier>" ];
            survivors = builtins.filter (r: r.value != null) (map (dischargeFragment args loc) g.fragments);
            values = map (r: r.value) survivors;
            law = lawFor g;
          in
          {
            value =
              if survivors == [ ] then
                null
              else
                # The carrier's content law, T4's at its top-level fields (`lawFor`). The fields are
                # LAZY, as the aspect type's own freeform slot is: a field whose every definition discharges
                # to nothing is kept and refused by name where it is read, and reading one field never forces another
                # (ADR-0010 §4(a), per-field substitution). Each field's definitions take gen-merge's spine,
                # so a property marker a raw fragment holds at a nested key is discharged at fire time, where
                # a fired record's content can meet its priority. So is the coerced fragment's: its typed
                # body keeps, at each nested key and at each declared `includes`, the priority that selected
                # its winners (gen-merge `partialAttrsOf`, den-hoag-fjdnf; `partialSubmodule`,
                # den-hoag-5ov3p), and an `includes` nobody wrote is its declared default at
                # `mkOptionDefault`, so the typed half, the remainders and the fired content meet in one
                # priority pass, as T4's definitions do; one survivor takes the law as several do, because
                # the law is not the identity on one definition.
                law.fold law.lazy loc (
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
      applyGuardWithCore = args: g: (applyGuardScoped args g).value;
    in
    {
      applyGuardScopedCore = applyGuardScoped;
      inherit
        pred
        guard
        fires
        ;
      applyGuardWith = firingRecord (args: applyGuardWithCore args);
      applyGuardScoped = firingRecord (args: applyGuardScoped args);
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
        applyGuardWithCore {
          context = ctx;
          sources = null;
          scope = { };
        } g;
    };
in
{
  inherit pred guard guardVocabOf;
  mkGuardVocab = cnfDoor prelude "gen-aspects.mkGuardVocab" (
    cnf: removeAttrs (guardVocabOf cnf) [ "applyGuardScopedCore" ]
  );
}
