# Introspect whether a function's required args are satisfiable by a param set.
# Used to distinguish module functions (take lib/config/options) from
# guard functions (take context like host/user) at the type level.
{ prelude }:
let
  canTake =
    params: func:
    let
      valid = prelude.isFunction func && builtins.isAttrs params;
      args = prelude.functionArgs func;
      required = builtins.filter (n: !args.${n}) (builtins.attrNames args);
      satisfied = valid && builtins.all (n: params ? ${n}) required;
      intersect = builtins.intersectAttrs args params;
    in
    {
      inherit satisfied;
      upTo = satisfied && intersect != { };
    };
in
{
  atLeast = params: func: (canTake params func).satisfied;
  upTo = params: func: (canTake params func).upTo;
}
