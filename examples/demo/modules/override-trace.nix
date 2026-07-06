# Warm-override memoization TRACE showcase (gen-flake v1).
#
# `composed.override edits` re-composes the tree; when `edits` carries ONLY `modules` (a modules-only
# append) gen-flake fires gen-merge's WARM path — it SPLICES the previous eval's declared leaves the
# edit provably cannot touch and re-merges only the rest, byte-identically to a cold re-compose (the
# standing cold-parity oracle pins it). The override result carries a `trace` = the engine's
# memoization decision (gen-flake README §"Warm override + trace"; gen-merge README §"Warm re-eval").
#
# Here we override the composed tree by appending ONE host-level settings layer (a modules-only edit ⇒
# warm) and project the trace: the FLEET inventory (gen-modules/entities.nix, marked `pureModule`) is
# SPLICED unchanged (`fleet.hosts` / `fleet.environments` ∈ `reused`), while the settings registry the
# edit lands on re-merges. This is "what the engine reused vs recomputed when we overrode the fleet's
# settings", delivered as data.
#
# READER side (gen-flake value-injection): consumes `genComposed` (the compose result, carrying its
# `.override` handle) threaded via _module.args in flake.nix.
{
  genComposed,
  ...
}:
let
  # The override edit: append a host-level settings override (bump prod-web-2's nginx workers). A plain
  # attrset module (no function head) ⇒ classified CLEAN, but EDITED (in the appended tail) ⇒ its
  # `scopeSettings` def re-merges. `edits` carries ONLY `modules`, so `override` fires the warm path.
  settingsEdit = {
    config.scopeSettings."host:prod-web-2" = {
      nginx.performance.workers = 48;
    };
  };

  trace = (genComposed.override { modules = [ settingsEdit ]; }).trace;
in
{
  config.flake = {
    # The memoization decision, projected verbatim (gen-flake threads the engine's `warmDecision`).
    # Real shape here: mode="warm"; reused=["fleet.environments" "fleet.hosts"] (the marked fleet,
    # SPLICED); remerged={aspects,namespaces,schema,scopeSettings} (the dirty function modules + the
    # edited settings leaf); modules.clean=["<gen-merge>"] (the marked-pure fleet entry — modules with
    # no source path are labelled "<gen-merge>", incl. the inline edit).
    overrideTrace = {
      inherit (trace)
        mode
        reason
        reused
        remerged
        modules
        ;
    };

    # Invariants (grounded in the real trace above):
    overrideModeWarm = trace.mode == "warm"; # true — a modules-only edit fires the warm path
    overrideFleetReused =
      builtins.elem "fleet.hosts" trace.reused && builtins.elem "fleet.environments" trace.reused; # true
    overrideSettingsRemerged = trace.remerged ? scopeSettings; # true — the edit lands on scopeSettings
    overrideMarkedPureClean = trace.modules.clean != [ ]; # true — the marked-pure fleet is the sole clean entry
  };
}
