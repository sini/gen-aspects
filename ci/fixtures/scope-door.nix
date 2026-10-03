# A stub of the framework's door (gen-rules `mkApply`'s contract, lib/apply.nix) over a closure tree
# `outer { thimble } → mid { thimble } → inner { thimble, bobbin }` (den-hoag-ohvjc). Each output's
# closures are lowered to door nodes keyed by nested registration identifiers, the closures returned
# in `scope`. A nested firing handed `captured` applies it; handed none it is the fallback, which
# re-applies its outer (recursively) to recover the closure. Every output carries `via`, the path that
# produced it. `door poison` is the same door whose declared outer closure THROWS when applied: a
# firing that reaches the fallback throws, one that reads its closure from the scope does not.
{
  aspects,
  T,
}:
let
  t = T.term;
  names = builtins.attrNames;
  rOuter =
    depth:
    (T.refId {
      declared = {
        site = "scope-outer-${toString depth}";
        reads = [ "thimble" ];
      };
    }).right;
  inner = { thimble, bobbin, ... }: { description = "inner@${thimble}/${bobbin}"; };
  mid =
    { thimble, ... }:
    {
      description = "mid@${thimble}";
      includes = [ inner ];
    };
  outerOf =
    depth:
    { thimble, ... }:
    {
      description = "outer@${thimble}";
      includes = [ (if depth == 1 then inner else mid) ];
    };
  # The closure at `includes.<i>` of the output of registration `id`, as a nested identifier.
  nestedId =
    id: sources: i: f:
    (T.refId {
      nested = {
        outer = id;
        sources = { inherit (sources) thimble; };
        position = [
          "includes"
          i
        ];
        reads = names (removeAttrs (builtins.functionArgs f) [ "thimble" ]);
      };
    }).right;
  lower =
    id: sources: out:
    let
      xs = out.includes or [ ];
      at = builtins.genList (i: {
        inherit i;
        x = builtins.elemAt xs i;
      }) (builtins.length xs);
      fns = builtins.filter (e: builtins.isFunction e.x) at;
    in
    {
      output =
        out
        // (
          if out ? includes then
            {
              includes = map (
                e:
                if builtins.isFunction e.x then
                  aspects.guard (aspects.pred.all (map aspects.pred.has (names (builtins.functionArgs e.x)))) (
                    t.ref (nestedId id sources e.i e.x)
                  )
                else
                  e.x
              ) at;
            }
          else
            { }
        );
      scope = builtins.listToAttrs (
        map (e: {
          name = nestedId id sources e.i e.x;
          value = e.x;
        }) fns
      );
    };
  door =
    depth: poison:
    let
      outer = if poison then _: throw "scope-door: the outer closure was re-applied" else outerOf depth;
      self =
        {
          id,
          context,
          sources,
          captured,
        }:
        let
          r = builtins.fromJSON id;
          fn =
            if r ? declared then
              outer
            else if captured != null then
              captured
            else
              (self {
                id = r.nested.outer;
                inherit context sources;
                captured = null;
              }).right.scope.${id};
          via =
            if r ? declared then
              "declared"
            else if captured != null then
              "scope"
            else
              "reapply";
        in
        if r ? nested && r.nested.sources.thimble != sources.thimble then
          {
            left = {
              code = "source-rebound";
              witness = { };
            };
          }
        else
          { right = lower id sources (fn context // { inherit via; }); };
    in
    self;
in
{
  inherit rOuter door;
  # The declared node of the outer registration: what an aspect writes for it.
  outerNode = depth: aspects.guard (aspects.pred.has "thimble") (t.ref (rOuter depth));
}
