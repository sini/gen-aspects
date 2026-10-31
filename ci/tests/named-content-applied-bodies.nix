# NAMED CONTENT IN AN APPLIED BODY IS ONE NODE PER CLASS (den-hoag-named-include-instance-bodies-sfkyy;
# identity design 2026-09-30 §2, Q5 "yes").
#
# A named value in an instance's fired body is a sighting at its §2 key like a static one. The
# sightings are classed across EVERY vertex of the relation, with the static classes as the frozen
# prior: a sighting the rung identifies with a static class joins it, and only the rest form classes of
# their own, so no static id depends on an instance (ADR-0016 r7; ADR-0033).
#
# Each cell carries the arm that discriminates it: the `RED` comment names the edit that turns it.
{
  lib,
  mkSchemaEval,
  aspects,
  genIdentity,
  genAlgebra,
  ...
}:
let
  tryValue =
    v:
    let
      r = builtins.tryEval (builtins.deepSeq v v);
    in
    if r.success then r.value else "REFUSED";
  inherit (aspects) guard pred;
  entity = n: genIdentity.hashIdentity "entity" [ "name" ] (_: n);
  marked = m: { T.marks = [ m ]; };
  # `hosts` maps a host to its members; each host is its own entity binding `host`. `t.<host>.<member>`
  # is the include-site targets of the instance the host reaches for that member.
  run =
    defs: hosts:
    let
      as =
        (mkSchemaEval {
          fixtureKeySemantics.T.category = "class";
          modules = [ { config.aspects = defs; } ];
        }).config.aspects;
      rel =
        aspects.instancesFor { } as
          {
            suppliers = lib.mapAttrs' (h: _: lib.nameValuePair (entity h) { host = h; }) hosts;
            containment = { };
          }
          (
            lib.mapAttrs (h: ms: {
              members = ms;
              sources.host = entity h;
            }) hosts
          );
      at = aspects.includeSitesOfInstance { } as rel;
      f = aspects.graphFacts { } as;
    in
    {
      inherit f at rel;
      t = lib.mapAttrs (
        h: ms:
        lib.genAttrs (builtins.filter (m: rel.reaches.${h} ? ${m}) ms) (
          m: map (s: s.target or "<none>") (at (builtins.head rel.reaches.${h}.${m}))
        )
      ) hosts;
      inner =
        h: m: map (s: map (x: x.target or "<none>") s.sites) (at (builtins.head rel.reaches.${h}.${m}));
    };
  # Total over a RED arm: an absent target reads `<none>`, never an abort.
  first = l: if builtins.isList l && l != [ ] then builtins.head l else "<none>";
  bare = n: id: builtins.match "@/includes/${n}@[^/]*" id != null;
  suffixed = n: id: builtins.match "@/includes/${n}@[^/]*/.+" id != null;
  inApplied = id: lib.hasPrefix "aspect-instance:" id;
  g = body: guard (pred.has "host") body;

  tmux = {
    name = "tmux";
    T.marks = [ "tmux" ];
  };
  # A factory: its `name` sits at one source position however often it is called.
  mk = m: {
    name = "t";
    T.marks = [ m ];
  };
  lit = marked "lit";
  # §4 row 4's second shape: a named value with a cyclic unnamed sub-value, distinct per call.
  cyc =
    _:
    let
      m = {
        self = m;
        v = 1;
      };
    in
    m;
  mkc = inc: {
    name = "c";
    T.marks = [ "c" ];
    meta = cyc 0;
    includes = inc;
  };
  mke = inc: {
    name = "e";
    T.marks = [ "e" ];
    extra = cyc 0;
    includes = inc;
  };
  mkq = c: {
    name = "q";
    T.marks = [ "q" ];
    meta = if c then cyc 0 else 1;
  };
  tf = m: {
    name = "tf";
    T.marks = [ m ];
  };
  # `y`'s include-site targets, each host's value reached two ways: a handed relation (one vertex per
  # host, its body the value) and `instancesFor`'s context route (one guard including the host's
  # context value, so the value is the instance's fired body).
  readY =
    vals:
    let
      as =
        (mkSchemaEval {
          fixtureKeySemantics.T.category = "class";
          modules = [
            {
              config.aspects.g = g {
                includes = [ ((genAlgebra.term genIdentity.hashIdentity).term.readCtx "host" [ ]) ];
              };
            }
          ];
        }).config.aspects;
      rel =
        aspects.instancesFor { } as
          {
            suppliers = lib.mapAttrs' (h: v: lib.nameValuePair (entity h) { host = v; }) vals;
            containment = { };
          }
          (
            lib.mapAttrs (h: _: {
              members = [ "g" ];
              sources.host = entity h;
            }) vals
          );
      targets = r: iid: map (s: s.target) (aspects.includeSitesOfInstance { } as r iid);
    in
    {
      handed = targets { vertices = lib.mapAttrs (_: v: { entry.includes = [ v ]; }) vals; } "y";
      ctx = targets rel (builtins.head rel.reaches.y.g);
    };
