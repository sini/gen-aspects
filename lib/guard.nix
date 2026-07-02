# Guard-function defunctionalization — closed predicate vocabulary + global applyGuard.
# Theory: Reynolds 1972 "Elimination of Higher-Order Functions" (md:718; FUNVAL->ENV->CONT at
# md:874/1318) as formalized by Danvy & Nielsen 2001 (obligations O1-O7). A guard = predicate +
# body; the predicate is pure first-order data, so identity (identity.nix guardKey) never hashes a
# closure. Raw closures remain the non-defunctionalized escape hatch (functionTo, see types.nix).
{ lib }:
let
  # O1/OQ4: first-order enforcement + type tagging (Palmer Typeable guard) --------
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
    host = name: mkP "host" { host = name; };
    class = name: mkP "class" { class = name; };
    user = name: mkP "user" { user = name; };
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
  };

  guard = pr: body: {
    __guard = true;
    pred = pr;
    inherit body;
  };
in
{
  inherit toArgData pred guard;

  mkGuardVocab =
    cnf:
    let
      getPath = path: ctx: lib.attrByPath path null ctx;
      # A consumer form is { eval = ctx: argData: bool; reads = [ [attrPath] ... ]; } (reads
      # is metadata for read-set analysis; not consulted at eval time).
      userForms = cnf.guardForms or { };
      # O2: ONE global dispatcher, case-analysis on the predicate tag.
      evalPred =
        ctx: pr:
        let
          core = {
            host = (getPath [ "host" "name" ] ctx) == pr.a.host.v;
            class = (getPath [ "class" ] ctx) == pr.a.class.v;
            user = (getPath [ "user" "name" ] ctx) == pr.a.user.v;
            tagEq = (getPath [ "tags" pr.a.tag.v ] ctx) == pr.a.value.v;
            eq = (getPath (map (s: s.v) pr.a.path.v) ctx) == pr.a.value.v;
            all = builtins.all (evalPred ctx) pr.a.preds;
            any = builtins.any (evalPred ctx) pr.a.preds;
            always = true;
          }
          // builtins.mapAttrs (_: form: form.eval ctx pr.a) userForms;
        in
        core.${pr.p} or (throw "gen-aspects.guard: unknown predicate form '${pr.p}'");
      fires = ctx: g: evalPred ctx g.pred;
    in
    {
      inherit
        pred
        guard
        fires
        evalPred
        ;
      vocab = {
        whenHost = name: guard (pred.host name);
        whenClass = name: guard (pred.class name);
        whenUser = name: guard (pred.user name);
        whenTagEq = tag: value: guard (pred.tagEq tag value);
        whenEq = path: value: guard (pred.eq path value);
        whenAll = ps: guard (pred.all ps);
        whenAny = ps: guard (pred.any ps);
        always = body: guard pred.always body;
      };
      # O2/O5: single entry point. Vocabulary guards dispatch as data; raw closures /
      # functionTo functors take the escape hatch (NOT defunctionalized).
      applyGuard =
        ctx: g:
        if g.__guard or false then
          (if fires ctx g then g.body else null)
        else if lib.isFunction g || (g.__isWrappedFn or false) then
          g ctx
        else
          throw "gen-aspects.guard: applyGuard: not a guard record or callable";
    };
}
