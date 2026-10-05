# `instanceOf` — the instance mint, and `instancesFor`, the instance relation (lib/instance.nix;
# den-hoag-0cmbt spec §2.5 and §2.6, cells I-1 to I-7, R-1 to R-9, and
# K-a/K-b through the mint). Every source is IDENTITY-shaped, minted here through gen-identity's
# `hashIdentity` under the entity and argument-binding kinds, because the mint refuses a context value
# as a source (the doors' cells are in ci/tests-error.nix, `instance-doors`; the relation's source
# door is ci/tests/source-door.nix).
{
  aspects,
  genIdentity,
  genAlgebra,
  mkSchemaEval,
  ...
}:
let
  t = (genAlgebra.term genIdentity.hashIdentity).term;
  entity = n: genIdentity.hashIdentity "entity" [ "name" ] (_: n);
  binding = n: genIdentity.hashIdentity "argument-binding" [ "name" ] (_: n);
  aspect = aspects.aspectId [ "probe" ] { name = "p"; };
  # A first-order guard reading `host` (design Section 3: context reads become read terms).
  p = aspects.guard (aspects.pred.has "host") {
    description = t.concat [
      (t.lit "p-")
      (t.readCtx "host" [ ])
    ];
  };
  # A guard reading nothing (design Section 3: constants become `always`).
  empty = aspects.guard aspects.pred.always { description = "e"; };
  # Two guard-record definitions under one key, one reading `host` and one reading `x`: the aspect
  # type's merge builds a guard carrier (K2's site). The two bodies set DISTINCT keys: two firing
  # definitions that disagree on one scalar are refused (den-hoag-ywlww, guard.test-guard-multidef-
  # carrier-discharge-merges-by-module-law), and this fixture asserts the union.
  kinds = {
    entityKinds = [ "host" ];
  };
  # `x` is a declared coordinate that is not an entity kind (design Q5 (A)).
  kindsX.entityKinds = {
    host = true;
    x = false;
  };
  twoDefs =
    (aspects.aspectType kindsX).merge
      [ "m" ]
      [
        {
          file = "/a.nix";
          value = aspects.guard (aspects.pred.has "host") {
            description = t.concat [
              (t.lit "a:")
              (t.readCtx "host" [ ])
            ];
          };
        }
        {
          file = "/b.nix";
          value = aspects.guard (aspects.pred.has "x") {
            note = t.concat [
              (t.lit "b:")
              (t.readCtx "x" [ ])
            ];
          };
        }
      ];
  scope = host: extra: {
    context = { inherit host extra; };
    sources = {
      host = entity host;
      extra = binding extra;
    };
  };
  inst =
    cnf: value: s:
    aspects.instanceOf cnf {
      inherit aspect value;
      inherit (s) context sources;
    };
  twoDefsScope = {
    context = {
      host = "h1";
      x = "X";
      extra = "E";
    };
    sources = {
      host = entity "h1";
      x = binding "X";
      extra = binding "E";
    };
  };
  # The relation's fixture (spec §2.6): a and c are two entities on host h1 (equal tuples), b another
  # host; `w` is static and reaches `e` (host) and `u` (user, a descendant formal); `e`'s body includes
  # `q`. Each case's node is named in its cell.
  # Placed through the aspect type, where each guard meets its cnf and is checked (a first-order
  # guard has an identity once checked).
  rel = (mkSchemaEval { modules = [ { config.aspects = relDefs; } ]; }).config.aspects;
  relDefs = {
    e = aspects.guard (aspects.pred.has "host") {
      description = t.concat [
        (t.lit "e-")
        (t.readCtx "host" [ ])
      ];
      includes = [ "q" ];
    };
    q = aspects.guard (aspects.pred.has "host") {
      description = t.concat [
        (t.lit "q-")
        (t.readCtx "host" [ ])
      ];
    };
    u = aspects.guard (aspects.pred.has "user") {
      description = t.concat [
        (t.lit "u-")
        (t.readCtx "user" [ ])
      ];
    };
    # one global argument binding supplies `flavor` to every scope
    s = aspects.guard (aspects.pred.has "flavor") {
      description = t.concat [
        (t.lit "s-")
        (t.readCtx "flavor" [ ])
      ];
    };
    w = {
      name = "w";
      includes = [
        "e"
        "u"
        "s"
      ];
    };
    # a parametric body including a STATIC node (the static-node rule)
    e2 = aspects.guard (aspects.pred.has "host") { includes = [ "w2" ]; };
    w2 = {
      name = "w2";
      includes = [ "q" ];
    };
    # a parametric body including `q` and a static node under inline content
    e3 = aspects.guard (aspects.pred.has "host") {
      includes = [
        {
          name = "lit";
          includes = [
            "q"
            "w3"
          ];
        }
      ];
    };
    w3 = {
      name = "w3";
      includes = [ "u" ];
    };
    # a parametric body including an aspect whose formal its tuple lacks
    eu = aspects.guard (aspects.pred.has "host") { includes = [ "u" ]; };
    # a static node holding inline content (stamped by the aspect type's merge, so it is content and
    # not sealed), and a guard record (no instance identity yet: O1)
    wc.includes = [
      {
        name = "lit";
        includes = [ "e" ];
      }
      "gr"
    ];
    gr = (aspects.mkGuardVocab { }).vocab.whenEq [ "host" ] "h1" { description = "gr"; };
  };
  # A tuple names its suppliers only; its context is derived through `relSuppliers` (spec §2.6).
  tuple = host: user: {
    sources = {
      host = entity host;
      flavor = binding "flavor";
    }
    // (if user == null then { } else { user = entity user; });
  };
  relScope =
    host: users: members:
    tuple host null
    // {
      inherit members;
      descendants = map (tuple host) users;
    };
  relScopes = {
    a = relScope "h1" [ "u1" "u2" ] [ "w" ];
    c = relScope "h1" [ "u3" ] [ "w" ];
    b = relScope "h2" [ ] [ "e" "s" ];
    d = relScope "h3" [ ] [ "e2" ];
    f = relScope "h4" [ ] [ "w" ];
    g = relScope "h1" [ ] [ "w" "q" ];
    i = relScope "h5" [ "u5" ] [ "e3" ];
    j = relScope "h6" [ "u6" ] [ "eu" ];
    k = relScope "h7" [ ] [ "wc" ];
  };
  # Written as a literal: one value per (source, key) by construction, and a repeated name aborts.
  relSuppliers = {
    ${entity "h1"}.host = "h1";
    ${entity "h2"}.host = "h2";
    ${entity "h3"}.host = "h3";
    ${entity "h4"}.host = "h4";
    ${entity "h5"}.host = "h5";
    ${entity "h6"}.host = "h6";
    ${entity "h7"}.host = "h7";
    ${entity "u1"}.user = "u1";
    ${entity "u2"}.user = "u2";
    ${entity "u3"}.user = "u3";
    ${entity "u5"}.user = "u5";
    ${entity "u6"}.user = "u6";
    ${binding "flavor"}.flavor = "vanilla";
  };
  r = aspects.instancesFor { } rel {
    suppliers = relSuppliers;
    scopes = relScopes;
  };
  desc = id: r.vertices.${id}.entry.description;
  descs = map desc;
  facts = aspects.graphFacts { } rel;
  # H1–H6 (den-hoag-ehkse): a guard placed at a path is a declaration, identified by origin + declared
  # path (identity design §1). `marked` guards are one condition and one non-class body apart from
  # their `classOne` payloads, which are module content outside the term's mint (ADR-0034 a0gc).
  # One cnf at placement and at the relation, so a carrier's fragments discharge against the class
  # key the single records were checked against.
  idCnf = {
    keySemantics.classOne.category = "class";
    entityKinds = {
      host = true;
      user = true;
    };
  };
  marked = m: aspects.guard (aspects.pred.has "host") { classOne.marks = [ m ]; };
  placedMods =
    mods: (mkSchemaEval (idCnf // { modules = map (m: { config.aspects = m; }) mods; })).config.aspects;
  placed = defs: placedMods [ defs ];
  idSuppliers = {
    ${entity "h1"}.host = "h1";
    ${entity "h2"}.host = "h2";
    ${entity "u1"}.user = "u1";
  };
  hostAt = h: members: {
    inherit members;
    sources.host = entity h;
  };
  userAt = h: u: members: {
    inherit members;
    sources = {
      host = entity h;
      user = entity u;
    };
  };
  relOf =
    tree: scopes:
    aspects.instancesFor idCnf tree {
      suppliers = idSuppliers;
      inherit scopes;
    };
  vertexCount = rr: builtins.length (builtins.attrNames rr.vertices);
  marksAt =
    rr: n: a:
    map (id: rr.vertices.${id}.entry.classOne.marks) rr.reaches.${n}.${a};
  siblings = placed {
    x = marked "x";
    y = marked "y";
  };
  nestedPair = placed {
    f.x = marked "fx";
    g.x = marked "gx";
  };
  # two definitions per key: each is a guard carrier of two record fragments
  carriers = placedMods [
    {
      x = marked "x1";
      y = marked "y1";
    }
    {
      x = marked "x2";
      y = marked "y2";
    }
  ];
in
{
  flake.tests.instances = {
    # I-1. Two contexts handing the aspect different values are two instances. RED (seeded: the
    # preimage without `formals`): the ids are equal.
    test-distinct-tuples = {
      expr = (inst { } p (scope "h1" "x")).id != (inst { } p (scope "h2" "x")).id;
      expected = true;
    };
    # I-2. Contexts that differ only in a key the aspect never receives are one instance, and its
    # formals are the received keys' sources. RED (seeded: keys = the whole context): the ids differ.
    test-equal-tuples-one-id = {
      expr = {
        same = (inst { } p (scope "h1" "x1")).id == (inst { } p (scope "h1" "x2")).id;
        formals = (inst { } p (scope "h1" "x1")).formals;
        entry = (inst { } p (scope "h1" "x1")).entry.description;
      };
      expected = {
        same = true;
        formals.host = entity "h1";
        entry = "p-h1";
      };
    };
    # The id is keyed on the received keys' SOURCES, never their values (design K3). At an equal
    # context value, an entity source and an argument binding are two instances; at an equal source,
    # two context values are one. RED (seeded: the id's formals = the received keys' context values):
    # both arms are false.
    test-id-keyed-on-sources = {
      expr =
        let
          at =
            v: s:
            inst { } p {
              context.host = v;
              sources.host = s;
            };
        in
        {
          bySource = (at "h1" (entity "h1")).id != (at "h1" (binding "h1")).id;
          byValue = (at "h1" (entity "h1")).id == (at "h2" (entity "h1")).id;
        };
      expected = {
        bySource = true;
        byValue = true;
      };
    };
    # I-3. `{ }:` receives nothing: no formals, one id across scopes.
    test-closed-empty-one-id = {
      expr = {
        formals = (inst { } empty (scope "h1" "x")).formals;
        same = (inst { } empty (scope "h1" "x")).id == (inst { } empty (scope "h2" "y")).id;
      };
      expected = {
        formals = { };
        same = true;
      };
    };
    # I-4. Two definitions: the carrier's formals are the union of its record fragments' reads
    # (`host` and `x`, not the unread `extra`), and the entry is the carrier discharged.
    test-two-definitions-union = {
      expr = {
        isCarrier = twoDefs ? fragments;
        formals = builtins.attrNames (inst kindsX twoDefs twoDefsScope).formals;
        entry =
          (inst kindsX twoDefs twoDefsScope).entry
          == (aspects.mkGuardVocab kindsX).applyGuard twoDefsScope.context twoDefs;
      };
      expected = {
        isCarrier = true;
        formals = [
          "host"
          "x"
        ];
        entry = true;
      };
    };
    # I-5. A formal named `aspect` nests under `formals` and does not clash with the relatum.
    test-formal-named-aspect = {
      expr =
        (inst { }
          (aspects.guard (aspects.pred.has "aspect") {
            description = t.concat [
              (t.lit "fa-")
              (t.readCtx "aspect" [ ])
            ];
          })
          {
            context.aspect = "A";
            sources.aspect = binding "A";
          }
        ).formals;
      expected.aspect = binding "A";
    };
    # I-7's minting arm: an identity-shaped source of a supplier kind mints an instance identity.
    test-identity-source-mints = {
      expr = builtins.match "aspect-instance:[0-9a-f]{64}" (inst { } p (scope "h1" "x")).id != null;
      expected = true;
    };
  };

  # `instancesFor` (spec §2.6). The REDs named per cell were driven on this tree under a plant
  # (reports/den-hoag-0cmbt-u4b-build-v0.md).
  flake.tests.instance-relation = {
    # R-1. Only reached pairs are edges: `a` reaches `e`, `s` and `u` through static `w`, never `w` itself
    # or an unreached parametric node. RED (every parametric node minted at every scope): `a` carries
    # e2, e3, eu and q too.
    test-reached-edges-only = {
      expr = {
        a = builtins.attrNames r.reaches.a;
        d = builtins.attrNames r.reaches.d;
        vertexAspects = builtins.attrNames (
          builtins.groupBy (id: builtins.head r.instantiates.${id}) (builtins.attrNames r.vertices)
        );
      };
      expected = {
        a = [
          "e"
          "s"
          "u"
        ];
        d = [
          "e2"
          "q"
        ];
        vertexAspects = [
          "e"
          "e2"
          "e3"
          "eu"
          "q"
          "s"
          "u"
        ];
      };
    };
    # R-2. Identity sharing: equal tuples are one id (a, c on h1), different tuples two (b on h2), and
    # one global binding is one id across hosts. RED (the id keyed per reaching node): all false.
    test-identity-sharing = {
      expr = {
        sameE = r.reaches.a.e == r.reaches.c.e;
        eDiffersB = r.reaches.a.e != r.reaches.b.e;
        shareS = r.reaches.a.s == r.reaches.b.s;
        entryS = descs r.reaches.b.s;
      };
      expected = {
        sameE = true;
        eDiffersB = true;
        shareS = true;
        entryS = [ "s-vanilla" ];
      };
    };
    # R-3. `q` in the shared E(h1) body is one nested id with entry q-h1; g, reaching `q` at node scope
    # too, reaches that same vertex (one node, two edges). RED (nested ids minted apart from node
    # scope): `same` false.
    test-nested-and-node-edge = {
      expr = {
        qDesc = map (eid: descs r.nested.${eid}.q) r.reaches.a.e;
        same = r.reaches.g.q == builtins.concatMap (eid: r.nested.${eid}.q) r.reaches.g.e;
        gSharesE = r.reaches.g.e == r.reaches.a.e;
      };
      expected = {
        qDesc = [ [ "q-h1" ] ];
        same = true;
        gSharesE = true;
      };
    };
    # R-4. The static-node rule: static `w2` inside e2's body resolves `q` at node scope, a `reaches.d`
    # edge with entry q-h3, never a nested one. RED (static targets of a body not walked): no `q`.
    test-static-node-rule = {
      expr = {
        node = descs (r.reaches.d.q or [ ]);
        nested = builtins.any (eid: r.nested.${eid} ? q) r.reaches.d.e2;
      };
      expected = {
        node = [ "q-h3" ];
        nested = false;
      };
    };
    # R-5. An unsuppliable reached pair has no edge and no throw: f reaches `u` with no tuple carrying
    # `user`; eu's vertex at h6 includes `u` and its tuple lacks `user` (O3: no nested fan-out). RED
    # (minted regardless): the guard's `has user` condition never holds, so a mint would refuse on
    # any read.
    test-unsuppliable-no-edge = {
      expr = {
        fHasE = r.reaches.f ? e;
        fHasU = r.reaches.f ? u;
        nestedU = map (eid: r.nested.${eid} ? u) r.reaches.j.eu;
        jHasU = r.reaches.j ? u;
      };
      expected = {
        fHasE = true;
        fHasU = false;
        nestedU = [ false ];
        jHasU = false;
      };
    };
    # R-6. One classifier, two callers: `includeSitesOfEntry` over each node's value is that node's
    # `includeSitesOf`, inline content included (`wc`). RED (a top-level-only classifier): false.
    test-include-sites-of-entry = {
      expr = {
        same = builtins.all (
          id: aspects.includeSitesOfEntry { } rel facts.nodeData.${id} == facts.includeSitesOf.${id}
        ) facts.nodes;
        wc = map (x: x.kind) (aspects.includeSitesOfEntry { } rel facts.nodeData.wc);
      };
      expected = {
        same = true;
        wc = [
          "content"
          "local"
        ];
      };
    };
    # R-7. Fan-out: at a (users u1, u2) `u` has two ids, `e` one; c (one user) one; b (none) no edge.
    # RED (the first descendant tuple taken): one id, [ "u-u1" ].
    test-fan-out = {
      expr = {
        # membership only; the order is test-fan-out-declared-order's
        uA = builtins.sort builtins.lessThan (descs r.reaches.a.u);
        eCountA = builtins.length r.reaches.a.e;
        uC = descs r.reaches.c.u;
        bHasU = r.reaches.b ? u;
      };
      expected = {
        uA = [
          "u-u1"
          "u-u2"
        ];
        eCountA = 1;
        uC = [ "u-u3" ];
        bHasU = false;
      };
    };
    # A1 (den-hoag-htfv3 U3a). Fan-out siblings follow the scope's `descendants`, in both orders, never
    # the ids' (ADR-0016 r5). RED (ascending id, the descendant order ignored): one arm differs.
    test-fan-out-declared-order = {
      expr =
        map
          (
            users:
            let
              rr = aspects.instancesFor { } rel {
                suppliers = relSuppliers;
                scopes.a = relScope "h1" users [ "w" ];
              };
            in
            map (id: rr.vertices.${id}.formals.user) rr.reaches.a.u
          )
          [
            [
              "u1"
              "u2"
            ]
            [
              "u2"
              "u1"
            ]
          ];
      expected = [
        [
          (entity "u1")
          (entity "u2")
        ]
        [
          (entity "u2")
          (entity "u1")
        ]
      ];
    };
    # R-8 (structure). a and c hold one `e` id, read from one `vertices` cell, whose nested `q` is one
    # id. This gates the structure that gives value sharing, not the application count (spec §3b G2).
    # RED (the id keyed per reaching node): two ids, two cells.
    test-one-vertex-structure = {
      expr =
        let
          ids = r.reaches.a.e ++ r.reaches.c.e;
        in
        {
          distinct = builtins.length (builtins.attrNames (builtins.groupBy (x: x) ids));
          cells = builtins.length (
            builtins.filter (id: r.vertices ? ${id}) (builtins.attrNames (builtins.groupBy (x: x) ids))
          );
          nestedQ = builtins.length (builtins.concatMap (eid: r.nested.${eid}.q) r.reaches.a.e);
        };
      expected = {
        distinct = 1;
        cells = 1;
        nestedQ = 1;
      };
    };
    # C-A. A body's include under inline content is classified as `project` classifies it: `q` is a
    # nested edge of E3(h5), and static `w3` resolves `u` at node scope (fanned out over i's user).
    # RED (a top-level-only body walk): no nested `q`, no `u`.
    test-inline-content-in-body = {
      expr = {
        nestedQ = map (eid: descs (r.nested.${eid}.q or [ ])) r.reaches.i.e3;
        nodeU = descs (r.reaches.i.u or [ ]);
      };
      expected = {
        nestedQ = [ [ "q-h5" ] ];
        nodeU = [ "u-u5" ];
      };
    };
    # OQ-U2.9 arm (B), one uniform rule (den-hoag-lwbb1 v2 gate BC-1/BC-2): in an APPLIED body a
    # key-less attrset is content, and a guard record stays sealed, its content awaiting its own firing.
    # The body is a real firing (`applyGuard` over a placed guard). RED (the guard-leaf exclusion
    # dropped, gate `arm-Bng.patch`): `nestedGuard` reads "content". RED (2a's stamp-only test, no arm
    # (B)): `literal` reads "sealed".
    test-applied-body-sites =
      let
        body =
          aspects.applyGuard { }
            (mkSchemaEval {
              modules = [
                {
                  config.aspects.fired = aspects.guard aspects.pred.always {
                    includes = [
                      (aspects.guard (aspects.pred.has "host") { includes = [ "q" ]; })
                      { includes = [ "q" ]; }
                      "q"
                    ];
                  };
                }
              ];
            }).config.aspects.fired;
        kinds = map (x: x.kind) (aspects.includeSitesOfEntry { } rel body);
      in
      {
        expr = {
          nestedGuard = builtins.elemAt kinds 0;
          literal = builtins.elemAt kinds 1;
          reference = builtins.elemAt kinds 2;
        };
        expected = {
          nestedGuard = "sealed";
          literal = "content";
          reference = "local";
        };
      };
    # ★ s6 — A DEFAULTED-REVERSIBLE CHOICE, PINNED AT TODAY'S BEHAVIOUR, PENDING AN OWNER CONFIRMATION.
    # This cell does not assert what is right. A module function written as an include element of an
    # applied parametric body (`includes = [ ({ config, ... }: { includes = [ "q" ]; }) ]`) is SEALED:
    # arm (B) reads only attrsets, and the design makes a module slot opaque to the algebra. 2a's
    # `wrapFn` path served it as content with site `q`; arm (s6-b), coercing such an element through
    # the aspect type at its include position, would serve it again (den-hoag-lwbb1 v2 gate G2-C1,
    # §4). Pinned so the reading that decides s6 flips it deliberately rather than silently. Control:
    # the same `includes` written as a literal is content.
    test-s6-module-fn-in-applied-body-is-sealed =
      let
        fire =
          elem:
          aspects.applyGuard { }
            (mkSchemaEval {
              modules = [
                { config.aspects.fired = aspects.guard aspects.pred.always { includes = [ elem ]; }; }
              ];
            }).config.aspects.fired;
        kinds = body: map (x: x.kind) (aspects.includeSitesOfEntry { } rel body);
      in
      {
        expr = {
          pinned = kinds (fire ({ config, ... }: { includes = [ "q" ]; }));
          control = kinds (fire {
            includes = [ "q" ];
          });
        };
        expected = {
          pinned = [ "sealed" ];
          control = [ "content" ];
        };
      };
    # A static node's inline content is walked at depth 0, and a guard record (O1) is a leaf with no
    # edge, never a refusal. `nested` is total over `vertices`.
    test-content-walked-guard-record-no-edge = {
      expr = {
        k = builtins.attrNames r.reaches.k;
        total = builtins.attrNames r.nested == builtins.attrNames r.vertices;
      };
      expected = {
        k = [ "e" ];
        total = true;
      };
    };
    # The restriction property (gate P-3): the relation handed one scope is the whole relation's
    # slice for it, its edges and every vertex it reaches, nested ones included. `control` is the slice
    # of another node, which differs. RED (an id that depends on which scopes are handed): false.
    test-restriction-to-one-scope =
      let
        rA = aspects.instancesFor { } rel {
          suppliers = relSuppliers;
          scopes = { inherit (relScopes) a; };
        };
        # an id the other relation lacks reads null, so a mismatch is a false cell, never an abort
        slice =
          rr:
          builtins.mapAttrs (
            id: _: if rr.vertices ? ${id} then rr.vertices.${id} // { nested = rr.nested.${id}; } else null
          ) rA.vertices;
      in
      {
        expr = {
          reaches = rA.reaches.a == r.reaches.a;
          vertices = slice rA == slice r;
          control = rA.reaches.a == r.reaches.b;
        };
        expected = {
          reaches = true;
          vertices = true;
          control = false;
        };
      };
    # H1. Siblings `x` and `y`, a payload apart, are two declarations and two instances, each reach
    # delivering its own payload. RED (`key` reads the term's mint): one vertex, and `y` delivers `x`'s
    # marks. Controls in both arms: a distinct `description`, or a distinct condition, splits the terms.
    test-guard-siblings-two-instances =
      let
        rr = relOf siblings {
          n = hostAt "h1" [
            "x"
            "y"
          ];
        };
        ctlDescription =
          relOf
            (placed {
              x = aspects.guard (aspects.pred.has "host") {
                classOne.marks = [ "x" ];
                description = "x";
              };
              y = aspects.guard (aspects.pred.has "host") {
                classOne.marks = [ "y" ];
                description = "y";
              };
            })
            {
              n = hostAt "h1" [
                "x"
                "y"
              ];
            };
        ctlCondition =
          relOf
            (placed {
              x = marked "x";
              y = aspects.guard (aspects.pred.not (aspects.pred.has "user")) { classOne.marks = [ "y" ]; };
            })
            {
              n = hostAt "h1" [
                "x"
                "y"
              ];
            };
      in
      {
        expr = {
          vertices = vertexCount rr;
          x = marksAt rr "n" "x";
          y = marksAt rr "n" "y";
          ctlDescription = vertexCount ctlDescription;
          ctlCondition = vertexCount ctlCondition;
        };
        expected = {
          vertices = 2;
          x = [ [ "x" ] ];
          y = [ [ "y" ] ];
          ctlDescription = 2;
          ctlCondition = 2;
        };
      };
    # H2. One leaf name under two parents, `f.x` and `g.x`: the declared path, not the leaf name,
    # tells them apart. RED (`key` reads the term's mint, or `aspectPath`, which reduces a guard leaf
    # with no `aspect-chain` to its name): one vertex, and `g/x` delivers `f/x`'s marks.
    test-guard-nested-two-instances =
      let
        rr = relOf nestedPair {
          n = hostAt "h1" [
            "f/x"
            "g/x"
          ];
        };
      in
      {
        expr = {
          vertices = vertexCount rr;
          fx = marksAt rr "n" "f/x";
          gx = marksAt rr "n" "g/x";
        };
        expected = {
          vertices = 2;
          fx = [ [ "fx" ] ];
          gx = [ [ "gx" ] ];
        };
      };
    # H3. Across nodes: a host node reaches `x`, a user node sourcing `host` from the same entity
    # reaches `y`. RED: one vertex, and the user node's `y` delivers `x`'s marks.
    test-guard-cross-node-two-instances =
      let
        rr = relOf siblings {
          hostN = hostAt "h1" [ "x" ];
          userU = userAt "h1" "u1" [ "y" ];
        };
      in
      {
        expr = {
          vertices = vertexCount rr;
          distinct = rr.reaches.hostN.x != rr.reaches.userU.y;
          y = marksAt rr "userU" "y";
        };
        expected = {
          vertices = 2;
          distinct = true;
          y = [ [ "y" ] ];
        };
      };
    # H4. Two two-definition carriers, a payload apart: two instances. RED (`key` reads `carrierKey`, a
    # hash over the fragment tokens): one vertex, and `y` delivers `x`'s marks. Control in both arms: a
    # carrier holding a function fragment keys apart.
    test-guard-carriers-two-instances =
      let
        rr = relOf carriers {
          n = hostAt "h1" [
            "x"
            "y"
          ];
        };
        carrFn = placedMods [
          {
            x = marked "x1";
            y = marked "y1";
          }
          {
            x.classOne = _: { };
            y.classOne = _: { };
          }
        ];
      in
      {
        expr = {
          vertices = vertexCount rr;
          x = marksAt rr "n" "x";
          y = marksAt rr "n" "y";
          ctlFunctionFragment = aspects.aspectId [ ] carrFn.x != aspects.aspectId [ ] carrFn.y;
        };
        expected = {
          vertices = 2;
          x = [
            [
              "x2"
              "x1"
            ]
          ];
          y = [
            [
              "y2"
              "y1"
            ]
          ];
          ctlFunctionFragment = true;
        };
      };
    # H5. The sharing H1–H4 must not break: one declaration reached from two host nodes at equal
    # formals is one instance (design Q6), and so is one reached from a host node and a user node
    # sourcing one `host`; from two hosts it is two.
    test-guard-one-declaration-shared =
      let
        one = placed { x = marked "x"; };
        count = scopes: vertexCount (relOf one scopes);
      in
      {
        expr = {
          equal = count {
            a = hostAt "h1" [ "x" ];
            b = hostAt "h1" [ "x" ];
          };
          crossNode = count {
            hostN = hostAt "h1" [ "x" ];
            userU = userAt "h1" "u1" [ "x" ];
          };
          distinct = count {
            a = hostAt "h1" [ "x" ];
            b = hostAt "h2" [ "x" ];
          };
        };
        expected = {
          equal = 1;
          crossNode = 1;
          distinct = 2;
        };
      };
    # H6. `key` of a placed guard is its declared path; `guardKey` of the same value, the TERM's key,
    # is unchanged (`guard:` + 64 hex, one for all four); static keys are unchanged.
    test-guard-key-is-the-declared-path =
      let
        stat = placed {
          sx.classOne.marks = [ "sx" ];
          f.sz.classOne.marks = [ "fz" ];
        };
        terms = map aspects.guardKey [
          siblings.x
          siblings.y
          nestedPair.f.x
          nestedPair.g.x
        ];
      in
      {
        expr = {
          keys = map aspects.key [
            siblings.x
            siblings.y
            nestedPair.f.x
            nestedPair.g.x
          ];
          oneTerm = builtins.all (k: k == builtins.head terms) terms;
          termPrefix = builtins.substring 0 6 (builtins.head terms);
          termLength = builtins.stringLength (builtins.head terms);
          static = [
            (aspects.key stat.sx)
            (aspects.key stat.f.sz)
          ];
        };
        expected = {
          keys = [
            "x"
            "y"
            "f/x"
            "g/x"
          ];
          oneTerm = true;
          termPrefix = "guard:";
          termLength = 70;
          static = [
            "sx"
            "f/sz"
          ];
        };
      };
    # R-9 (gate C-1). One scope never reads another's content: every instance a scope reaches, and the
    # nested one under it, is applied at the value its OWN sources name in `suppliers`. x and y share
    # source H, w has its own. RED (every key read from the first `suppliers` entry): w reads h1, or x
    # and y read h2.
    test-scope-reads-own-content =
      let
        sup = {
          ${entity "H"}.host = "h1";
          ${entity "H2"}.host = "h2";
        };
        src = {
          x = entity "H";
          y = entity "H";
          w = entity "H2";
        };
        rr = aspects.instancesFor { } rel {
          suppliers = sup;
          scopes = builtins.mapAttrs (_: s: {
            members = [ "e" ];
            sources.host = s;
          }) src;
        };
        read = n: map (id: rr.vertices.${id}.entry.description) rr.reaches.${n}.e;
      in
      {
        expr = {
          read = builtins.mapAttrs (n: _: read n) src;
          agrees = builtins.all (n: read n == [ "e-${sup.${src.${n}}.host}" ]) (builtins.attrNames src);
          nestedW = map (
            eid: map (id: rr.vertices.${id}.entry.description) rr.nested.${eid}.q
          ) rr.reaches.w.e;
        };
        expected = {
          read = {
            x = [ "e-h1" ];
            y = [ "e-h1" ];
            w = [ "e-h2" ];
          };
          agrees = true;
          nestedW = [ [ "q-h2" ] ];
        };
      };
    # n8wb5: the relation publishes its DECISION per handed scope. `declined.reaches.<node>` and
    # `declined.nested.<iid>` list the walked first-order guards whose condition RESOLVED FALSE at every
    # tuple tried. An edge is never declined; under the open world `has` over an absent coordinate is
    # refused (R), so the guard is in neither. `n`: `d` (eq FALSE) and `u` (reached through static `st` inside `o`'s
    # body, at node scope); `m` nested in `o`'s vertex. `nu`: `u` fans out to the user descendant.
    # RED (declined = walked minus edges, reading R as FALSE): `openN` = [ d u ], `openNested` = [ m ].
    test-declined-decision =
      let
        defs = {
          o = aspects.guard (aspects.pred.has "host") {
            description = "o";
            includes = [
              "m"
              "st"
            ];
          };
          m = aspects.guard (aspects.pred.has "user") { description = "m"; };
          st.includes = [ "u" ];
          u = aspects.guard (aspects.pred.has "user") { description = "u"; };
          d = aspects.guard (aspects.pred.eq [ "host" ] "other") { description = "d"; };
        };
        relOf =
          c:
          aspects.instancesFor c
            (mkSchemaEval ({ modules = [ { config.aspects = defs; } ]; } // c)).config.aspects
            {
              suppliers = {
                ${entity "h"}.host = "h";
                ${entity "u1"}.user = "u1";
              };
              scopes = {
                n = {
                  members = [
                    "o"
                    "d"
                  ];
                  sources.host = entity "h";
                };
                nu = {
                  members = [ "o" ];
                  sources.host = entity "h";
                  descendants = [ { sources.user = entity "u1"; } ];
                };
                omit = {
                  members = [ ];
                  sources.host = entity "h";
                };
              };
            };
        rc = relOf {
          entityKinds = {
            host = true;
            user = true;
          };
        };
        ro = relOf { };
        oAt = rr: builtins.head rr.reaches.n.o;
        disjoint =
          rr:
          builtins.all (n: builtins.all (a: !(rr.reaches.${n} ? ${a})) rr.declined.reaches.${n}) (
            builtins.attrNames rr.reaches
          );
      in
      {
        expr = {
          closedN = rc.declined.reaches.n;
          closedNested = rc.declined.nested.${oAt rc};
          closedNu = rc.declined.reaches.nu;
          nuReachesU = rc.reaches.nu ? u;
          omit = rc.declined.reaches.omit;
          openN = ro.declined.reaches.n;
          openNested = ro.declined.nested.${oAt ro};
          disjoint = disjoint rc && disjoint ro;
        };
        expected = {
          closedN = [
            "d"
            "u"
          ];
          closedNested = [ "m" ];
          closedNu = [ ];
          nuReachesU = true;
          omit = [ ];
          openN = [ "d" ];
          openNested = [ ];
          disjoint = true;
        };
      };
  };
}
