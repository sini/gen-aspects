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
  inherit (aspects) flatten;

  # Two "files" each contribute a child of apps.dev.security -> multi-def collision
  # at `dev` and `security` (mirrors den's gpg.nix + ssh.nix shape).
  eval = mkSchemaEval {
    classes = {
      nixos = { };
    };
    modules = [
      { config.aspects.apps.dev.security.gpg.nixos.programs.gnupg.agent.enable = true; }
      { config.aspects.apps.dev.security.ssh.nixos.programs.ssh.startAgent = true; }
    ];
  };

  flat = flatten eval.config.aspects;
  keys = lib.sort (a: b: a < b) (builtins.attrNames flat);
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
  flake.tests.multi-def-identity.test-identity-key-is-positional = {
    expr = aspects.key eval.config.aspects.apps.dev.security.gpg;
    expected = "gpg";
  };

  # No anonymous identities anywhere in the registry.
  flake.tests.multi-def-identity.test-no-anonymous-identities = {
    expr = builtins.filter (k: lib.hasInfix "<anon>" k || lib.hasInfix ":" k) keys;
    expected = [ ];
  };
}
