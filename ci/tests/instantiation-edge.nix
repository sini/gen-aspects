# The instantiation edge, declaration members and per-field substitution (den-hoag-bgeum; ADR-0010
# §4(a); specs/2026-10-03-gen-aspects-instantiation-edge-spec.md §3a, cells A1–A12 and the gate's
# C3/P6). `instancesFor` gains `instantiates` (instance → declaration, van Antwerpen 2018's `I`
# edge), a parametric declaration publishes its members from its checked body term (`deferred` for
# a context-dependent one), and an instance's entry resolves each field where it is read. The
# message halves (A3, C1) are in ci/tests-error.nix, `instantiation-edge`.
{
  aspects,
  genIdentity,
  genAlgebra,
  mkSchemaEval,
  factsInternals,
  ...
}:
let
  t = (genAlgebra.term genIdentity.hashIdentity).term;
  entity = n: genIdentity.hashIdentity "entity" [ "name" ] (_: n);
  g = aspects.guard;
  has = aspects.pred.has;
  refuses = v: !(builtins.tryEval (builtins.deepSeq v v)).success;
  place = defs: (mkSchemaEval { modules = [ { config.aspects = defs; } ]; }).config.aspects;

  tree = place {
    # parametric `e`: its body includes parametric `q` and static `s2`
    e = g (has "host") {
      description = t.concat [
        (t.lit "e-")
        (t.readCtx "host" [ ])
      ];
      includes = [
        "q"
        "s2"
      ];
    };
    q = g (has "host") {
      description = t.concat [
        (t.lit "q-")
        (t.readCtx "host" [ ])
      ];
    };
    s2.name = "s2";
    s = {
      name = "s";
      includes = [ "e" ];
    };
    # clause 3: a sound field beside one whose projection path is missing
    lazy = g (has "host") {
      fine = "fine";
      bad = t.readCtx "host" [ "deep" ];
      includes = [ "q" ];
    };
    lazyCtl = g (has "host") {
      fine = "fine";
      alsoFine = t.readCtx "host" [ ];
    };
    # context-dependent includes: an element that is a context read, a whole member chosen by `If`,
    # and a list mixing a resolved member with a deferred one
    dynRead = g (has "host") { includes = [ (t.readCtx "host" [ ]) ]; };
    dynIf = g (has "host") {
      includes = t.ifThenElse (t.eq [ "host" ] "h1") (t.list [ (t.lit "q") ]) (t.list [ ]);
    };
    dynMixed = g (has "host") {
      includes = [
        "q"
        (t.readCtx "host" [ ])
      ];
    };
    h1.name = "h1";
  };
  suppliers = {
    ${entity "h1"}.host = "h1";
    ${entity "h2"}.host = "h2";
  };
  at = h: members: {
    sources.host = entity h;
    inherit members;
  };
  rOf = scopes: aspects.instancesFor { } tree { inherit suppliers scopes; };
  r = rOf {
    n1 = at "h1" [ "s" ];
    n2 = at "h2" [ "s" ];
  };
  facts = aspects.graphFacts { } tree;
  e1 = builtins.head r.reaches.n1.e;
  # one node on h1 reaching `which`: the relation and that instance's vertex
  one =
    which:
    let
      x = rOf { n = at "h1" [ which ]; };
    in
    {
      inherit x;
      id = builtins.head x.reaches.n.${which};
      v = x.vertices.${builtins.head x.reaches.n.${which}};
    };
  kinds = sites: map (s: s.kind) sites;

  # C3 / D3: path consistency along every nested edge — the child's substitution restricts its
  # parent's (keys a subset, equal on shared keys) — and its liveness count. `qu` reads `user`, which
  # its parent `pe` does not read and the scope DOES supply. A read must be covered by the condition
  # (`unsafe-read`), so `qu` holds only where `user` is in its context: at `pe`'s tuple, narrowed to
  # `pe`'s formals, it does not, and it has no nested edge. Handed the tuple unnarrowed, it would be
  # minted with a `user` formal its parent lacks.
  pathTree = place {
    pe = g (has "host") {
      description = t.readCtx "host" [ ];
      includes = [
        "pq"
        "qu"
      ];
    };
    pq = g (has "host") { description = t.readCtx "host" [ ]; };
    qu = g (aspects.pred.all [
      (has "host")
      (has "user")
    ]) { who = t.readCtx "user" [ ]; };
  };
  pathRel = aspects.instancesFor { } pathTree {
    suppliers = {
      ${entity "h1"}.host = "h1";
      ${entity "u1"}.user = "u1";
    };
    scopes.n = {
      members = [ "pe" ];
      sources = {
        host = entity "h1";
        user = entity "u1";
      };
    };
  };
  nestedPairs =
    rel:
    builtins.concatMap (
      p:
      map (c: {
        pf = rel.vertices.${p}.formals;
        cf = rel.vertices.${c}.formals;
      }) (builtins.concatLists (builtins.attrValues rel.nested.${p}))
    ) (builtins.attrNames rel.nested);
  consistent =
    x: builtins.intersectAttrs x.pf x.cf == x.cf && builtins.intersectAttrs x.cf x.pf == x.cf;

  # A11: gen-delivery's G9j′ fixture (a parametric aspect delivering a class key), with a refusing
  # non-class sibling. The class key's content reads through `reaches` and the entry.
  dcnf.keySemantics.nixos.category = "class";
  wRel =
    p:
    aspects.instancesFor dcnf
      (mkSchemaEval {
        keySemantics.nixos.category = "class";
        modules = [ { config.aspects.p = p; } ];
      }).config.aspects
      {
        suppliers.${entity "server"}.host = "server";
        scopes.server = {
          members = [ "p" ];
          sources.host = entity "server";
        };
      };
  wContent =
    p:
    let
      x = wRel p;
    in
    map (i: x.vertices.${i}.entry.nixos.marks) x.reaches.server.p;
