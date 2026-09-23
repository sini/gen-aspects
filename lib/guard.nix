# Guard-function defunctionalization — closed predicate vocabulary + global applyGuard.
# Theory: Reynolds 1972 "Elimination of Higher-Order Functions" (md:718; FUNVAL->ENV->CONT at
# md:874/1318) as formalized by Danvy & Nielsen 2001 (obligations O1-O7). A guard = predicate +
# body; the predicate is pure first-order data, so identity (identity.nix guardKey) never hashes a
# closure. Raw closures remain the non-defunctionalized escape hatch (functionTo, see types.nix).
{ prelude, merge }:
let
  inherit (import ./cnf.nix) checkedEntry;
  # Vendored attrByPath (gen-prelude has no attrByPath): walk `path` into `set`, `default` if absent.
  attrByPath =
    path: default: set:
    let
      go =
        p: s:
        if p == [ ] then
          s
        else if builtins.isAttrs s && s ? ${builtins.head p} then
          go (builtins.tail p) s.${builtins.head p}
        else
          default;
    in
    go path set;

  # O1: first-order enforcement + type tagging (Palmer Typeable guard) --------
  tagVal =
    v:
    if builtins.isString v then
      {
        __t = "string";
        inherit v;
      }
    else if builtins.isInt v then
      {
        __t = "int";
        inherit v;
      }
    else if builtins.isBool v then
      {
        __t = "bool";
        inherit v;
      }
    else if builtins.isFloat v then
      {
        __t = "float";
        inherit v;
      }
    else if builtins.isPath v then
      {
        __t = "path";
        v = toString v;
      }
    else if builtins.isList v then
      {
        __t = "list";
        v = map tagVal v;
      }
    else if builtins.isAttrs v then
      {
        __t = "attrs";
        v = builtins.mapAttrs (_: tagVal) v;
      }
    else
      throw (
        "gen-aspects.guard: predicate arg must be first-order data (got a "
        + "function/opaque value); use the raw-closure escape hatch for context-computed guards"
      );
  toArgData = builtins.mapAttrs (_: tagVal);

  # O3/O4: predicates — pure first-order data, nestable, NO body -----------------
  mkP = p: a: {
    inherit p;
    a = toArgData a;
  };
  assertPred =
    pr:
    if pr ? p && pr ? a then pr else throw "gen-aspects.guard: all/any expects predicates, not guards";
  pred = {
    class = name: mkP "class" { class = name; };
    tagEq = tag: value: mkP "tagEq" { inherit tag value; };
    eq = path: value: mkP "eq" { inherit path value; };
    all = ps: {
      p = "all";
      a = {
        preds = map assertPred ps;
      };
    };
    any = ps: {
      p = "any";
      a = {
        preds = map assertPred ps;
      };
    };
    always = {
      p = "always";
      a = { };
    };
    custom = formName: a: mkP formName a; # constructor for a cnf.guardForms form
  };

  guard = pr: body: {
    __guard = true;
    pred = pr;
    inherit body;
  };
