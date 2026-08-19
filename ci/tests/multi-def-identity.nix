# Test (regression for den #603): a nested aspect reached through a MULTI-DEF
# (colliding-key) namespace key keeps a stable structural identity, regardless of
# how many definitions collide. It is NOT assigned a fresh anonymous identity.
#
# den #603: aspectContentType's multi-def branch forwarded colliding-key children
# as raw attrsets with no `name`/`__provider`; children.nix then renamed each to
# `<parent>/<anon>:<idx>`, so the same aspect reached via two inclusion paths got
# two identities -> emit-class dedup failed and class content double-applied.
#
# gen-aspects has no raw-forwarding walk: colliding attrset defs of one key route
# through aspectSubmodule.merge, collapsing to ONE submodule whose children carry
# positional names from their attribute keys. flatten keys by structural path
# (def-count- and inclusion-path-independent), so there is no `<anon>:<idx>` minting.
#
# The cross-include dedup itself (collapsing the same child included via two roles
# to one class emission) is den-hoag PIPELINE work; the type-level guarantee here is
# the stable identity the pipeline must dedup on (see den-hoag ISSUES #13c).
{
  lib,
  mkSchemaEval,
  aspects,
  ...
}:
let
  inherit (aspects) flatten graphFacts;

  # Two "files" each contribute a child of apps.dev.security -> multi-def collision
  # at `dev` and `security` (mirrors den's gpg.nix + ssh.nix shape).
  eval = mkSchemaEval {
    fixtureKeySemantics = {
      nixos = {
        category = "class";
      };
    };
    modules = [
      { config.aspects.apps.dev.security.gpg.nixos.programs.gnupg.agent.enable = true; }
      { config.aspects.apps.dev.security.ssh.nixos.programs.ssh.startAgent = true; }
    ];
  };

  flat = flatten eval.config.aspects;
  keys = lib.sort (a: b: a < b) (builtins.attrNames flat);

  # The same multi-def tree under a NON-EMPTY ORIGIN, so the projection below is measured against a
  # real qualifier rather than an empty one.
  originFacts = graphFacts { providerPrefix = [ "acme" ]; } eval.config.aspects;
in
{
  # Multi-def collision collapses to ONE structural identity per attribute path —
  # no per-definition `<anon>:<idx>` duplicates.
  flake.tests.multi-def-identity.test-collision-collapses-to-one-path = {
    expr = keys;
    expected = [
      "apps"
      "apps/dev"
      "apps/dev/security"
      "apps/dev/security/gpg"
      "apps/dev/security/ssh"
    ];
  };

  # The colliding-key child keeps its positional name (from its attribute key).
  flake.tests.multi-def-identity.test-child-keeps-positional-name = {
    expr = eval.config.aspects.apps.dev.security.gpg.name;
    expected = "gpg";
  };

  # identity.key for the child is its stable positional key, not an anonymous one.
  # A-IDENT (2b): that positional key is path-bearing and container-RELATIVE — literally
  # equal to the flatten walk key for the same node ("apps/dev/security/gpg").
  flake.tests.multi-def-identity.test-identity-key-is-positional = {
    expr = aspects.key eval.config.aspects.apps.dev.security.gpg;
    expected = "apps/dev/security/gpg";
  };

  # No anonymous identities anywhere in the registry.
  flake.tests.multi-def-identity.test-no-anonymous-identities = {
    expr = {
      anonymous = builtins.filter (k: lib.hasInfix "<anon>" k || lib.hasInfix ":" k) keys;
      # WITNESS, in the same record: the registry the filter ran over is the multi-def tree. Held
      # apart, the empty-list expectation is satisfied by dropping the `apps` tree entirely, and the
      # assertion reports success over nothing at all.
      registrySize = builtins.length keys;
    };
    expected = {
      anonymous = [ ];
      registrySize = 5;
    };
  };

  # THE REGISTRY IS A PROJECTION OF THE PUBLISHED FACTS, identical modulo the origin qualifier —
  # asserted over the multi-def fixture, where the collapse this suite pins is what makes the node
  # set well-defined in the first place.
  flake.tests.multi-def-identity.test-registry-projects-from-published-facts = {
    expr = {
      strippedKeysMatch =
        lib.sort (a: b: a < b) (map (lib.removePrefix "acme/") originFacts.nodes) == keys;
      differBeforeStripping = lib.sort (a: b: a < b) originFacts.nodes != keys;
      valuesUntouched = builtins.all (k: originFacts.nodeData."acme/${k}" == flat.${k}) keys;
    };
    expected = {
      strippedKeysMatch = true;
      differBeforeStripping = true;
      valuesUntouched = true;
    };
  };
}
