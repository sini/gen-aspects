# ANONYMOUS DECLARATIONS ARE NODES (den-hoag-8hlo3; identity design 2026-09-30 §1, §2, §4 row 1).
#
# Inline include content is its own node of `graphFacts`, keyed by its declaration: the declaring
# module's anchor and the structural path to the element (gen-merge `nests.declAt`), rendered
# injectively and never minted (7gp66 OQ4 (b′)). A content site gains the `target` naming its node,
# and `includesOf` lists it; a content position that is no node (a named element, content past the
# depth budget) stays in `unresolvedIncludesOf`.
#
# Each cell carries the arm that discriminates it: the `RED` comment names the edit that turns it.
{
  lib,
  mkSchemaEval,
  aspects,
  genMerge,
  ...
}:
let
  caught = e: (builtins.tryEval e).success;
  tryValue =
    v:
    let
      r = builtins.tryEval (builtins.deepSeq v v);
    in
    if r.success then r.value else "REFUSED";
  sorted = lib.sort (a: b: a < b);

  facts =
    mods:
    aspects.graphFacts { }
      (mkSchemaEval {
        fixtureKeySemantics = {
          T = {
            category = "class";
          };
        };
        modules = mods;
      }).config.aspects;
  marked = m: { T.marks = [ m ]; };
  # A class key's content is a deferred module: its marks are read through each `imports` layer.
  marksIn =
    v:
    if builtins.isAttrs v then
      (v.marks or [ ]) ++ builtins.concatMap marksIn (v.imports or [ ])
    else if builtins.isList v then
      builtins.concatMap marksIn v
    else
      [ ];
  marksOf = f: n: marksIn (f.nodeData.${n}.T or [ ]);
  # The node set less the walk's own nodes: the anonymous declarations.
  anonOf = f: builtins.filter (n: lib.hasInfix "/includes/" n) f.nodes;
  # One read of a facts record that must not refuse: its node set, parents and published relations.
  readAll =
    f:
    tryValue {
      inherit (f)
        nodes
        parentOf
        includesOf
        unresolvedIncludesOf
        ;
    };

  # A NAMED value, and a factory whose `name` sits at one source position however often it is called.
  named = {
    name = "t";
    T.marks = [ "t" ];
  };
  mk = m: {
    name = "t";
    T.marks = [ m ];
  };
  # A literal that includes itself: positions without end.
  cyc =
    let
      s = marked "s" // {
        includes = [ s ];
      };
    in
    s;

  kA = {
    key = "mA";
    config.aspects.a.includes = [ (marked "p") ];
  };
  kB = {
    key = "mB";
    config.aspects.a.includes = [ (marked "q") ];
  };
  keysOf = f: sorted (anonOf f);
