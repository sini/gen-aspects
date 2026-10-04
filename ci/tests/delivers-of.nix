# den-hoag-ouuwg: `graphFacts.deliversOf`, total over `nodes`, and the dead-nested view it names.
{
  aspects,
  mkSchemaEval,
  factsInternals,
  lib,
  ...
}:
let
  cnf.keySemantics.nixos.category = "class";
  dead =
    body:
    let
      f =
        aspects.graphFacts cnf
          (mkSchemaEval {
            keySemantics = cnf.keySemantics;
            modules = [ { config.aspects = body; } ];
          }).config.aspects;
    in
    f.deadNested;
in
{
  flake.tests.delivers-of.test-names-the-typos-iv-misses = {
    expr = {
      attrsetOnly = dead {
        stitch.nixos.x = { };
        stitch.nixso.boot.loader = { };
      };
      empty = dead {
        stitch.nixos.x = { };
        stitch.nixso = { };
      };
      placeholder = dead {
        asp.nixos.x = { };
        asp.child.description = "child";
      };
    };
    expected = {
      attrsetOnly = [
        "stitch/nixso"
        "stitch/nixso/boot"
        "stitch/nixso/boot/loader"
      ];
      empty = [ "stitch/nixso" ];
      placeholder = [ "asp/child" ];
    };
  };
  flake.tests.delivers-of.test-delivering-nested-is-not-named = {
    expr = {
      classContent = dead { stitch.trim.nixos.x = { }; };
      includes = dead {
        stitch.trim.includes = [ "other" ];
        other.nixos.x = { };
      };
      guardChild = dead { stitch.trim.g = aspects.guard (aspects.pred.has "host") { nixos.x = { }; }; };
      topLevel = dead { lonely = { }; };
    };
    expected = {
      classContent = [ ];
      includes = [ ];
      guardChild = [ ];
      topLevel = [ ];
    };
  };
  # The view is the one filter over the relation, and the record still reads as a value when it
  # warns: the warning is a message, never a refusal.
  flake.tests.delivers-of.test-view-is-the-filter-and-warns-without-refusing =
    let
      f =
        aspects.graphFacts cnf
          (mkSchemaEval {
            keySemantics = cnf.keySemantics;
            modules = [
              {
                config.aspects = {
                  stitch.nixos.x = { };
                  stitch.nixso = { };
                };
              }
            ];
          }).config.aspects;
    in
    {
      expr = {
        same =
          f.deadNested == builtins.filter (id: f.parentOf.${id} != null && !f.deliversOf.${id}) f.nodes;
        readable = (builtins.tryEval (builtins.deepSeq f.nodes true)).success;
      };
      expected = {
        same = true;
        readable = true;
      };
    };

  # The WARNED subset of the view (den-hoag-l62pz): a dead nested node whose NODE ID the caller listed
  # in `freeformKeys` is declared taxonomy and is not said. The view is untouched; the id is the
  # node's own (never an ancestor's), so a typo below a listed placeholder is still said, and a
  # same-NAMED dead stray elsewhere is still said (`stitch.eyelet` beside the listed
  # `hemline/placket/eyelet`).
  flake.tests.delivers-of.test-warned-subset-is-the-view-less-listed-ids =
    let
      taxonomy = {
        hemline.nixos.x = { };
        hemline.placket.eyelet = { };
        hemline.facing = { };
      };
      ids = [
        "hemline/placket"
        "hemline/placket/eyelet"
        "hemline/facing"
      ];
      facts =
        listed: body:
        aspects.graphFacts (cnf // { freeformKeys = listed; })
          (mkSchemaEval {
            keySemantics = cnf.keySemantics;
            modules = [ { config.aspects = body; } ];
          }).config.aspects;
      said =
        listed: body:
        factsInternals.warnedDeadNested (cnf // { freeformKeys = listed; }) (facts listed body);
    in
    {
      expr = {
        deadTypo = said [ ] {
          stitch.nixos.x = { };
          stitch.nixso = { };
        };
        undeclared = said [ ] taxonomy;
        declared = said ids taxonomy;
        partial = said [ "hemline/placket" "hemline/facing" ] taxonomy;
        typoBelowListed = said ids {
          hemline.nixos.x = { };
          hemline.placket.nixso.boot = { };
        };
        deadBesideListed = said ids (
          taxonomy
          // {
            stitch.nixso = { };
            stitch.nixos.x = { };
          }
        );
        # the F1 witness: a same-named dead stray beside the listed placeholder
        sameNamedStray = said ids (
          taxonomy
          // {
            stitch.eyelet = { };
            stitch.nixos.x = { };
          }
        );
        # a bare name is not an id: it names no node
        bareNameSilencesNothing = said [ "eyelet" "placket" "facing" ] taxonomy;
        viewUntouched = (facts ids taxonomy).deadNested;
      };
      expected = {
        deadTypo = [ "stitch/nixso" ];
        undeclared = [
          "hemline/facing"
          "hemline/placket"
          "hemline/placket/eyelet"
        ];
        declared = [ ];
        partial = [ "hemline/placket/eyelet" ];
        typoBelowListed = [
          "hemline/placket/nixso"
          "hemline/placket/nixso/boot"
        ];
        deadBesideListed = [ "stitch/nixso" ];
        sameNamedStray = [ "stitch/eyelet" ];
        bareNameSilencesNothing = [
          "hemline/facing"
          "hemline/placket"
          "hemline/placket/eyelet"
        ];
        viewUntouched = [
          "hemline/facing"
          "hemline/placket"
          "hemline/placket/eyelet"
        ];
      };
    };
  # The id is `providerPrefix`-qualified and the caller writes the rendered form: a prefixed tree
  # is silenced by the prefixed ids and by nothing else.
  flake.tests.delivers-of.test-listed-ids-are-the-published-ids-under-a-provider-prefix =
    let
      pcnf = cnf // {
        providerPrefix = [ "acme" ];
      };
      factsAt =
        listed:
        aspects.graphFacts (pcnf // { freeformKeys = listed; })
          (mkSchemaEval {
            keySemantics = cnf.keySemantics;
            modules = [
              {
                config.aspects = {
                  hemline.nixos.x = { };
                  hemline.facing = { };
                };
              }
            ];
          }).config.aspects;
      said =
        listed: factsInternals.warnedDeadNested (pcnf // { freeformKeys = listed; }) (factsAt listed);
    in
    {
      expr = {
        prefixed = said [ "acme/hemline/facing" ];
        unprefixed = said [ "hemline/facing" ];
      };
      expected = {
        prefixed = [ ];
        unprefixed = [ "acme/hemline/facing" ];
      };
    };
  # THE GLUE: the line that chooses what `graphFacts` says. `warn` is injected, so a recorder shows
  # whether it was called; reverting `said = warnedDeadNested cnf facts` to the whole view reds this
  # while every pure selector cell above stays green (measured at the gate: 435/435 without it).
  flake.tests.delivers-of.test-the-record-says-only-the-warned-subset =
    let
      record = ids: {
        deadNested = ids;
      };
      recorder = msg: _: { said = msg; };
      listed = cnf // {
        freeformKeys = [ "a/b" ];
      };
      go = c: ids: factsInternals.sayDeadNested recorder c (record ids);
    in
    {
      expr = {
        listedIsNotSaid = go listed [ "a/b" ] == record [ "a/b" ];
        unlistedIsSaid = (go listed [ "a/c" ]) ? said;
        onlyTheUnlistedIsNamed =
          let
            m =
              (go listed [
                "a/b"
                "a/c"
              ]).said;
          in
          lib.hasInfix "`a/c`" m && !(lib.hasInfix "`a/b`" m);
        nothingDeadIsNotSaid = go listed [ ] == record [ ];
      };
      expected = {
        listedIsNotSaid = true;
        unlistedIsSaid = true;
        onlyTheUnlistedIsNamed = true;
        nothingDeadIsNotSaid = true;
      };
    };
  # The message names the remedy it now has and no longer says there is none.
  flake.tests.delivers-of.test-warning-names-its-remedy =
    let
      msg = factsInternals.deadNestedWarning [ "a/b" ];
    in
    {
      expr = {
        names = lib.hasInfix "`a/b`" msg;
        remedy = lib.hasInfix "node id in `freeformKeys`" msg;
        noLongerDeniesOne = !(lib.hasInfix "no silencing remedy" msg);
        namesThePrefix = lib.hasInfix "`providerPrefix` of the cnf the facts are read with" msg;
      };
      expected = {
        names = true;
        remedy = true;
        noLongerDeniesOne = true;
        namesThePrefix = true;
      };
    };
}
