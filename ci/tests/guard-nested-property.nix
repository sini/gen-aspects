# A guard carrier discharges a property marker nested in its definitions (den-hoag-15wnx, ADR-0025 item 1).
#
# A carrier's survivors fold by the module system's law for untyped content (lib/guard.nix
# `applyGuardScoped`). That law reached gen-merge's `anything`, which carried a marker below the top level
# as data, and one survivor skipped the law altogether; so an `mkIf false`'s content was SERVED and an
# `mkForce` lost to the plain value it overrides. The survivors now fold as `lazyAttrsOf anything`, whose
# fields take gen-merge's spine and whose `anything` is nixpkgs'.
#
# ★ THE REFERENCE IS nixpkgs, RUN IN THE CELL. Each grid cell evaluates the carrier and, beside it, nixpkgs'
# `types.anything` over the same survivors (the fired record's body when it fires, then the plain
# definition), written with nixpkgs' own constructors. Each side is its value or "THROWS" (a catchable
# refusal), so a cell where both engines refuse is a cell too.
#
# THE GRID: carrier shape × depth × wrapper. Shapes: `fire` (the record fires beside the plain definition),
# `quiet` (it does not: one survivor), `clash` (it fires and writes the plain definition's keys: the
# priority cells), and `body` (the marker sits in the fired RECORD's body rather than the plain
# definition). Depths: `d1`/`d2` nested aspect keys, `c1` a class key, `c2` a scalar in class content.
#
# NOT THE GRID, each stated where it is pinned:
#   · a field whose every definition discharges is KEPT and refused where it is read (T4's lazy field;
#     ADR-0010 §4(a)), where nixpkgs drops it: `test-all-discharged-field-is-kept` here, and the message in
#     ci/tests-error.nix `guard-nested-property`. The grid skips those five cells by name (an `mkIf false`
#     field, `d1` or `c1`, in the plain definition or the record's body).
#   · a top-level priority on the definition itself (depth 0) is discharged by the aspect option before the
#     carrier exists, so it is outside this law; this unit leaves it as it was.
#   · a module function at a nested key is a typed position (route (a), den-hoag-3849t), not content; a
#     priority over one is ci/tests-error.nix `guard-nested-property`'s override refusal.
#   · survivors that are not all plain attrsets (a scalar body at a freeform field, as gen-demo's corpus
#     writes `stitch.trim`; a construction carrying `__mint`) take `anything` whole:
#     `test-scalar-survivors-*`, `test-minted-survivor-*` here, the mixed refusal in the error plane.
#
# RED: gen-merge's `anything` reverted (the marker as data in 60+ cells); the one-survivor short-circuit
# restored in lib/guard.nix (every `quiet` cell carrying a marker).
{
  lib,
  aspects,
  mkSchemaEval,
  genMerge,
  ...
}:
let
  np = lib;
  gv = aspects.mkGuardVocab { };
  try =
    v:
    let
      r = builtins.tryEval (builtins.deepSeq v v);
    in
    if r.success then r.value else "THROWS";
  fires.thimble.name = "cortex";
  quiet.thimble.name = "vault";
  rec_ = body: { config.aspects.main = gv.vocab.whenEq [ "thimble" "name" ] "cortex" body; };
  plain = v: { config.aspects.main = v; };
  # each wrapper, written with constructor set `L`
  W = L: {
    ifFalse = L.mkIf false;
    ifTrue = L.mkIf true;
    merge =
      v:
      L.mkMerge [
        v
        { classOne.m = "M"; }
      ];
    force = L.mkForce;
    default = L.mkDefault;
    before = L.mkBefore;
  };
  D = {
    d1 = w: { sub = w { classTwo.s = "S"; }; };
    d2 = w: { sub.sub2 = w { classTwo.s = "S"; }; };
    c1 = w: { classTwo = w { s = "S"; }; };
    c2 = w: { classTwo.s = w "S"; };
  };
  # each shape's record body and plain definition, the wrapped value placed by `x`
  S = {
    fire = {
      ctx = fires;
      rb = _: { classTwo.r = "R"; };
      pl = x: x;
    };
    quiet = {
      ctx = quiet;
      rb = _: { classTwo.r = "R"; };
      pl = x: x;
    };
    clash = {
      ctx = fires;
      rb = _: {
        classTwo.s = "R";
        sub.classTwo.s = "R";
        sub.sub2.classTwo.s = "R";
      };
      pl = x: x;
    };
    body = {
      ctx = fires;
      rb = x: x;
      pl = _: { classOne.p = "P"; };
    };
  };
  carrier =
    s: d: w:
    let
      x = D.${d} (W genMerge).${w};
    in
    gv.applyGuard S.${s}.ctx
      (mkSchemaEval {
        modules = [
          (rec_ (S.${s}.rb x))
          (plain (S.${s}.pl x))
        ];
      }).config.aspects.main;
  reference =
    s: d: w:
    let
      x = D.${d} (W np).${w};
    in
    np.types.anything.merge [ "main" ] (
      map (v: {
        file = "f";
        value = v;
      }) ((if s == "quiet" then [ ] else [ (S.${s}.rb x) ]) ++ [ (S.${s}.pl x) ])
    );
  # T4's lazy field, where nixpkgs drops the key: pinned below and in the error plane
  kept = [
    "fire-d1-ifFalse"
    "quiet-d1-ifFalse"
    "quiet-c1-ifFalse"
    "body-d1-ifFalse"
    "body-c1-ifFalse"
  ];
  grid = lib.listToAttrs (
    lib.concatMap (
      s:
      lib.concatMap (
        d:
        lib.concatMap (
          w:
          let
            n = "${s}-${d}-${w}";
          in
          lib.optional (!(builtins.elem n kept)) {
            name = "test-${n}";
            value = {
              expr = try (carrier s d w);
              expected = try (reference s d w);
            };
          }
        ) (builtins.attrNames (W np))
      ) (builtins.attrNames D)
    ) (builtins.attrNames S)
  );
  fireMain =
    ctx: defs: gv.applyGuard ctx (mkSchemaEval { modules = map plain defs; }).config.aspects.main;
