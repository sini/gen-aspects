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
  # attrset module (no function head) ⇒ classified CLEAN, and EDITED (in the appended tail). `edits`
  # carries ONLY `modules`, so `override` fires the warm path. (This def does NOT drive scopeSettings'
  # re-merge — settings.nix, a dirty function module, DECLARES scopeSettings, so it re-merges regardless.)
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
    # SPLICED); remerged={aspects,namespaces,schema,scopeSettings} (the dirty function modules — e.g.
    # scopeSettings re-merges as `dirty-decl settings.nix`, NOT because the edit touched it);
    # modules.clean=["<gen-merge>"] is the marked-pure fleet entry. NB "<gen-merge>" is the label for ANY
    # module without a source path (the marked-pure inner fn AND the inline edit both), so it recurs
    # across clean/dirty/edited — it does not always denote the fleet.
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
    overrideSettingsRemerged = trace.remerged ? scopeSettings; # true — scopeSettings is dirty-decl (settings.nix), re-merges regardless of the edit
    overrideMarkedPureClean = trace.modules.clean != [ ]; # true — the marked-pure fleet is the sole clean entry
  };
}
