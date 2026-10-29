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
  Live installed-app proof and release are pending.
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
  control paths still require audit.
- Encrypted SSD cache: CLI 0.9.20 added `cache status` and `cache set`, including
  directory and daily write limits. Bloomy lacks these controls. Readback,
  validation, storage semantics, restart behavior, and native review remain.
- New coordinator connectivity, add-on hold, model load and Autopilot busy
  diagnostics are present in 0.10.4 state. Compare upstream contracts with
  existing readiness and status presentation before exposing them.
- Provider-internal inference features and performance changes do not
  automatically imply Bloomy UI controls. Review model capabilities and chat
  transport against actual supported API contracts; do not infer entitlement
  from catalog presence.

This list is a starting point, not an exhaustive 0.9.11–0.10.4 release diff.
Record exact evidence and verification for each implementation as work proceeds.
