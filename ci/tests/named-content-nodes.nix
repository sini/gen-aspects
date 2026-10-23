# NAMED INLINE CONTENT IS ONE NODE PER CLASS (den-hoag-qxip5; identity design 2026-09-30 §2, Q5 "yes").
#
# A named element's §2 key is the position of its `name` and the name. The sightings at one §2 key are
# decided same-or-distinct by the rung over their authored values (rung 1: two exact constructor
# outputs, gen-algebra's `conservativeEq`; rung 2: Nix `==`), and each connected component is ONE
# node, `@/includes/<§2 key>`, plus its least inclusion site when the key holds several classes.
#
# Each cell carries the arm that discriminates it: the `RED` comment names the edit that turns it.
{
  lib,
  mkSchemaEval,
  aspects,
  genMerge,
  genAlgebra,
  genIdentity,
  ...
}:
let
  tryValue =
    v:
    let
      r = builtins.tryEval (builtins.deepSeq v v);
    in
    if r.success then r.value else "REFUSED";
  facts =
    mods:
    aspects.graphFacts { }
      (mkSchemaEval {
        fixtureKeySemantics.T.category = "class";
        modules = mods;
      }).config.aspects;
  marked = m: { T.marks = [ m ]; };
  marksIn =
    v:
    if builtins.isAttrs v then
      (v.marks or [ ]) ++ builtins.concatMap marksIn (v.imports or [ ])
    else if builtins.isList v then
      builtins.concatMap marksIn v
    else
      [ ];
  # Total over a RED arm: a node the arm does not publish reads `[ ]`, never an abort.
  marksOf = f: n: marksIn ((f.nodeData.${n} or { }).T or [ ]);
  first = l: if l == [ ] then "<none>" else builtins.head l;
  classes = f: builtins.filter (lib.hasPrefix "@/includes/") f.nodes;
  # The node each owner's include sites name, and that node's marks.
  seen =
    f: owners:
    lib.genAttrs owners (
      o:
      map (t: {
        marks = marksOf f t;
        class = lib.hasPrefix "@/includes/" t;
      }) f.includesOf.${o}
    );

  tmux = {
    name = "tmux";
    T.marks = [ "tmux" ];
  };
  # A factory: its `name` sits at one source position however often it is called.
  mk = m: {
    name = "t";
    T.marks = [ m ];
  };
  reg = {
    revision = 1;
    members.tool = m: { T.marks = [ m ]; };
  };
  mkTool = genAlgebra.mkIntensional genIdentity.hashIdentity reg "tool";