in
{
  # A1. An owner's inline literals are nodes, nested content included, and each content site names
  # one. RED (no anonymous nodes): `nodes = [ "a" "b" ]`, no site carries a `target`, and
  # `unresolvedIncludesOf.a = [ 0 1 ]`.
  flake.tests.anonymous-nodes.test-inline-literals-are-nodes =
    let
      f = facts [
        {
          config.aspects.b = marked "b";
          config.aspects.a.includes = [
            (marked "1")
            (
              marked "2"
              // {
                includes = [ (marked "3") ];
              }
            )
            "b"
          ];
        }
      ];
      outer = (builtins.elemAt f.includeSitesOf.a 1).target;
      inner = (builtins.head (builtins.elemAt f.includeSitesOf.a 1).sites).target;
    in
    {
      expr = {
        anonymous = builtins.length (anonOf f);
        targetsAreNodes = builtins.all (t: builtins.elem t f.nodes) (
          lib.concatLists (builtins.attrValues f.includesOf)
        );
        includesOf = f.includesOf.a;
        unresolved = f.unresolvedIncludesOf.a;
        outerParent = f.parentOf.${outer};
        innerParent = f.parentOf.${inner} == outer;
        innerIncludesOf = f.includesOf.${outer} == [ inner ];
        # The value under the anonymous id is the element itself.
        valueIsTheElement = f.nodeData.${outer} == builtins.elemAt f.nodeData.a.includes 1;
        # `nodes` is `attrNames` order, so every relation's domain is it by construction.
        domains = builtins.attrNames f.parentOf == f.nodes && builtins.attrNames f.includesOf == f.nodes;
      };
      expected = {
        anonymous = 3;
        targetsAreNodes = true;
        includesOf = [
          "a/includes/[\"a:2\",\"aspects\",\"a\",\"includes\",0]"
          "a/includes/[\"a:2\",\"aspects\",\"a\",\"includes\",1]"
          "b"
        ];
        unresolved = [ ];
        outerParent = "a";
        innerParent = true;
        innerIncludesOf = true;
        valueIsTheElement = true;
        domains = true;
      };
    };

  # A2. A forged key stays at its site: the element's site refuses, and `nodes` and its sibling read.
  # RED (the node predicate reads the key unguarded): `nodes` REFUSED.
  flake.tests.anonymous-nodes.test-forged-key-stays-at-its-site =
    let
      f = facts [
        {
          config.aspects.app.includes = [
            (marked "s")
            (
              {
                key = "app/includes/zz";
              }
              // marked "f"
            )
          ];
        }
      ];
    in
    {
      expr = {
        nodes = tryValue f.nodes;
        siteRefuses = !(caught (builtins.deepSeq (builtins.elemAt f.includeSitesOf.app 1).kind null));
        siblingReads = caught (builtins.deepSeq (builtins.head f.includeSitesOf.app).target null);
      };
      expected = {
        nodes = [
          "app"
          "app/includes/[\"a:2\",\"aspects\",\"app\",\"includes\",0]"
        ];
        siteRefuses = true;
        siblingReads = true;
      };
    };

  # K1. NAMED content is a position, not a node: its §2 site (the position of its `name`) is not
  # injective, and EVERY route by which two declarations reach one named site is celled here: one
  # value twice in one definition, a factory applied twice, one value from two modules, one value in
  # two `mkMerge` branches, and the same pair nested inside an inline literal. The node set and every
  # relation read, the named positions are unresolved, and a node reaching none of them (`z`) is
  # untouched. RED (named content keyed into the node set): every arm's `nodes` REFUSED, `z` with it.
  flake.tests.anonymous-nodes.test-named-content-is-a-position =
    let
      arm =
        mods:
        let
          f = facts mods;
        in
        {
          read = readAll f != "REFUSED";
          unresolved = tryValue f.unresolvedIncludesOf.a;
          anonymous = tryValue (builtins.length (anonOf f));
        };
    in
    {
      expr = {
        namedDup = arm [
          {
            config.aspects.a.includes = [
              named
              named
            ];
          }
        ];
        namedFactory = arm [
          {
            config.aspects.a.includes = [
              (mk "1")
              (mk "2")
            ];
          }
        ];
        namedTwoMods = arm [
          { config.aspects.a.includes = [ named ]; }
          { config.aspects.a.includes = [ named ]; }
        ];
        namedMkMerge = arm [
          {
            config.aspects.a.includes = genMerge.mkMerge [
              [ named ]
              [ named ]
            ];
          }
        ];
        namedNested = arm [
          {
            config.aspects.a.includes = [
              {
                includes = [
                  named
                  named
                ];
              }
            ];
          }
        ];
        # The blast radius: `z` reaches only `c`, beside a duplicated named value at `a`.
        namedDupBlast =
          let
            f = facts [
              {
                config.aspects.c = marked "c";
                config.aspects.z.includes = [ "c" ];
                config.aspects.a.includes = [
                  named
                  named
                ];
              }
            ];
          in
          tryValue f.includesOf.z;
      };
      expected = {
        namedDup = {
          read = true;
          unresolved = [
            0
            1
          ];
          anonymous = 0;
        };
        namedFactory = {
          read = true;
          unresolved = [
            0
            1
          ];
          anonymous = 0;
        };
        namedTwoMods = {
          read = true;
          unresolved = [
            0
            1
          ];
          anonymous = 0;
        };
        namedMkMerge = {
          read = true;
          unresolved = [
            0
            1
          ];
          anonymous = 0;
        };
        # The unnamed literal holding them is a node; its named contents are its positions.
        namedNested = {
          read = true;
          unresolved = [ ];
          anonymous = 1;
        };
        namedDupBlast = [ "c" ];
      };
    };

  # K3. An unnamed element writing `meta.loc` (here, its sibling's rendered site) refuses by name at
  # the element: its site refuses, and the node set and the sibling read. The same write at another
  # owner refuses there. RED (the stamp skips an element already carrying `meta.loc`): the two keys
  # are equal and `nodes` REFUSED.
  flake.tests.anonymous-nodes.test-authored-loc-refuses-at-the-element =
    let
      victimSeg = builtins.toJSON [
        "a:2"
        "aspects"
        "a"
        "includes"
        0
      ];
      forged = {
        meta.loc = [
          "a"
          "includes"
          victimSeg
        ];
      }
      // marked "forged";
      f = facts [
        {
          config.aspects.a.includes = [
            (marked "1")
            forged
          ];
        }
      ];
      g = facts [
        {
          config.aspects.a.includes = [ (marked "1") ];
          config.aspects.b.includes = [ forged ];
        }
      ];
    in
    {
      expr = {
        nodes = tryValue f.nodes;
        forgedSiteRefuses = !(caught (builtins.deepSeq (builtins.elemAt f.includeSitesOf.a 1).kind null));
        siblingReads = tryValue (builtins.head f.includeSitesOf.a).target;
        otherOwnerNodes = tryValue g.nodes;
        otherOwnerRefuses = !(caught (builtins.deepSeq g.includesOf.b null));
        otherOwnerVictimReads = tryValue g.includesOf.a;
      };
      expected = {
        nodes = [
          "a"
          "a/includes/[\"a:2\",\"aspects\",\"a\",\"includes\",0]"
        ];
        forgedSiteRefuses = true;
        siblingReads = "a/includes/[\"a:2\",\"aspects\",\"a\",\"includes\",0]";
        otherOwnerNodes = [
          "a"
          "a/includes/[\"a:2\",\"aspects\",\"a\",\"includes\",0]"
          "b"
        ];
        otherOwnerRefuses = true;
        otherOwnerVictimReads = [ "a/includes/[\"a:2\",\"aspects\",\"a\",\"includes\",0]" ];
      };
    };

  # K4 (and design §4 row 1, "it stays lazy"). A cyclic literal is a node only within the depth
  # budget: the published relations deep-read, the deepest node lists its past-budget site as an
  # unresolved position, and only a reader descending past the budget refuses. RED (`includesOf`
  # reads `target` over a target-less site): the deep read aborts with `attribute 'target' missing`,
  # which `tryEval` cannot catch, so the cell dies.
  flake.tests.anonymous-nodes.test-past-budget-content-is-unresolved =
    let
      f = facts [
        {
          config.aspects.a.includes = [ cyc ];
          config.aspects.b.includes = [ (marked "bl") ];
        }
      ];
      depthOf = n: if f.parentOf.${n} == null then 0 else 1 + depthOf f.parentOf.${n};
      atBudget = builtins.head (lib.sort (x: y: depthOf x > depthOf y) (anonOf f));
    in
    {
      expr = {
        relationsRead = caught (
          builtins.deepSeq [
            f.includesOf
            f.unresolvedIncludesOf
            f.parentOf
          ] null
        );
        nodeCount = builtins.length f.nodes;
        deepestDepth = depthOf atBudget;
        deepestUnresolved = f.unresolvedIncludesOf.${atBudget};
        deepestIncludesOf = f.includesOf.${atBudget};
        pastBudgetRefuses =
          !(caught (builtins.deepSeq (builtins.head f.includeSitesOf.${atBudget}).sites null));
        # CONTROL: the unrelated owner is untouched.
        b = builtins.length f.includesOf.b;
      };
      expected = {
        relationsRead = true;
        # a, b, b's literal, and 255 levels of the cyclic literal.
        nodeCount = 258;
        deepestDepth = 255;
        deepestUnresolved = [ 0 ];
        deepestIncludesOf = [ ];
        pastBudgetRefuses = true;
        b = 1;
      };
    };

  # A5. One let-bound literal included by two owners is two nodes (identity design Q1, "two").
  # RED (content keyed by its value): one id.
  flake.tests.anonymous-nodes.test-one-literal-at-two-owners-is-two-nodes =
    let
      l = marked "l";
      f = facts [
        {
          config.aspects.v.includes = [ l ];
          config.aspects.w.includes = [ l ];
        }
      ];
    in
    {
      expr = {
        v = f.includesOf.v;
        w = f.includesOf.w;
      };
      expected = {
        v = [ "v/includes/[\"a:2\",\"aspects\",\"v\",\"includes\",0]" ];
        w = [ "w/includes/[\"a:2\",\"aspects\",\"w\",\"includes\",0]" ];
      };
    };

  # A6. An element's id is its DECLARATION: invariant under a reorder of keyed modules and under a
  # sibling module's discharged `mkIf`; an anonymous module's elements move with that module's own
  # position (identity design §1 item 2, declared). RED (the merge position): the keyed pair moves,
  # `[definition 1-entry 1]` ↔ `[definition 2-entry 1]`.
  flake.tests.anonymous-nodes.test-element-id-is-its-declaration =
    let
      sib = on: {
        config.aspects.a.includes = genMerge.mkIf on [ (marked "s") ];
      };
      lone = {
        config.aspects.a.includes = [ (marked "e") ];
      };
      elemId =
        mods: tag:
        let
          f = facts mods;
        in
        builtins.head (builtins.filter (n: marksOf f n == [ tag ]) (anonOf f));
    in
    {
      expr = {
        keyed =
          keysOf (facts [
            kA
            kB
          ]) == keysOf (facts [
            kB
            kA
          ]);
        keyedP = elemId [ kA kB ] "p";
        siblingMkIf = elemId [ lone (sib true) ] "e" == elemId [ lone (sib false) ] "e";
        anonymousAB = elemId [ lone (sib false) ] "e";
        anonymousBA = elemId [ (sib false) lone ] "e";
      };
      expected = {
        keyed = true;
        keyedP = "a/includes/[\"kmA\",\"aspects\",\"a\",\"includes\",0]";
        siblingMkIf = true;
        anonymousAB = "a/includes/[\"a:2\",\"aspects\",\"a\",\"includes\",0]";
        anonymousBA = "a/includes/[\"a:3\",\"aspects\",\"a\",\"includes\",0]";
      };
    };

  # C1. A typed content value placed at a second position is re-declared there: its own node, keyed by
  # its own inclusion site, its content unchanged (identity design Q1; ADR-0016 r5). Routes: an edited
  # same-tree copy, an unedited one, and a copy from another evaluation. RED (the copy keeps its
  # source's key): b's include names a's node.
  flake.tests.anonymous-nodes.test-a-copy-is-its-own-node =
    let
      other = facts [ { config.aspects.a.includes = [ (marked "o") ]; } ];
      otherEval =
        (mkSchemaEval {
          fixtureKeySemantics.T.category = "class";
          modules = [ { config.aspects.a.includes = [ (marked "o") ]; } ];
        }).config.aspects;
      copy =
        edit:
        facts [
          (
            { config, ... }:
            {
              config.aspects.a.includes = [ (marked "h") ];
              config.aspects.b.includes = [ (edit (builtins.head config.aspects.a.includes)) ];
            }
          )
        ];
      edited = copy (e: e // marked "edited");
      plain = copy (e: e);
      fromOther = facts [ { config.aspects.b.includes = [ (builtins.head otherEval.a.includes) ]; } ];
      bNode = f: builtins.head f.includesOf.b;
    in
    {
      expr = {
        editedIsB = bNode edited;
        editedMarks = marksOf edited (bNode edited);
        aUnmoved = marksOf edited (builtins.head edited.includesOf.a);
        plainIsB = bNode plain;
        fromOtherIsB = bNode fromOther;
        fromOtherMarks = marksOf fromOther (bNode fromOther);
        # CONTROL: the source's own id, in its own evaluation.
        sourceId = builtins.head other.includesOf.a;
      };
      expected = {
        editedIsB = "b/includes/[\"a:2\",\"aspects\",\"b\",\"includes\",0]";
        editedMarks = [ "edited" ];
        aUnmoved = [ "h" ];
        plainIsB = "b/includes/[\"a:2\",\"aspects\",\"b\",\"includes\",0]";
        fromOtherIsB = "b/includes/[\"a:2\",\"aspects\",\"b\",\"includes\",0]";
        fromOtherMarks = [ "o" ];
        sourceId = "a/includes/[\"a:2\",\"aspects\",\"a\",\"includes\",0]";
      };
    };
}
