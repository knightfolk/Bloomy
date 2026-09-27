# CLI 0.9.10 and Companion Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make CLI lifecycle/model control reliable, bring Darkbloom Control to the v0.9.10 state contract, and complete the first usable zero-trust iOS companion vertical slice.

**Architecture:** Fix provider invariants in the exact v0.9.10 source branch first. Then make the macOS app a version-aware coordinator that consumes sparse state and invokes bounded official CLI commands. Finally integrate the existing companion protocol foundation and build the paired Mac/helper and iOS clients on top of that coordinator.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI, Network.framework, CryptoKit/Security, launchd/SMAppService, Swift Package Manager, Xcode iOS Simulator.

**Spec:** `docs/superpowers/specs/2026-09-27-cli-0910-companion-control-contract.md`

**Candidate status (2026-09-27):** Tasks 1–8 are implemented in local commits.
The synthetic Mac host and iPhone vertical slice are implemented and verified,
including a post-review idle-session repair. The signed persistent helper, live
Control adapters, physical-device/Tailscale proof, and release packaging remain
Coming Soon gates and are intentionally not represented as shipped behavior.

## Global Constraints

- Preserve unrelated and dirty worktrees; use `codex/0910-lifecycle-fixes` for the CLI and `codex/cli-0910-integration` for Control.
- Never expose provider credentials or device private keys in state, logs, QR payloads, or companion DTOs.
- Never silently fall back from local to paid inference or from live switch to restart.
- User-managed Tailscale is the v1 remote transport; embedded Tailscale remains future work.
- Use failing tests before each behavior change and commit coherent verified milestones locally.
- Do not push, publish, deploy, install a provider build, or mutate the live provider during implementation verification.

## Review Focus

- A drain lasting 31-600 seconds must not be killed by Control or strand recovery.
- A scheduled-idle replacement with no trust/capacity must remain controllable and visible.
- A custom cache must be used by explicit, all-model, and interactive live-switch paths.
- Stop during standalone preload must prevent later listener publication.
- Replayed, oversized, stale-revision, or wrong-device companion commands must fail closed.

---

### Task 1: Provider live-switch cache correctness

**Files:** `provider-swift/Sources/darkbloom/SwitchCommand.swift`, model selection helpers, `provider-swift/Tests/DarkbloomCLITests/SwitchCommandTests.swift`

**Interfaces:** Produces one explicit effective-cache selection context used by explicit, all, picker, and download paths.

- [x] Add a failing test with different default and configured caches.
- [x] Make every switch selection path consume the configured cache context.
- [x] Run focused CLI tests and commit (`247b8682`).

### Task 2: Provider lifecycle completion and stale-owner recovery

**Files:** `ServiceDrain.swift`, `StartCommand+ScheduledDrain.swift`, relevant CLI/process lifecycle tests.

**Interfaces:** Produces restart completion states that distinguish serving from scheduled idle and exact-identity ownership from PID reuse.

- [x] Add failing scheduled-idle restart and stale-PID reuse tests.
- [x] Accept a fresh scheduled-idle identity without weakening serving authorization.
- [x] Defer ownership to exact process identity and the lifetime lock.
- [x] Run focused tests and commit (`b8e3624b`).

### Task 3: Stop standalone startup during preload

**Files:** `StartCommand+Modes.swift`, standalone lifecycle/preload helpers and tests.

**Interfaces:** Produces startup lifecycle control that exists before preload and prevents bind after stop.

- [x] Add a blocked-preload stop regression test that proves no listener bind.
- [x] Publish lifecycle identity/control before preload and cancel cleanly on stop.
- [x] Run focused tests and commit (`18b34d49`).

### Task 4: Provider cleanup and hardening

**Files:** `StopCommand.swift`, cache-directory APIs/callers, configuration key detection, owner-only file/mailbox and command-runner tests.

**Interfaces:** Removes duplicate stop work and unreachable optional cache paths; preserves existing public CLI behavior.

- [x] Add/adjust tests for parsed TOML presence, FIFO rejection, and bounded diagnostic output.
- [x] Remove duplicate stop and optional cache branches.
- [x] Replace fragile section-text matching where selection authority depends on it.
- [x] Add nonblocking special-file rejection and bounded subprocess capture.
- [x] Run focused provider tests/build and commit (`f3094cde`, `1b4e58a7`).

### Task 5: Control lifecycle deadline compatibility

**Files:** `SourcePolicy.swift`, `ProviderControlService.swift`, `ProcessRunner.swift` only if required, lifecycle tests.

