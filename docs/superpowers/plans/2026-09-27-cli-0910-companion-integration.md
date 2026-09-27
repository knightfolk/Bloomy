# CLI 0.9.10 and Companion Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make CLI lifecycle/model control reliable, bring Darkbloom Control to the v0.9.10 state contract, and complete the first usable zero-trust iOS companion vertical slice.

**Architecture:** Fix provider invariants in the exact v0.9.10 source branch first. Then make the macOS app a version-aware coordinator that consumes sparse state and invokes bounded official CLI commands. Finally integrate the existing companion protocol foundation and build the paired Mac/helper and iOS clients on top of that coordinator.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI, Network.framework, CryptoKit/Security, launchd/SMAppService, Swift Package Manager, Xcode iOS Simulator.

**Spec:** `docs/superpowers/specs/2026-09-27-cli-0910-companion-control-contract.md`

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

- [ ] Add a failing test with different default and configured caches.
- [ ] Make every switch selection path consume the configured cache context.
- [ ] Run focused CLI tests and commit.

### Task 2: Provider lifecycle completion and stale-owner recovery

**Files:** `ServiceDrain.swift`, `StartCommand+ScheduledDrain.swift`, relevant CLI/process lifecycle tests.

**Interfaces:** Produces restart completion states that distinguish serving from scheduled idle and exact-identity ownership from PID reuse.

- [ ] Add failing scheduled-idle restart and stale-PID reuse tests.
- [ ] Accept a fresh scheduled-idle identity without weakening serving authorization.
- [ ] Defer ownership to exact process identity and the lifetime lock.
- [ ] Run focused tests and commit.

### Task 3: Stop standalone startup during preload

**Files:** `StartCommand+Modes.swift`, standalone lifecycle/preload helpers and tests.

**Interfaces:** Produces startup lifecycle control that exists before preload and prevents bind after stop.

- [ ] Add a blocked-preload stop regression test.
- [ ] Publish lifecycle identity/control before preload and cancel cleanly on stop.
- [ ] Run focused tests and commit.

### Task 4: Provider cleanup and hardening

**Files:** `StopCommand.swift`, cache-directory APIs/callers, configuration key detection, owner-only file/mailbox and command-runner tests.

**Interfaces:** Removes duplicate stop work and unreachable optional cache paths; preserves existing public CLI behavior.

- [ ] Add/adjust tests for parsed TOML presence, FIFO rejection, and bounded diagnostic output.
- [ ] Remove duplicate stop and optional cache branches.
- [ ] Replace fragile section-text matching where selection authority depends on it.
- [ ] Add nonblocking special-file rejection and bounded subprocess capture.
- [ ] Run provider tests/build and commit.

### Task 5: Control lifecycle deadline compatibility

**Files:** `SourcePolicy.swift`, `ProviderControlService.swift`, `ProcessRunner.swift` only if required, lifecycle tests.

**Interfaces:** Produces explicit CLI drain arguments and a caller deadline covering drain, shutdown, and startup confirmation.

- [ ] Add a failing test proving Start/Restart outlive the CLI drain deadline.
- [ ] Pass explicit drain/startup timeouts and derive a bounded command deadline.
- [ ] Verify timeout/cancellation reconciliation and commit.

### Task 6: Control v0.9.10 sparse state and lifecycle presentation

**Files:** `StateParsers.swift`, `TelemetryModels.swift`, daemon fixtures, lifecycle and selection views/tests.

**Interfaces:** Produces optional trust/capacity state plus typed preload, switch, drain, and scheduled-idle presentation.

- [ ] Add v0.9.10 fixtures for scheduled idle, preload, switch phases, busy, forced, and timeout.
- [ ] Decode optional fields without dropping verified identity/lifecycle data.
- [ ] Render truthful Preloading, On demand, Switching, Draining, and scheduled-idle states.
- [ ] Replace stale interruption copy and commit.

### Task 7: Feature-gated live model switch and cache diagnostics

**Files:** command builders, provider control service/store, model manager UI/tests, cache-location client/view.

**Interfaces:** Produces separate Save and Apply Live actions; Apply Live is available only from fresh matching capability state.

- [ ] Add failing command, capability, receipt, conflict, and older-provider fallback tests.
- [ ] Implement bounded `darkbloom switch` dispatch and reconciliation.
- [ ] Add read-only effective-cache location diagnostics.
- [ ] Inspect rendered macOS UI, run the full suite/release build, and commit.

### Task 8: Integrate the preserved companion foundation

**Files:** companion design/evidence commits from `codex/ios-companion-foundation`, `Package.swift`, `Sources/DarkbloomCompanionProtocol`, protocol tests.

**Interfaces:** Produces versioned, size-bounded DTOs and framing shared by Mac and iOS targets.

- [ ] Preserve and integrate the existing native TLS/Tailscale evidence and uncommitted protocol work.
- [ ] Rebase DTOs on the corrected lifecycle/state model and add privacy/limit fixtures.
- [ ] Run protocol tests and commit.

### Task 9: Mac companion host and background lifecycle helper

**Files:** new companion host/helper targets, pairing store, command coordinator, audit log, tests.

**Interfaces:** Produces QR bootstrap, mutually authenticated sessions, snapshot streaming, revision-checked settings, provider controls, and Control quit/reopen commands.

- [ ] Add failing identity, pairing, replay, authorization, revision, size, redaction, and lifecycle recovery tests.
- [ ] Implement one host coordinator over Network.framework with Keychain-backed identity and paired-device allowlist.
- [ ] Route every provider action through the tested Control lifecycle service and app actions through the helper.
- [ ] Run host integration tests and commit.

### Task 10: iOS companion application

**Files:** new iOS app target/project, pairing scanner, connection/session store, status/models/performance/earnings/settings/control views, tests.

**Interfaces:** Consumes the shared protocol and Mac host; produces the user-facing companion.

- [ ] Add failing view-model and transport tests for pairing, reconnect, stale data, command confirmation, revision conflict, and revocation.
- [ ] Implement QR pairing and authenticated LAN/Tailscale connection.
- [ ] Implement telemetry, safe settings, provider lifecycle/switch, and Mac app controls.
- [ ] Build/test on iOS Simulator and inspect all primary rendered states.
- [ ] Commit.

### Task 11: End-to-end verification and documentation

**Files:** README, compatibility contract, companion runbook, evidence manifests.

**Interfaces:** Produces reproducible proof for CLI, Control, Mac helper, and iOS simulator.

- [ ] Run focused and full provider tests/build without the prior Metal artifact failure.
- [ ] Run the full Control suite and release build.
- [ ] Pair a simulator with the local Mac host and verify monitor, settings conflict, start/stop/restart/switch, app quit/reopen, reconnect, and revocation.
- [ ] Update compatibility documentation and keep unreleased companion UI marked Coming Soon until all gates pass.
- [ ] Run a final cross-repository review, fix important findings test-first, and commit.
