# Darkbloom CLI 0.10.4 compatibility audit — 2026-10-28

Status: in progress. This is not a release or a complete feature inventory.
Baseline: Bloomy main at b9c91e9, installed provider CLI 0.10.4. The provider
and installed Bloomy remain running; no configuration changes or inference were
used for this audit.

Evidence: [provider releases](https://github.com/Layr-Labs/d-inference/releases),
[0.10.4 CLI reference](https://github.com/Layr-Labs/d-inference/blob/v0.10.4/docs/provider/cli-reference.md),
and the installed CLI's read-only help and status output.

- Model refresh: the current saved startup selector is outside the enabled set.
  Bloomy's old document reader rejected it, hiding all model controls. The
  revised reader preserves it for explicit repair; saves retain validation.
  An opt-in read-only contract test now runs the current model-control service
  against this Mac's actual config, catalog and local inventory; it refreshed
  successfully with fresh catalog and local sources on CLI 0.10.4. Installed-app
  proof and release are pending.
- Autopilot: 0.10.1 and later can download models on the operator's behalf;
  current CLI reports download settings and usage. Enrollment does not itself
  download, but automatic downloads default on with consent. Bloomy now reports
  the observed enabled flag and discloses this behavior before enrollment.
  Bloomy reads download limits and usage and offers explicit configuration.
  `downloads enable` replaces both limits, so blank is presented explicitly
  as no limit; disabling preserves existing limits. Tests exercise the official
  command mapping, recheck, readback and uncertain outcomes. The isolated native
  fixture verified the form, invalid input, disabling, and updated limits.
  Actual-provider writes and installed-app/release proof remain outstanding.
- Pending work: the daemon's `request_work_pending` includes accepted or queued
  work before decoding; `load_transition_active` signals model loading. Bloomy's
  idle-driven actions must use both. Compatibility with older snapshots and
  malformed new fields must remain explicit. Broader presentation and all
  control paths still require audit. Readiness and request activity now surface
  pending work and model loading; an explicit coordinator disconnect blocks
  verified readiness, and malformed connection evidence is unconfirmed.
  Native review and live installed-app verification remain outstanding.
- Encrypted SSD cache: CLI 0.9.20 added `cache status` and `cache set`, including
  directory and daily write limits. Bloomy now reads and edits these settings
  through the CLI, preserving unset versus unlimited and requiring readback.
  Changes are labeled restart-required and leave old files in place. Tests and
  an isolated native fixture cover the main paths; actual-provider writes and
  installed-app review remain outstanding. Darkbloom reports the selected
  parent folder separately from the effective namespaced cache root; Bloomy now
  reads and displays both and confirms directory changes against the selected
  parent, including the CLI's `/var` and `/tmp` alias normalization. A real-CLI
  disposable-config test exercises the client path.
- Configuration preservation caveat: the 0.10.4 CLI's `autopilot pin`,
  `unpin`, `pause`, and `resume` share `changeAutopilotPolicy`, which saves via
  `ConfigManager.save`. A disposable pin probe showed that this serializer drops
  unknown configuration fields and tables. Bloomy's previous pause and resume
  implementation used this CLI path; its readback checks covered selected
  policies but did not prove preservation of arbitrary unknown fields.
  The current CLI source also uses `ConfigManager.save` for Autopilot download
  limits and encrypted cache edits. Download controls now use a preserving
  transaction qualified for 0.10.4, with real-CLI disposable-file and conflict
  tests. Cache daily-write limits now also use a preserving transaction for
  0.10.4. Folder selection and reset now use a preserving transaction as well:
  selection is checked by Darkbloom against a private disposable config, then
  the candidate is checked again before publication. Real-CLI disposable-file
  tests cover selection, write limits, reset with a missing folder, and unknown
  field preservation. Cache readings are now bound to a configuration revision;
  a mounted-volume UUID mismatch can be repaired or reset only if that revision
  still matches. A disposable real-CLI test covered both UUID mismatch and a
  missing folder, and a conflict test rejects an outdated revision.
  Pause, resume and disable now use a targeted policy writer qualified for CLI
  0.10.4; other versions are refused with a clear message until qualified. The
  complete client path passed disposable-config tests against the real CLI for
  all three actions while retaining unknown fields, plus an external-edit
  conflict test. Live-provider behavior and installed-app review remain open.
  This requires a preserving mutation path or a reliable preflight before those
  controls can be considered fully compatible with future configurations.
- Weekly availability schedules: introduced in 0.9.15. Bloomy reports scheduled
  waiting but has no schedule editor. The supported CLI editor is interactive;
  the 0.10.4 desktop API supports editing with a configuration revision, but
  saves name, automatic updates, and idle timeout alongside the schedule. Its
  authenticated service supports an isolated discovery directory. A 0.10.4
  disposable-config probe confirmed that the API saves an overnight schedule
  and rejects an outdated configuration revision, but also drops an unknown
  backend key and an unknown table when saving. Do not use that save path on
  the operator's config without a preservation solution. Bloomy's existing
  targeted, validated configuration writer is a possible alternative, subject
  to schedule parsing and concurrency tests. Its validated atomic publication
  path has been extracted for reuse; the existing 26 configuration-store tests
  passed after this refactor. Saved changes require a provider
  restart. Bloomy now has a tested schedule value model for local wall time,
  overnight and full-day windows, and the desktop's 14-window limit. A bounded
  configuration reader handles the CLI's schedule tables and reports malformed
  or unsupported forms as unreadable instead of guessing that scheduling is off.
  Provider settings now display the saved windows, local time zone and stale
  status from a locked read. A schedule writer now stages only recognized
  schedule statements through the guarded configuration transaction, preserving
  unrelated fields and refusing windows with unknown fields or inline comments.
  Provider settings now include an editor with retained drafts, stale-file
  rejection and readback. An isolated native fixture exercised a save and an
  invalid time. An opt-in real CLI contract test saved an overnight schedule to
  a disposable config, verified Darkbloom's output, and confirmed unrelated
  unknown fields survived. Live-config writes and installed-app review remain
  outstanding. No live schedule changes were made during the audit.
- Autopilot model pins: Bloomy now offers pin and unpin controls for enrolled
  models. For 0.10.4 it checks downloaded models, configured slots and the
  desktop's memory budget, including its environment overrides. The CLI's
  filtered inventory still includes every model that can pass this budget: its
  ceiling is physical memory minus 4 GiB, while the desktop budget is at most
  physical memory minus 8.5 GiB. A preserving, revision-checked config edit
  avoids the CLI serializer dropping unfamiliar settings. Tests cover limits,
  conflicts, comments, preservation and disposable CLI readback; the positive
  pin test uses a synthetic inventory. A fresh isolated dashboard fixture showed
  the pin list and successfully changed a synthetic model from Pin to Unpin and
  back. The CLI says pins remain protected during an explicit pause. No live
  pins were changed during the audit; installed-app review remains outstanding.
- Add-on holds can leave the provider connected while inference is paused.
  Bloomy now recognizes held, draining and unrecognized hold states without
  retaining add-on identifiers, blocks idle-driven work and live model apply,
  and explains the observed hold. Autopilot reports bounded busy reasons using
  fixed labels. An isolated native fixture showed the held state and busy
  explanations; installed-app review remains outstanding. Operator controls now
  expose a 30–600 second shared hold and explicitly labeled global release;
  force release has a separate confirmation warning about other apps' VMs.
  Lease expiry can be delayed by the machine lock. Status is parsed into bounded
  aggregate values, and a command is confirmed only with matching response and
  independent readback; timeout or cancellation remains uncertain. Mock-only
  tests cover release races and malformed output. Isolated native fixtures
  exercised a hold and release and displayed the force warning with a simulated
  machine lock. No live add-on hold/release
  command was issued during testing. Bloomy cannot own a scoped hold: 0.10.4
  only permits Darkbloom's signed sandbox to use the scoped add-on socket.
- Further model-load, Autopilot and coordinator diagnostics remain to audit.
- Model load memory: Bloomy now derives a current no-eviction shortfall and,
  when available, the remaining shortfall after idle eviction from the daemon's
  capacity and local scanner estimate. It requires fresh capacity, local
  inventory, matching configuration and process identity; activity prevents a
  definitive shortfall verdict. This is an estimate, not a record proving a
  preload was skipped or a promise that a later load will succeed. Missing
  GPU-cache figures are shown as unreported instead of rejecting the snapshot.
  Automated tests cover the distinctions and freshness. An isolated native
  fixture displayed the current shortfall in a model card and its detail sheet.
  Installed-app review remains outstanding.
- Chat now accepts incrementally streamed text for local and network requests,
  preserving partial output on cancellation or failure. Parser and store tests
  cover framing, cancellation and errors. Media and tool-call conversations are
  not yet supported. The local provider accepts inline media only, with
  architecture-specific support and size limits; audio has a separate native
  model path, and catalog labels alone do not establish route support. Tool
  calls need structured proposals and explicit execution authorization rather
  than automatically running model output. No live
  inference was run for this work; an isolated native fixture displayed partial
  text followed by a completed response. Installed-app review remains outstanding.
- Provider-internal inference features and performance changes do not
  automatically imply Bloomy UI controls. Review model capabilities and chat
  transport against actual supported API contracts; do not infer entitlement
  from catalog presence.

This list is a starting point, not an exhaustive 0.9.11–0.10.4 release diff.
Record exact evidence and verification for each implementation as work proceeds.