**Interfaces:** Produces explicit CLI drain arguments and a caller deadline covering drain, shutdown, and startup confirmation.

- [x] Add a failing test proving Start/Restart outlive the CLI drain deadline.
- [x] Pass explicit drain/startup timeouts and derive a bounded command deadline.
- [x] Verify timeout/cancellation reconciliation and commit (`7d72e04`, `63f3834`).

### Task 6: Control v0.9.10 sparse state and lifecycle presentation

**Files:** `StateParsers.swift`, `TelemetryModels.swift`, daemon fixtures, lifecycle and selection views/tests.

**Interfaces:** Produces optional trust/capacity state plus typed preload, switch, drain, and scheduled-idle presentation.

- [x] Add v0.9.10 fixtures for scheduled idle, preload, switch phases, busy, forced, and timeout.
- [x] Decode optional fields without dropping verified identity/lifecycle data.
- [x] Render truthful Preloading, On demand, Switching, Draining, and scheduled-idle states.
- [x] Replace stale interruption copy and commit (`970b6ad`).

### Task 7: Feature-gated live model switch and cache diagnostics

**Files:** command builders, provider control service/store, model manager UI/tests, cache-location client/view.

**Interfaces:** Produces separate Save and Apply Live actions; Apply Live is available only from fresh matching capability state.

- [x] Add failing command, capability, receipt, conflict, and older-provider fallback tests.
- [x] Implement bounded `darkbloom switch` dispatch and reconciliation.
- [x] Add read-only effective-cache location diagnostics.
- [x] Inspect rendered macOS UI, run the full suite/release build, and commit (`3eb6f0f`).

### Task 8: Integrate the preserved companion foundation

**Files:** companion design/evidence commits from `codex/ios-companion-foundation`, `Package.swift`, `Sources/DarkbloomCompanionProtocol`, protocol tests.

**Interfaces:** Produces versioned, size-bounded DTOs and framing shared by Mac and iOS targets.

- [x] Preserve and integrate the existing native TLS/Tailscale evidence and uncommitted protocol work.
- [x] Rebase DTOs on the corrected lifecycle/state model and add privacy/limit fixtures.
- [x] Run protocol tests and commit (`63f3834`).

### Task 9: Mac companion host and background lifecycle helper

**Files:** new companion host/helper targets, pairing store, command coordinator, audit log, tests.

**Interfaces:** Produces QR bootstrap, mutually authenticated sessions, snapshot streaming, revision-checked settings, provider controls, and Control quit/reopen commands.

- [x] Add identity, pairing, replay, authorization, revision, size, redaction, and lifecycle adapter tests.
- [x] Implement one host coordinator over Network.framework with Keychain-backed identity and paired-device allowlist.
- [ ] Package the signed persistent helper and connect the host adapters to live Control telemetry, provider control, and app lifecycle.
- [ ] Run host integration tests and commit.

### Task 10: iOS companion application

**Files:** new iOS app target/project, pairing scanner, connection/session store, status/models/performance/earnings/settings/control views, tests.

**Interfaces:** Consumes the shared protocol and Mac host; produces the user-facing companion.

- [ ] Add failing view-model and transport tests for pairing, reconnect, stale data, command confirmation, revision conflict, and revocation.
- [x] Implement QR pairing and authenticated LAN/user-managed-Tailscale routes.
- [x] Implement telemetry, safe settings, provider lifecycle/switch, and Mac app control surfaces against the authenticated host contract.
- [x] Build/test on iOS Simulator and inspect Status, Models, Control, and Settings with the synthetic paired host.
- [x] Commit the vertical slice (`63f3834`); keep production-only gates Coming Soon.

### Task 11: End-to-end verification and documentation

**Files:** README, compatibility contract, companion runbook, evidence manifests.

**Interfaces:** Produces reproducible proof for CLI, Control, Mac helper, and iOS simulator.

- [ ] Run focused and full provider tests/build without the prior Metal artifact failure.
- [x] Run the full Control suite and release build.
- [ ] Pair a simulator with the local Mac host and verify monitor, settings conflict, start/stop/restart/switch, app quit/reopen, reconnect, and revocation.
- [x] Update compatibility documentation and keep unreleased companion UI marked Coming Soon until all gates pass.
- [x] Run a final cross-repository review with GLM-5.3 Max plus local verification, fix important findings, and commit (`2add75e`, CLI `9d47cc40`).