in
{
  flake.tests.instantiation-edge = {
    # A1/A2. A sound field reads beside one that refuses, and the relation's edges survive it. RED
    # (whole-body resolveTerm in fireScoped): `fine`, `reaches` and `nested` all refuse.
    test-sound-field-reads-beside-a-refusing-one = {
      expr = {
        fine = (one "lazy").v.entry.fine;
        badRefuses = refuses (one "lazy").v.entry.bad;
        reaches = builtins.attrNames (one "lazy").x.reaches.n;
        nestedQ = builtins.length (one "lazy").x.nested.${(one "lazy").id}.q;
        ctl = {
          inherit ((one "lazyCtl").v.entry) fine alsoFine;
        };
      };
      expected = {
        fine = "fine";
        badRefuses = true;
        reaches = [ "lazy" ];
        nestedQ = 1;
        ctl = {
          fine = "fine";
          alsoFine = "h1";
        };
      };
    };
    # A4. Through a guard carrier whose two record fragments both fire. RED (whole-body resolution):
    # `fine` and `reaches` refuse.
    test-carrier-field-reads-beside-a-refusing-one =
      let
        carrier =
          (aspects.aspectType { }).merge
            [ "c" ]
            [
              {
                file = "/a.nix";
                value = g (has "host") { fine = "fine"; };
              }
              {
                file = "/b.nix";
                value = g (has "host") { bad = t.readCtx "host" [ "deep" ]; };
              }
            ];
        x = aspects.instanceOf { } {
          aspect = "c";
          value = carrier;
          context.host = "h1";
          sources.host = entity "h1";
        };
      in
      {
        expr = {
          isCarrier = carrier ? fragments;
          fine = x.entry.fine;
          badRefuses = refuses x.entry.bad;
        };
        expected = {
          isCarrier = true;
          fine = "fine";
          badRefuses = true;
        };
      };
    # A5. A parametric declaration publishes its members without firing. RED (members reached only by
    # firing): `[ ]`. Control: a static node's sites.
    test-declaration-publishes-members = {
      expr = {
        e = facts.includeSitesOf.e;
        ctl = facts.includeSitesOf.s;
      };
      expected = {
        e = [
          {
            kind = "local";
            target = "q";
          }
          {
            kind = "local";
            target = "s2";
          }
        ];
        ctl = [
          {
            kind = "local";
            target = "e";
          }
        ];
      };
    };
    # A6 and P6. A context-dependent element is `deferred`, and only it: a list mixing a resolved
    # member with a read publishes both, and a whole `includes` chosen by `If` publishes ONE deferred
    # whose instance classifies the whole fired field. Admission is unchanged: each still reaches
    # what its fired body includes. RED (members reached only by firing): every declaration `[ ]`.
    test-context-dependent-members-defer = {
      expr = {
        dynRead = kinds facts.includeSitesOf.dynRead;
        dynMixed = kinds facts.includeSitesOf.dynMixed;
        dynIf = kinds facts.includeSitesOf.dynIf;
        unresolved = {
          inherit (facts.unresolvedIncludesOf) dynRead dynMixed dynIf;
        };
        dynReadIncludes = (one "dynRead").v.entry.includes;
        dynMixedNested = builtins.attrNames (one "dynMixed").x.nested.${(one "dynMixed").id};
        dynIfNested = builtins.attrNames (one "dynIf").x.nested.${(one "dynIf").id};
        dynIfAtH2 = builtins.attrValues (rOf { n = at "h2" [ "dynIf" ]; }).nested;
      };
      expected = {
        dynRead = [ "deferred" ];
        dynMixed = [
          "local"
          "deferred"
        ];
        dynIf = [ "deferred" ];
        unresolved = {
          dynRead = [ 0 ];
          dynMixed = [ 1 ];
          dynIf = [ 0 ];
        };
        dynReadIncludes = [ "h1" ];
        dynMixedNested = [ "q" ];
        dynIfNested = [ "q" ];
        dynIfAtH2 = [ { } ];
      };
    };
    # A7. `instantiates` is total over `vertices`, one target each, the declaration's facts id; a
    # vertex carries no `aspect` field (the edge states it). RED: the edge set absent, `aspect` a field.
    test-instantiates-edge = {
      expr = {
        fields = builtins.attrNames r;
        total = builtins.attrNames r.instantiates == builtins.attrNames r.vertices;
        oneEach = builtins.all (i: builtins.length r.instantiates.${i} == 1) (
          builtins.attrNames r.instantiates
        );
        e1 = r.instantiates.${e1};
        isNode = builtins.all (i: builtins.elem (builtins.head r.instantiates.${i}) facts.nodes) (
          builtins.attrNames r.instantiates
        );
        vertexFields = builtins.attrNames r.vertices.${e1};
      };
      expected = {
        fields = [
          "instantiates"
          "nested"
          "reaches"
          "vertices"
        ];
        total = true;
        oneEach = true;
        e1 = [ "e" ];
        isNode = true;
        vertexFields = [
          "entry"
          "formals"
          "scope"
        ];
      };
    };
    # A8 (composed by hand here; gen-demo's cell runs it as a gen-graph query). `instantiates ·
    # includes` from an instance answers its declaration's RESOLVED members. Control: `includes` from
    # static `s`. RED (no edge, no members): `[ ]`.
    test-members-through-the-edge = {
      expr = {
        members = builtins.concatMap (d: facts.includesOf.${d}) r.instantiates.${e1};
        ctl = facts.includesOf.s;
      };
      expected = {
        members = [
          "q"
          "s2"
        ];
        ctl = [ "e" ];
      };
    };
    # A9 / C3. Clause 4 is vacuous because along every nested edge the child's substitution restricts
    # its parent's. Live: nested edges exist (`count`), one of them to `qu`, which reads `user`, a
    # coordinate the scope supplies and its parent does not read. RED: a nested rebind of the parent's
    # source (spec plant `plant-c4.diff`) and an unnarrowed child tuple (gate plant 2) each read
    # `consistent = false`.
    test-path-consistency =
      let
        pairs = nestedPairs pathRel;
      in
      {
        expr = {
          count = builtins.length pairs;
          quNested = builtins.attrNames pathRel.nested.${builtins.head pathRel.reaches.n.pe};
          # the scope reaches `qu` itself, with `user` (control: it is admissible where supplied)
          quAtNode =
            let
              x = aspects.instancesFor { } pathTree {
                suppliers = {
                  ${entity "h1"}.host = "h1";
                  ${entity "u1"}.user = "u1";
                };
                scopes.n = {
                  members = [ "qu" ];
                  sources = {
                    host = entity "h1";
                    user = entity "u1";
                  };
                };
              };
            in
            map (i: x.vertices.${i}.entry.who) x.reaches.n.qu;
          consistent = builtins.all consistent pairs;
          also = builtins.all consistent (nestedPairs r);
          alsoCount = builtins.length (nestedPairs r);
        };
        expected = {
          count = 1;
          quNested = [ "pq" ];
          quAtNode = [ "u1" ];
          consistent = true;
          also = true;
          alsoCount = 2;
        };
      };
    # A11 (wpn8c). A parametric aspect's delivered class key reads through the relation although a
    # non-class sibling refuses. RED (whole-body resolution): the content refuses. Control: the plain
    # G9j′ fixture.
    test-class-key-reads-beside-a-refusing-sibling = {
      expr = {
        sibling = wContent (
          g (has "host") {
            nixos.marks = [ "host" ];
            description = t.readCtx "host" [ "deep" ];
          }
        );
        ctl = wContent (g (has "host") { nixos.marks = [ "host" ]; });
      };
      expected = {
        sibling = [ [ "host" ] ];
        ctl = [ [ "host" ] ];
      };
    };
    # C1. A context-free include element is resolved once, AT THE DECLARATION, so one that refuses
    # refuses there, by name with the aspect and the include position, wherever the declaration's
    # sites are read, even when nothing instantiates it (the admission change: at the base such a
    # declaration was admitted, its sites `[ ]`). Another node's sites still answer: the refusal is
    # per id. The message on the real path is pinned in ci/tests-error.nix; here, catchability and
    # the renderer. RED (an unnamed `throw`): the renderer is absent.
    test-declaration-member-refuses-by-name =
      let
        f = aspects.graphFacts { } (place {
          neverFires = g (has "user") { includes = [ (t.concat [ (t.lit 1) ]) ]; };
          other = {
            name = "other";
            includes = [ "neverFires" ];
          };
        });
      in
      {
        expr = {
          enumerationRefuses = refuses f.includesOf;
          siteRefuses = refuses f.includeSitesOf.neverFires;
          otherAnswers = f.includesOf.other;
          message = factsInternals.declarationMemberRefusal "neverFires" "include position 0" {
            code = "former-operand-type";
            witness.former = "Concat";
          };
        };
        expected = {
          enumerationRefuses = true;
          siteRefuses = true;
          otherAnswers = [ "neverFires" ];
          message = "gen-aspects.guard: aspect `neverFires`, include position 0, a declaration member resolved once at the declaration: former-operand-type: {\"former\":\"Concat\"}";
        };
      };
    # A12. The declaration's sites agree with each instance's entry where nothing defers: the shared
    # route (`instanceSites`) and `includeSitesOfEntry` over the fired entry classify alike. RED
    # (members reached only by firing): the declaration `[ ]` against the entry's `[ q s2 ]`.
    test-declaration-sites-equal-entry-sites = {
      expr = builtins.all (
        i:
        let
          d = builtins.head r.instantiates.${i};
        in
        facts.includeSitesOf.${d} == aspects.includeSitesOfEntry { } tree r.vertices.${i}.entry
      ) (builtins.attrNames r.vertices);
      expected = true;
    };
  };
}
