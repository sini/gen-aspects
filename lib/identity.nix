# Aspect identity: path-based key for dedup.
{ lib }:
let
  aspectPath = a: (a.meta.aspect-chain or [ ]) ++ [ (a.name or "<anon>") ];

  pathKey = path: lib.concatStringsSep "/" path;

  isMeaningfulName =
    name: name != "<anon>" && name != "<function body>" && !(lib.hasPrefix "[definition " name);
in
{
  inherit aspectPath pathKey isMeaningfulName;
  key =
    a:
    if a.__isWrappedFn or false then
      pathKey (a.meta.loc or [ (a.name or "<anon>") ])
    else
      pathKey (aspectPath a);
}
