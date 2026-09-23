# keyRef: the by-key `includes` variant (design §Kernel fixes / decision 6). An origin-qualified
# reference to a node that may live OUTSIDE the local fixpoint (cross-source direct-use). Accepted
# additively alongside by-value includes, which stay byte-unchanged.
{
  aspects,
  mkSchemaEval,
  ...
}:
let
  # structured form
  ref =
    builtins.head
      (mkSchemaEval {
        modules = [
          {
            config.aspects.main.includes = [
              (aspects.keyRef {
                origin = [ "y" ];
                path = [
                  "apps"
                  "media"
                  "pg"
                ];
              })
            ];
          }
        ];
      }).config.aspects.main.includes;

  # string-sugar form
  refStr =
    builtins.head
      (mkSchemaEval {
        modules = [
          { config.aspects.main.includes = [ (aspects.keyRef "y/apps/media/pg") ]; }
        ];
      }).config.aspects.main.includes;

  # normalized {origin, path, key} of a string-sugar keyRef — malformed slash input (leading /
  # trailing / doubled) must collapse to the SAME clean segment list as the well-formed form,
  # because splitSlash drops empty segments.
  normOf =
    s:
    let
      r = aspects.keyRef s;
    in
    {
      inherit (r) origin path key;
    };

  # single-segment (bare-origin) ref: origin = [ "y" ], path = [ ], key = "" — unchanged behavior.
  bare = aspects.keyRef "y";

  # by-value include (unchanged path)
  byVal =
    (mkSchemaEval {
      modules = [
        (
          { config, ... }:
          {
            config.aspects = {
              main.includes = [ config.aspects.helper ];
              helper.classOne = { };
            };
          }
        )
      ];
    }).config.aspects.main.includes;
in
{
  flake.tests.key-ref.test-keyref-marked = {
    expr = ref.__keyRef;
    expected = true;
  };
  flake.tests.key-ref.test-keyref-target-key-readable = {
    expr = ref.key;
    expected = "apps/media/pg";
  };
  flake.tests.key-ref.test-keyref-origin = {
    expr = ref.origin;
    expected = [ "y" ];
  };
  flake.tests.key-ref.test-keyref-string-sugar = {
    expr = {
      key = refStr.key;
      origin = refStr.origin;
      path = refStr.path;
    };
    expected = {
      key = "apps/media/pg";
      origin = [ "y" ];
      path = [
        "apps"
        "media"
        "pg"
      ];
    };
  };
  # well-formed baseline: "y/x" → origin [ "y" ], path [ "x" ], key "x".
  flake.tests.key-ref.test-keyref-wellformed-baseline = {
    expr = normOf "y/x";
    expected = {
      origin = [ "y" ];
      path = [ "x" ];
      key = "x";
    };
  };
  flake.tests.key-ref.test-keyref-leading-slash-normalizes = {
    expr = normOf "/y/x";
    expected = {
      origin = [ "y" ];
      path = [ "x" ];
      key = "x";
    };
  };
  flake.tests.key-ref.test-keyref-doubled-slash-normalizes = {
    expr = normOf "y//x";
    expected = {
      origin = [ "y" ];
      path = [ "x" ];
      key = "x";
    };
  };
  flake.tests.key-ref.test-keyref-trailing-slash-normalizes = {
    expr = normOf "y/x/";
    expected = {
      origin = [ "y" ];
      path = [ "x" ];
      key = "x";
    };
  };
  flake.tests.key-ref.test-keyref-single-segment-bare-origin = {
    expr = {
      inherit (bare) origin path key;
    };
    expected = {
      origin = [ "y" ];
      path = [ ];
      key = "";
    };
  };
  flake.tests.key-ref.test-byvalue-include-length = {
    expr = builtins.length byVal;
    expected = 1;
  };
  flake.tests.key-ref.test-byvalue-include-is-aspect = {
    expr = (builtins.head byVal) ? name;
    expected = true;
  };

  # A wrong-typed reference is REFUSED, catchably (den-hoag-bkdkg). Before the guard every shape
  # below aborted past `tryEval`, which crashes this cell rather than failing it. What the refusal
  # says is pinned in `ci/tests-error.nix`. The structured and path-only arms are the controls.
  flake.tests.key-ref.test-wrong-typed-refs-refused-catchably = {
    expr = map (ref: (builtins.tryEval (builtins.deepSeq (aspects.keyRef ref) null)).success) [
      { name = "a"; }
      3
      { path = 3; }
      { path = [ { name = "a"; } ]; }
      {
        path = "s";
        origin = 3;
      }
      {
        path = "s";
        origin = [ { } ];
      }
      {
        origin = [ "y" ];
        path = [ "a" ];
      }
      { path = "a/b"; }
    ];
    expected = [
      false
      false
      false
      false
      false
      false
      true
      true
    ];
  };
  # The guard sits in the body, so the door stays a plain lambda: a wrapper that made it a functor
  # set would make `functionArgs` abort here.
  flake.tests.key-ref.test-keyref-is-a-plain-lambda = {
    expr = builtins.functionArgs aspects.keyRef;
    expected = { };
  };
}
