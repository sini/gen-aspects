# Introspect whether a function's required args are satisfiable by a param set.
# Used to distinguish module functions (take lib/config/options) from
# guard functions (take an evaluation context) at the type level.
{ prelude }:
let
  canTake =
    params: func:
    let
      args = prelude.functionArgs func;
      # A functor's `__functionArgs` is author-written: a non-attrset or non-Boolean formals map is not a
      # formals declaration, so it takes nothing rather than aborting the read below.
      valid =
        prelude.isFunction func
        && builtins.isAttrs params
        && builtins.isAttrs args
        && builtins.all builtins.isBool (builtins.attrValues args);
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
