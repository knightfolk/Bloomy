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
  0.10.4; selecting or resetting a cache folder still uses the CLI serializer
  and retains the preservation concern even though its own settings are read back.
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
- Autopilot model pins: Bloomy displays saved pins and labels stale readings;
  pin and unpin controls are not yet exposed. The upstream desktop app checks selected models, available slots,
  and estimated memory before pinning; these safeguards need to be carried into
  any implementation. The desktop service supports a private discovery directory
  via `DARKBLOOM_DESKTOP_DIR`, a possible route to its own checks; operation
  coordination and lifecycle still need investigation. A disposable-config
  0.10.4 pin command removed an unfamiliar backend key and an unfamiliar table,
  so directly invoking it would not preserve arbitrary future configuration.
  The CLI says pins remain protected during an explicit pause; the presentation
  now reflects that distinction. No live pins were changed during the audit.
- Add-on holds can leave the provider connected while inference is paused.
  Bloomy now recognizes held, draining and unrecognized hold states without
  retaining add-on identifiers, blocks idle-driven work and live model apply,
  and explains the observed hold. Autopilot reports bounded busy reasons using
  fixed labels. An isolated native fixture showed the held state and busy
  explanations; installed-app review remains outstanding. The CLI's operator
  hold/release commands are not yet exposed in Bloomy; releasing all holds can
  affect other apps and needs a separate design and safe testing. No add-on
  hold/release command was issued during testing.
- Further model-load, Autopilot and coordinator diagnostics remain to audit.
- Provider-internal inference features and performance changes do not
  automatically imply Bloomy UI controls. Review model capabilities and chat
  transport against actual supported API contracts; do not infer entitlement
  from catalog presence.

This list is a starting point, not an exhaustive 0.9.11–0.10.4 release diff.
Record exact evidence and verification for each implementation as work proceeds.
