# Introspect whether a function's required args are satisfiable by a param set.
{ lib }:
let
  canTake =
    params: func:
    let
      valid = lib.isFunction func && builtins.isAttrs params;
      args = lib.functionArgs func;
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
