# den-hoag-nwshf: the orphan-leaf refusal (on by default) and what it must leave alone.
{
  aspects,
  genMerge,
  mkSchemaEval,
  ...
}:
let
  hem =
    extra: body:
    (mkSchemaEval (
      {
        keySemantics.nixos.category = "class";
        modules = [ { config.aspects.hem = body; } ];
      }
      // extra
    )).config.aspects.hem;
  caught = v: (builtins.tryEval (builtins.deepSeq v v)).success;
  t = genMerge.types;
  ks.nixos.category = "class";
  # A DECLARED aspect position other than an `includes` element: a container and a single aspect
  # declared as schema extensions, and a container declared as a keySemantics facet.
  declared = type: default: genMerge.mkOption { inherit type default; };
  inner = aspects.aspectType { keySemantics = ks; };
  extOf = k: o: { config.schema.aspect.options.${k} = o; };
  withExt =
    ext: body:
    (mkSchemaEval {
      keySemantics = ks;
      modules = [
        ext
        { config.aspects.hem = body; }
      ];
    }).config.aspects.hem;
  facetKs = {
    provides = {
      category = "facet";
      option = declared (t.lazyAttrsOf inner) { };
    };
  };
  tagsExt = {
    config.schema.aspect.options.tags = genMerge.mkOption {
      type = genMerge.types.listOf genMerge.types.str;
      default = [ ];
    };
  };
in
{
  flake.tests.orphan-leaf.test-refusal-is-catchable = {
    expr = caught (hem { } { nixso.boot.enable = true; }).nixso.boot.enable;
    expected = false;
  };
  flake.tests.orphan-leaf.test-what-it-leaves-alone = {
    expr = {
      firstLevel = (hem { } { binding = [ "bias" ]; }).binding;
      nullDeep = (hem { } { sub.x = null; }).sub.x;
      includeLiteral = (builtins.head (hem { } { includes = [ { tag = "x"; } ]; }).includes).tag;
      extensionDeep =
        (hem {
          modules = [
            tagsExt
            { config.aspects.hem.sub.inner.tags = [ "deep" ]; }
          ];
        } { }).sub.inner.tags;
    };
    expected = {
      firstLevel = [ "bias" ];
      nullDeep = null;
      includeLiteral = "x";
      extensionDeep = [ "deep" ];
    };
  };
  # The position decides, never the key's spelling (spec gate v0 C1): a declared aspect's first-level
  # datum passes wherever the aspect is declared, and an aspect NAMED `includes` is a root aspect like
  # any other, so a datum below its nested aspect is refused.
  flake.tests.orphan-leaf.test-position-not-spelling = {
    expr = {
      extContainer =
        (withExt (extOf "provides" (declared (t.lazyAttrsOf inner) { })) { provides.foo.tag = "x"; })
        .provides.foo.tag;
      extSingle = (withExt (extOf "main" (declared (t.nullOr inner) null)) { main.tag = "x"; }).main.tag;
      facetContainer =
        (hem { keySemantics = ks // facetKs; } { provides.foo.tag = "x"; }).provides.foo.tag;
      namedIncludes =
        caught
          (mkSchemaEval {
            keySemantics = ks;
            modules = [ { config.aspects.includes.sub.x = 1; } ];
          }).config.aspects.includes.sub.x;
      declaredNested =
        caught
          (withExt (extOf "main" (declared (t.nullOr inner) null)) { main.sub.x = 1; }).main.sub.x;
    };
    expected = {
      extContainer = "x";
      extSingle = "x";
      facetContainer = "x";
      namedIncludes = false;
      declaredNested = false;
    };
  };
}
