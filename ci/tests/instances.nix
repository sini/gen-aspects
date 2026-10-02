# `instanceOf` — the instance mint, and `instancesFor`, the instance relation (lib/instance.nix;
# den-hoag-0cmbt spec §2.5 and §2.6, cells I-1 to I-7, R-1 to R-9, and
# K-a/K-b through the mint). Every source is IDENTITY-shaped, minted here through gen-identity's
# `hashIdentity` under the entity and argument-binding kinds, because the mint refuses a context value
# and an aspect or instance identity as a source (the doors' cells are in ci/tests-error.nix,
# `instance-doors`).
{
  aspects,
  genIdentity,
  ...
}:
let
  entity = n: genIdentity.hashIdentity "entity" [ "name" ] (_: n);
  binding = n: genIdentity.hashIdentity "argument-binding" [ "name" ] (_: n);
  aspect = aspects.aspectId [ "probe" ] { name = "p"; };
  keys = c: builtins.concatStringsSep "," (builtins.attrNames c);
  p = aspects.wrapFn { } "p" ({ host, ... }: { description = "p-${host}"; });
  bare = aspects.wrapFn { } "b" (c: {
    description = "b:${keys c}";
  });
  bareK = aspects.wrapFn { entityKinds = [ "host" ]; } "b" (c: {
    description = "b:${keys c}";
  });
  empty = aspects.wrapFn { } "e" ({ }: { description = "e"; });
  # Two definitions under one key, one a context shape and one with formals: the aspect type's merge
  # builds a guard carrier (K2's site), never a wrap record.
  kinds = {
    entityKinds = [ "host" ];
  };
  twoDefs =
    (aspects.aspectType kinds).merge
      [ "m" ]
      [
        {
          file = "/a.nix";
          value = c: { description = "a:${keys c}"; };
        }
        {
          file = "/b.nix";
          value = { x }: { description = "b:${x}"; };
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
  rel = {
    e = aspects.wrapFn { } "e" (
      { host, ... }:
      {
        description = "e-${host}";
        includes = [ "q" ];
      }
    );
    q = aspects.wrapFn { } "q" ({ host, ... }: { description = "q-${host}"; });
    u = aspects.wrapFn { } "u" ({ user, ... }: { description = "u-${user}"; });
    # one global argument binding supplies `flavor` to every scope
    s = aspects.wrapFn { } "s" ({ flavor, ... }: { description = "s-${flavor}"; });
    w = {
      name = "w";
      includes = [
        "e"
        "u"
        "s"
      ];
    };
    # a parametric body including a STATIC node (the static-node rule)
    e2 = aspects.wrapFn { } "e2" ({ host, ... }: { includes = [ "w2" ]; });
    w2 = {
      name = "w2";
      includes = [ "q" ];
    };
    # a parametric body including `q` and a static node under inline content
    e3 = aspects.wrapFn { } "e3" (
      { host, ... }:
      {
        includes = [
          {
            name = "lit";
            includes = [
              "q"
              "w3"
            ];
          }
        ];
      }
    );
    w3 = {
      name = "w3";
      includes = [ "u" ];
    };
    # a parametric body including an aspect whose formal its tuple lacks
    eu = aspects.wrapFn { } "eu" ({ host, ... }: { includes = [ "u" ]; });
    # a static node holding inline content (stamped by the aspect type's merge, so it is content and
    # not sealed), and a guard record (no instance identity yet: O1)
    wc =
      (aspects.aspectType { }).merge
        [ "wc" ]
        [
          {
            file = "<wc>";
            value.includes = [
              {
                name = "lit";
                includes = [ "e" ];
              }
              "gr"
            ];
          }
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
    # I-4. Two definitions: the carrier's formals are the union of its function fragments' door keys
    # (`c:` narrowed to the kinds, `{ x }:` its formal), and the entry is the carrier discharged.
    test-two-definitions-union = {
      expr = {
        isCarrier = twoDefs ? fragments;
        formals = builtins.attrNames (inst kinds twoDefs twoDefsScope).formals;
        entry =
          (inst kinds twoDefs twoDefsScope).entry
          == (aspects.mkGuardVocab kinds).applyGuard twoDefsScope.context twoDefs;
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
        (inst { } (aspects.wrapFn { } "fa" ({ aspect }: { description = "fa-${aspect}"; })) {
          context.aspect = "A";
          sources.aspect = binding "A";
        }).formals;
      expected.aspect = binding "A";
    };
    # I-7's minting arm: an identity-shaped source of a supplier kind mints an instance identity.
    test-identity-source-mints = {
      expr = builtins.match "aspect-instance:[0-9a-f]{64}" (inst { } p (scope "h1" "x")).id != null;
      expected = true;
    };
    # K-a through the mint. A context shape under `entityKinds = [ "host" ]` receives `host` alone.
    test-kinds-narrow-formals = {
      expr = {
        formals = builtins.attrNames (inst kinds bareK (scope "h1" "x")).formals;
        entry = (inst kinds bareK (scope "h1" "x")).entry.description;
      };
      expected = {
        formals = [ "host" ];
        entry = "b:host";
      };
    };
    # K-b through the mint. With the kinds undeclared it receives, and is keyed on, the whole context.
    test-kinds-null-whole-context = {
      expr = {
        formals = builtins.attrNames (inst { } bare (scope "h1" "x")).formals;
        entry = (inst { } bare (scope "h1" "x")).entry.description;
      };
      expected = {
        formals = [
          "extra"
          "host"
        ];
        entry = "b:extra,host";
      };
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
          builtins.groupBy (id: r.vertices.${id}.aspect) (builtins.attrNames r.vertices)
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
    # (minted regardless): wrapFn's `requires context coord(s) 'user'` refusal on any read.
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
        uA = descs r.reaches.a.u;
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
        slice =
          rr: builtins.mapAttrs (id: _: rr.vertices.${id} // { nested = rr.nested.${id}; }) rA.vertices;
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
  };
}
