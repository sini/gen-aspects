# Test (regression for den #580): deciding whether a freeform/unregistered key
# is a nested aspect must NOT force that key's content to WHNF.
#
# den #580: key-classification.nix's `hasRecognizedSubKeys` force-walked sub-key
# values (`builtins.isAttrs (val.${sk})`) to classify them. Classification ran
# while the flake output set was still assembling, so forcing a value that read
# `self.outputs.*` re-entered the flake `self` fixpoint -> infinite recursion.
#
# gen-aspects has no eager classification walk: nesting is decided by the module
# system's name-based option-vs-freeform split, which inspects attr NAMES only and
# never forces VALUES. A `throw` in a freeform leaf is the type-level analogue of
# the self-output fixpoint re-entry: if classification forced it, the test throws.
{ lib, mkSchemaEval, ... }:
let
  # Stands in for `attrValues self.outputs.overlays`: any forcing during
  # structural classification would re-enter the fixpoint (here: throw).
  bomb = throw "gen-aspects #580: freeform leaf forced during classification";

  eval = mkSchemaEval {
    classes = {
      nixos = { };
    };
    modules = [
      {
        config.aspects.web = {
          # registered class -> stays a lazy deferredModule
          nixos.networking.hostName = "no-recursion";
          # unregistered key -> freeform nested aspect; its `overlays` leaf is the
          # exact position den #580 force-walked. It must stay deferred here.
          nixpkgs.overlays = bomb;
        };
      }
    ];
  };

  nixosEval = lib.evalModules {
    modules = [
      { options.networking.hostName = lib.mkOption { type = lib.types.str; }; }
      eval.config.aspects.web.nixos
    ];
  };
in
{
  # `nixpkgs` is classified as a nested aspect (gets identity) WITHOUT forcing its
  # `overlays` leaf.
  flake.tests.lazy-classification.test-freeform-key-classified-without-forcing-leaf = {
    expr = {
      name = eval.config.aspects.web.nixpkgs.name;
      isNested = eval.config.aspects.web.nixpkgs ? includes;
    };
    expected = {
      name = "nixpkgs";
      isNested = true;
    };
  };

  # Sibling registered class content resolves while the freeform leaf stays unforced.
  flake.tests.lazy-classification.test-sibling-class-resolves-past-unforced-leaf = {
    expr = nixosEval.config.networking.hostName;
    expected = "no-recursion";
  };

  # The leaf really is a bomb: it fires only on demand (consumption time), never
  # during classification — proving the immunity tests above are meaningful.
  flake.tests.lazy-classification.test-leaf-is-genuinely-deferred = {
    expr = (builtins.tryEval eval.config.aspects.web.nixpkgs.overlays).success;
    expected = false;
  };

  # Boundary guard (mirrors den's test-registered-key-self-output): a bomb inside
  # REGISTERED class content also stays lazy under structural reads — the immunity
  # must not be "fixed" by over-forcing registered content either.
  flake.tests.lazy-classification.test-registered-class-content-stays-lazy =
    let
      eval2 = mkSchemaEval {
        classes = {
          nixos = { };
        };
        modules = [
          { config.aspects.web2.nixos.networking.hostName = throw "must stay lazy"; }
        ];
      };
    in
    {
      expr = eval2.config.aspects.web2.name;
      expected = "web2";
    };
}
