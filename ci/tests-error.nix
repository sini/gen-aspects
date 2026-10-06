# THE SECOND TEST OUTPUT — cells whose subject is an ERROR MESSAGE.
#
# `tryEval` discards a thrown text, so it can assert THAT a door refuses and never WHAT it says.
# `expectedError` asserts the message. These cells cannot live in `flake.tests`: the batch asserter
# behind `checks.default` forces every `expr` there unconditionally, so a throwing cell crashes that
# gate instead of failing. This file sits outside `./tests` (the whole of `testModules`), so the split
# is structural. `expectedError.msg` is SEARCHED, not whole-matched, so every pattern is anchored at
# both ends and built by escaping the literal text.
#
#   nix-unit --flake ./ci#testsError
{
  lib,
  aspects,
  mkSchemaEval,
  genMerge,
  genSchema,
  genIdentity,
  genAlgebra,
  ...
}:
let
  exactly = msg: "^" + lib.escapeRegex msg + "$";
  wcnf.keySemantics.classOne.category = "class";
  gv = aspects.mkGuardVocab { };
  carrier =
    v:
    (aspects.aspectType wcnf).merge
      [ "n" ]
      [
        {
          file = "<a>";
          value = v;
        }
        {
          file = "<b>";
          value = gv.vocab.whenEq [ "host" ] "nope" { description = "b"; };
        }
      ];
  thrown = expr: msg: {
    expr = builtins.deepSeq expr null;
    expectedError = {
      type = "ThrownError";
      inherit msg;
    };
  };
  schemaBad = aspects.mkAspectSchema { keySemantics.bad.category = "bogus"; };
  refusal =
    got:
    exactly (
      "gen-aspects.keyRef: got ${got}, expected a reference: an origin-qualified string "
      + "(\"<origin>/<path>\") or { path; origin ? [ ]; }, each a \"/\"-joined string or a list of strings"
    );
  # deepSeq, so a refusal left lazy inside a field still reaches the cell.
  cell = ref: got: {
    expr = builtins.deepSeq (aspects.keyRef ref) null;
    expectedError = {
      type = "ThrownError";
      msg = refusal got;
    };
  };