in
{
  # N1 (the premise). Two takers of one named value reach ONE node; both sites name it, neither is
  # unresolved, and the class has no parent (its key carries no host). RED (base, K1): `includesOf`
  # a = b = [ ], `unresolvedIncludesOf` a = b = [ 0 ].
  flake.tests.named-content-nodes.test-two-takers-one-node =
    let
      f = facts [
        {
          config.aspects.a.includes = [ tmux ];
          config.aspects.b.includes = [ tmux ];
        }
      ];
      t = first f.includesOf.a;
    in
    {
      expr = {
        same = f.includesOf.a == f.includesOf.b;
        classes = builtins.length (classes f);
        unresolved = [
          f.unresolvedIncludesOf.a
          f.unresolvedIncludesOf.b
        ];
        parent = tryValue (f.parentOf.${t} or "<none>");
        marks = tryValue (marksOf f t);
        domains = builtins.attrNames f.parentOf == f.nodes;
      };
      expected = {
        same = true;
        classes = 1;
        unresolved = [
          [ ]
          [ ]
        ];
        parent = null;
        marks = [ "tmux" ];
        domains = true;
      };
    };

  # N2 (K1's injectivity). What makes two named sightings one node, and what keeps two apart:
  #   factory   one `name` position, different content: two classes, each its own content.
  #   twoLits   one name at two positions: two §2 keys, two nodes.
  #   twoNames  one content under two names: two §2 keys, two nodes.
  #   dup       one value twice at one owner: one node, two edges.
  #   twoMods   one value from two modules: one node.
  #   factoryEqual        a factory applied twice to EQUAL arguments: two objects, one node by deep `==`.
  #   lambdaFactoryEqual  the same, its content holding a function (design §2 case 2): fresh closures
  #                       are unequal under `==`, so two classes.
  # RED (the §2 key alone, no rung): `factory` is one node and b receives a's content. RED (a rung 2
  # that ignores functions): `lambdaFactoryEqual` is one class. RED (base): `factoryEqual` has none.
  flake.tests.named-content-nodes.test-what-keeps-two-apart =
    let
      lit1 = {
        name = "tmux";
        T.marks = [ "1" ];
      };
      lit2 = {
        name = "tmux";
        T.marks = [ "2" ];
      };
      factory = facts [
        {
          config.aspects.a.includes = [ (mk "1") ];
          config.aspects.b.includes = [ (mk "2") ];
        }
      ];
      twoLits = facts [
        {
          config.aspects.a.includes = [ lit1 ];
          config.aspects.b.includes = [ lit2 ];
        }
      ];
      twoNames = facts [
        {
          config.aspects.a.includes = [ tmux ];
          config.aspects.b.includes = [ (tmux // { name = "screen"; }) ];
        }
      ];
      dup = facts [
        {
          config.aspects.a.includes = [
            tmux
            tmux
          ];
        }
      ];
      twoMods = facts [
        { config.aspects.a.includes = [ tmux ]; }
        { config.aspects.b.includes = [ tmux ]; }
      ];
      mkF = m: {
        name = "t";
        T.marks = [ m ];
        T.f = x: x;
      };
      factoryEqual = facts [
        {
          config.aspects.a.includes = [ (mk "1") ];
          config.aspects.b.includes = [ (mk "1") ];
        }
      ];
      lambdaFactoryEqual = facts [
        {
          config.aspects.a.includes = [ (mkF "1") ];
          config.aspects.b.includes = [ (mkF "1") ];
        }
      ];
    in
    {
      expr = {
        factory = {
          classes = builtins.length (classes factory);
          seen = seen factory [
            "a"
            "b"
          ];
        };
        twoLits = {
          classes = builtins.length (classes twoLits);
          seen = seen twoLits [
            "a"
            "b"
          ];
        };
        twoNames = builtins.length (classes twoNames);
        dup = {
          classes = builtins.length (classes dup);
          edges = builtins.length dup.includesOf.a;
          oneTarget = builtins.length (lib.unique dup.includesOf.a);
        };
        twoMods = {
          classes = builtins.length (classes twoMods);
          same = twoMods.includesOf.a == twoMods.includesOf.b;
        };
        factoryEqual = {
          classes = builtins.length (classes factoryEqual);
          same = factoryEqual.includesOf.a == factoryEqual.includesOf.b;
        };
        lambdaFactoryEqual = builtins.length (classes lambdaFactoryEqual);
      };
      expected = {
        factory = {
          classes = 2;
          seen = {
            a = [
              {
                marks = [ "1" ];
                class = true;
              }
            ];
            b = [
              {
                marks = [ "2" ];
                class = true;
              }
            ];
          };
        };
        twoLits = {
          classes = 2;
          seen = {
            a = [
              {
                marks = [ "1" ];
                class = true;
              }
            ];
            b = [
              {
                marks = [ "2" ];
                class = true;
              }
            ];
          };
        };
        twoNames = 2;
        dup = {
          classes = 1;
          edges = 2;
          oneTarget = 1;
        };
        twoMods = {
          classes = 1;
          same = true;
        };
        factoryEqual = {
          classes = 1;
          same = true;
        };
        lambdaFactoryEqual = 2;
      };
    };

  # N3 (C2, order-free). Class "1" is sighted twice (at p, declared by module m1, and at r, by m2),
  # class "2" once; the id each class gets, and its content, are the same in both module orders, and
  # class "1" is keyed by its LEAST site (p's), whichever sighting the walk meets first. RED (the
  # first claimant's site keys the class): `late`'s class "1" is keyed by `a/b`'s site.
  flake.tests.named-content-nodes.test-class-keys-are-order-free =
    let
      m1 = {
        key = "m1";
        config.aspects.p.includes = [ (mk "1") ];
      };
      m2 = {
        key = "m2";
        config.aspects.q.includes = [ (mk "2") ];
        config.aspects.r.includes = [ (mk "1") ];
      };
      byMarks =
        f:
        builtins.listToAttrs (
          map (n: {
            name = builtins.concatStringsSep "," (marksOf f n);
            value = n;
          }) (classes f)
        );
      ab = facts [
        m1
        m2
      ];
      ba = facts [
        m2
        m1
      ];
      # The walk meets `a/b` before `a-c` (depth first), while `a-c`'s site sorts first ('-' < '/').
      late = facts [
        {
          key = "m1";
          config.aspects.a.b.includes = [ (mk "1") ];
        }
        {
          key = "m2";
          config.aspects.q.includes = [ (mk "2") ];
          config.aspects.a-c.includes = [ (mk "1") ];
        }
      ];
    in
    {
      expr = {
        modules = byMarks ab == byMarks ba;
        twoClasses = builtins.attrNames (byMarks ab);
        oneNodeForTwoSightings = ab.includesOf.p == ab.includesOf.r;
        leastIsP = lib.hasSuffix "/p%2Fincludes%2F[\"km1\",\"aspects\",\"p\",\"includes\",0]" (
          (byMarks ab)."1" or ""
        );
        leastNotFirstWalked =
          lib.hasSuffix "/a-c%2Fincludes%2F[\"km2\",\"aspects\",\"a-c\",\"includes\",0]"
            ((byMarks late)."1" or "");
      };
      expected = {
        modules = true;
        twoClasses = [
          "1"
          "2"
        ];
        oneNodeForTwoSightings = true;
        leastIsP = true;
        leastNotFirstWalked = true;
      };
    };

  # N4 (F10). Content inside a named value is keyed under its class, so two sightings share it: one
  # inner node, its parent the class. RED (each sighting keys its own content): two inner nodes.
  flake.tests.named-content-nodes.test-content-inside-a-class-is-shared =
    let
      t = {
        name = "t";
        includes = [ (marked "inner") ];
      };
      f = facts [
        {
          config.aspects.a.includes = [ t ];
          config.aspects.b.includes = [ t ];
        }
      ];
      c = first f.includesOf.a;
      inner = builtins.filter (n: marksOf f n == [ "inner" ]) f.nodes;
    in
    {
      expr = {
        inner = inner;
        innerParent = map (n: f.parentOf.${n}) inner == [ c ];
        classIncludes = (f.includesOf.${c} or null) == inner;
      };
      expected = {
        inner = [ "${c}/includes/0" ];
        innerParent = true;
        classIncludes = true;
      };
    };

  # N5 (C3, the back edge). A named value that includes itself is one node whose site names itself,
  # and the reach back is an edge, never a site of the class: so two such values at one §2 key with
  # different content are two classes keyed by their least sites, and the node set reads. RED (no
  # back edge): the reach back joins the class as a site keyed under the class itself, and the
  # two-class arm aborts the evaluator (stack overflow), so the cell dies.
  flake.tests.named-content-nodes.test-named-self-reference-is-a-back-edge =
    let
      s = {
        name = "s";
        includes = [ s ];
      };
      # The pair differs in attribute count, so `==` decides before its interning-ordered walk (R7).
      mkS =
        content:
        let
          r = {
            name = "r";
            includes = [ r ];
          }
          // content;
        in
        r;
      f = facts [ { config.aspects.a.includes = [ s ]; } ];
      g = facts [
        {
          config.aspects.a.includes = [ (mkS { T.marks = [ "1" ]; }) ];
          config.aspects.b.includes = [ (mkS { }) ];
        }
      ];
      c = first f.includesOf.a;
      selfLoop = fx: o: map (t: (fx.includesOf.${t} or null) == [ t ]) fx.includesOf.${o};
    in
    {
      expr = {
        nodes = builtins.length f.nodes;
        self = selfLoop f "a";
        twoClasses = builtins.length (classes g);
        twoSelf = selfLoop g "a" ++ selfLoop g "b";
      };
      expected = {
        nodes = 2;
        self = [ true ];
        twoClasses = 2;
        twoSelf = [
          true
          true
        ];
      };
    };

  # N6 (rung 1, C1). Two constructions of one registered term are one node, though Nix `==` splits
  # them (fresh closures); two `//`-extensions of one construction with different `includes` are two,
  # though `conservativeEq` alone merges them. RED (rung 2 only): `ctor` is 2. RED (`conservativeEq`
  # without the exact-name-set guard): `extended` is 1.
  flake.tests.named-content-nodes.test-rung-one-is-exact-constructor-output =
    let
      t = mkTool "x";
      ctor = facts [
        {
          config.aspects.a.includes = [ (mkTool "x") ];
          config.aspects.b.includes = [ (mkTool "x") ];
        }
      ];
      extended = facts [
        {
          config.aspects.a.includes = [ (t // { includes = [ (marked "p") ]; }) ];
          config.aspects.b.includes = [ (t // { includes = [ (marked "q") ]; }) ];
        }
      ];
    in
    {
      expr = {
        ctor = builtins.length (classes ctor);
        rawSplits = mkTool "x" == mkTool "x";
        extended = builtins.length (classes extended);
      };
      expected = {
        ctor = 1;
        rawSplits = false;
        extended = 2;
      };
    };

  # N7 (the class's edges). A typed named sighting copied to a second owner is re-declared there, its
  # own node (anonymous-nodes C1), never the class, whether edited or verbatim (OQ4: so the typed-copy
  # route splits Q5's diamond); a `name` with no position (a `mapAttrs`-built value, F14) is keyed by
  # its inclusion site; a node reaching neither is untouched. RED (the copy carries its sighting into
  # the class): b names the class, with a's content.
  flake.tests.named-content-nodes.test-copies-and-positionless-names-are-not-the-class =
    let
      copy = facts [
        (
          { config, ... }:
          {
            config.aspects.a.includes = [ tmux ];
            config.aspects.b.includes = [ (builtins.head config.aspects.a.includes // marked "edited") ];
            config.aspects.c = marked "c";
            config.aspects.z.includes = [ "c" ];
          }
        )
      ];
      verbatim = facts [
        (
          { config, ... }:
          {
            config.aspects.a.includes = [ tmux ];
            config.aspects.b.includes = [ (builtins.head config.aspects.a.includes) ];
          }
        )
      ];
      noPos = builtins.mapAttrs (_: v: v) tmux;
      positionless = facts [
        {
          config.aspects.a.includes = [ noPos ];
          config.aspects.b.includes = [ noPos ];
        }
      ];
    in
    {
      expr = {
        copy = seen copy [
          "a"
          "b"
        ];
        z = copy.includesOf.z;
        verbatim = seen verbatim [
          "a"
          "b"
        ];
        positionless = {
          classes = builtins.length (classes positionless);
          distinct = positionless.includesOf.a != positionless.includesOf.b;
        };
      };
      expected = {
        copy = {
          a = [
            {
              marks = [ "tmux" ];
              class = true;
            }
          ];
          b = [
            {
              marks = [ "edited" ];
              class = false;
            }
          ];
        };
        z = [ "c" ];
        verbatim = {
          a = [
            {
              marks = [ "tmux" ];
              class = true;
            }
          ];
          b = [
            {
              marks = [ "tmux" ];
              class = false;
            }
          ];
        };
        positionless = {
          classes = 0;
          distinct = true;
        };
      };
    };

  # N8 (rung 2 is sound under failure). A factory's two sightings at one §2 key each carry a lazy
  # `throw` leaf no graph reader demands (an unfree package's `outPath`, say): the comparison throws,
  # which is NOT the same, so they are two classes and the graph reads, as at base; ONE such value at
  # two takers is still one class (`==` answers on one object without forcing it). RED (rung 2 without
  # `tryEval`): every read of the factory's graph throws.
  flake.tests.named-content-nodes.test-a-comparison-that-throws-is-not-the-same =
    let
      mkB = _: {
        name = "t";
        T = {
          marks = [ "m" ];
          boom = throw "lazy-leaf-forced";
        };
      };
      one = mkB 0;
      factory = facts [
        {
          config.aspects.a.includes = [ (mkB 1) ];
          config.aspects.b.includes = [ (mkB 2) ];
        }
      ];
      shared = facts [
        {
          config.aspects.a.includes = [ one ];
          config.aspects.b.includes = [ one ];
        }
      ];
    in
    {
      expr = {
        factory = tryValue {
          classes = builtins.length (classes factory);
          nodes = builtins.length factory.nodes;
          apart = factory.includesOf.a != factory.includesOf.b;
        };
        shared = tryValue {
          classes = builtins.length (classes shared);
          same = shared.includesOf.a == shared.includesOf.b;
        };
      };
      expected = {
        factory = {
          classes = 2;
          nodes = 4;
          apart = true;
        };
        shared = {
          classes = 1;
          same = true;
        };
      };
    };

  # ★ THE STATED BOUNDARY (ADR-0034 quotient clause; den-hoag-r089k, a third declared exception
  # pending owner ratification, den-hoag-0n4mg; README "Named content and string context"). Rung 2 is
  # `==`, blind to string context, and the class keeps its least sighting's value WITHOUT walking the
  # others, so a twin's dependency edges are dropped silently:
  #   boundary   the kept (least-site) sighting lacks the context `b`'s copy carries: `[ false ]`.
  #   single     one taker, no collapse (the control): its context is kept, `[ true ]`.
  #   reverse    the kept sighting carries it: `[ true ]`.
  # Flips when den-hoag-gkrtw carries every datum's edges (if gkrtw lands by walking values, it stays).
  # RED (a collapse that carried or refused the union): `boundary` reads `[ true ]` or "REFUSED".
  flake.tests.named-content-nodes.test-a-static-collapse-drops-the-twins-context-the-stated-boundary =
    let
      drv = derivation {
        name = "r089k";
        builder = "/bin/sh";
        system = "x86_64-linux";
      };
      withCtx = "${drv}";
      noCtx = builtins.unsafeDiscardStringContext withCtx;
      ctxOf =
        a: b:
        let
          f = facts [
            {
              config.aspects = {
                a.includes = if a == null then [ ] else [ (mk a) ];
                b.includes = [ (mk b) ];
              };
            }
          ];
        in
        tryValue (map builtins.hasContext (marksOf f (first f.includesOf.b)));
    in
    {
      expr = {
        control = [
          (mk noCtx == mk withCtx)
          (builtins.hasContext withCtx)
          (builtins.hasContext noCtx)
        ];
        boundary = ctxOf noCtx withCtx;
        single = ctxOf null withCtx;
        reverse = ctxOf withCtx noCtx;
      };
      expected = {
        control = [
          true
          true
          false
        ];
        boundary = [ false ];
        single = [ true ];
        reverse = [ true ];
      };
    };

  # Why the boundary is not closed by a walk here: the class walks no member's content, so one
  # self-referential value shared by two takers is a class (`==` shortcuts on the pointer) and its
  # node's value reads. An edge walk overflows on it uncatchably (ADR-0025 item 1); a bounded one
  # refuses deep valid input (ADR-0032). RED (an unbounded edge walk at the class): stack overflow,
  # which takes the batch down; (a bounded one): `"REFUSED"`.
  flake.tests.named-content-nodes.test-a-shared-self-referential-class-is-a-value =
    let
      cyc = {
        me = cyc;
        tag = "c";
      };
      v = {
        name = "t";
        T.marks = [ "m" ];
        T.extra = cyc;
      };
      f = facts [
        {
          config.aspects = {
            a.includes = [ v ];
            b.includes = [ v ];
          };
        }
      ];
    in
    {
      expr = {
        same = f.includesOf.a == f.includesOf.b;
        marks = tryValue (marksOf f (first f.includesOf.b));
      };
      expected = {
        same = true;
        marks = [ "m" ];
      };
    };
}
