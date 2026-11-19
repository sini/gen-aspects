# AN UNNAMED INCLUDE ELEMENT MOUNTED THROUGH UNMODIFIED nixpkgs IS ADDRESSED BY ITS POSITION IN THE HAND-OVER
# ORDER, AND HAS NO ID GUARANTEE ACROSS A MODULE REORDER (ADR-0025 item 1, its interoperability limit).
#
# nixpkgs' `lib.evalModules` hands the include member only `{ file; value; }` per definition and drops a
# module's `key`, so the export bridge's root anchors each seed by its index in that list (gen-merge
# `declAnchorOf`, the `a:<i>` arm under `nestedTreeAt`): keyed and path declaring modules do not reach the
# address there. Under gen's engine the same declarations keep their address under reorder. Named elements
# (a positioned `name`) and native nested aspects are keyed alike by both engines and do not move. The
# fixture is the rogbu identity probe's reversal pairs: each cell is evaluated in one order and its reverse.
#
# Read per element in list order, as `{ key; id_hash; }`:
#   follows    — every element keeps its ids across the reorder (matched by `description`);
#   positional — the ids, read slot by slot, are the same in both orders (the ids belong to the position);
#   distinct   — no two elements share a `key` or an `id_hash`, in each evaluation.
# The nixpkgs `positional` rows pin today's behaviour, not a guarantee: a change that makes them
# order-stable is a contract change, owed a ruling and an ADR-0025 amendment, not a fixture edit.
# Values and spellings are not pinned: the key carries a source path, so only relations are asserted.
{
  lib,
  aspects,
  genMerge,
  ...
}:
let
  m = (aspects.mkAspectSchema { }).mkAspectModule { };
  d = f: x: {
    _file = f;
    config.aspects = x;
  };
  kd =
    k: f: x:
    (d f x) // { key = "m-${k}"; };
  inc = e: { stitch.includes = [ e ]; };
  u = s: { description = s; };
  nA = {
    name = "nA";
    description = "nA";
  };
  nB = {
    name = "nB";
    description = "nB";
  };
  pA = builtins.toFile "foreign-include-order-pA.nix" "{ config.aspects.stitch.includes = [ { description = \"i0\"; } ]; }";
  pB = builtins.toFile "foreign-include-order-pB.nix" "{ config.aspects.stitch.includes = [ { description = \"i1\"; } ]; }";
  engines = {
    gen = ms: genMerge.evalModuleTree { } ms;
    nixpkgs = ms: lib.evalModules { modules = ms; };
  };
  ids = e: { inherit (e) key id_hash; };
  # the elements of one evaluation, in list order
  includesOf =
    ev: ms:
    map (e: {
      d = e.description;
      ids = ids e;
    }) (ev ([ m ] ++ ms)).config.aspects.stitch.includes;
  # a native nested aspect at two owners, read by its path
  nativeOf =
    ev: ms:
    let
      as = (ev ([ m ] ++ ms)).config.aspects;
    in
    [
      {
        d = "stitch.sub";
        ids = ids as.stitch.sub;
      }
      {
        d = "thimble.sub";
        ids = ids as.thimble.sub;
      }
    ];
  byD = l: lib.listToAttrs (map (e: lib.nameValuePair e.d e.ids) l);
  distinct = l: f: lib.length (lib.unique (map (e: e.ids.${f}) l)) == lib.length l;
  reorder =
    read: ev: ms:
    let
      fwd = read ev ms;
      rev = read ev (lib.reverseList ms);
    in
    {
      follows = byD fwd == byD rev;
      positional = map (e: e.ids) fwd == map (e: e.ids) rev;
      distinct = lib.all (l: distinct l "key" && distinct l "id_hash") [
        fwd
        rev
      ];
    };
  both = read: ms: lib.mapAttrs (_: ev: reorder read ev ms) engines;
  # gen's engine and nixpkgs' give each element the same ids
  agree = read: ms: byD (read engines.gen ms) == byD (read engines.nixpkgs ms);
  keyed = [
    (kd "A" "def-1" (inc (u "i0")))
    (kd "B" "def-2" (inc (u "i1")))
  ];
  paths = [
    pA
    pB
  ];
  named = [
    (d "def-1" (inc nA))
    (d "def-2" (inc nB))
  ];
  native = [
    (d "def-1" { stitch.sub.description = "sub"; })
    (d "def-2" { thimble.sub.description = "sub2"; })
  ];
  moves = {
    follows = false;
    positional = true;
    distinct = true;
  };
  holds = {
    follows = true;
    positional = false;
    distinct = true;
  };
in
{
  flake.tests.foreign-include-order = {
    # The limit: under nixpkgs an unnamed element of a keyed or a path module takes its hand-over slot's ids.
    # Under gen's engine the same elements keep theirs.
    # RED: a bridge root that orders its seeds by anything but nixpkgs' hand-over (gen-merge `nestedTreeAt`
    # sorting `site.defs` by `file`) turns the nixpkgs rows; a root anchor that drops the module key
    # (`declAnchorOf`'s `top` spelling every top-level module `a:<i>`) turns the gen rows.
    test-unnamed-foreign-include-ids-are-positional = {
      expr = {
        keyed = both includesOf keyed;
        paths = both includesOf paths;
      };
      expected = {
        keyed = {
          gen = holds;
          nixpkgs = moves;
        };
        paths = {
          gen = holds;
          nixpkgs = moves;
        };
      };
    };
    # The stable route: a named element and a native nested aspect keep their ids across the reorder in both
    # engines, and the two engines agree on them.
    # RED: the named element keyed as an unnamed one (gen-aspects `includeSite` always `unnamedSite`).
    test-named-and-native-ids-are-order-stable-in-both-engines = {
      expr = {
        named = both includesOf named;
        native = both nativeOf native;
        namedAgree = agree includesOf named;
        nativeAgree = agree nativeOf native;
      };
      expected = {
        named = {
          gen = holds;
          nixpkgs = holds;
        };
        native = {
          gen = {
            follows = true;
            positional = true;
            distinct = true;
          };
          nixpkgs = {
            follows = true;
            positional = true;
            distinct = true;
          };
        };
        namedAgree = true;
        nativeAgree = true;
      };
    };
  };
}
