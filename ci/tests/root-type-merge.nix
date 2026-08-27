# `aspectsRoot`'s TYPE-MERGE relation (den-hoag-a0gc) — before this fix, `aspectsRootWith` supplied
# no `functor` of its own, so `completeType` (gen-merge lib/types.nix) derived the nixpkgs-default
# `pureDefaultFunctor "aspectsRoot"`: `payload = null`. `pureTypeMerge` merges any two same-named,
# null-payload functors UNCONDITIONALLY — two `aspectsRoot` declarations typeMerged on the
# CONTAINER'S NAME ALONE, blind to their elements, the silent-collision shape den-hoag-k1uv named
# one layer down (gen-types' name-only `__id`, since fixed there).
#
# ★ THE CI PIN, MEASURED NOT ASSUMED: gen-aspects' `ci/flake.lock` pins gen-merge at
# `2701d8bbf5d81ed137ecda3eddfae1241509b728`, a revision that PREDATES `lib/interface.nix`'s
# `carries`/`recarry` gen-native boundary entirely (`git show <rev>:lib/interface.nix` ⇒ no such
# path at that commit). At this revision, `completeType`'s own escape hatch is the nixpkgs-shaped
# `functor = { name; payload; binOp; type; }` field directly — the "elemTypeFunctor pattern" the fix
# implements: `payload` carries the element type, `binOp` asks whether two elements merge, and
# `type` rebuilds the container over the merged element. `typeMerge` is then AUTO-DERIVED from that
# functor by `pureTypeMerge` — this suite calls `.typeMerge` directly (the real protocol hook
# `evalModuleTree` itself would call), never a hand-rolled stand-in.
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

  # A partner merely NAMED "aspectsRoot" with no payload of its own (`functor.payload` absent, the
  # nixpkgs-default shape). Under the pre-fix behaviour (own functor also null-payload) this
  # silently MERGED — literally any same-named functor did, element or no. It now refuses: the
  # container's `binOp` sees a `null` partner payload and refuses rather than picking one side.
  flake.tests.root-type-merge.test-refuses-a-same-named-partner-with-no-element = {
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

  # ★ HONEST SCOPE (see file header): `aspectType`'s own functor does not discriminate on `cnf`, so
  # two `aspectsRoot`s over differing `keySemantics` still merge. Recorded as a PASSING assertion of
  # CURRENT, MEASURED behaviour — not a TODO and not silently dropped — so a future change to
  # `aspectType`'s functor that starts refusing this pair reds this cell instead of silently
  # changing behaviour unnoticed.
  flake.tests.root-type-merge.test-differing-cnf-same-element-name-still-merges = {
    expr = verdict (root1.typeMerge root2.functor);
    expected = "MERGED:aspectsRoot";
  };
}
