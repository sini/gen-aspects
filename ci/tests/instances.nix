# `instanceOf` — the instance mint (lib/instance.nix; den-hoag-0cmbt spec §2.5, cells I-1 to I-7 and
# K-a/K-b through the mint). Every source is IDENTITY-shaped, minted here through gen-identity's
# `hashIdentity` under the entity and argument-binding kinds, because the mint refuses a context value
# and an aspect or instance identity as a source (the doors' cells are in ci/tests-error.nix,
# `instance-doors`).
{
  aspects,
  genIdentity,
  ...
}:
let
  entity = n: genIdentity.hashIdentity "entity" [ "name" ] (_: n);
  binding = n: genIdentity.hashIdentity "argument-binding" [ "name" ] (_: n);
  aspect = aspects.aspectId [ "probe" ] { name = "p"; };
  keys = c: builtins.concatStringsSep "," (builtins.attrNames c);
  p = aspects.wrapFn { } "p" ({ host, ... }: { description = "p-${host}"; });
  bare = aspects.wrapFn { } "b" (c: {
    description = "b:${keys c}";
  });
  bareK = aspects.wrapFn { entityKinds = [ "host" ]; } "b" (c: {
    description = "b:${keys c}";
  });
  empty = aspects.wrapFn { } "e" ({ }: { description = "e"; });
  # Two definitions under one key, one a context shape and one with formals: the aspect type's merge
  # builds a guard carrier (K2's site), never a wrap record.
  kinds = {
    entityKinds = [ "host" ];
  };
  twoDefs =
    (aspects.aspectType kinds).merge
      [ "m" ]
      [
        {
          file = "/a.nix";
          value = c: { description = "a:${keys c}"; };
        }
        {
          file = "/b.nix";
          value = { x }: { description = "b:${x}"; };
        }
      ];
  scope = host: extra: {
    context = { inherit host extra; };
    sources = {
      host = entity host;
      extra = binding extra;
    };
  };
  inst =
    cnf: value: s:
    aspects.instanceOf cnf {
      inherit aspect value;
      inherit (s) context sources;
    };
  twoDefsScope = {
    context = {
      host = "h1";
      x = "X";
      extra = "E";
    };
    sources = {
      host = entity "h1";
      x = binding "X";
      extra = binding "E";
    };
  };
in
{
  flake.tests.instances = {
    # I-1. Two contexts handing the aspect different values are two instances. RED (seeded: the
    # preimage without `formals`): the ids are equal.
    test-distinct-tuples = {
      expr = (inst { } p (scope "h1" "x")).id != (inst { } p (scope "h2" "x")).id;
      expected = true;
    };
    # I-2. Contexts that differ only in a key the aspect never receives are one instance, and its
    # formals are the received keys' sources. RED (seeded: keys = the whole context): the ids differ.
    test-equal-tuples-one-id = {
      expr = {
        same = (inst { } p (scope "h1" "x1")).id == (inst { } p (scope "h1" "x2")).id;
        formals = (inst { } p (scope "h1" "x1")).formals;
        entry = (inst { } p (scope "h1" "x1")).entry.description;
      };
      expected = {
        same = true;
        formals.host = entity "h1";
        entry = "p-h1";
      };
    };
    # I-3. `{ }:` receives nothing: no formals, one id across scopes.
    test-closed-empty-one-id = {
      expr = {
        formals = (inst { } empty (scope "h1" "x")).formals;
        same = (inst { } empty (scope "h1" "x")).id == (inst { } empty (scope "h2" "y")).id;
      };
      expected = {
        formals = { };
        same = true;
      };
    };
    # I-4. Two definitions: the carrier's formals are the union of its function fragments' door keys
    # (`c:` narrowed to the kinds, `{ x }:` its formal), and the entry is the carrier discharged.
    test-two-definitions-union = {
      expr = {
        isCarrier = twoDefs ? fragments;
        formals = builtins.attrNames (inst kinds twoDefs twoDefsScope).formals;
        entry =
          (inst kinds twoDefs twoDefsScope).entry
          == (aspects.mkGuardVocab kinds).applyGuard twoDefsScope.context twoDefs;
      };
      expected = {
        isCarrier = true;
        formals = [
          "host"
          "x"
        ];
        entry = true;
      };
    };
    # I-5. A formal named `aspect` nests under `formals` and does not clash with the relatum.
    test-formal-named-aspect = {
      expr =
        (inst { } (aspects.wrapFn { } "fa" ({ aspect }: { description = "fa-${aspect}"; })) {
          context.aspect = "A";
          sources.aspect = binding "A";
        }).formals;
      expected.aspect = binding "A";
    };
    # I-7's minting arm: an identity-shaped source of a supplier kind mints an instance identity.
    test-identity-source-mints = {
      expr = builtins.match "aspect-instance:[0-9a-f]{64}" (inst { } p (scope "h1" "x")).id != null;
      expected = true;
    };
    # K-a through the mint. A context shape under `entityKinds = [ "host" ]` receives `host` alone.
    test-kinds-narrow-formals = {
      expr = {
        formals = builtins.attrNames (inst kinds bareK (scope "h1" "x")).formals;
        entry = (inst kinds bareK (scope "h1" "x")).entry.description;
      };
      expected = {
        formals = [ "host" ];
        entry = "b:host";
      };
    };
    # K-b through the mint. With the kinds undeclared it receives, and is keyed on, the whole context.
    test-kinds-null-whole-context = {
      expr = {
        formals = builtins.attrNames (inst { } bare (scope "h1" "x")).formals;
        entry = (inst { } bare (scope "h1" "x")).entry.description;
      };
      expected = {
        formals = [
          "extra"
          "host"
        ];
        entry = "b:extra,host";
      };
    };
  };
}