in
{
  inherit toArgData pred guard;

  mkGuardVocab = checkedEntry (
    cnf:
    let
      getPath = path: ctx: attrByPath path null ctx;
      # Custom forms (O7 extension). Each MUST be { eval = ctx: argData: bool; reads = [ [attrPath] ... ]; }.
      # `reads` is required (load-bearing for read-set congruence, OQ-A) though not consulted at dispatch —
      # it is for downstream read-set analysis. A custom form may NOT shadow a core form.
      coreFormNames = [
        "class"
        "tagEq"
        "eq"
        "all"
        "any"
        "always"
      ];
      checkForm =
        name: form:
        if builtins.elem name coreFormNames then
          throw "gen-aspects.guard: custom form '${name}' collides with a core predicate form"
        else if !(form ? eval && form ? reads) then
          throw "gen-aspects.guard: custom form '${name}' must be { eval; reads; }"
        else
          name;
      # Force every custom form's validation eagerly (den-hoag-cr72): a bad or colliding form must
      # throw at the vocabulary's first use, not silently never-fire until the one dispatch that
      # happens to look it up — the same idiom as lib/types.nix's checkCategory/ks, and completing
      # checkedEntry's own stated intent (lib/cnf.nix): "put that construction on the STRICT path of
      # the result." The forcing point is applyGuard's body, NOT this record or mkGuardVocab's
      # return: a `guardForms` KEY may be derived from a sibling option inside a caller's config
      # fixpoint, and making the return's own WHNF depend on that key set cycles with an `infinite
      # recursion` that escapes tryEval (den-hoag-fvxh's mkInstanceRegistry, same shape — the
      # forcing point MOVES to the guaranteed downstream call site, eagerness is not abandoned).
      # checkForm returns the NAME, never the form: deepSeq over a returned form would additionally
      # make every entry's `reads` and `eval` strict, which is not what the check needs and is a
      # strictness the caller never asked for. checkedCustomForms is the validated passthrough.
      checkedCustomForms = builtins.deepSeq (builtins.mapAttrs checkForm cnf.guardForms) cnf.guardForms;
      # O2: ONE global dispatcher, case-analysis on the predicate tag.
      evalPred =
        ctx: pr:
        let
          core = {
            class = (getPath [ "class" ] ctx) == pr.a.class.v;
            tagEq = (getPath [ "tags" pr.a.tag.v ] ctx) == pr.a.value.v;
            eq = (getPath (map (s: s.v) pr.a.path.v) ctx) == pr.a.value.v;
            all = builtins.all (evalPred ctx) pr.a.preds;
            any = builtins.any (evalPred ctx) pr.a.preds;
            always = true;
          }
          // builtins.mapAttrs (_: form: form.eval ctx pr.a) checkedCustomForms;
        in
        # The refusal is the door: it renders the recognised set (never restated) and names the
        # path-parameterised form, so a caller holding a form name this vocabulary does not declare
        # learns both what exists and how to address any context path without a named form.
        core.${pr.p} or (throw (
          "gen-aspects.guard: unknown predicate form '${pr.p}'. Recognised forms: "
          + builtins.concatStringsSep ", " (coreFormNames ++ builtins.attrNames checkedCustomForms)
          + ". `eq` compares the value at a caller-supplied context path; a form this vocabulary "
          + "does not declare enters through the vocabulary's guardForms."
        ));
      fires = ctx: g: evalPred ctx g.pred;
      # Multi-def guard carrier discharge (den-hoag-sezf Arm B) — one fragment per definition,
      # included iff its condition holds, evaluated HERE at the stratum where guards are
      # evaluable (per evaluation context, downstream). A record fragment's condition is `evalPred`, unchanged;
      # a function fragment IS its own condition-and-body, computed together by the closure
      # (opaque before this call, per the declared limit at the carrier's construction site,
      # `lib/types.nix`); an unconditional fragment always survives.
      dischargeFragment =
        ctx: f:
        if f.kind == "record" then
          (if evalPred ctx f.pred then f.body else null)
        else if f.kind == "fn" then
          f.fn ctx
        else
          f.body;
    in
    {
      inherit
        pred
        guard
        fires
        evalPred
        ;
      vocab = {
        whenClass = name: guard (pred.class name);
        whenTagEq = tag: value: guard (pred.tagEq tag value);
        whenEq = path: value: guard (pred.eq path value);
        whenAll = ps: guard (pred.all ps);
        whenAny = ps: guard (pred.any ps);
        always = body: guard pred.always body;
      };
      # O2/O5: single entry point. Vocabulary guards dispatch as data; raw closures /
      # functionTo functors take the escape hatch (NOT defunctionalized). A multi-def carrier
      # (`g ? fragments`) widens the codomain from *one body or `null`* to *the Arm A merge of
      # the surviving fragments' bodies, or `null` when none survive* — `mkIf`'s discharge-at-merge
      # cannot transfer here because a guard's condition is a function of an evaluation context that
      # does not exist at merge time; the carrier is what carries the undischarged condition
      # across that gap. A single survivor reduces to itself by construction, via
      # `mergeDefaultOption`'s own singleton arm — not a special case here.
      applyGuard =
        ctx: g:
        # checkedCustomForms is forced HERE, before any dispatch answers: every real guard evaluation
        # passes through this one entry point, so a malformed or colliding custom form refuses on the
        # first call through a vocab regardless of which predicate that call names — and memoizes,
        # one shared thunk per vocab, for every later call.
        builtins.seq checkedCustomForms (
          if g ? fragments then
            let
              survivors = builtins.filter (v: v != null) (map (dischargeFragment ctx) g.fragments);
            in
            if survivors == [ ] then
              null
            else
              merge.mergeDefaultOption (g.meta.loc or [ "<guard-carrier>" ]) (
                map (v: {
                  file = g.meta.file or "<unknown>";
                  value = v;
                }) survivors
              )
          else if g.__guard or false then
            (if fires ctx g then g.body else null)
          else if prelude.isFunction g || (g.__isWrappedFn or false) then
            g ctx
          else
            throw "gen-aspects.guard: applyGuard: not a guard record or callable"
        );
    }
  );
}