in
{
  # One cell per shape the door refuses (den-hoag-bkdkg). Each aborted uncaught before the guard:
  # `attribute 'path' missing`, `expected a list but found an integer`, `cannot coerce a set to a
  # string`; a bad `origin` was admitted and aborted downstream in gen-link.
  flake.testsError.key-ref-refusal = {
    test-set-without-path = cell { name = "a"; } "a set with no 'path' field";
    test-int = cell 3 "int";
    test-path-int = cell { path = 3; } "path = int";
    test-path-list-of-set = cell { path = [ { name = "a"; } ]; } "path = list holding a non-string";
    test-origin-int = cell {
      path = "s";
      origin = 3;
    } "origin = int";
    test-origin-list-of-set = cell {
      path = "s";
      origin = [ { } ];
    } "origin = list holding a non-string";
    # `splitSlash` drops empty segments, so these reached `builtins.head [ ]` (den-hoag-6c5s3).
    test-empty-string = cell "" "the string \"\", which has no non-empty segment";
    test-all-slash = cell "/" "the string \"/\", which has no non-empty segment";
    test-all-slashes = cell "///" "the string \"///\", which has no non-empty segment";
  };

  # den-hoag-2ejx: a malformed keySemantics category refuses BY NAME at the key that carries it, and
  # only there (an unrelated aspect's `name` read returns; ci/tests/key-semantics.nix (7)).
  flake.testsError.key-semantics-lazy-refusal.test-carrier-bad-category = {
    expr =
      builtins.deepSeq
        (genMerge.evalModuleTree { } [
          { options.schema = schemaBad.schemaOption; }
          (schemaBad.mkAspectModule { })
          { config.aspects.carrier.bad.x = 1; }
        ]).config.aspects.carrier.bad
        null;
    expectedError = {
      type = "ThrownError";
      msg = exactly "gen-aspects: keySemantics key 'bad' has unknown category 'bogus' (expected class|channel|facet)";
    };
  };

  # den-hoag-plm1h: `aspectsRoot(port) ∥ aspectsRoot(int)` is refused BY NAME at the declaration.
  flake.testsError.root-element-join-refusal.test-port-int =
    let
      rootWith = (aspects.aspectsRoot { keySemantics.a.category = "class"; }).functor.type;
      res = genMerge.evalModuleTree { } [
        { options.p = genMerge.mkOption { type = rootWith lib.types.port; }; }
        { options.p = genMerge.mkOption { type = rootWith lib.types.int; }; }
        { p.a = 70000; }
      ];
    in
    {
      expr = res.options.p.type.name;
      expectedError = {
        type = "ThrownError";
        msg = exactly (
          "gen-merge: option `p' is declared with types that do not merge (`aspectsRoot' and "
          + "`aspectsRoot', which the first type's own `functor' does not reconcile); "
          + "declared in <gen-merge>, <gen-merge>"
        );
      };
    };

  # den-hoag-7gp66 P1: the closed doors' shared checks, message pinned on the real path.
  flake.testsError.doors =
    let
      schema = aspects.mkAspectSchema { };
      unknown =
        door: accepted:
        exactly "${door}: 'notAnOption' is not an option of this door; the options are closed (accepted: ${accepted}) (in prelude.checkOptions)";
    in
    {
      test-mk-aspect-option-unknown = thrown (schema.mkAspectOption { notAnOption = 1; }) (
        unknown "gen-aspects.mkAspectSchema.mkAspectOption" "'providerPrefix'"
      );
      test-mk-aspect-module-unknown = thrown (schema.mkAspectModule { notAnOption = 1; }) (
        unknown "gen-aspects.mkAspectSchema.mkAspectModule" "'providerPrefix'"
      );
      test-mk-namespace-type-unknown = thrown (schema.mkNamespaceType {
        config = { };
        notAnOption = 1;
      }) (unknown "gen-aspects.mkAspectSchema.mkNamespaceType" "'config'");
      test-mk-namespace-type-config-required = thrown (schema.mkNamespaceType { }) (
        exactly "gen-aspects.mkAspectSchema.mkNamespaceType: required field 'config' is missing (required: 'config') (in prelude.checkRequired)"
      );
    };

  # den-hoag-7gp66 P1: an include reference resolved by `prelude.resolve`, refused naming the door,
  # the aspect and the include position first.
  flake.testsError.includes-resolve =
    let
      tree =
        elems:
        mkSchemaEval {
          fixtureKeySemantics.nixos.category = "class";
          modules = [
            (
              { config, ... }:
              {
                config.aspects.lib.base.nixos.networking.domain = "b";
                config.aspects.app.includes = elems config;
              }
            )
          ];
        };
      read = elems: (aspects.graphFacts { } (tree elems).config.aspects).includesOf.app;
      door = "gen-aspects.includes (aspect 'app', include position 0): ";
      notMember =
        h:
        exactly "${door}declaration '${h}' is not a member of the registry (available: 'app', 'lib', 'lib/base') (in prelude.resolve)";
      a = (tree (_: [ ])).config.aspects;
    in
    {
      # 6-c: a member re-keyed to spell another member.
      test-rekeyed-member = thrown (read (config: [ (config.aspects.lib.base // { key = "app"; }) ])) (
        notMember "app"
      );
      # gate C1: a stampless value naming a real member (handed to graphFacts directly — the include
      # element type re-mints the stamp from the value's own identity).
      test-stampless-real-member =
        thrown
          (aspects.graphFacts { } (
            a
            // {
              app = a.app // {
                includes = [ (removeAttrs a.lib.base [ "id_hash" ]) ];
              };
            }
          )).includesOf.app
          (notMember "lib/base");
      # A literal's `key` is a caller write of an identity input, refused by the type that writes it
      # (den-hoag-gywcg) before any registry lookup.
      test-key-naming-no-node = thrown (read (_: [ { key = "no/such"; } ])) (
        exactly "gen-aspects: the option `app.includes.\"[definition 1-entry 1]\".key' is written by the aspect type; remove the definition."
      );
      test-bare-string-naming-nothing = thrown (read (_: [ "lib/bsae" ])) (
        exactly "${door}reference 'lib/bsae' names no entry of the registry (in prelude.resolve)"
      );
    };

  # den-hoag-rc4mb: a member key `graphFacts` reads with an assumed type refuses naming the door, the
  # aspect, the include position where there is one, and the key.
  flake.testsError.member-key-type =
    let
      sites =
        m:
        (aspects.graphFacts { } {
          x = {
            name = "x";
          }
          // m;
        }).includeSitesOf;
      content = {
        key = "x/includes/0";
        meta.aspect-chain = [
          "x"
          "includes"
        ];
      };
      at0 = "gen-aspects.includes (aspect 'x', include position 0): ";
    in
    {
      test-includes-not-a-list = thrown (sites { includes = "notalist"; }) (
        exactly "gen-aspects.includes (aspect 'x'): 'includes' must be a list, not a string"
      );
      test-content-includes-not-a-list = thrown (sites {
        includes = [ (content // { includes = "notalist"; }) ];
      }) (exactly "${at0}'includes' must be a list, not a string");
      test-key-not-a-string = thrown (sites { includes = [ { key = 5; } ]; }) (
        exactly "${at0}'key' must be a string, not a int"
      );
      test-chain-not-a-list = thrown (sites {
        includes = [ (content // { meta.aspect-chain = "x/includes"; }) ];
      }) (exactly "${at0}'meta.aspect-chain' must be a list, not a string");
    };

  # den-hoag-661s2: the closed-key gate names the aspect beside the key, on both of its refusals.
  flake.testsError.closed-key-names-aspect =
    let
      gated =
        extra: body:
        (mkSchemaEval (
          {
            closedKeys = true;
            keySemantics.nixos.category = "class";
            modules = [ { config.aspects.hem = body; } ];
          }
          // extra
        )).config.aspects.hem;
    in
    {
      test-open-gate = thrown (gated { } { nixso.boot = { }; }).nixso (
        exactly "gen-aspects: aspect `hem`: undeclared aspect key 'nixso' (closed-key gate on; declare it in keySemantics or list it in freeformKeys)"
      );
      # An inline `includes` element is gated by the same submodule, and is named by its position:
      # nixpkgs `listOf`'s segment, `[definition n-entry m]`, which gen-merge's `listOf` folds it at.
      test-open-gate-include =
        thrown (builtins.head (gated { } { includes = [ { nixso.x = 1; } ]; }).includes).nixso
          (
            exactly "gen-aspects: aspect `hem.includes.[definition 1-entry 1]`: undeclared aspect key 'nixso' (closed-key gate on; declare it in keySemantics or list it in freeformKeys)"
          );
      test-recursive-gate = thrown (gated { recursiveClosed = true; } { ns.nixso = "x"; }).ns.nixso (
        exactly (
          "gen-aspects: aspect `hem.ns`: undeclared aspect key 'nixso' (value is not a nested aspect — a closed "
          + "aspect vocabulary admits an undeclared key only as a namespace attrset that recurses to a "
          + "declared class/channel/facet; a primitive/function/list value here is a typo or misplaced "
          + "content). Declare it in keySemantics, or nest it under a declared key."
        )
      );
      test-bare-module-include =
        thrown
          (builtins.head
            (mkSchemaEval {
              rejectBareModuleInclude = true;
              modules = [ { config.aspects.hem.includes = [ { imports = [ { } ]; } ]; } ];
            }).config.aspects.hem.includes
          )
          (
            exactly (
              "gen-aspects: includes element is a bare module ({ imports = [ … ]; }) with no aspect identity — "
              + "a class-content node included AS an aspect? An include must be an aspect (by value or fixpoint "
              + "ref), a keyRef, or a deferred fn/policy; `imports` is the module merge slot, never an aspect "
              + "content key."
            )
          );
    };

  # den-hoag-nwshf: a scalar or list at a freeform position whose enclosing aspect was itself reached
  # through the freeform slot is an orphan leaf, refused by name with its full key path, the declared
  # aspect it hangs below, and the declared class keys in full (no edit-distance suggestion). The
  # remedy names the extension route only where the type reads extensions.
  flake.testsError.orphan-leaf-names-path =
    let
      # Two classes and a channel: the message lists the class keys in full and only those.
      cnf.keySemantics = {
        nixos.category = "class";
        darwin.category = "class";
        welt.category = "channel";
      };
      at =
        body:
        (mkSchemaEval (
          cnf
          // {
            fixtureKeySemantics = { };
            modules = [ { config.aspects.hem = body; } ];
          }
        )).config.aspects.hem;
      # Composed from the cnf above, never restated, so the pin cannot drift from the fixture.
      classKeys = lib.concatStringsSep ", " (
        builtins.attrNames (lib.filterAttrs (_: e: e.category == "class") cnf.keySemantics)
      );
      declare =
        "Declare the key — a keySemantics class/channel/facet, or a schema extension "
        + "`schema.aspect.options.<key>` — or correct its spelling. Declared class keys: ${classKeys}.";
      # The include element's own segment, read from the library rather than restated, so the pin
      # cannot drift with gen-merge's naming of a list element (den-hoag-26thl).
      seg = (builtins.head (at { includes = [ { } ]; }).includes).name;
      show = genMerge.showOption;
      viaOption =
        (genMerge.evalModuleTree { } [
          { options.aspects = (aspects.mkAspectSchema cnf).mkAspectOption { }; }
          { config.aspects.hem.trim.x = 1; }
        ]).config.aspects.hem;
    in
    {
      test-names-the-class-keys = thrown (at { nixso.boot.enable = true; }).nixso.boot.enable (
        exactly (
          "gen-aspects: aspect `hem`: orphan leaf at `hem.nixso.boot.enable` (a value of type bool below "
          + "the undeclared key path `nixso.boot` is neither class content nor an aspect). "
          + declare
        )
      );
      test-list-leaf = thrown (at { trim.x = [ "a" ]; }).trim.x (
        exactly (
          "gen-aspects: aspect `hem`: orphan leaf at `hem.trim.x` (a value of type list below the "
          + "undeclared key path `trim` is neither class content nor an aspect). "
          + declare
        )
      );
      test-include-element-anchors =
        thrown (builtins.head (at { includes = [ { sub.x = 1; } ]; }).includes).sub.x
          (
            exactly (
              "gen-aspects: aspect `${
                show [
                  "hem"
                  "includes"
                  seg
                ]
              }`: orphan leaf at `${
                show [
                  "hem"
                  "includes"
                  seg
                  "sub"
                  "x"
                ]
              }` (a value of type int below the undeclared key path `sub` is neither class content "
              + "nor an aspect). "
              + declare
            )
          );
      test-option-door-names-keysemantics = thrown viaOption.trim.x (
        exactly (
          "gen-aspects: aspect `hem`: orphan leaf at `hem.trim.x` (a value of type int below the "
          + "undeclared key path `trim` is neither class content nor an aspect). Declare the key as a "
          + "keySemantics class/channel/facet (this aspect type reads no schema extension; "
          + "`mkAspectModule` threads them), or correct its spelling. Declared class keys: ${classKeys}."
        )
      );
    };

  # den-hoag-q17cc · a construction formal written at the kind entry's top level. Before the door each
  # evaluated at exit 0 and landed on EVERY aspect as a nested aspect, while the kind's own formal
  # stayed what the constructor fixed. Each cell reads the instance's key set, the read that used to
  # show the landed key, and never forces the landed value itself (it is self-similar).
  flake.testsError.construction-formal-refusals =
    let
      barKeysWith =
        entry:
        builtins.attrNames
          (mkSchemaEval {
            modules = [
              {
                config.schema.aspect = entry;
                config.aspects.bar = { };
              }
            ];
          }).config.aspects.bar;
    in
    {
      # G1 · a formal both libraries take: gen-schema's door answers, because its check wraps this
      # library's whole `mkType` result.
      test-shared-formal-gets-gen-schema-text =
        thrown (barKeysWith { keySemantics.darwin.category = "class"; })
          (
            exactly "gen-schema: kind 'aspect': declaration key 'keySemantics' is a construction formal of this schema — it is fixed by the call that builds the schema option (`mkSchemaOption`, `mkSchemaEntryType`), and written on a kind entry it is not read as one; pass 'keySemantics' to that constructor, or write `config.keySemantics` for an instance field of that name, which a strict instance must declare as an option"
          );

      # G2 · a formal only mkAspectSchema takes.
      test-cnf-formal-refuses-by-name = thrown (barKeysWith { providerPrefix = [ ]; }) (
        exactly "gen-aspects: kind 'aspect': declaration key 'providerPrefix' is an mkAspectSchema construction formal — it is fixed by `mkAspectSchema { providerPrefix = …; }`, and written on a kind entry it is not read as one; pass it there, or write `config.providerPrefix` for an instance field of that name, which a `closedKeys` schema must declare or list in `freeformKeys`"
      );

      # C2 on this path · a name gen-schema writes onto the kind value.
      test-published-name-refuses-on-this-path = thrown (barKeysWith { refs.forged = 1; }) (
        exactly "gen-schema: kind 'aspect': declaration key 'refs' is a name gen-schema writes onto the kind value — written on a kind entry it lands on every instance, while reading `config.schema.aspect.refs` returns the published one; write `config.refs` for an instance field of that name, which a strict instance must declare as an option"
      );

      # G7 · a collection named for a cnf formal.
      test-collection-named-for-a-formal-is-reserved =
        thrown
          (builtins.attrNames
            (mkSchemaEval {
              collections.providerPrefix.default = [ ];
              modules = [ { config.schema.aspect = { }; } ];
            }).config.schema.aspect
          )
          (
            exactly "gen-aspects: mkAspectSchema: collection 'providerPrefix' is reserved — it is an mkAspectSchema construction formal"
          );
    };

  # ★ THE SAME NAMES IN A MODULE THE KIND ENTRY IMPORTS (den-hoag-8x97u). `mkType` marks the instance
  # modules it builds with gen-merge's `__reservedKeys` (`cnfKeys` ∪ gen-schema's `entryReservation`),
  # so the collector refuses the name with its owner's text and the module's attribution. Before the
  # door each read below listed the name among `aspects.bar`'s keys. Every read is SHALLOW, the key
  # list only: a deep force of the landed value at RED does not terminate under a 12G cap. The
  # controls, forced first: an imported declared option, and the same functor def importing one,
  # both compose 7.
  flake.testsError.imports-route-refusals =
    let
      int0 = genMerge.mkOption {
        type = genMerge.types.int;
        default = 0;
      };
      barWith =
        entry:
        (mkSchemaEval {
          modules = [
            {
              config.schema.aspect = entry;
              config.aspects.bar = { };
            }
          ];
        }).config.aspects.bar;
      functorDef = imported: { __functor = _: _: { imports = imported; }; };
      controls =
        (barWith {
          options.priority = int0;
          imports = [ { priority = 7; } ];
        }).priority == 7
        &&
          (barWith (functorDef [
            { options.priority = int0; }
            { priority = 7; }
          ])).priority == 7;
      owned = text: {
        type = "ThrownError";
        msg = "^" + lib.escapeRegex text + " [(]module `[^']*'[)]$";
      };
      cnfText =
        f:
        "gen-aspects: kind 'aspect': declaration key '${f}' is an mkAspectSchema construction formal, written in a module this kind entry imports — it is fixed by `mkAspectSchema { ${f} = …; }`, and written there it is not read as one; pass it there, or write `config.${f}` for an instance field of that name, which a `closedKeys` schema must declare or list in `freeformKeys`";
      cell = entry: text: {
        expr =
          assert controls;
          builtins.attrNames (barWith entry);
        expectedError = owned text;
      };
    in
    {
      # A cnf formal through a function module, read after gen-merge applies it.
      test-cnf-formal-through-function-module = cell {
        imports = [ ({ ... }: { closedKeys = true; }) ];
      } (cnfText "closedKeys");

      # A gen-schema formal through `imports`: gen-schema's text wins on the shared name.
      test-shared-formal-through-imports-gets-gen-schema-text =
        cell { imports = [ { keySemantics.darwin.category = "class"; } ]; }
          "gen-schema: kind 'aspect': declaration key 'keySemantics' is a construction formal of this schema, written in a module this kind entry imports — it is fixed by the call that builds the schema option (`mkSchemaOption`, `mkSchemaEntryType`), and written there it is not read as one; pass 'keySemantics' to that constructor, or write `config.keySemantics` for an instance field of that name, which a strict instance must declare as an option";

      # A cnf formal through a whole-module `mkIf`, read after push-down.
      test-cnf-formal-through-mkif = cell {
        imports = [ (genMerge.mkIf true { providerPrefix = [ "x" ]; }) ];
      } (cnfText "providerPrefix");

      # A FUNCTOR kind entry def importing a cnf formal: the def is wrapped, since its applied result
      # would drop an in-place marker. Its default-branch twin is gen-schema's function-def cell.
      test-functor-def-imports-route-formal-refuses = cell (functorDef [ { closedKeys = true; } ]) (
        cnfText "closedKeys"
      );
    };

  # The instance mint's doors (lib/instance.nix; den-hoag-0cmbt spec §2.5, cells I-6 and I-7). Each is a
  # catchable throw naming `instanceOf`. The spec gate's C3, a source refused by its kind tag, retired
  # with den-hoag-fkkzk: the mint now admits every identity-shaped source (ci/tests/source-door.nix).
  flake.testsError.instance-doors =
    let
      entity = n: genIdentity.hashIdentity "entity" [ "name" ] (_: n);
      t = (genAlgebra.term genIdentity.hashIdentity).term;
      p = aspects.guard (aspects.pred.has "host") {
        description = t.concat [
          (t.lit "p-")
          (t.readCtx "host" [ ])
        ];
      };
      # reads `host` and `extra`, so `extra` with no source is the I-6 refusal
      bare = aspects.guard (aspects.pred.all [
        (aspects.pred.has "host")
        (aspects.pred.has "extra")
      ]) { description = t.readCtx "extra" [ ]; };
      mint =
        value: context: sources:
        aspects.instanceOf { } {
          aspect = "A";
          inherit value context sources;
        };
      at = msg: exactly "gen-aspects.instanceOf: aspect `A` ${msg}";
    in
    {
      # RED (without the door): `attempt to call something which is not a function but a set`, uncatchable.
      test-not-parametric = thrown (mint { description = "s"; } { } { }) (
        at "is not parametric: it is not a guard record or carrier, so it has no instances."
      );
      # A first-order guard, alone or as a carrier's fragment, receives the coordinates it READS
      # (den-hoag-lwbb1, design Section 3's instance rule, answering 0cmbt O1), so a read with no
      # source is refused by the I-6 door. RED (without the derived reads): the lone record aborts as
      # above, uncatchably.
      test-guard-record = thrown (mint (gv.vocab.whenEq [ "host" ] "h1" { }) { host = "h1"; } { }) (
        at "reads formal(s) `host` with no known supplier; the sources map carries: ."
      );
      test-carrier-record-fragment = thrown (mint
        (carrier (
          gv.vocab.whenEq [ "host" ] "h1" {
            description = "a";
          }
        ))
        { host = "h1"; }
        { }
      ) (at "reads formal(s) `host` with no known supplier; the sources map carries: .");
      # I-6. RED (without the door): `attribute 'extra' missing`, uncatchable.
      test-no-supplier = thrown (mint bare
        {
          host = "h1";
          extra = "x";
        }
        { host = entity "h1"; }
      ) (at "reads formal(s) `extra` with no known supplier; the sources map carries: host.");
      # I-7. RED (without the door): `expected a list but found null`, uncatchable, in the kind check that
      # reads the shape this door establishes.
      test-value-as-source = thrown (mint p { host = "h1"; } { host = "h1"; }) (
        at "was handed a source for formal(s) `host` that is not an identity (`<kind>:<sha256>`); hand the identity of the entity or argument binding that supplied it, never its value."
      );
      # The argument record and its field types. RED (without the doors): the extra field and the
      # non-string `aspect` are admitted silently and the cell's empty context refuses at the
      # derived-reads door instead; string `sources` aborts `expected a set but found a string`, uncatchably.
      test-unknown-field =
        thrown
          (aspects.instanceOf { } {
            aspect = "A";
            value = p;
            context = { };
            sources = { };
            extra = 1;
          })
          (
            exactly "gen-aspects.instanceOf: 'extra' is not an option of this door; the options are closed (accepted: 'aspect', 'value', 'context', 'sources', 'scope') (in prelude.checkOptions)"
          );
      test-aspect-not-string =
        thrown
          (aspects.instanceOf { } {
            aspect = { };
            value = p;
            context = { };
            sources = { };
          })
          (
            exactly "gen-aspects.instanceOf: `aspect` must be the aspect's identity, a string; received: set."
          );
      test-sources-not-attrs = thrown (mint p { host = "h1"; } "h1") (
        at "was handed sources of type string; sources map each context key to the identity that supplied it."
      );
      # den-hoag-ohvjc: `scope` is an instance's `scope`. RED (without the door): `//` aborts `expected a
      # set but found a string` inside the firing, naming no door.
      test-scope-not-attrs =
        thrown
          (aspects.instanceOf { } {
            aspect = "A";
            value = p;
            context.host = "h1";
            sources.host = entity "h1";
            scope = "s";
          })
          (
            at "was handed a scope of type string; a scope is an instance's `scope`, closures keyed by nested registration identifiers."
          );
    };

  # The instance relation's doors (lib/instance.nix `instancesFor`; den-hoag-0cmbt spec §2.6, the C1
  # revision gate's C-B, and R-10). Each is a catchable throw naming `instancesFor`, and the node.
  flake.testsError.instance-relation-doors =
    let
      entity = n: genIdentity.hashIdentity "entity" [ "name" ] (_: n);
      tree = {
        p = aspects.guard (aspects.pred.has "host") {
          description = (genAlgebra.term genIdentity.hashIdentity).term.readCtx "host" [ ];
        };
        w = {
          name = "w";
          includes = [ "p" ];
        };
      };
      sup = {
        ${entity "h1"}.host = "h1";
        ${entity "u1"}.user = "u1";
      };
      ok = {
        members = [ "w" ];
        sources.host = entity "h1";
      };
      relC =
        suppliers: containment: scope:
        aspects.instancesFor { } tree {
          inherit suppliers containment;
          scopes.a = scope;
        };
      relWith = suppliers: relC suppliers { };
      rel = relWith sup;
      at = msg: exactly "gen-aspects.instancesFor (node 'a'): ${msg}";
      # The containment doors (den-hoag-8g2rn §2.6): h1 ⊃ u1.
      rec0 = parent: key: x: {
        inherit parent key;
        identity = entity x;
        marked = false;
        bindings = { };
      };
      cont = {
        h1 = rec0 null "host" "h1";
        u1 = rec0 "h1" "user" "u1";
      };
      supC = sup // {
        ${entity "kx"}.user = "kx";
        ${entity "kf"}.flavor = "kf";
        ${entity "kf2"}.flavor = "kf2";
      };
      relCont = c: relC supC c ok;
      atE = x: msg: exactly "gen-aspects.instancesFor (containment '${x}'): ${msg}";
      repeated =
        k: y: z:
        "entity key `${k}` is bound by '${y}' and again by its ancestor '${z}'; an entity key is bound once along containment (an argument binding re-declared there shadows).";
      # The source door (den-hoag-fkkzk arm (d)): `p`'s node id, and a vertex of this relation. The
      # tree is PLACED, since an unchecked first-order guard has no identity to be a member by.
      placed = (mkSchemaEval { modules = [ { config.aspects = tree; } ]; }).config.aspects;
      pid = aspects.aspectId [ ] (aspects.graphFacts { } placed).nodeData.p;
      vid = builtins.head (
        builtins.attrNames
          (aspects.instancesFor { } placed {
            suppliers = sup;
            scopes.a = ok;
            containment = { };
          }).vertices
      );
      ownRefused =
        src:
        thrown
          (aspects.instancesFor { } placed {
            containment = { };
            suppliers = sup // {
              ${src}.host = "h2";
            };
            scopes = {
              a = ok;
              b = ok // {
                sources.host = src;
              };
            };
          })
          (
            exactly (
              "gen-aspects.instancesFor: aspect `${pid}` was handed, for formal(s) `host`, the identity of "
              + "a node of this relation's own graph, which supplies no argument; hand the identity of the "
              + "entity or argument binding that supplied it. An instance's reaching node is an edge, never "
              + "a formal's source."
            )
          );
      unsupplied =
        k:
        "key(s) '${k}' name a source that `suppliers` holds no value for under that key; a context value is supplied as `suppliers.<source>.<key>`, never beside the scope.";
    in
    {
      # The previous surface's call (scopes in the input's place) names the new field.
      test-input-missing-suppliers = thrown (aspects.instancesFor { } tree { a = ok; }) (
        exactly "gen-aspects.instancesFor: required field 'suppliers' is missing (required: 'suppliers', 'scopes', 'containment') (in prelude.checkRequired)"
      );
      test-input-unknown-field =
        thrown
          (aspects.instancesFor { } tree {
            suppliers = sup;
            scopes = { };
            containment = { };
            extra = 1;
          })
          (
            exactly "gen-aspects.instancesFor: 'extra' is not an option of this door; the options are closed (accepted: 'suppliers', 'scopes', 'containment') (in prelude.checkOptions)"
          );
      test-suppliers-not-attrs = thrown (relWith [ ] ok) (
        exactly "gen-aspects.instancesFor: `suppliers` must be an attrset `<source identity>.<key> = <value>`, not a list."
      );
      test-scopes-not-attrs = thrown (aspects.instancesFor { } tree {
        suppliers = sup;
        scopes = [ ];
        containment = { };
      }) (exactly "gen-aspects.instancesFor: `scopes` must be an attrset of node scopes, not a list.");
      # C-B. RED (without the door): `attribute '<member>' missing`, uncatchable.
      test-member-not-a-node = thrown (rel (ok // { members = [ "absent" ]; })) (
        at "member 'absent' is not a node of this tree; a member is a `graphFacts` node id (resolve a local key through `nodeIdOf`)."
      );
      test-member-not-a-string = thrown (rel (ok // { members = [ 1 ]; })) (
        at "member of type int is not a node of this tree; a member is a `graphFacts` node id (resolve a local key through `nodeIdOf`)."
      );
      test-members-not-a-list = thrown (rel (ok // { members = "w"; })) (
        at "`members` must be a list of facts ids, not a string."
      );
      test-scope-missing-sources = thrown (rel (removeAttrs ok [ "sources" ])) (
        exactly "gen-aspects.instancesFor (node 'a'): required field 'sources' is missing (required: 'members', 'sources') (in prelude.checkRequired)"
      );
      test-scope-unknown-field = thrown (rel (ok // { extra = 1; })) (
        exactly "gen-aspects.instancesFor (node 'a'): 'extra' is not an option of this door; the options are closed (accepted: 'members', 'sources') (in prelude.checkOptions)"
      );
      # R-10. The retired per-tuple `context` refuses through the closed-field door, with no tombstone.
      # RED (at bcc1329): `context` is accepted beside `sources`.
      test-scope-context-retired = thrown (rel (ok // { context.host = "h1"; })) (
        exactly "gen-aspects.instancesFor (node 'a'): 'context' is not an option of this door; the options are closed (accepted: 'members', 'sources') (in prelude.checkOptions)"
      );
      # R-10. The supplier door: a source with no `suppliers` entry, an entry lacking the key, and a
      # source that is not a string, each named. RED (the door removed): an uncatchable missing attribute.
      test-source-not-supplied = thrown (rel (ok // { sources.host = entity "h9"; })) (
        at (unsupplied "host")
      );
      test-source-lacks-key = thrown (rel (ok // { sources.host = entity "u1"; })) (
        at (unsupplied "host")
      );
      test-source-not-a-string = thrown (rel (ok // { sources.host = 1; })) (at (unsupplied "host"));
      # RED (the membership check removed): each mints at rc 0.
      test-source-own-node-id = ownRefused pid;
      test-source-own-vertex-id = ownRefused vid;
      # den-hoag-8g2rn §2.6. The retired per-scope `descendants` refuses through the closed-field door
      # (LEGACY), and so does a handed transitive view beside `containment`.
      test-scope-descendants-retired = thrown (rel (ok // { descendants = [ ]; })) (
        exactly "gen-aspects.instancesFor (node 'a'): 'descendants' is not an option of this door; the options are closed (accepted: 'members', 'sources') (in prelude.checkOptions)"
      );
      test-descendants-of-view-refused =
        thrown
          (aspects.instancesFor { } tree {
            suppliers = sup;
            scopes.a = ok;
            containment = { };
            descendantsOf = { };
          })
          (
            exactly "gen-aspects.instancesFor: 'descendantsOf' is not an option of this door; the options are closed (accepted: 'suppliers', 'scopes', 'containment') (in prelude.checkOptions)"
          );
      # OMIT: `containment` is required (`{ }` when there is none).
      test-containment-missing =
        thrown
          (aspects.instancesFor { } tree {
            suppliers = sup;
            scopes.a = ok;
          })
          (
            exactly "gen-aspects.instancesFor: required field 'containment' is missing (required: 'suppliers', 'scopes', 'containment') (in prelude.checkRequired)"
          );
      test-containment-not-attrs = thrown (relCont [ ]) (
        exactly "gen-aspects.instancesFor: `containment` must be an attrset `<identifier> = { parent; key; identity; marked; bindings; }`, not a list."
      );
      # BADREC: the record is exactly its five fields, each of its type.
      test-containment-record-missing-bindings =
        thrown (relCont (cont // { u1 = removeAttrs cont.u1 [ "bindings" ]; }))
          (
            atE "u1" "required field 'bindings' is missing (required: 'parent', 'key', 'identity', 'marked', 'bindings') (in prelude.checkRequired)"
          );
      test-containment-record-unknown-field =
        thrown
          (relCont (
            cont
            // {
              u1 = cont.u1 // {
                extra = 1;
              };
            }
          ))
          (
            atE "u1" "'extra' is not an option of this door; the options are closed (accepted: 'parent', 'key', 'identity', 'marked', 'bindings') (in prelude.checkOptions)"
          );
      test-containment-key-not-a-string = thrown (relCont (
        cont
        // {
          u1 = cont.u1 // {
            key = 1;
          };
        }
      )) (atE "u1" "`key` must be the coordinate the entity binds, a string, not a int.");
      test-containment-bindings-not-attrs =
        thrown
          (relCont (
            cont
            // {
              u1 = cont.u1 // {
                bindings = [ ];
              };
            }
          ))
          (
            atE "u1" "`bindings` must be an attrset `<key> = <source>` of the argument bindings declared at this entity, not a list."
          );
      test-containment-marked-not-bool = thrown (relCont (
        cont
        // {
          u1 = cont.u1 // {
            marked = "yes";
          };
        }
      )) (atE "u1" "`marked` must be a bool, not a string.");
      # DANGLING and CYCLE.
      test-containment-dangling-parent = thrown (relCont (
        cont
        // {
          u1 = cont.u1 // {
            parent = "h9";
          };
        }
      )) (atE "u1" "`parent` must be null (a root) or the identifier of an entity of `containment`.");
      test-containment-cycle = thrown (relCont (
        cont
        // {
          h1 = cont.h1 // {
            parent = "u1";
          };
        }
      )) (atE "h1" "its parent chain is a cycle through 'h1'; containment is a forest.");
      # REPKEY: an entity key bound twice along a chain, in both directions (an ancestor's argument
      # binding named like a descendant's entity key too), and in a subtree no node reaches (the door's
      # totality, gate C2). RED (the fold checking only the entity's own key): `-arg` admits; (the
      # chains forced only where a neighbourhood reads them, v1.1): `-unreached` admits.
      test-containment-repeated-entity-key = thrown (relCont (cont // { h2 = rec0 "h1" "host" "h2"; })) (
        atE "h2" (repeated "host" "h2" "h1")
      );
      test-containment-repeated-entity-key-arg = thrown (relCont (
        cont
        // {
          h1 = cont.h1 // {
            bindings.user = entity "kx";
          };
        }
      )) (atE "u1" (repeated "user" "u1" "h1"));
      test-containment-repeated-entity-key-unreached = thrown (relC
        (
          supC
          // {
            ${entity "h3"}.host = "h3";
            ${entity "h4"}.host = "h4";
          }
        )
        (
          cont
          // {
            h3 = rec0 null "host" "h3";
            h4 = rec0 "h3" "host" "h4";
          }
        )
        ok
      ) (atE "h4" (repeated "host" "h4" "h3"));
      # A containment entity's coordinate naming a source `suppliers` lacks refuses at every call,
      # reached or not (gate C2). RED (v1.1): admitted while no neighbourhood reads u9.
      test-containment-coordinate-not-supplied-unreached = thrown (relCont (
        cont
        // {
          u9 = rec0 "h9" "user" "u9" // {
            parent = null;
          };
        }
      )) (atE "u9" (unsupplied "user"));
      # ALIAS-dupid and SELFKEY (P1).
      test-containment-one-identity-two-identifiers = thrown (relCont (cont // { u1b = cont.u1; })) (
        exactly "gen-aspects.instancesFor: containment entities 'u1', 'u1b' carry one identity; an entity has one identifier."
      );
      # ... with no node scope at all too. RED (v1.1, the identity index forced only by a node's
      # tuple): admitted.
      test-containment-one-identity-two-identifiers-no-scope =
        thrown
          (aspects.instancesFor { } tree {
            suppliers = supC;
            scopes = { };
            containment = cont // {
              x1 = rec0 null "host" "q";
              x2 = rec0 null "host" "q";
            };
          })
          (
            exactly "gen-aspects.instancesFor: containment entities 'x1', 'x2' carry one identity; an entity has one identifier."
          );
      test-containment-keyed-by-identity =
        thrown
          (relCont {
            ${entity "h1"} = rec0 null "host" "h1";
          })
          (
            atE (entity "h1") "is keyed by its own identity; key it by the entity's identifier, which orders siblings (an identity is a hash, and no order may depend on it, ADR-0016 r5)."
          );
      # MISKEY: a node binding an entity under another key than its own.
      test-node-binds-entity-under-another-key = thrown (relC
        (
          supC
          // {
            ${entity "u1"} = {
              user = "u1";
              host = "u1h";
            };
          }
        )
        cont
        (ok // { sources.host = entity "u1"; })
      ) (at "binds `host` to containment entity 'u1', whose key is `user`.");
      # PLANT-node: a descendant rebinding an entity key the node binds to another source.
      test-node-descendant-rebinds =
        thrown
          (relC supC cont (
            ok
            // {
              sources = {
                host = entity "h1";
                user = entity "kx";
              };
            }
          ))
          (
            at "a descendant of the tuple binds `user` to another source than the tuple does; a descendant extends its ancestor's bindings and never rebinds one."
          );
      # THE NODE DOOR (gate C3): a node binding an argument against the coordinate of an entity it binds;
      # the override belongs on the containment record, where it shadows. RED (v1.1, no node door):
      # admitted at rc 0 whenever no member fans out.
      test-node-overrides-an-inherited-binding =
        thrown
          (relC supC
            (
              cont
              // {
                h1 = cont.h1 // {
                  bindings.flavor = entity "kf";
                };
              }
            )
            (
              ok
              // {
                sources = {
                  host = entity "h1";
                  user = entity "u1";
                  flavor = entity "kf2";
                };
              }
            )
          )
          (
            at "binds `flavor` to another source than the containment coordinate of an entity it binds; a node reads its entities' coordinates, and a binding is overridden only on a containment record, where it shadows."
          );
    };

  # First-order guards (den-hoag-lwbb1 unit 2, specs/2026-10-02-gen-aspects-first-order-guards-spec-v1.md
  # §3a's message parity): each refusal of the declaration check, of the door's totality and of the
  # declared set, by its whole text. The value plane's `first-order-guards` cells assert that each is
  # CATCHABLE; these assert what it SAYS.
  flake.testsError.first-order-guards =
    let
      T = genAlgebra.term genIdentity.hashIdentity;
      t = T.term;
      src = n: genIdentity.hashIdentity "entity" [ "name" ] (_: n);
      place =
        cnf: defs:
        (mkSchemaEval (
          cnf
          // {
            keySemantics.nixos.category = "class";
            modules = [ { config.aspects = defs; } ];
          }
        )).config.aspects;
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
            sources.thimble = src "p";
            position = [
              "includes"
              0
            ];
            reads = [ ];
          };
        }).right;
      dn = aspects.guard (aspects.pred.has "thimble") (t.ref rid);
      go =
        door:
        (aspects.instanceOf { ref = door; } {
          aspect = "x";
          value = dn;
          context.thimble = "p";
          sources.thimble = src "p";
        }).entry;
      self = aspects.guard aspects.pred.always { sub = self; };
      door =
        msg:
        exactly "gen-aspects: cnf.ref must be null or the framework's door, a function of `{ id; context; sources; captured; }`; ${msg}.";
      shape =
        msg:
        exactly "gen-aspects.guard: aspect `<guard>`: door-result-shape: the door (`cnf.ref`) answered ${rid} with ${msg}; a door answers `{ right = { output; scope; }; }`, its scope keyed by nested registration identifiers (gen-algebra `refId`) each naming the position of a guard in `output`.";
      kinds =
        got:
        exactly "gen-aspects: cnf.entityKinds must be null, a list of coordinate names (strings), or an attrset marking each declared coordinate `true` when it is an entity kind; received: ${got}.";
    in
    {
      test-guard-depth = thrown (aspects.key (place { } { s = self; }).s) (
        exactly "gen-aspects.guard: aspect `s`, the guard nested 256 deep at `sub`: guard-depth: the guard body nests deeper than 256 levels at `sub`; a body that deep is almost always CYCLIC (a guard whose body holds itself, or an attrset containing itself). Pass a finite, acyclic body."
      );
      test-door-not-a-function = thrown (go "x") (door "received: string");
      test-door-functor-not-a-function = thrown (go { __functor = 5; }) (
        door "received: a set whose `__functor` is of type int, not a function"
      );
      test-door-functor-forgot-its-argument =
        thrown
          (go {
            __functor = self: {
              right = {
                output = { };
                scope = { };
              };
            };
          })
          (
            door "received: a functor whose `__functor` returns a value of type set, not a function; a functor door is `self: { id, context, sources, captured, ... }: …`"
          );
      test-door-formals-omit = thrown (go ({ id }: { })) (
        door "its formals omit `context`, `sources`, `captured` and take no `...`, so the call would be refused"
      );
      test-door-formals-foreign = thrown (go (
        {
          id,
          context,
          sources,
          captured,
          extra,
        }:
        { }
      )) (door "it requires `extra`, which the call never supplies");
      test-door-right-int = thrown (go (_: {
        right = 5;
      })) (shape "a `right` that is not { output; scope; } (got int)");
      test-door-scope-key = thrown (go (_: {
        right = {
          output = { };
          scope.nope = null;
        };
      })) (shape "a scope key that is not a nested registration identifier: nope");
      test-door-scope-position-absent = thrown (go (_: {
        right = {
          output = { };
          scope.${nid} = null;
        };
      })) (shape "a scope position [\"includes\",0] that `output` does not hold");
      test-door-scope-position-not-a-guard = thrown (go (_: {
        right = {
          output.includes = [ "plain" ];
          scope.${nid} = null;
        };
      })) (shape "a scope position [\"includes\",0] that holds a string, not a guard");
      test-ref-id-domain =
        thrown (place { } { d = aspects.guard aspects.pred.always (t.ref "{\"declared\":{\"site\":"); }).d
          (
            exactly "gen-aspects.guard: aspect `d`: ref-id-domain: a door registration reference's identifier is outside refId's grammar (or longer than 8192 characters), so it cannot be read back: {\"declared\":{\"site\":; build it with gen-algebra's `refId`."
          );
      test-entity-kinds-list-witness = thrown (place {
        entityKinds = [
          "a"
          1
        ];
      } { }) (kinds "a list holding a value of type int");
      test-entity-kinds-attrset-witness = thrown (place { entityKinds.a = "yes"; } { }) (
        kinds "an attrset whose value at `a` is of type string"
      );
      test-entity-kinds-string-witness = thrown (place { entityKinds = "host"; } { }) (kinds "string");
      test-module-fn-self-returning-at-aspect =
        thrown
          (place { } {
            n =
              let
                m = { lib, ... }: m;
              in
              m;
          }).n.description
          (
            exactly "gen-merge: module `<gen-merge>' is a function whose result is lambda, not an attribute set. A module function is applied once, to the module arguments, and must return the module itself; a function that returns another function (`a: b: { … }`) is not a module."
          );
      test-pred-custom-retired = thrown (aspects.pred.custom "x" { }) (
        exactly "gen-aspects.pred.custom was RETIRED by den-hoag-lwbb1: a custom condition is a term built from `pred.has`, `pred.eq`, `pred.all`, `pred.any` and `pred.not`; one no term can state is a context closure, which crosses the gen-rules door: declare the aspect through the framework's surface."
      );
      test-closure-body-remedy =
        thrown (place { } { g = aspects.guard aspects.pred.always (ctx: { }); }).g
          (
            exactly "gen-aspects.guard: aspect `g`: term-function: {\"remedy\":\"a closure is not a term\"}. A guard body is data: module content belongs under a class key. A context closure crosses the gen-rules door: declare the aspect through the framework's surface, or write the body as a guard term (`guard (pred.has <coordinate>) <body>`)."
          );
    };

  # Stage 2b, the message (spec §2.10 [v1 G-C4], §3a): every site that refuses a context closure names
  # the gen-rules door and the guard-term remedy, and the retired forms refuse by name. The structure
  # half (that each refusal is catchable, beside its admitted control) is `ci/tests` `closure-door`.
  flake.testsError.closure-door =
    let
      place =
        defsList:
        (mkSchemaEval {
          keySemantics.nixos.category = "class";
          modules = map (d: { config.aspects = d; }) defsList;
        }).config.aspects;
      bare =
        loc:
        exactly (
          "gen-aspects: aspect `${loc}`: a context closure reached a gen-aspects-typed position. gen-aspects "
          + "holds first-order guards only; a closure crosses the gen-rules door. Declare the aspect through the "
          + "framework's surface, so that gen-rules' lowering turns the closure into a door node, or write it as a "
          + "guard term (`guard (pred.has <coordinate>) <body>`). If the closure sits in the result of a module "
          + "function written at an aspect position (`{ config, ... }: { includes = [ ({ host, ... }: …) ]; }`), the "
          + "lowering reaches it only where the framework mounts gen-rules' registration table inside the aspect "
          + "submodule (`cnf.aspectModules`); "
          + "without that mount the closure arrives here unlowered. A closure that reads none of the module function's "
          + "arguments can also be written beside the function instead of inside it."
        );
      retired =
        name:
        exactly "gen-aspects.${name} was RETIRED by den-hoag-lwbb1: gen-aspects holds first-order guards only, and a context closure crosses the gen-rules door. Declare the aspect through the framework's surface, so that gen-rules' lowering turns the closure into a door node, or write it as a guard term (`guard (pred.has <coordinate>) <body>`).";
    in
    {
      test-bare-closure-at-aspect = thrown (place [ { x = { thimble, ... }: { }; } ]).x (bare "x");
      test-closure-in-includes =
        thrown (place [ { x.includes = [ ({ host, ... }: { }) ]; } ]).x.includes
          (bare "x.includes.[definition 1-entry 1]");
      test-closure-multidef =
        thrown
          (place [
            { x.description = "a"; }
            { x = { thimble, ... }: { }; }
          ]).x
          (bare "x");
      # alhfc gate X1: the closure inside an aspect-position module function's result. The message says
      # what happened to it and recommends no route for that shape (an open owner reading).
      test-closure-inside-module-fn-result =
        thrown (place [ { x = { config, ... }: { includes = [ ({ host, ... }: { }) ]; }; } ]).x.includes
          (bare "x.includes.[definition 1-entry 1]");
      test-closure-guard-body =
        thrown (place [ { g = aspects.guard aspects.pred.always ({ host, ... }: { }); } ]).g
          (
            exactly "gen-aspects.guard: aspect `g`: term-function: {\"remedy\":\"a closure is not a term\"}. A guard body is data: module content belongs under a class key. A context closure crosses the gen-rules door: declare the aspect through the framework's surface, or write the body as a guard term (`guard (pred.has <coordinate>) <body>`)."
          );
      test-wrapfn-retired = thrown (aspects.wrapFn { } "w" ({ host, ... }: { })) (retired "wrapFn");
      test-wrapgatedfn-retired = thrown (aspects.wrapGatedFn { functionArgs.host = false; }) (
        retired "wrapGatedFn"
      );
      test-applyguard-closure = thrown (aspects.applyGuard { host = "h"; } ({ host, ... }: { })) (
        exactly "gen-aspects.guard: applyGuard: a context closure was handed where a guard record belongs. gen-aspects holds first-order guards only; a closure crosses the gen-rules door. Declare the aspect through the framework's surface, or write it as a guard term (`guard (pred.has <coordinate>) <body>`)."
      );
      test-defer-include-resolution-retired =
        thrown
          (mkSchemaEval {
            deferIncludeResolution = true;
            modules = [ ];
          }).config.aspects
          ("^" + lib.escapeRegex "gen-aspects: unrecognised cnf key 'deferIncludeResolution'.");
    };

  # den-hoag-ywlww: two firing definitions of one parametric aspect that disagree on a scalar are
  # refused by name at the carrier's discharge, as nixpkgs refuses the same two definitions. They
  # read one value at rc 0 before (`mergeDefaultOption`'s `//` fold).
  flake.testsError.guard-carrier-conflict.test-conflicting-scalar-refused =
    let
      always = gv.vocab.always;
      eval = mkSchemaEval {
        modules = [
          { config.aspects.dup = always { description = "a"; }; }
          { config.aspects.dup = always { description = "b"; }; }
        ];
      };
    in
    thrown (gv.applyGuard { } eval.config.aspects.dup) (
      "^" + lib.escapeRegex "gen-merge: the option `dup.description' has conflicting definitions:"
    );
  # den-hoag-bgeum (spec §3a A3, gate C1): an instance's member that refuses is refused at its own
  # read, named by aspect AND field; a context-free include element that refuses at the declaration
  # is named by aspect and include position, though nothing instantiates the declaration. The
  # structure halves are `ci/tests` `instantiation-edge`.
  flake.testsError.instantiation-edge =
    let
      t = (genAlgebra.term genIdentity.hashIdentity).term;
      g = aspects.guard;
      has = aspects.pred.has;
      # `k` holding `elem` at its static `includes`, and the read that forces its classification.
      staticTerm =
        elem:
        (aspects.graphFacts { } (
          (mkSchemaEval { modules = [ { config.aspects.k.includes = [ elem ]; } ]; }).config.aspects
        )).includeSitesOf.k;
      tree =
        (mkSchemaEval {
          modules = [
            {
              config.aspects = {
                lazy = g (has "host") {
                  fine = "fine";
                  bad = t.readCtx "host" [ "deep" ];
                };
                neverFires = g (has "user") { includes = [ (t.concat [ (t.lit 1) ]) ]; };
              };
            }
          ];
        }).config.aspects;
      src = "entity:" + builtins.hashString "sha256" "h1";
      r = aspects.instancesFor { } tree {
        containment = { };
        suppliers.${src}.host = "h1";
        scopes.n = {
          members = [ "lazy" ];
          sources.host = src;
        };
      };
    in
    {
      test-member-refuses-by-field = thrown r.vertices.${builtins.head r.reaches.n.lazy}.entry.bad (
        "^" + lib.escapeRegex "gen-aspects.guard: aspect `lazy`, field `bad`: projection-path-missing: "
      );
      # P1: the TOP former decides the code. `ReadCtx` and `Default` are `unsafe-read`; every other former
      # is `static-term`, whose message claims nothing about what the term reads (`readFrom` reads a
      # source, a `concat` may hold a context read), and neither message is the other's.
      test-static-term-at-include-refuses-by-name = thrown (staticTerm (t.readCtx "host" [ ])) (
        "^"
        + lib.escapeRegex "gen-aspects.guard: aspect `k`, include position 0, a static declaration: unsafe-read: the include position holds a ReadCtx term, and a static declaration has no condition covering a context read (`always` covers nothing); declare the aspect parametrically, `guard (pred.has <coordinate>) { includes = [ … ]; }`, or name the aspect to include"
      );
      test-static-default-refuses-as-unsafe-read =
        thrown (staticTerm (t.default "host" [ ] (t.lit "d")))
          (
            "^"
            + lib.escapeRegex "gen-aspects.guard: aspect `k`, include position 0, a static declaration: unsafe-read: the include position holds a Default term"
          );
      test-static-lit-refuses-as-static-term = thrown (staticTerm (t.lit "c")) (
        "^"
        + lib.escapeRegex "gen-aspects.guard: aspect `k`, include position 0, a static declaration: static-term: the include position holds a Lit term; only static content is admitted at a static include position; declare the aspect parametrically, `guard (pred.has <coordinate>) { includes = [ … ]; }`, or name the aspect to include"
      );
      test-static-read-from-refuses-as-static-term = thrown (staticTerm (t.readFrom "src" [ ])) (
        "^"
        + lib.escapeRegex "gen-aspects.guard: aspect `k`, include position 0, a static declaration: static-term: the include position holds a ReadFrom term"
      );
      test-static-reading-concat-refuses-as-static-term =
        thrown
          (staticTerm (
            t.concat [
              (t.lit "a")
              (t.readCtx "host" [ ])
            ]
          ))
          (
            "^"
            + lib.escapeRegex "gen-aspects.guard: aspect `k`, include position 0, a static declaration: static-term: the include position holds a Concat term"
          );
      test-static-term-in-carrier-refuses-by-name =
        thrown
          (aspects.graphFacts { } (
            (mkSchemaEval {
              modules = [
                { config.aspects.k = g (has "host") { includes = [ (t.readCtx "host" [ ]) ]; }; }
                { config.aspects.k.includes = [ (t.lit "s2") ]; }
              ];
            }).config.aspects
          )).includeSitesOf.k
          (
            "^"
            + lib.escapeRegex "gen-aspects.guard: aspect `k`, include position 0, a static declaration: static-term: the include position holds a Lit term"
          );
      test-declaration-member-refuses-by-position = thrown (aspects.graphFacts { } tree).includesOf (
        "^"
        + lib.escapeRegex "gen-aspects.guard: aspect `neverFires`, include position 0, a declaration member resolved once at the declaration: former-operand-type: "
      );
    };

  # The unscoped arm of `instance-scope` (den-hoag-ohvjc §3a G1′): a deferred door node fired with no
  # scope takes the door's fallback, which re-applies the outer, and the poisoned door
  # (`ci/fixtures/scope-door.nix`) throws there. It pins that the out-of-domain path is still the
  # fallback; the value plane pins that the scoped arm does not throw.
  flake.testsError.instance-scope =
    let
      T = genAlgebra.term genIdentity.hashIdentity;
      sd = import ./fixtures/scope-door.nix { inherit aspects T; };
      src = n: "entity:" + builtins.hashString "sha256" n;
      kinds.entityKinds = {
        thimble = true;
        bobbin = true;
      };
      unscoped =
        depth:
        let
          o = aspects.instanceOf (kinds // { ref = sd.door depth false; }) {
            aspect = "outer";
            value = sd.outerNode depth;
            context.thimble = "h0";
            sources.thimble = src "h0";
          };
          first = builtins.head o.entry.includes;
        in
        (aspects.instanceOf (kinds // { ref = sd.door depth true; }) {
          aspect = "inner";
          value = if depth == 1 then first else builtins.head first.includes;
          context = {
            thimble = "h0";
            bobbin = "u0";
          };
          sources = {
            thimble = src "h0";
            bobbin = src "u0";
          };
        }).entry;
    in
    {
      test-unscoped-takes-fallback = thrown (unscoped 1) (
        exactly "scope-door: the outer closure was re-applied"
      );
      test-unscoped-takes-fallback-depth-2 = thrown (unscoped 2) (
        exactly "scope-door: the outer closure was re-applied"
      );
    };

  # den-hoag-3sk7j (spec §3a, the message): a refusal VALUE of a value-regime library at an aspect
  # position is refused by name, naming its encoding, its code and the gen-rules door; the producer's
  # own message is carried. The structure half (catchable, beside its admitted control) is
  # `ci/tests` `refusal-value`.
  flake.testsError.refusal-value-door =
    let
      place =
        defs:
        (mkSchemaEval {
          keySemantics.nixos.category = "class";
          modules = [ { config.aspects = defs; } ];
        }).config.aspects;
      inc = v: builtins.head (place { x.includes = [ v ]; }).x.includes;
      door =
        loc: kind: code: carried:
        exactly (
          "gen-aspects: aspect `${loc}`: a refusal value reached an aspect position: ${kind}"
          + (if code == null then "" else " with code `${code}`")
          + ", not an aspect. A call that returns its refusals as values refused, and its result was "
          + "placed here unread; read the refusal where it was returned.${carried} A context closure crosses "
          + "the gen-rules door: declare the aspect through the framework's surface, so that gen-rules' "
          + "lowering turns the closure into a door node, or write it as a guard term."
        );
      record = "a refusal record (`{ refused = true; code; … }`, gen-program)";
      at = "x.includes.[definition 1-entry 1]";
    in
    {
      test-record-escape-retired-in-includes = thrown (inc {
        refused = true;
        blamed = "author";
        code = "policy-body/escape-retired";
        witness.retired = "escape";
        message = "`escape` is retired";
      }) (door at record "policy-body/escape-retired" " Its message: `escape` is retired.");
      test-record-flat-witness-in-includes = thrown (inc {
        refused = true;
        blamed = "author";
        code = "policy-body/skeleton-malformed";
        witness = 42;
        message = "a policy body is a record.";
      }) (door at record "policy-body/skeleton-malformed" " Its message: a policy body is a record.");
      test-either-left-in-includes =
        thrown
          (inc {
            left = {
              code = "unsafe-read";
              witness.message = "read outside the guard";
            };
          })
          (
            door at "an Either refusal (`{ left = { code; witness; }; }`, gen-algebra / gen-rules)"
              "unsafe-read"
              " Its message: read outside the guard."
          );
      test-crossing-refusal-in-includes = thrown (inc {
        __crossingResult = "refusal";
        refusal = {
          code = "c";
          blamed = "author";
          witness = { };
        };
      }) (door at "a crossing refusal (`__crossingResult = \"refusal\"`, gen-bind)" "c" "");
      test-record-flat-witness-at-root =
        thrown
          (place {
            x = {
              refused = true;
              blamed = "author";
              code = "policy-body/skeleton-malformed";
              witness = 42;
              message = "m";
            };
          }).x
          (door "x" record "policy-body/skeleton-malformed" " Its message: m.");
      # The failure-list Either from its real producer (gen-schema `runValidators`): no code, and the
      # first failure's message is carried.
      test-failure-list-left-in-includes =
        thrown
          (inc (
            genSchema.runValidators "host" [
              {
                name = "named";
                pred = i: i ? name;
                message = "a host is named";
              }
            ] { h = { }; }
          ))
          (
            door at
              "an Either refusal carrying a failure list (`{ left = [ failure … ]; }`, gen-types / gen-schema `runValidators`, gen-algebra `collectErrors`)"
              null
              " Its message: a host is named."
          );
    };

  # A declaration's identity inputs (den-hoag-qseuh, den-hoag-gywcg). The type defines `meta.loc` at a
  # tree position, so a caller's unequal write, malformed or not, conflicts with it at merge and refuses
  # by name; `"zz"` and `[ 1 ]` aborted the evaluator inside the key before. A chain that contradicts the
  # declared path refuses by name (identity design Q4).
  flake.testsError.identity-inputs =
    let
      keyOf =
        def:
        aspects.key
          (mkSchemaEval {
            modules = [ { config.aspects.x = def; } ];
          }).config.aspects.x;
      conflicting =
        got:
        exactly (
          "gen-merge: the option `x.meta.loc' has conflicting definitions:\n"
          + "- In `<gen-merge>': <a list>\n"
          + "- In `<gen-merge>': ${got}"
        );
      contradicts =
        chain:
        exactly (
          "gen-aspects: identity: `x` sets meta.aspect-chain = ${chain}, which contradicts its declared path [ x ]. "
          + "meta.aspect-chain is a rendering of the declared path and never an identity input; remove the definition."
        );
    in
    {
      test-loc-string = thrown (keyOf { meta.loc = "zz"; }) (conflicting "\"zz\"");
      test-loc-non-string = thrown (keyOf { meta.loc = [ 1 ]; }) (conflicting "<a list>");
      test-loc-empty = thrown (keyOf { meta.loc = [ ]; }) (conflicting "<a list>");
      test-chain-contradicts = thrown (keyOf { meta.aspect-chain = [ "k" ]; }) (contradicts "[ k ]");
      # A malformed chain is rendered by its type, never coerced: interpolating it aborted uncatchably.
      test-chain-malformed = thrown (keyOf { meta.aspect-chain = [ 1 ]; }) (contradicts "a list");
    };

  # The type is the one writer of `key`, `id_hash` and `meta.loc` (den-hoag-gywcg). A write that wins
  # by priority refuses where it is read, and a NAMED include element's write refuses by name before the
  # element is read as a module (where its `key` would be the module key, dropped silently).
  flake.testsError.structured-key-writes =
    let
      at =
        def:
        (mkSchemaEval {
          modules = [ { config.aspects.x = def; } ];
        }).config.aspects.x;
      el =
        write:
        builtins.head
          (mkSchemaEval {
            modules = [
              {
                config.aspects.loom.includes = [
                  (
                    {
                      name = "t";
                    }
                    // write
                  )
                ];
              }
            ];
          }).config.aspects.loom.includes;
      typeWrites =
        field:
        exactly "gen-aspects: the option `x.${field}' is written by the aspect type; remove the definition.";
      elementWrites =
        field:
        exactly "gen-aspects: an include element named `t' writes `${field}', which the aspect type writes; remove the definition.";
    in
    {
      test-key = thrown (at { key = "y"; }).key (typeWrites "key");
      test-id-hash = thrown (at { id_hash = "aspect:0"; }).id_hash (typeWrites "id_hash");
      test-loc-forced-at-key = thrown (aspects.key (at {
        meta.loc = genMerge.mkForce [ "y" ];
      })) (typeWrites "meta.loc");
      test-loc-forced-at-id = thrown (aspects.aspectId [ ] (at {
        meta.loc = genMerge.mkForce [ "y" ];
      })) (typeWrites "meta.loc");
      test-element-key = thrown (el { key = "q"; }).key (elementWrites "key");
      test-element-id-hash = thrown (el { id_hash = "aspect:0"; }).id_hash (elementWrites "id_hash");
      test-element-loc = thrown (aspects.key (el {
        meta.loc = [ "q" ];
      })) (elementWrites "meta.loc");
    };

  # A functor-form module function at an aspect position is refused by name at every site that reads a
  # definition: single def, multi def, a guard-bearing multi def and an include element (den-hoag-a3eys).
  # The structure half, beside its lambda twin and den v1's unchanged `__functor` aspect form, is
  # `ci/tests` `functor-module-refusal`.
  flake.testsError.functor-module-refusal =
    let
      fm = {
        __functionArgs = {
          config = false;
        };
        __functor =
          _:
          { config, ... }:
          { };
      };
      place =
        defs:
        (mkSchemaEval {
          keySemantics.nixos.category = "class";
          modules = map (d: { config.aspects.x = d; }) defs;
        }).config.aspects.x;
      other.description = "o";
      guarded = gv.vocab.whenEq [ "host" ] "nope" { description = "g"; };
      msg =
        loc:
        exactly (
          "gen-aspects: aspect `${loc}`: a functor-form module function (an attrset with `__functor`, as "
          + "`setFunctionArgs` builds) reached an aspect position. A submodule reads an attrset definition as "
          + "config, never as a module, so its `__functor` key would be kept as an aspect attribute and nothing "
          + "would be delivered. Write it as a lambda: `{ config, ... }: { ... }`."
        );
    in
    {
      test-single = thrown (place [ fm ]).nixos (msg "x");
      test-multi =
        thrown
          (place [
            fm
            other
          ]).nixos
          (msg "x");
      test-guard-sibling =
        thrown
          (place [
            fm
            guarded
          ]).nixos
          (msg "x");
      test-element = thrown (place [ { includes = [ fm ]; } ]).includes (
        msg "x.includes.[definition 1-entry 1]"
      );
      # A functor whose `__functionArgs` is not an attrset is not a module function: it must neither
      # abort the interpreter uncatchably nor be refused as one.
      test-malformed-functionargs-is-not-an-abort = {
        expr =
          (place [
            {
              __functionArgs = 5;
              __functor =
                _:
                { config, ... }:
                { };
            }
          ]).nixos;
        expected = null;
      };
    };
}
