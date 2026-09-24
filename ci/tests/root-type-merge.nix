# `aspectsRoot`'s TYPE-MERGE relation (den-hoag-a0gc) — before this fix, `aspectsRootWith` supplied
# no `functor` of its own, so the protocol's own default applied: a descriptor that states no
# relation merges any two same-named operands UNCONDITIONALLY — two `aspectsRoot` declarations
# typeMerged on the CONTAINER'S NAME ALONE, blind to their elements, the silent-collision shape
# den-hoag-k1uv named one layer down (gen-types' name-only `__id`, since fixed there).
#
# ★ WHAT THE FIX RESTS ON, AND IT IS A PROPERTY OF THE DEPENDENCY: gen-merge HONOURS A CALLER'S
# STATED `functor.binOp` (the owner's 2026-09-08 fork-1 ruling). `importType` RETAINS the relation
# an author states — `statesRelation` keys on `functor.binOp` precisely because that asks what the
# author said rather than which library built the record — and `exportType` republishes it, so the
# relation stated here is the one a foreign engine reads back. `protoTypeMerge` is the combinator
# that relation is read through. THAT is the sentence a future pin bump must be checked against;
# the pin itself is the lock's to state, never a comment's.
#
# The shape is the "elemTypeFunctor pattern": `payload` carries the element type, `binOp` asks
# whether two elements merge, and `type` rebuilds the container over the merged element. This suite
# calls `.typeMerge` directly (the real protocol hook `evalModuleTree` itself would call), never a
# hand-rolled stand-in.
#
# ★ HONEST SCOPE, MEASURED NOT ASSUMED: `aspectType` itself (gen-aspects' element type) answers
# every partner named `"aspect"` with a merge — its own functor carries no payload either (it does
# not customise `functor`), so its `typeMerge` is the SAME name-only nixpkgs default. Two
# `aspectsRoot`s built over DIFFERING `keySemantics` therefore still merge after this fix
# (`test-differing-cnf-same-element-name-still-merges` below) — the bead's literal witness is NOT
# discharged by this change, and giving `aspectType` a cnf-sensitive functor would be a NEW merge
# semantics (what does "these two cnfs merge" mean — deep equality? a minted digest over the
# vocabulary, k1uv-style?), which is its own design fork and out of this fix's scope. What IS
# discharged, and is the actual defect this bead named — the container's functor carrying no
# payload at all, so it could not discriminate on ANYTHING — is measured directly by the two
# refusal cells below: a partner sharing the name but not the element now REFUSES, where before the
# container never looked past its own name.
{
  lib,
  aspects,
  genMerge,
  ...
}:
let
  t = genMerge.types;
  cnf1 = {
    keySemantics = {
      a = {
        category = "class";
      };
    };
  };
  cnf2 = {
    keySemantics = {
      b = {
        category = "class";
      };
    };
  };
  root1 = aspects.aspectsRoot cnf1;
  root1b = aspects.aspectsRoot cnf1;
  root2 = aspects.aspectsRoot cnf2;

  verdict = v: if v == null then "REFUSED" else "MERGED:${v.name or "?"}";

  # `aspectsRoot` over any element, through the public surface: the functor's `type` IS
  # `aspectsRootWith`. `nt` are FOREIGN (nixpkgs) types, whose own `typeMerge` joins `port ∥ int` to
  # bare `int` — the shape the element join must not take on the element's word.
  rootWith = root1.functor.type;
  nt = lib.types;
  nsub = nt.submodule { options.x = lib.mkOption { type = nt.int; }; };
  # Declares `p` once per type, defines `val`, and reads the merged type and whether `val` passed.
  ev =
    tys: val:
    let
      res = genMerge.evalModuleTree {
        modules = map (ty: { options.p = genMerge.mkOption { type = ty; }; }) tys ++ [ { p = val; } ];
      };
      ty = builtins.tryEval (builtins.deepSeq res.options.p.type.name res.options.p.type.name);
      v = builtins.tryEval (builtins.deepSeq res.config.p res.config.p);
    in
    if ty.success then
      "MERGED ${ty.value} / ${if v.success then "ACCEPTED" else "REJECTED"}"
    else
      "REFUSED";
