# First-order guards, gen-aspects end to end (den-hoag-lwbb1 unit 2 stage 2a;
# specs/2026-10-02-gen-aspects-first-order-guards-spec-v1.md §3a, the gating oracle). A guard is a
# condition term and a body term of gen-algebra's one algebra, checked where it meets its cnf, keyed by
# the mint over the two, fired through a read environment that carries the framework's door
# (`cnf.ref`) and, inside one firing, the scope it returns (design G5). Each cell holds its refusal and
# its admitted control in one expression. The message each refusal SAYS is pinned on the error plane
# (`ci/tests-error.nix`, `first-order-guards`); these cells pin that it is CATCHABLE.
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
  t = T.term;
  ok = v: (builtins.tryEval (builtins.deepSeq v true)).success;
  src = n: "entity:" + builtins.hashString "sha256" n;

  # A guard placed at an aspect position of a schema evaluation under `cnf`, with `nixos` a class key.
  place =
    cnf: defs:
    (mkSchemaEval (
      cnf
      // {
        keySemantics.nixos.category = "class";
        modules = [ { config.aspects = defs; } ];
      }
    )).config.aspects;

  tuck = a.guard (a.pred.has "thimble") {
    description = t.concat [
      (t.lit "tuck-")
      (t.readCtx "thimble" [ ])
    ];
  };
  fireIn =
    cnf: ctx:
    let
      gv = a.mkGuardVocab cnf;
      g = (place cnf { inherit tuck; }).tuck;
    in
    gv.applyGuard ctx g;

  # The framework side: a stub door over two registered closures, an outer and the inner it returns.
  rOuter =
    (T.refId {
      declared = {
        site = "outer";
        reads = [ "thimble" ];
      };
    }).right;
  inner = { bobbin, ... }: { description = "i-${bobbin}"; };
  outer = { thimble, ... }: {
    description = "o-${thimble}";
    includes = [ inner ];
  };
  nestedId =
    sources:
    (T.refId {
      nested = {
        outer = rOuter;
        sources = { inherit (sources) thimble; };
        position = [
          "includes"
          0
        ];
        reads = [ "bobbin" ];
      };
    }).right;
  lowerOuter =
    sources: out:
    let
      r = nestedId sources;
    in
    {
      output = out // {
        includes = [
          (a.guard (a.pred.all [
            (a.pred.has "thimble")
            (a.pred.has "bobbin")
          ]) (t.ref r))
        ];
      };
      scope.${r} = builtins.head out.includes;
    };
  door =
    {
      id,
      context,
      sources,
      captured,
    }:
    let
      r = builtins.fromJSON id;
    in
    if r ? declared then
      {
        right = lowerOuter sources (outer {
          inherit (context) thimble;
        });
      }
    else if r.nested.sources.thimble != sources.thimble then
      {
        left = {
          code = "source-mismatch";
          witness = { };
        };
      }
    else
      let
        f =
          if captured != null then
            captured
          else
            builtins.head (outer { inherit (context) thimble; }).includes;
      in
      {
        right = {
          output = f { inherit (context) bobbin; } // {
            via = if captured != null then "scope" else "reapply";
          };
          scope = { };
        };
      };
  dcnf = {
    entityKinds = {
      thimble = true;
      bobbin = true;
    };
    ref = door;
  };
  doorNode = a.guard (a.pred.all [ (a.pred.has "thimble") ]) (t.ref rOuter);
  ctx2 = {
    thimble = "pewter";
    bobbin = "damask";
  };
  srcs2 = {
    thimble = src "pewter";
    bobbin = src "damask";
  };
  inst =
    cnf: value: context: sources:
    a.instanceOf cnf {
      aspect = "x";
      inherit value context sources;
    };

  cells = {
    # Design Section 3, `tuck`'s target and C116 per regime.
    test-tuck-open-world = {
      expr = {
        fires = fireIn { } { thimble = "pewter"; };
        missingRefused = !(ok (fireIn { } { bobbin = "damask"; }));
      };
      expected = {
        fires.description = "tuck-pewter";
        missingRefused = true;
      };
    };
    test-tuck-closed-declared = {
      expr = {
        fires = fireIn {
          entityKinds = {
            thimble = false;
            bobbin = false;
          };
        } { thimble = "pewter"; };
        missing = fireIn {
          entityKinds = {
            thimble = false;
            bobbin = false;
          };
        } { bobbin = "damask"; };
      };
      expected = {
        fires.description = "tuck-pewter";
        missing = null;
      };
    };
    test-tuck-closed-undeclared = {
      expr = {
        undeclared =
          ok
            (place {
              entityKinds = {
                thimbel = false;
                bobbin = false;
              };
            } { inherit tuck; }).tuck;
        control =
          ok
            (place {
              entityKinds = {
                thimble = false;
                bobbin = false;
              };
            } { inherit tuck; }).tuck;
      };
      expected = {
        undeclared = false;
        control = true;
      };
    };
    # Section 2 safety, at declaration: a read no positive atom covers.
    test-unsafe-read-refused = {
      expr = {
        unsafe = ok (place { } { u = a.guard a.pred.always { description = t.readCtx "thimble" [ ]; }; }).u;
        control =
          ok
            (place { } { u = a.guard (a.pred.has "thimble") { description = t.readCtx "thimble" [ ]; }; }).u;
      };
      expected = {
        unsafe = false;
        control = true;
      };
    };
    # `class` lowers to the core `eq` (design P1); firing is unchanged on a scalar.
    test-class-lowers-to-eq = {
      expr = {
        same = a.pred.class "nixos" == t.eq [ "class" ] "nixos";
        tagSame = a.pred.tagEq "k" "v" == t.eq [ "tags" "k" ] "v";
        fires = (a.mkGuardVocab { }).applyGuard { class = "nixos"; } (
          a.guard (a.pred.class "nixos") "piping"
        );
      };
      expected = {
        same = true;
        tagSame = true;
        fires = "piping";
      };
    };
    # The measured eq changes (unifying §2.3): a composite value fires on equality; a path value is unmintable.
    test-eq-composite-fires = {
      expr = (a.mkGuardVocab { }).applyGuard { host.name = "x"; } (
        a.guard (a.pred.eq [ "host" ] { name = "x"; }) "y"
      );
      expected = "y";
    };
    # The TERM is unmintable (a path as an `eq` value), so `guardKey` refuses; the declaration still
    # has its key, its declared path (design §4's sealed row: "the site has a declaration key").
    test-eq-path-guard-unmintable = {
      expr = {
        key = ok (
          a.guardKey (place { } { p = a.guard (a.pred.eq [ "p" ] ./first-order-guards.nix) "y"; }).p
        );
        control = ok (a.guardKey (place { } { p = a.guard (a.pred.eq [ "p" ] "s") "y"; }).p);
        declared = a.key (place { } { p = a.guard (a.pred.eq [ "p" ] ./first-order-guards.nix) "y"; }).p;
      };
      expected = {
        key = false;
        control = true;
        declared = "p";
      };
    };
    # The guard mint's DECISION site answers off the minted arm (den-hoag-dg8d1): a guard over a term
    # with no identity still checks, and its tagged sum, read through gen-algebra's `identityOf`, is
    # the unmintable arm, an answer and not an abort.
    test-guard-over-an-unmintable-term-answers-unmintable = {
      expr = genAlgebra.regimeTagOf (
        genAlgebra.identityOf
          (place { } { p = a.guard (a.pred.eq [ "p" ] ./first-order-guards.nix) "y"; }).p
      );
      expected = "s";
    };
    # UC1: a door-registration `ref` only as the whole body.
    test-ref-position = {
      expr = {
        below = ok (place { } { d = a.guard a.pred.always { a = t.ref rOuter; }; }).d;
        inList = ok (place { } { d = a.guard a.pred.always [ (t.ref rOuter) ]; }).d;
        atClassKey = ok (place { } { d = a.guard a.pred.always { nixos = t.ref rOuter; }; }).d;
        whole = ok (place { } { d = a.guard (a.pred.has "thimble") (t.ref rOuter); }).d;
      };
      expected = {
        below = false;
        inList = false;
        atClassKey = false;
        whole = true;
      };
    };
    # den-hoag-gkar9 term 2: a fired body that is the lift's image of plain data (no term its author
    # wrote, nothing nested but module slots) is served as written, a slot's function as written; every
    # other body is resolved: a term at a class key or in a list, an authored closed term (`t.lit`,
    # whose source is the term record, not its value), and a nested guard, which arrives as the CHECKED
    # record the outer's firing resolves it to.
    test-fired-body-served-or-resolved =
      let
        gv = a.mkGuardVocab { };
        fire = ctx: g: gv.applyGuard ctx (place { } { d = g; }).d;
        modFn = { config, ... }: { marker = "m"; };
        slotted = a.guard a.pred.always { includes = [ modFn ]; };
        ground = {
          description = "g";
          xs = [
            1
            { y = "z"; }
          ];
        };
      in
      {
        expr = {
          ground = fire { } (a.guard a.pred.always ground);
          classTerm = fire { thimble = "p"; } (
            a.guard (a.pred.has "thimble") { nixos = t.readCtx "thimble" [ ]; }
          );
          listTerm = fire { thimble = "p"; } (
            a.guard (a.pred.has "thimble") { xs = [ (t.readCtx "thimble" [ ]) ]; }
          );
          nestedChecked =
            (fire { } (a.guard a.pred.always { sub = a.guard a.pred.always { description = "d"; }; }))
            .sub.__checked or false;
          authoredClosed = fire { } (a.guard a.pred.always { description = t.lit "x"; });
          slot = {
            served = ((place { } { d = slotted; }).d.__served or null) != null;
            fn = ((builtins.head (fire { } slotted).includes) { config = { }; }).marker;
          };
        };
        expected = {
          inherit ground;
          classTerm.nixos = "p";
          listTerm.xs = [ "p" ];
          nestedChecked = true;
          authoredClosed.description = "x";
          slot = {
            served = true;
            fn = "m";
          };
        };
      };
    # A door node fires through the framework's door (cnf.ref), its nested node at the same context
    # through the returned scope (G5's lexically nested path).
    test-door-node-nested-scope = {
      expr = (inst dcnf doorNode ctx2 srcs2).entry;
      expected = {
        description = "o-pewter";
        includes = [
          {
            description = "i-damask";
            via = "scope";
          }
        ];
      };
    };
    # The fallback: the nested node fired outside the producing firing re-applies the outer.
    test-door-node-fallback = {
      expr =
        let
          node =
            builtins.head
              (lowerOuter srcs2 (outer {
                thimble = "pewter";
              })).output.includes;
        in
        (inst dcnf node ctx2 srcs2).entry;
      expected = {
        description = "i-damask";
        via = "reapply";
      };
    };
    test-door-node-applyGuard-refused = {
      expr = {
        refused = !(ok ((a.mkGuardVocab dcnf).applyGuard ctx2 doorNode));
        control = (inst dcnf doorNode ctx2 srcs2).entry.description;
      };
      expected = {
        refused = true;
        control = "o-pewter";
      };
    };
    # Instance keys by derived reads, each by its source (design Section 3; 0cmbt O1).
    test-instance-keys-by-reads = {
      expr =
        let
          i1 = inst { } tuck ctx2 srcs2;
          i2 = inst { } tuck (ctx2 // { bobbin = "silk"; }) (srcs2 // { bobbin = src "silk"; });
          i3 = inst { } tuck (ctx2 // { thimble = "tin"; }) (srcs2 // { thimble = src "tin"; });
        in
        {
          formals = builtins.attrNames i1.formals;
          sameAcrossUnread = i1.id == i2.id;
          differsOnRead = i1.id != i3.id;
          doorFormals = builtins.attrNames (inst dcnf doorNode ctx2 srcs2).formals;
        };
      expected = {
        formals = [ "thimble" ];
        sameAcrossUnread = true;
        differsOnRead = true;
        doorFormals = [ "thimble" ];
      };
    };
    # Guard TERM identity (`guardKey`) is the mint over (condition, body): site-independent,
    # body-discriminating, and a module slot's payload is outside the preimage (its key is not). Each
    # placement is a declaration of its own, keyed by its declared path (identity design §1).
    test-guard-identity-mint = {
      expr =
        let
          ps = place { } {
            p1 = a.guard (a.pred.has "thimble") { nixos = { pkgs, ... }: { }; };
            p2 = a.guard (a.pred.has "thimble") { nixos = { config, ... }: { }; };
            p3 = a.guard (a.pred.has "thimble") { description = "d"; };
            p4 = a.guard (a.pred.has "thimble") { description = "e"; };
            p5 = a.guard (a.pred.has "thimble") { nixos.networking.hostName = "a"; };
            p6 = a.guard (a.pred.has "thimble") { nixos.networking.hostName = "b"; };
          };
        in
        {
          slotPayloadOutside = a.guardKey ps.p1 == a.guardKey ps.p2;
          attrsetSlotOutside = a.guardKey ps.p5 == a.guardKey ps.p6;
          bodyDiscriminates = a.guardKey ps.p3 != a.guardKey ps.p4;
          minted = builtins.substring 0 6 (a.guardKey ps.p3);
          declarations = map a.key [
            ps.p1
            ps.p2
            ps.p5
            ps.p6
          ];
        };
      expected = {
        slotPayloadOutside = true;
        attrsetSlotOutside = true;
        bodyDiscriminates = true;
        minted = "guard:";
        declarations = [
          "p1"
          "p2"
          "p5"
          "p6"
        ];
      };
    };
    # A function outside a module slot is refused by name; a module function at a class key is admitted
    # and handed back unapplied (design Section 1, [gate v1 Q7]).
    test-module-slot-rule = {
      expr = {
        closureBody = ok (place { } { c = a.guard a.pred.always (ctx: { }); }).c;
        notModuleFn = ok (place { } { c = a.guard a.pred.always { nixos = x: x; }; }).c;
        moduleFn =
          builtins.isFunction
            ((a.mkGuardVocab { }).applyGuard { }
              (place { } { c = a.guard a.pred.always { nixos = { pkgs, ... }: { }; }; }).c
            ).nixos;
        # An attrset module holding a module function at depth is one slot, never descended.
        moduleAttrs =
          ok
            (place { } { c = a.guard a.pred.always { nixos.imports = [ ({ pkgs, ... }: { }) ]; }; }).c;
      };
      expected = {
        closureBody = false;
        notModuleFn = false;
        moduleFn = true;
        moduleAttrs = true;
      };
    };
    # P3: one D to the check and the resolver.
    test-one-declared-set = {
      expr =
        let
          cw = {
            entityKinds = {
              thimble = false;
            };
          };
          g = (place cw { inherit tuck; }).tuck;
        in
        {
          mismatch = ok ((a.mkGuardVocab { }).applyGuard { thimble = "pewter"; } g);
          same = ((a.mkGuardVocab cw).applyGuard { bobbin = "x"; } g);
        };
      expected = {
        mismatch = false;
        same = null;
      };
    };
    # An aspect reference (design Q7 (2), `selfw`'s migration) resolves to the include position's local
    # reference, the bare key.
    test-aspect-ref = {
      expr = (a.mkGuardVocab { }).applyGuard { } (
        a.guard a.pred.always { includes = [ (t.ref "selfw") ]; }
      );
      expected = {
        includes = [ "selfw" ];
      };
    };
    # The instance relation mints a first-order guard where its condition holds.
    test-instances-for-term-guard = {
      expr =
        let
          aspects = place { } {
            host = {
              includes = [ "tuck" ];
            };
            inherit tuck;
          };
          r = a.instancesFor { } aspects {
            containment = { };
            suppliers = {
              ${src "pewter"}.thimble = "pewter";
              ${src "none"}.bobbin = "b";
            };
            scopes = {
              with_ = {
                members = [ "host" ];
                sources.thimble = src "pewter";
              };
              without = {
                members = [ "host" ];
                sources.bobbin = src "none";
              };
            };
          };
        in
        {
          withEdges = builtins.length (r.reaches.with_.tuck or [ ]);
          withoutEdges = builtins.length (r.reaches.without.tuck or [ ]);
          entries = map (v: v.entry) (builtins.attrValues r.vertices);
        };
      expected = {
        withEdges = 1;
        withoutEdges = 0;
        entries = [ { description = "tuck-pewter"; } ];
      };
    };
    # ── v1 (gate contact 1) ──
    # G-C1: a guard nested in a guard's body stays a guard, fires at its own firing, reads under its own
    # condition, and its identity enters the outer's.
    test-nested-guard-stays-guard = {
      expr =
        let
          gv = a.mkGuardVocab { };
          o =
            (place { } {
              o = a.guard a.pred.always { sub = a.guard (a.pred.class "nixos") { description = "d"; }; };
            }).o;
          fired = gv.applyGuard { class = "darwin"; } o;
          inList =
            gv.applyGuard { class = "darwin"; }
              (place { } {
                o = a.guard a.pred.always {
                  includes = [ (a.guard (a.pred.class "nixos") { description = "d"; }) ];
                };
              }).o;
          covered =
            (place { } {
              o = a.guard a.pred.always {
                sub = a.guard (a.pred.has "thimble") { description = t.readCtx "thimble" [ ]; };
              };
            }).o;
          k = inner: a.guardKey (place { } { o = a.guard a.pred.always { sub = inner; }; }).o;
        in
        {
          subIsGuard = fired.sub.__guard or false;
          refire = gv.applyGuard { class = "nixos"; } fired.sub;
          refireFalse = gv.applyGuard { class = "darwin"; } fired.sub;
          listRefire = gv.applyGuard { class = "nixos"; } (builtins.head inList.includes);
          innerCovered = gv.applyGuard { thimble = "p"; } (gv.applyGuard { } covered).sub;
          innerIdentityEnters =
            k (a.guard (a.pred.class "nixos") "x") != k (a.guard (a.pred.class "darwin") "x");
          outerReadsNotInner = (inst { } covered ctx2 srcs2).formals;
          declared = a.key o;
        };
      expected = {
        subIsGuard = true;
        refire.description = "d";
        refireFalse = null;
        listRefire.description = "d";
        innerCovered.description = "p";
        innerIdentityEnters = true;
        outerReadsNotInner = { };
        declared = "o";
      };
    };
    # G-C2: a cyclic body is refused catchably (den-hoag-49xc's property, now a refusal); an acyclic control mints.
    test-cyclic-body-refused = {
      expr =
        let
          self = a.guard a.pred.always { sub = self; };
          cyc =
            let
              x = {
                a = x;
              };
            in
            a.guard a.pred.always x;
        in
        {
          selfLoop = ok (a.key (place { } { s = self; }).s);
          cyclicAttrs = ok (a.key (place { } { s = cyc; }).s);
          control = ok (
            a.key (place { } { s = a.guard a.pred.always { sub = a.guard a.pred.always "x"; }; }).s
          );
        };
      expected = {
        selfLoop = false;
        cyclicAttrs = false;
        control = true;
      };
    };
    # G-C2: base's budgets kept (256): a 248-guard chain checks, keys and fires to its leaf; a
    # 260-guard chain is refused catchably.
    test-guard-chain-depth = {
      expr =
        let
          chain = n: builtins.foldl' (b: _: a.guard a.pred.always b) "leaf" (builtins.genList (x: x) n);
          down =
            v:
            if builtins.isAttrs v && (v.__guard or false) then
              down ((a.mkGuardVocab { }).applyGuard { } v)
            else
              v;
          c248 = (place { } { c = chain 248; }).c;
        in
        {
          within = ok (a.key c248);
          firesToLeaf = down c248;
          over = ok (a.key (place { } { c = chain 260; }).c);
        };
      expected = {
        within = true;
        firesToLeaf = "leaf";
        over = false;
      };
    };
    # A module function at an aspect position of a guard body (the whole body, an `includes` element) is
    # a module slot, carried unapplied as base carried it; a context closure there is refused; the slot's
    # position, not its payload, enters the identity.
    test-module-fn-aspect-positions = {
      expr =
        let
          gv = a.mkGuardVocab { };
          fire =
            body: gv.applyGuard { class = "nixos"; } (place { } { g = a.guard (a.pred.class "nixos") body; }).g;
          k = body: a.guardKey (place { } { g = a.guard a.pred.always body; }).g;
        in
        {
          wholeBody = builtins.isFunction (fire ({ config, ... }: { }));
          inIncludes = builtins.isFunction (
            builtins.head (fire { includes = [ ({ config, ... }: { }) ]; }).includes
          );
          contextClosureInIncludes = ok (fire {
            includes = [ ({ host, ... }: { }) ];
          });
          payloadOutside =
            k { includes = [ ({ config, ... }: { a = 1; }) ]; } == k { includes = [ ({ pkgs, ... }: { }) ]; };
          positionEnters =
            k { includes = [ ({ config, ... }: { }) ]; } != k {
              includes = [
                "x"
                ({ config, ... }: { })
              ];
            };
          declared =
            a.key
              (place { } { g = a.guard a.pred.always { includes = [ ({ config, ... }: { }) ]; }; }).g;
        };
      expected = {
        wholeBody = true;
        inIncludes = true;
        contextClosureInIncludes = false;
        payloadOutside = true;
        positionEnters = true;
        declared = "g";
      };
    };
    # G-C3: every malformed door refuses catchably; a conforming door fires.
    test-door-totality =
      let
        rid =
          (T.refId {
            declared = {
              site = "outer";
              reads = [ "thimble" ];
            };
          }).right;
        nid =
          (T.refId {
            nested = {
              outer = rid;
              sources = {
                thimble = src "pewter";
              };
              position = [
                "includes"
                0
              ];
              reads = [ ];
            };
          }).right;
        dn = a.guard (a.pred.has "thimble") (t.ref rid);
        go = door: ok (inst { ref = door; } dn ctx2 srcs2).entry;
      in
      {
        expr = {
          notFunction = go "x";
          notEither = go (_: {
            output = { };
            scope = { };
          });
          rightInt = go (_: {
            right = 5;
          });
          rightNoScope = go (_: {
            right = {
              output = { };
            };
          });
          scopeKeyNotJson = go (_: {
            right = {
              output = { };
              scope.nope = null;
            };
          });
          scopeKeyDeclared = go (_: {
            right = {
              output = { };
              scope.${rid} = null;
            };
          });
          scopePosAbsent = go (_: {
            right = {
              output.description = "o";
              scope.${nid} = null;
            };
          });
          scopePosNotGuard = go (_: {
            right = {
              output.includes = [ "plain" ];
              scope.${nid} = null;
            };
          });
          functorForgotArgs = go {
            __functor = self: {
              right = {
                output = { };
                scope = { };
              };
            };
          };
          functorNotFn = go { __functor = 5; };
          formalsMissing = go (
            { id }: {
              right = {
                output = { };
                scope = { };
              };
            }
          );
          formalsForeign = go (
            {
              id,
              context,
              sources,
              captured,
              extra,
            }:
            {
              right = {
                output = { };
                scope = { };
              };
            }
          );
          malformedIdBody =
            ok
              (place { } { d = a.guard a.pred.always (t.ref "{\"declared\":{\"site\":"); }).d;
          okDoor =
            (inst {
              ref = _: {
                right = {
                  output.description = "o";
                  scope = { };
                };
              };
            } dn ctx2 srcs2).entry;
          okFormals =
            (inst {
              ref =
                {
                  id,
                  context,
                  sources,
                  captured,
                }:
                {
                  right = {
                    output.description = "f";
                    scope = { };
                  };
                };
            } dn ctx2 srcs2).entry;
        };
        expected = {
          notFunction = false;
          notEither = false;
          rightInt = false;
          rightNoScope = false;
          scopeKeyNotJson = false;
          scopeKeyDeclared = false;
          scopePosAbsent = false;
          scopePosNotGuard = false;
          functorForgotArgs = false;
          functorNotFn = false;
          formalsMissing = false;
          formalsForeign = false;
          malformedIdBody = false;
          okDoor.description = "o";
          okFormals.description = "f";
        };
      };
    # ── build (gate contact 2) ──
    # C-1: a door-shaped id of 300000 characters is refused catchably (the prefix is tested before the
    # length bound, so it must not be a regex); an aspect reference of the same length is the control.
    test-door-id-overlong =
      let
        long = "{\"declared\":" + builtins.concatStringsSep "" (builtins.genList (_: "x") 300000);
      in
      {
        expr = {
          body = ok (place { } { d = a.guard a.pred.always (t.ref long); }).d;
          nestedBody =
            ok
              (place { } { d = a.guard a.pred.always { sub = a.guard (a.pred.has "thimble") (t.ref long); }; }).d;
          scopeKey =
            ok
              (inst {
                ref = _: {
                  right = {
                    output = { };
                    scope.${long} = null;
                  };
                };
              } (a.guard (a.pred.has "thimble") (t.ref rOuter)) ctx2 srcs2).entry;
          control = (a.mkGuardVocab { }).applyGuard { } (
            a.guard a.pred.always { includes = [ (t.ref "selfw") ]; }
          );
        };
        expected = {
          body = false;
          nestedBody = false;
          scopeKey = false;
          control.includes = [ "selfw" ];
        };
      };
    # P-2: ids `toJSON` never emits, which `fromJSON` aborts on or mis-types, are refused catchably.
    test-door-id-grammar =
      let
        dn = a.guard (a.pred.has "thimble") (t.ref rOuter);
        go = id: ok (place { } { d = a.guard a.pred.always (t.ref id); }).d;
        scopeAt =
          position:
          ok
            (inst {
              ref = _: {
                right = {
                  output.a = "x";
                  scope.${
                    "{\"nested\":{\"outer\":\"o\",\"position\":[" + position + "],\"reads\":[],\"sources\":{}}}"
                  } =
                    null;
                };
              };
            } dn ctx2 srcs2).entry;
      in
      {
        expr = {
          surrogate = go "{\"declared\":{\"reads\":null,\"site\":\"\\ud800\"}}";
          nul = go "{\"declared\":{\"reads\":null,\"site\":\"\\u0000\"}}";
          rawControl = go "{\"declared\":{\"reads\":null,\"site\":\"a\nb\"}}";
          overlongIntFirst = scopeAt "99999999999999999999";
          leadingZero = scopeAt "007";
          control =
            go
              (T.refId {
                declared = {
                  site = builtins.fromJSON "\"s\\u0001\"";
                  reads = null;
                };
              }).right;
        };
        expected = {
          surrogate = false;
          nul = false;
          rawControl = false;
          overlongIntFirst = false;
          leadingZero = false;
          control = true;
        };
      };
    # P-4: a door node nested in a first-order guard's body is admitted, carried unfired, and fires later
    # (not lexically nested: no scope reaches it).
    test-door-node-in-first-order = {
      expr =
        let
          o = (place dcnf { o = a.guard a.pred.always { sub = doorNode; }; }).o;
          carried = (a.mkGuardVocab dcnf).applyGuard ctx2 o;
        in
        {
          carriedAsGuard = carried.sub.__guard or false;
          firesLater = (inst dcnf carried.sub ctx2 srcs2).entry.description;
        };
      expected = {
        carriedAsGuard = true;
        firesLater = "o-pewter";
      };
    };
  };
  # Stage 2b (spec §3a, structure): a context closure at a gen-aspects-typed position is refused,
  # catchably, at every arity and position; a module function there is still a module. The message
  # each refusal says is pinned on the error plane (`closure-door`).
  placeMany =
    defsList:
    (mkSchemaEval {
      keySemantics.nixos.category = "class";
      modules = map (d: { config.aspects = d; }) defsList;
    }).config.aspects;
  stage2b = {
    test-bare-closure-at-aspect = {
      expr = {
        refused = ok (place { } { x = { thimble, ... }: { description = thimble; }; }).x;
        control = (place { } { x.description = "s"; }).x.description;
      };
      expected = {
        refused = false;
        control = "s";
      };
    };
    test-closure-in-includes = {
      expr = {
        refused = ok (place { } { x.includes = [ ({ host, ... }: { }) ]; }).x.includes;
        control =
          map (i: i.description)
            (place { } { x.includes = [ { description = "i"; } ]; }).x.includes;
      };
      expected = {
        refused = false;
        control = [ "i" ];
      };
    };
    test-closure-multidef = {
      expr = {
        refused =
          ok
            (placeMany [
              { x.description = "a"; }
              { x = { thimble, ... }: { }; }
            ]).x;
        control =
          (placeMany [
            { x.description = "a"; }
            { x.nixos.foo = 1; }
          ]).x.description;
      };
      expected = {
        refused = false;
        control = "a";
      };
    };
    test-module-fn-aspect-control = {
      expr = (place { } { x = { config, ... }: { description = "m"; }; }).x.description;
      expected = "m";
    };
    # alhfc gate X1: a closure inside an aspect-position module function's result is refused too (the
    # lowering does not enter the result); its message is pinned on the error plane.
    test-closure-inside-module-fn-result = {
      expr = ok (place { } { x = { config, ... }: { includes = [ ({ host, ... }: { }) ]; }; }).x.includes;
      expected = false;
    };
    # The retired forms (spec §2.10), each refused catchably at its first application; their text is
    # pinned on the error plane.
    test-retired-forms-refuse = {
      expr = {
        wrapFn = ok (a.wrapFn { } "w" ({ host, ... }: { }));
        wrapGatedFn = ok (a.wrapGatedFn { functionArgs.host = false; });
        applyGuardClosure = ok (a.applyGuard { host = "h"; } ({ host, ... }: { }));
        deferIncludeResolution = ok (place { deferIncludeResolution = true; } { x.description = "d"; }).x;
        applyGuardControl = (a.applyGuard { } (a.guard a.pred.always { description = "g"; })).description;
      };
      expected = {
        wrapFn = false;
        wrapGatedFn = false;
        applyGuardClosure = false;
        deferIncludeResolution = false;
        applyGuardControl = "g";
      };
    };
  };
in
{
  flake.tests.first-order-guards = cells;
  flake.tests.closure-door = stage2b;
}
