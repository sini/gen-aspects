# The declared set and a guard's condition: under `cnf.entityKinds` a guard's condition is never
# narrowed (the wrap, wrap-totality and shape-classifier cells retired with their constructs,
# den-hoag-lwbb1 stage 2b).
{
  aspects,
  ...
}:
let
  kcnf = {
    keySemantics.classOne.category = "class";
    entityKinds = [ "host" ];
  };
in
{
  flake.tests.entity-kinds = {
    # A guard's condition is never narrowed: under the kinds, the built-in `tagEq` reads `tags.role`
    # (a field of this library's own, in the declared set the kinds widen) and fires where the role
    # matches, and a mismatch does not fire.
    test-kinds-condition-not-narrowed =
      let
        tctx = {
          host = "h";
          tags.role = "web";
        };
        v = aspects.mkGuardVocab kcnf;
        run = pr: (v.applyGuard tctx (v.guard pr { description = "fired"; })).description or "not fired";
      in
      {
        expr = {
          web = run (aspects.pred.tagEq "role" "web");
          db = run (aspects.pred.tagEq "role" "db");
        };
        expected = {
          web = "fired";
          db = "not fired";
        };
      };
  };
}
