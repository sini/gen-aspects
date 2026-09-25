# `aspectsRoot` IS LEGIBLE AS THE ELEMENT-CARRYING CONTAINER IT IS. It states its element in the
# carrying spelling (`nestedTypes.elemType`, beside a top-level `elemType`) and its merge relation in
# `functor.binOp` over a payload that is the element itself. gen-merge's boundary reads what a type
# carries from the carrying spelling, so the root reports `carries.element` and a populated
# `nestedTypes`, as gen-merge's own `attrsOf` does. Its payload stays what its relation merges on.
#
# The identity walk: a root over an element holding identity is read TOTALLY on a warm re-compose.
# The root states its own relation and no rebuild, so nothing says whether it adds a path level, and
# the walk stops there rather than guess; the warm read equals cold. The real root's element is the
# aspect type, which carries nothing, so the walk stops at it on every arm.
{
  aspects,
  genMerge,
  ...
}:
let
  t = genMerge.types;
  inherit (genMerge) evalModuleTree mkOption;
  root = aspects.aspectsRoot { };
  rootOver = root.functor.type;
  idSub = t.submodule (
    { config, ... }:
    {
      options.id_hash = mkOption { type = t.str; };
      options.spool = mkOption {
        type = t.str;
        default = "";
      };
      config.id_hash = "thimble:" + config.spool;
    }
  );
  ok = e: (builtins.tryEval (builtins.deepSeq e e)).success;
  coldOf = mods: evalModuleTree { modules = mods; };
  held =
    ty: v:
    let
      base = [
        { options.reg = mkOption { type = t.attrsOf idSub; }; }
        {
          _file = "anc";
          config.reg.p.spool = "anchor";
        }
        { options.h = mkOption { type = ty; }; }
        {
          _file = "sb";
          config.h = v;
        }
      ];
      edit = [
        {
          _file = "o";
          options.other = mkOption { type = t.str; };
          config.other = "o";
        }
      ];
      w =
        (evalModuleTree {
          modules = base ++ edit;
          warmFrom = coldOf base;
          editedModules = edit;
        }).config;
    in
    ok w && builtins.toJSON w == builtins.toJSON (coldOf (base ++ edit)).config;
in
{
  flake.tests.root-carries.test-aspects-root-carries-its-element = {
    expr = {
      carries = root ? carries.element;
      nestedTypes = root.nestedTypes ? elemType;
      # live control: gen-merge's own container states its element the same way
      ctlAttrsOf = (t.attrsOf t.str).nestedTypes ? elemType;
      ctlLeaf = t.str.nestedTypes ? elemType;
    };
    expected = {
      carries = true;
      nestedTypes = true;
      ctlAttrsOf = true;
      ctlLeaf = false;
    };
  };
  flake.tests.root-carries.test-the-identity-walk-reads-a-root-totally = {
    expr = {
      overIdentity = held (rootOver idSub) { a.spool = "silk"; };
      real = held root { foo = { }; };
      ctlAttrsOf = held (t.attrsOf idSub) { a.spool = "silk"; };
    };
    expected = {
      overIdentity = true;
      real = true;
      ctlAttrsOf = true;
    };
  };
}