in
{
  # S1 (the premise). One named value in applied bodies is ONE node: one guard reached by two hosts,
  # two guards reached by one host, and a guard beside a static taker, whose class the applied sighting
  # joins (a `graphFacts` node). RED (base): REFUSED, the classifier takes no relation; mutant
  # applied-per-instance (no applied sighting is named): `aspect-instance:<iid>/includes/0` per instance.
  flake.tests.named-content-applied-bodies.test-one-value-in-applied-bodies-is-one-node =
    let
      hostsTwo = run { a = g { includes = [ tmux ]; }; } {
        x = [ "a" ];
        y = [ "a" ];
      };
      guardsTwo =
        run
          {
            a = g { includes = [ tmux ]; };
            b = g { includes = [ tmux ]; };
          }
          {
            x = [
              "a"
              "b"
            ];
          };
      withStatic =
        run
          {
            s.includes = [ tmux ];
            a = g { includes = [ tmux ]; };
          }
          {
            x = [
              "s"
              "a"
            ];
          };
      one =
        r: h: m:
        first r.t.${h}.${m};
    in
    {
      expr = tryValue {
        hostsTwo = one hostsTwo "x" "a" == one hostsTwo "y" "a" && bare "tmux" (one hostsTwo "x" "a");
        guardsTwo = one guardsTwo "x" "a" == one guardsTwo "x" "b" && bare "tmux" (one guardsTwo "x" "a");
        joinsStatic =
          one withStatic "x" "a" == first withStatic.f.includesOf.s
          && withStatic.f.nodeData ? ${one withStatic "x" "a"};
      };
      expected = {
        hostsTwo = true;
        guardsTwo = true;
        joinsStatic = true;
      };
    };

  # S2. What keeps two apart, and the static id never moves. A factory's two contents in two guards are
  # two classes, each in the several-classes form; a static sighting and an applied one with different
  # content at one §2 key: the static class keeps its bare id (the one `graphFacts` publishes with no
  # relation at all) and the applied class takes the several-classes form, so they never collide; an
  # unnamed literal in applied bodies stays one node per instance (Q1; design §3 Content). RED mutant
  # applied-without-prior (the applied sightings classed with no static prior): the applied class takes
  # the bare id the static class holds, `apart` false.
  flake.tests.named-content-applied-bodies.test-what-keeps-applied-sightings-apart =
    let
      factory =
        run
          {
            a = g { includes = [ (mk "f1") ]; };
            b = g { includes = [ (mk "f2") ]; };
          }
          {
            x = [
              "a"
              "b"
            ];
          };
      mixed =
        run
          {
            s.includes = [ (mk "static") ];
            a = g { includes = [ (mk "applied") ]; };
          }
          {
            x = [
              "s"
              "a"
            ];
          };
      unnamed = run { a = g { includes = [ lit ]; }; } {
        x = [ "a" ];
        y = [ "a" ];
      };
      fa = first factory.t.x.a;
      fb = first factory.t.x.b;
      st = first mixed.f.includesOf.s;
      ap = first mixed.t.x.a;
    in
    {
      expr = tryValue {
        factory = fa != fb && suffixed "t" fa && suffixed "t" fb;
        staticBare = bare "t" st;
        apart = ap != st && suffixed "t" ap && !(mixed.f.nodeData ? ${ap});
        unnamedPerInstance = first unnamed.t.x.a != first unnamed.t.y.a && inApplied (first unnamed.t.x.a);
      };
      expected = {
        factory = true;
        staticBare = true;
        apart = true;
        unnamedPerInstance = true;
      };
    };

  # S3. Content inside an applied class is shared (F10): the literal a named value holds is ONE node
  # under the class whichever instance reaches it. RED mutant per-sighting (content in a class keyed by
  # its own address): one inner id per instance.
  flake.tests.named-content-applied-bodies.test-content-inside-an-applied-class-is-shared =
    let
      holder = tmux // {
        includes = [ (marked "inl") ];
      };
      r = run { a = g { includes = [ holder ]; }; } {
        x = [ "a" ];
        y = [ "a" ];
      };
      cls = first r.t.x.a;
    in
    {
      expr = tryValue {
        same = r.inner "x" "a" == r.inner "y" "a";
        underClass = r.inner "x" "a" == [ [ "${cls}/includes/0" ] ];
      };
      expected = {
        same = true;
        underClass = true;
      };
    };

  # S4. A value reached again inside itself never enters the applied classes: its spine is infinite, so
  # the depth budget refuses it by name inside the vertex's own enumeration, the vertex contributes no
  # sighting, and it reads as it did before this unit (its content keyed under the instance, its deep
  # read refused by name). Its neighbour reads. A guard refuses a cyclic body by name (`guard-depth`,
  # `lit-payload-budget`), so the vertices are handed. RED the spine cut at a back edge decided by the
  # rung (the static `recsFrom`'s): `v1` names a class.
  flake.tests.named-content-applied-bodies.test-an-applied-cycle-enters-no-class =
    let
      loop = {
        name = "loop";
        T.marks = [ "loop" ];
        includes = [ loop ];
      };
      as =
        (mkSchemaEval {
          fixtureKeySemantics.T.category = "class";
          modules = [ { config.aspects.s = { }; } ];
        }).config.aspects;
      at = aspects.includeSitesOfInstance { } as {
        vertices = {
          v1.entry.includes = [ loop ];
          good.entry.includes = [ tmux ];
        };
      };
    in
    {
      expr = {
        shallow = map (s: s.target or "<none>") (at "v1");
        deep = tryValue (at "v1");
        good = tryValue (map (s: bare "tmux" s.target) (at "good"));
      };
      expected = {
        shallow = [ "v1/includes/0" ];
        deep = "REFUSED";
        good = [ true ];
      };
    };

  # S5. A vertex whose `includes` refuses, at any depth, refuses where it is read, never for another
  # vertex: the classes are computed over every vertex, so a refusal there would otherwise reach every
  # reader. RED mutant unguarded-vertex (the vertex's `includes` read without `tryEval`): `good`
  # REFUSED; RED a guard on the top-level `includes` only: `good` REFUSED by the nested throw.
  flake.tests.named-content-applied-bodies.test-a-refusing-vertex-stays-local =
    let
      as =
        (mkSchemaEval {
          fixtureKeySemantics.T.category = "class";
          modules = [ { config.aspects.s = { }; } ];
        }).config.aspects;
      at = aspects.includeSitesOfInstance { } as {
        vertices = {
          bad.entry.includes = throw "bad-vertex";
          nested.entry.includes = [
            {
              name = "tn";
              includes = throw "nested-vertex";
            }
          ];
          good.entry.includes = [ tmux ];
        };
      };
    in
    {
      expr = {
        good = tryValue (map (s: bare "tmux" s.target) (at "good"));
        bad = tryValue (at "bad");
        nested = tryValue (at "nested");
      };
      expected = {
        good = [ true ];
        bad = "REFUSED";
        nested = "REFUSED";
      };
    };

  # S6. The classifier is the one reader of a vertex's entry: a vertex with none has no sites, as
  # gen-delivery read it before the classifier took the relation. RED the entry read with no
  # default: the vertex's read aborts.
  flake.tests.named-content-applied-bodies.test-a-vertex-without-an-entry-has-no-sites =
    let
      as =
        (mkSchemaEval {
          fixtureKeySemantics.T.category = "class";
          modules = [ { config.aspects.s = { }; } ];
        }).config.aspects;
      at = aspects.includeSitesOfInstance { } as {
        vertices = {
          empty = { };
          good.entry.includes = [ tmux ];
        };
      };
    in
    {
      expr = {
        empty = at "empty";
        good = map (s: bare "tmux" s.target) (at "good");
      };
      expected = {
        empty = [ ];
        good = [ true ];
      };
    };

  # S7–S9. A §4 row 4 pair (two distinct named values whose content contains a cycle; here an unnamed
  # cyclic sub-value, the design's second shape) aborts the readers whose answer needs that comparison,
  # and no other: `y` holds no sighting the pair is compared with. Each arm is its own relation, and
  # only `y` is read. Aborts are uncatchable, so a RED arm ends the run.
  #   S7: the pair on two vertices (`x`, `z`); on one vertex's ancestor chain (`x`); and a sighting at
  #       `y`'s key below the pair, when that key holds one class. RED the spine's descent decided by
  #       the rung (v1): the ancestor-chain arms abort `y`.
  #   S8: an applied sighting against a static one at its key (the join). RED the join forced over
  #       every key (v1): `y` aborts.
  #   S9: the pair at `y`'s own key, `y`'s sighting comparing apart from both. RED the classes of a
  #       key partitioned as a whole: `y` aborts.
  flake.tests.named-content-applied-bodies.test-a-row-4-pair-stays-with-its-readers =
    let
      as =
        (mkSchemaEval {
          fixtureKeySemantics.T.category = "class";
          modules = [ { config.aspects.s = { }; } ];
        }).config.aspects;
      read =
        vs:
        map (s: s.target) (
          aspects.includeSitesOfInstance { } as {
            vertices = lib.mapAttrs (_: v: { entry.includes = [ v ]; }) vs;
          } "y"
        );
    in
    {
      expr = {
        twoVertices = map (bare "tmux") (read {
          x = mkc [ ];
          z = mkc [ ];
          y = tmux;
        });
        ancestorChain = map (bare "tmux") (read {
          x = mkc [ (mkc [ ]) ];
          y = tmux;
        });
        belowOneClass = map (bare "tf") (read {
          x = mkc [ (mkc [ (tf "a") ]) ];
          y = tf "a";
        });
      };
      expected = {
        twoVertices = [ true ];
        ancestorChain = [ true ];
        belowOneClass = [ true ];
      };
    };
  flake.tests.named-content-applied-bodies.test-a-row-4-join-stays-with-its-readers =
    let
      as =
        (mkSchemaEval {
          fixtureKeySemantics.T.category = "class";
          modules = [ { config.aspects.st.includes = [ (mke [ ]) ]; } ];
        }).config.aspects;
      at = aspects.includeSitesOfInstance { } as {
        vertices = {
          x.entry.includes = [ (mke [ ]) ];
          y.entry.includes = [ tmux ];
        };
      };
    in
    {
      expr = map (s: bare "tmux" s.target) (at "y");
      expected = [ true ];
    };
  flake.tests.named-content-applied-bodies.test-a-row-4-pair-at-a-key-stays-with-its-members =
    let
      as =
        (mkSchemaEval {
          fixtureKeySemantics.T.category = "class";
          modules = [ { config.aspects.s = { }; } ];
        }).config.aspects;
      at = aspects.includeSitesOfInstance { } as {
        vertices = {
          x.entry.includes = [ (mkq true) ];
          z.entry.includes = [ (mkq true) ];
          y.entry.includes = [ (mkq false) ];
        };
      };
    in
    {
      expr = map (s: suffixed "q" s.target) (at "y");
      expected = [ true ];
    };

  # S10. A sighting written inside a §4 row 4 pair member, at a key holding several classes, is not
  # compared for a reader outside it: an applied class's least site is the sighting's instance-relative
  # address (`<iid>/includes/<i>…`), inside a named value too, so a class key never embeds another
  # (identity design §2 C3, amended for the applied stratum). `y`'s component holds `x`'s inner `tf "a"`,
  # and `z`'s `tf "b"` makes key `tf` hold two classes. RED the least site under the enclosing class
  # (C3's static form): `y`'s id embeds the pair's class key, and `y` aborts.
  flake.tests.named-content-applied-bodies.test-a-sighting-below-a-pair-at-a-several-classes-key-stays-with-its-readers =
    let
      r = readY {
        x = mkc [ (mkc [ (tf "a") ]) ];
        y = tf "a";
        z = tf "b";
      };
    in
    {
      expr = lib.mapAttrs (_: map (suffixed "tf")) r;
      expected = {
        handed = [ true ];
        ctx = [ true ];
      };
    };

  # S11. A `name` is read only by the readers of its position: a §2 key is the name and its position,
  # so a value whose `name` sits at another position is never at a reader's key, whatever the `name`
  # evaluates to. `x`'s `name` is a missing attribute, which `tryEval` cannot catch; in `nested`, `x`
  # also holds `y`'s value, and `z`'s makes key `tf` hold two classes, so `y`'s id is its component's
  # least site, one of which is written inside `x`. RED every applied candidate's `name` forced to key
  # it (the classes grouped by §2 key over every vertex): `y` aborts; RED an applied site that asks
  # whether it has a named ancestor (C3's `encl`): `nested` aborts.
  flake.tests.named-content-applied-bodies.test-a-name-is-read-only-at-its-own-position =
    let
      r = readY {
        x = {
          name = ({ }).nope;
          T.marks = [ "x" ];
        };
        y = tmux;
      };
      nested = readY {
        x = {
          name = ({ }).nope;
          T.marks = [ "x" ];
          includes = [ (tf "a") ];
        };
        y = tf "a";
        z = tf "b";
      };
    in
    {
      expr = lib.mapAttrs (_: map (bare "tmux")) r // {
        nested = lib.mapAttrs (_: map (suffixed "tf")) nested;
      };
      expected = {
        handed = [ true ];
        ctx = [ true ];
        nested = {
          handed = [ true ];
          ctx = [ true ];
        };
      };
    };

  # S12. A key's several classes are keyed by content as `==` decides it: a value the mint takes keys its
  # class by its digest, which follows `==` both ways, and one it cannot take (a lambda) is decided by
  # the rung. `a`'s value is the key's first sighting and apart from the rest, so each other value keys
  # its own class. `intFloat`: `{ v = 1; }` and `{ v = 1.0; }` are `==`, one class; `outPath`: two
  # records sharing an `outPath` with siblings apart are two; `fnShared`: one value holding a lambda,
  # reached twice, is one class; `fnApart`: two values holding their own lambdas are two. RED a digest
  # by `toJSON` (which renders an `outPath` record as that string alone, and a float apart from its
  # integer): `intFloat` and `outPath` false, and `fnShared` aborts uncatchably; RED the mint's
  # remainder keyed as one class: `fnApart` false.
  flake.tests.named-content-applied-bodies.test-several-classes-at-a-key-are-keyed-as-equality-decides =
    let
      as =
        (mkSchemaEval {
          fixtureKeySemantics.T.category = "class";
          modules = [ { config.aspects.s = { }; } ];
        }).config.aspects;
      mkv =
        extra:
        {
          name = "v";
          T.marks = [ "v" ];
        }
        // extra;
      ids =
        b: c:
        let
          at = aspects.includeSitesOfInstance { } as {
            vertices = {
              a.entry.includes = [ (mkv { first = true; }) ];
              b.entry.includes = [ (mkv b) ];
              c.entry.includes = [ (mkv c) ];
            };
          };
          one = v: first (map (s: s.target) (at v));
        in
        {
          same = one "b" == one "c";
          several = suffixed "v" (one "b") && suffixed "v" (one "c");
        };
      fv = mkv { fn = x: x; };
      shared =
        let
          at = aspects.includeSitesOfInstance { } as {
            vertices = {
              a.entry.includes = [ (mkv { first = true; }) ];
              b.entry.includes = [ fv ];
              c.entry.includes = [ fv ];
            };
          };
          one = v: first (map (s: s.target) (at v));
        in
        {
          same = one "b" == one "c";
          several = suffixed "v" (one "b");
        };
    in
    {
      expr = builtins.mapAttrs (_: tryValue) {
        intFloat = ids { x = 1; } { x = 1.0; };
        outPath =
          ids
            {
              o = {
                outPath = "p";
                a = 1;
              };
            }
            {
              o = {
                outPath = "p";
                a = 2;
              };
            };
        fnShared = shared;
        fnApart = ids { fn = x: x; } { fn = y: y; };
      };
      expected = {
        intFloat = {
          same = true;
          several = true;
        };
        outPath = {
          same = false;
          several = true;
        };
        fnShared = {
          same = true;
          several = true;
        };
        fnApart = {
          same = false;
          several = true;
        };
      };
    };
}
