# A functor-form module function at an aspect position is refused by name (den-hoag-a3eys; spec
# specs/2026-10-06-gen-aspects-functor-module-refusal-spec.md §3a). A submodule reads an attrset definition
# as config, so `{ __functor; __functionArgs; }` once landed in the freeform slot and the class value read
# null. Each cell holds the refusal and its lambda twin. A functor whose `__functor` yields a context closure
# is refused too (den-hoag-iy9qh), as an unlowered lambda closure is. The messages are pinned on the error
# plane (`ci/tests-error.nix`).
{ mkSchemaEval, ... }:
let
  ok = v: (builtins.tryEval (builtins.deepSeq v true)).success;
  fm = body: {
    __functionArgs = {
      config = false;
    };
    __functor =
      _:
      { config, ... }:
      body;
  };
  lm =
    body:
    { config, ... }:
    body;
  v1 = {
    __functor =
      _:
      { thimble, ... }:
      {
        description = thimble;
      };
  };
  body = {
    nixos =
      { pkgs, ... }:
      {
        marker = "m";
      };
  };
  other = {
    description = "o";
  };
  place =
    defs:
    (mkSchemaEval {
      keySemantics.nixos.category = "class";
      modules = map (d: { config.aspects.x = d; }) defs;
    }).config.aspects.x;
  read = defs: (place defs).nixos or "<carrier>";
in
{
  flake.tests.functor-module-refusal = {
    # single def (dispatch)
    test-single-functor-refused = {
      expr = ok (read [ (fm body) ]);
      expected = false;
    };
    test-single-lambda-served = {
      expr = ok (read [ (lm body) ]);
      expected = true;
    };
    # multi def (the coercion to includes) and a guard-bearing multi def (`toFragment`)
    test-multi-functor-refused = {
      expr = ok (read [
        (fm body)
        other
      ]);
      expected = false;
    };
    test-multi-lambda-is-an-include = {
      expr =
        builtins.length
          (place [
            (lm body)
            other
          ]).includes;
      expected = 1;
    };
    # an include element
    test-element-functor-refused = {
      expr = ok (map (i: i.nixos or null) (place [ { includes = [ (fm body) ]; } ]).includes);
      expected = false;
    };
    test-element-lambda-served = {
      expr = ok (map (i: i.nixos or null) (place [ { includes = [ (lm body) ]; } ]).includes);
      expected = true;
    };
    # a functor context closure is refused by name, never read as config (den-hoag-iy9qh)
    test-v1-functor-closure-refused = {
      expr = ok (read [ v1 ]);
      expected = false;
    };
  };
}