in
{
  flake.tests.guard-nested-property = grid // {
    # The grid's subject cells, as literals, so a reader sees the value without running the reference.
    # n4f's shape: an `mkIf false` two keys down is discharged, and its parent stays.
    test-mkif-false-content-is-not-served = {
      expr = carrier "fire" "d2" "ifFalse";
      expected = {
        classTwo.r = "R";
        sub = { };
      };
    };
    # one survivor takes the law: the marker is discharged, not carried
    test-one-survivor-discharges = {
      expr = carrier "quiet" "d1" "ifTrue";
      expected.sub.classTwo.s = "S";
    };
    # a priority at a nested key ranges over the fired record's content: `mkForce` beats the record's
    # `R`, `mkDefault` loses to it
    test-nested-priority-ranges-over-the-fired-record = {
      expr = {
        force = (carrier "clash" "d1" "force").sub.classTwo.s;
        default = (carrier "clash" "d1" "default").sub.classTwo.s;
      };
      expected = {
        force = "S";
        default = "R";
      };
    };
    # mkOrder on a list across the record and the plain definition: F1(b)'s concatenation, ordered as
    # the module system orders it (nixpkgs' `anything` refuses two lists, so this one is a literal)
    test-order-across-the-record-and-the-plain-definition = {
      expr = fireMain fires [
        (gv.vocab.whenEq [ "thimble" "name" ] "cortex" { classTwo.l = [ "R" ]; })
        { classTwo.l = genMerge.mkBefore [ "S" ]; }
      ];
      expected.classTwo.l = [
        "S"
        "R"
      ];
    };
    # The kept field: present in the key set, and its sibling reads beside it (per-field laziness).
    test-all-discharged-field-is-kept = {
      expr = {
        keys = builtins.attrNames (carrier "fire" "d1" "ifFalse");
        sibling = (carrier "fire" "d1" "ifFalse").classTwo.r;
      };
      expected = {
        keys = [
          "classTwo"
          "sub"
        ];
        sibling = "R";
      };
    };
    # The value-kind axis: a marker that is a LIST ELEMENT is content, not a definition, and is carried
    # on both engines.
    test-list-element-marker-is-carried-as-nixpkgs-carries-it = {
      expr = try (
        fireMain quiet [
          (gv.vocab.whenEq [ "thimble" "name" ] "cortex" { classTwo.r = "R"; })
          { classTwo.l = [ (genMerge.mkIf false "x") ]; }
        ]
      );
      expected = {
        classTwo.l = [
          {
            _type = "if";
            condition = false;
            content = "x";
          }
        ];
      };
    };
    # A guard over a SCALAR at a freeform field, written twice (the corpus's `stitch.trim`): the firing
    # survivor is served, and two firing equal scalars agree. RED (the field level applied to every
    # survivor list): refused as definitions `lazyAttrsOf' cannot consume.
    test-scalar-survivors-take-anything = {
      expr =
        let
          trim =
            ctx: a: b:
            gv.applyGuard ctx
              (mkSchemaEval {
                modules = [
                  { config.aspects.main.trim = a; }
                  { config.aspects.main.trim = b; }
                ];
              }).config.aspects.main.trim;
        in
        {
          one = trim fires (gv.vocab.whenEq [ "thimble" "name" ] "cortex" "piping") (
            gv.vocab.whenEq [ "thimble" "name" ] "damask" "lace"
          );
          equal = trim fires (gv.vocab.always "piping") (gv.vocab.always "piping");
        };
      expected = {
        one = "piping";
        equal = "piping";
      };
    };
    # A construction (an attrset carrying `__mint`) is carried WHOLE, as `anything` carries it, and not
    # rebuilt through the field level: its marker-shaped key is data of the construction and survives.
    # RED (the field level applied to it): `sub` discharged, kept, and refused where it is read.
    test-minted-survivor-carried-whole = {
      expr =
        try
          (fireMain quiet [
            (gv.vocab.whenEq [ "thimble" "name" ] "cortex" { classTwo.r = "R"; })
            {
              __mint = "m";
              sub = genMerge.mkIf false 1;
            }
          ]).sub;
      expected = {
        _type = "if";
        condition = false;
        content = 1;
      };
    };
    # LIVE CONTROL: no marker, the guard fires; served alike before and after
    test-control-no-marker = {
      expr = fireMain fires [
        (gv.vocab.whenEq [ "thimble" "name" ] "cortex" { classTwo.r = "R"; })
        { sub.classTwo.s = "S"; }
      ];
      expected = {
        classTwo.r = "R";
        sub.classTwo.s = "S";
      };
    };
  };
}
