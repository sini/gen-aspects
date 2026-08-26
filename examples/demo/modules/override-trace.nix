# Warm-override memoization TRACE showcase (the successor compose, `gen.lib.compose`).
#
# `composed.override edits` re-composes the tree; when `edits` carries ONLY `modules` (a modules-only
# append) the compose fires gen-merge's WARM path — it SPLICES the previous eval's declared leaves the
# edit provably cannot touch and re-merges only the rest, byte-identically to a cold re-compose (the
# standing cold-parity oracle pins it). The admission is gen-memo's (`warmAdmits`); the override
# result carries a `trace` = the engine's memoization decision, narrowed by gen-memo's `warmTrace`
# (gen-merge README §"Warm re-eval").
#
# Here we override the composed tree by appending ONE host-level settings layer (a modules-only edit ⇒
# warm) and project the trace: the FLEET inventory (gen-modules/entities.nix, marked `pureModule`) is
# SPLICED unchanged (`fleet.hosts` / `fleet.environments` ∈ `reused`), while the settings registry the
# edit lands on re-merges. This is "what the engine reused vs recomputed when we overrode the fleet's
# settings", delivered as data.
#
# READER side (value-injection): consumes `genComposed` (the compose result, carrying its
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

  # RED CONTROL — the SAME edit carrying a second key (`specialArgs`): the admission predicate
  # (gen-memo's `warmAdmits`) refuses warm, so `mode` flips to "cold" and the fleet leaves are NOT
  # spliced (`reused` is absent on a cold trace). The two control outputs below pin that the four
  # invariants measure the warm path rather than a constant — a control that does not flip is a dead
  # instrument.
  coldTrace =
    (genComposed.override {
      modules = [ settingsEdit ];
      specialArgs = { };
    }).trace;
in
{
  config.flake = {
    # The memoization decision, projected verbatim (the compose splices the engine's `warmDecision`,
    # narrowed by gen-memo's `warmTrace`).
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

    # The RED control's two reads (see `coldTrace` above):
    overrideColdControlMode = coldTrace.mode; # "cold" — the second edit key refuses warm
    overrideColdControlFleetDropped = !(builtins.elem "fleet.hosts" (coldTrace.reused or [ ])); # true — nothing spliced on the cold path
  };
}
