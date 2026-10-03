# A refusal VALUE at an aspect position (den-hoag-3sk7j; specs/2026-10-03-gen-aspects-include-refusal-
# record-spec.md §3a, structure). A library that returns its refusals as values hands a caller a
# record; forwarded unread into `includes` (or any aspect position) it is not an aspect, and it is
# refused, catchably, for each encoding live in the roster. Each cell holds the refusal and its
# admitted control in one expression; the message each refusal SAYS is pinned on the error plane
# (`ci/tests-error.nix`, `refusal-value-door`).
{
  mkSchemaEval,
  genSchema,
  genAlgebra,
  ...
}:
let
  ok = v: (builtins.tryEval (builtins.deepSeq v true)).success;
  place =
    defs:
    (mkSchemaEval {
      keySemantics.nixos.category = "class";
      modules = [ { config.aspects = defs; } ];
    }).config.aspects;
  inc = v: (place { x.includes = [ v ]; }).x.includes;
  # gen-program `escape`'s value at gen-program 8ee37c2 (`escapeRetired`): its witness is nested.
  escapeRetired = {
    refused = true;
    blamed = "author";
    code = "policy-body/escape-retired";
    witness.retired = "escape";
    message = "`escape` is retired";
  };
  # gen-program `admit 42`'s value: a FLAT witness, which nothing else at this position refuses.
  flatWitness = {
    refused = true;
    blamed = "author";
    code = "policy-body/skeleton-malformed";
    witness = 42;
    message = "a policy body is a record";
  };
  eitherLeft.left = {
    code = "unsafe-read";
    witness = { };
  };
  crossing = {
    __crossingResult = "refusal";
    refusal = {
      code = "c";
      blamed = "author";
      witness = { };
    };
  };
  # The failure-list Either, from its REAL producers: gen-schema's `runValidators` (gen-types' is the
  # same base) and gen-algebra's `collectErrors`, each called so that it fails.
  validatorsLeft = genSchema.runValidators "host" [
    {
      name = "named";
      pred = i: i ? name;
      message = "a host is named";
    }
  ] { h = { }; };
  collectedLeft = genAlgebra.either.collectErrors [ (_: genAlgebra.either.left "bad") ] 1;
  control = map (i: i.description) (inc {
    description = "i";
  });
in
{
  flake.tests.refusal-value = {
    test-record-escape-retired-in-includes = {
      expr = {
        refused = ok (inc escapeRetired);
        inherit control;
      };
      expected = {
        refused = false;
        control = [ "i" ];
      };
    };
    test-record-flat-witness-in-includes = {
      expr = {
        refused = ok (inc flatWitness);
        inherit control;
      };
      expected = {
        refused = false;
        control = [ "i" ];
      };
    };
    test-either-left-in-includes = {
      expr = {
        refused = ok (inc eitherLeft);
        inherit control;
      };
      expected = {
        refused = false;
        control = [ "i" ];
      };
    };
    test-crossing-refusal-in-includes = {
      expr = {
        refused = ok (inc crossing);
        inherit control;
      };
      expected = {
        refused = false;
        control = [ "i" ];
      };
    };
    # The aspect position, not the include grammar, is the door: the same record at a root.
    test-record-flat-witness-at-root = {
      expr = {
        refused = ok (place { x = flatWitness; }).x;
        control = (place { x.description = "s"; }).x.description;
      };
      expected = {
        refused = false;
        control = "s";
      };
    };
    # An aspect that merely carries one of the encodings' keys is an aspect: recognition is the exact
    # shape, so an extra key (here `description`) or a non-`true` `refused` is not a refusal.
    test-near-shapes-are-aspects = {
      expr = {
        extraKey = map (i: i.description) (inc (flatWitness // { description = "e"; }));
        notTrue = ok (inc (flatWitness // { refused = false; }));
        # A nested aspect named `left` whose child `code` is an aspect, not a string code.
        leftAspect = ok (inc {
          left.code.nixos = { };
        });
      };
      expected = {
        extraKey = [ "e" ];
        notTrue = true;
        leftAspect = true;
      };
    };
    # The failure-list Either, read off its producers rather than written: both are `{ left = [ … ]; }`.
    test-failure-list-left-in-includes = {
      expr = {
        validators = ok (inc validatorsLeft);
        collected = ok (inc collectedLeft);
        atRoot = ok (place { x = validatorsLeft; }).x;
        inherit control;
      };
      expected = {
        validators = false;
        collected = false;
        atRoot = false;
        control = [ "i" ];
      };
    };
    # A key this aspect type DECLARES is the author's: with a class `left` declared, `{ left.code = …; }`
    # is class content, at an include and at a root, and no encoding is recognised over it.
    test-declared-key-is-an-aspect =
      let
        placeL =
          defs:
          (mkSchemaEval {
            keySemantics.left.category = "class";
            modules = [ { config.aspects = defs; } ];
          }).config.aspects;
      in
      {
        expr = {
          inInclude = ok (placeL { x.includes = [ { left.code = "s"; } ]; }).x.includes;
          atRoot = ok (placeL { x.left.code = "s"; }).x;
        };
        expected = {
          inInclude = true;
          atRoot = true;
        };
      };
    # Several definitions at one aspect position: a refusal among them is refused whichever order the
    # modules give, and two aspect definitions still merge.
    test-refusal-among-several-definitions =
      let
        placeMany =
          defss:
          (mkSchemaEval {
            keySemantics.nixos.category = "class";
            modules = map (defs: { config.aspects = defs; }) defss;
          }).config.aspects.x;
      in
      {
        expr = {
          recordFirst = ok (placeMany [
            { x = flatWitness; }
            { x.description = "a"; }
          ]);
          recordSecond = ok (placeMany [
            { x.description = "a"; }
            { x = flatWitness; }
          ]);
          control =
            (placeMany [
              { x.description = "a"; }
              { x.nixos = { }; }
            ]).description;
        };
        expected = {
          recordFirst = false;
          recordSecond = false;
          control = "a";
        };
      };
  };
}
