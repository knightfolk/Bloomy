# App-native Autopilot enrollment

**Goal:** Let Kevin opt into experimental Darkbloom Autopilot, pause/resume it,
and leave it in Bloomy without using the interactive startup command.

**Architecture:** Reuse provider control's serialized mutation gate for enrollment
and policy changes. Read the supported CLI's bounded JSON status through the
existing extras polling. Enrollment uses explicit saved models and hosting flags;
it must preserve memory, startup, capacity, and schedule preferences. Native
settings explain consent and the graceful provider replacement before dispatch.

**Tech stack:** SwiftUI, existing telemetry/control stores, Darkbloom 0.9.17 CLI,
Swift Testing and isolated AppKit fixtures.

**Spec:** Kevin's explicit request on 2026-10-02; official v0.9.17
[enrollment](https://github.com/Layr-Labs/d-inference/blob/v0.9.17/provider-swift/Sources/darkbloom/Autopilot/AutopilotEnrollmentCommands.swift),
[policy commands](https://github.com/Layr-Labs/d-inference/blob/v0.9.17/provider-swift/Sources/darkbloom/Autopilot/AutopilotPolicyCommands.swift),
and [rollout semantics](https://github.com/Layr-Labs/d-inference/blob/v0.9.17/docs/operations/model-autopilot.md).

## Constraints and review focus

- Enrollment is consent, not activation. Only matching, fresh live evidence can
  say that automatic model changes are active.
- Preflight every enabled model against fresh cache/catalog evidence. Reject
  incomplete selection rather than letting the CLI silently save a subset.
- Use supported commands, never handwrite enrollment configuration. Read back
  after every dispatched result, including timeout, cancellation and failure.
- Dirty model edits or another mutation block changes. No real provider changes,
  inference, downloads, privacy changes, or production-app replacement for proof.
- Reuse existing observation cadence. Bound decoded status and exported labels;
  never log credentials, arbitrary CLI prose, session IDs, or private hashes.
- Cross-process configuration changes cannot be excluded by a CLI revision flag;
  compare semantic settings afterwards and report an unconfirmed outcome honestly.
- Defer Bloomy's optional profit swaps while native Autopilot owns residency;
  retain the saved opt-in and timing preferences. Pause retains ownership too.

## Ownership and interfaces

Backend worker owns telemetry DTO/client/start command, provider control service,
extras/control stores and their tests. Root owns settings UI, inert native fixture,
integration, builds, native inspection, docs and final verification. Contract
explorer is read-only. Preserve all concurrent and unrelated work.

Expected seam: `ProviderExtrasSnapshot.autopilotStatus`,
`ProviderExtrasStore.refreshAutopilot()/setAutopilotPolicy`, and
`ProviderControlStore.enrollAutopilot()` with unavailable reason and confirmed
enrollment feedback. Final concrete interfaces are agreed with the worker.

## Tasks

- [x] Verify installed CLI's opt-in, policy commands and exact status schema.
- [x] Implement bounded status parsing, freshness and supported policy actions.
- [x] Implement enrollment preflight, settings preservation and failure readback.
- [x] Add native experimental opt-in explanation and observing/active/paused states.
- [x] Add regression coverage for malformed/stale status, preserved settings,
  rejected selections and uncertain outcomes.
- [x] Build/test exact integrated source, inspect consent and controls in isolated
  native fixtures, and record source/binary provenance and remaining limitations.
- [x] Commit a coherent verified checkpoint. Keep broader polish and distribution
  gates separate from this feature's focused proof.