in
{
  # The functor `aspectsRoot` exported before this fix carried `payload = null` unconditionally
  # (the nixpkgs default for a descriptor with no `.functor` of its own) — indistinguishable from a
  # type that carries no element at all. The control (`t.str`, an ordinary leaf) shows that same
  # null-payload baseline; `aspectsRoot`'s payload now names its element by contrast.
  flake.tests.root-type-merge.test-functor-payload-carries-the-element = {
    expr = {
      payloadName = root1.functor.payload.name or "ABSENT";
      ctlLeafPayload = t.str.functor.payload or "ABSENT";
    };
    expected = {
      payloadName = "aspect";
      ctlLeafPayload = null;
    };
  };

  # THE CONTROL the dispatch requires alongside any refusal cell: two SEPARATELY-BUILT declarations
  # over the IDENTICAL construction must still merge to one, same run as the refusals below —
  # otherwise a "fix" that merely refuses everything would pass the refusal cells vacuously.
  flake.tests.root-type-merge.test-control-identical-declarations-still-merge = {
    expr = verdict (root1.typeMerge root1b.functor);
    expected = "MERGED:aspectsRoot";
  };

  # ★ THIS CELL ASSERTS THE DEPENDENCY'S BEHAVIOUR, NOT THIS LIBRARY'S — named for whose guard it
  # is, in the same register as the honest-scope cell below. A partner carrying neither `type` nor
  # `payload` never reaches this container's `binOp` at all: gen-merge's `importedPartner`
  # (`lib/interface.nix`) returns null for a functor with no `type`, and `protoTypeMerge` refuses on
  # payload asymmetry one clause earlier. BOTH refusals are the boundary's. It is kept rather than
  # deleted because that boundary property is exactly what the `type` key in the cell above depends
  # on — delete this and the record of why that key is there goes with it (den-hoag-a0gc report §2).
  flake.tests.root-type-merge.test-boundary-refuses-an-incomplete-partner-before-this-relation = {
    expr = verdict (
      root1.typeMerge {
        name = "aspectsRoot";
      }
    );
    expected = "REFUSED";
  };

  # A partner named "aspectsRoot" whose payload is a GENUINELY different, non-merging element type
  # (`t.str`, named "str" — `aspectType`'s own functor-derived typeMerge refuses anything not named
  # "aspect"). This is the mechanism the elemTypeFunctor `binOp` exists for: the container defers to
  # whatever the element's own `typeMerge` decides, and here that decision is refusal.
  flake.tests.root-type-merge.test-refuses-a-partner-whose-element-does-not-merge = {
    expr = verdict (
      root1.typeMerge {
        name = "aspectsRoot";
        payload = t.str;
      }
    );
    expected = "REFUSED";
  };

  # A second `aspectsRoot` DECLARATION over a genuinely different element, in the shape the foreign
  # protocol actually hands over. `protoTypeMerge` (gen-merge `lib/interface.nix`) APPLIES
  # `functor.type` to recover the partner TYPE, so a partner without one is refused by the boundary
  # before this container's `binOp` is ever consulted — which is why the two partner shapes above
  # cannot fail on a defect in this library (den-hoag-a0gc report §2).
  flake.tests.root-type-merge.test-refuses-a-well-formed-partner-over-a-different-element = {
    expr = verdict (
      root1.typeMerge {
        name = "aspectsRoot";
        payload = t.str;
        type = _: root1;
      }
    );
    expected = "REFUSED";
  };

  # ★ HONEST SCOPE (see file header): `aspectType`'s own functor does not discriminate on `cnf`, so
  # two `aspectsRoot`s over differing `keySemantics` still merge. Recorded as a PASSING assertion of
  # CURRENT, MEASURED behaviour — not a TODO and not silently dropped — so a future change to
  # `aspectType`'s functor that starts refusing this pair reds this cell instead of silently
  # changing behaviour unnoticed.
  flake.tests.root-type-merge.test-differing-cnf-same-element-name-still-merges = {
    expr = verdict (root1.typeMerge root2.functor);
    expected = "MERGED:aspectsRoot";
  };

  # den-hoag-plm1h: the element join is gen-merge's `mergeTypes`, so the check-family witness judges
  # it. Asking the element's own foreign `typeMerge` joined `port ∥ int` to `int` and accepted 70000
  # for a `port`, in either order.
  flake.tests.root-type-merge.test-an-element-join-that-drops-a-check-refuses = {
    expr = {
      portInt = ev [ (rootWith nt.port) (rootWith nt.int) ] { a = 70000; };
      intPort = ev [ (rootWith nt.int) (rootWith nt.port) ] { a = 70000; };
    };
    expected = {
      portInt = "REFUSED";
      intPort = "REFUSED";
    };
  };

  # CONTROL, same run: a redeclaration over the SAME element still merges (0lq9s: refusing every
  # self-redeclaration was the regression), and its element's check still runs. `portRejects` is
  # also a red arm: the foreign `port ∥ port` join is bare `int`, so the old path accepted 70000.
  flake.tests.root-type-merge.test-control-a-self-redeclared-element-still-merges = {
    expr = {
      port = ev [ (rootWith nt.port) (rootWith nt.port) ] { a = 80; };
      portRejects = ev [ (rootWith nt.port) (rootWith nt.port) ] { a = 70000; };
      submodule = ev [ (rootWith nsub) (rootWith nsub) ] { a.x = 1; };
      aspect = ev [ root1 root1b ] { foo = { }; };
    };
    expected = {
      port = "MERGED aspectsRoot / ACCEPTED";
      portRejects = "MERGED aspectsRoot / REJECTED";
      submodule = "MERGED aspectsRoot / ACCEPTED";
      aspect = "MERGED aspectsRoot / ACCEPTED";
    };
  };
}
