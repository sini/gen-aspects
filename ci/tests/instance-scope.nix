# An instance carries its instantiation scope (den-hoag-ohvjc; specs/2026-10-03-gen-aspects-
# application-memo-spec.md §3a). A door node left unfired in an instance's entry, its condition needing
# a key the instance's context lacks, is fired later through `instanceOf` handed that instance's
# `scope`, and reads its closure there instead of re-applying the outer. The door is
# `ci/fixtures/scope-door.nix`: the poisoned door throws on any re-application of the outer closure,
# so a firing that takes the fallback throws, and one that reads the scope does not. The unscoped
# arm's throw text is pinned on the error plane (`ci/tests-error.nix`, `instance-scope`).
{
  aspects,
  mkSchemaEval,
  genAlgebra,
  genIdentity,
  ...
}:
let
  a = aspects;
  T = genAlgebra.term genIdentity.hashIdentity;
  sd = import ../fixtures/scope-door.nix { inherit aspects T; };
  ok = v: (builtins.tryEval (builtins.deepSeq v true)).success;
  src = n: "entity:" + builtins.hashString "sha256" n;
  kinds.entityKinds = {
    thimble = true;
    bobbin = true;
  };
  cnfOf = depth: poison: kinds // { ref = sd.door depth poison; };
  bobbins = [
    "u0"
    "u1"
    "u2"
  ];
  # The outer instance at `{ thimble = host; }`, fired through the real door.
  outerAt =
    depth: host:
    a.instanceOf (cnfOf depth false) {
      aspect = "outer";
      value = sd.outerNode depth;
      context.thimble = host;
      sources.thimble = src host;
    };
  # The deferred inner node in an outer instance's entry: the outer's include at depth 1, the mid's
  # (fired in place, its condition holding at `{ thimble }`) at depth 2.
  innerOf =
    depth: o:
    let
      first = builtins.head o.entry.includes;
    in
    if depth == 1 then first else builtins.head first.includes;
  # The deferred inner of `o` (an outer instance at `host`) fired at `bobbin`, handed `scope`.
  innerAt =
    depth: poison: o: host: scope: bobbin:
    (a.instanceOf (cnfOf depth poison) {
      aspect = "inner";
      value = innerOf depth o;
      context = {
        thimble = host;
        inherit bobbin;
      };
      sources = {
        thimble = src host;
        bobbin = src bobbin;
      };
      inherit scope;
    }).entry;
  # G1 at one depth: the inner fired at three bobbins through the POISONED door. Handed the outer's
  # scope it reads its closure there (no throw); handed none it takes the fallback, which throws.
  g1 =
    depth:
    let
      o = outerAt depth "h0";
    in
    {
      scoped = map (b: (innerAt depth true o "h0" o.scope b).description) bobbins;
      unscopedThrows = map (b: !(ok (innerAt depth true o "h0" { } b))) bobbins;
    };
in
{
  flake.tests.instance-scope = {
    # G1, depth 1. RED (no scope plumbing: `instanceOf` refuses the `scope` field, or the firing hands
    # the door no `captured`): `scoped` throws the poisoned outer's text.
    test-deferred-node-reads-scope = {
      expr = g1 1;
      expected = {
        scoped = [
          "inner@h0/u0"
          "inner@h0/u1"
          "inner@h0/u2"
        ];
        unscopedThrows = [
          true
          true
          true
        ];
      };
    };
    # G1, depth 2 (gate C1): the mid node fires IN PLACE inside the outer's firing, and its own door
    # returns the inner's closure. RED (the instance's scope is the top door's only, the nested
    # firing's dropped): `scoped` throws, the fallback re-applying the mid and so the outer.
    test-deferred-node-reads-scope-depth-2 = {
      expr = g1 2;
      expected = {
        scoped = [
          "inner@h0/u0"
          "inner@h0/u1"
          "inner@h0/u2"
        ];
        unscopedThrows = [
          true
          true
          true
        ];
      };
    };
    # The scope path itself (gate C2), through the unpoisoned door, at depth 2: the inner of the outer at
    # h1 fired with h1's scope reads it (`via = "scope"`); with h0's scope, whose keys are h0's nested
    # identifiers, and with none, it takes the fallback (`via = "reapply"`), and all three values are
    # equal (G2). RED (no scope plumbing): `right` reads "reapply".
    test-scope-path-and-wrong-key = {
      expr =
        let
          o0 = outerAt 2 "h0";
          o1 = outerAt 2 "h1";
          at = scope: innerAt 2 false o1 "h1" scope "u0";
        in
        {
          via = map (s: (at s).via) [
            o1.scope
            o0.scope
            { }
          ];
          values = map (s: (at s).description) [
            o1.scope
            o0.scope
            { }
          ];
        };
      expected = {
        via = [
          "scope"
          "reapply"
          "reapply"
        ];
        values = [
          "inner@h1/u0"
          "inner@h1/u0"
          "inner@h1/u0"
        ];
      };
    };
    # G3, the PRE-EXISTING door guard (gate C2): h0's inner fired at host h1 is refused by the door's
    # source check, which reads the nested identifier's recorded sources before `captured`, so the
    # outcome is the same whichever scope is handed. It pins the guard, not the scope path.
    test-rebound-refused-whichever-scope = {
      expr =
        let
          o0 = outerAt 2 "h0";
          at =
            scope:
            ok
              (a.instanceOf (cnfOf 2 false) {
                aspect = "inner";
                value = innerOf 2 o0;
                context = {
                  thimble = "h1";
                  bobbin = "u0";
                };
                sources = {
                  thimble = src "h1";
                  bobbin = src "u0";
                };
                inherit scope;
              }).entry;
        in
        {
          withScope = at o0.scope;
          without = at { };
          control = ok (innerAt 2 false o0 "h0" o0.scope "u0");
        };
      expected = {
        withScope = false;
        without = false;
        control = true;
      };
    };
    # G4: the relation's vertex carries the instance's scope, `instanceOf`'s for the same tuple: at
    # depth 2 the outer's door scope (the mid's identifier) and the mid's in-place firing's (the inner's).
    # RED (the field absent): `attribute 'scope' missing`.
    test-vertex-carries-scope = {
      expr =
        let
          tree =
            (mkSchemaEval (
              kinds
              // {
                modules = [ { config.aspects.o = sd.outerNode 2; } ];
              }
            )).config.aspects;
          r = a.instancesFor (cnfOf 2 false) tree {
            containment = { };
            suppliers.${src "h0"}.thimble = "h0";
            scopes.n = {
              members = [ "o" ];
              sources.thimble = src "h0";
            };
          };
          v = r.vertices.${builtins.head r.reaches.n.o};
        in
        {
          same = builtins.attrNames v.scope == builtins.attrNames (outerAt 2 "h0").scope;
          size = builtins.length (builtins.attrNames v.scope);
        };
      expected = {
        same = true;
        size = 2;
      };
    };
  };
}
