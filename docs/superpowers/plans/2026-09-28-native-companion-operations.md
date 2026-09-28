# Native Companion and Operations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the useful companion, alerting, diagnostics, recommendation, and multi-host additions as original native Swift code while preserving the existing provider safety contract.

**Architecture:** Reuse Darkbloom Control's own portable protocol and native TLS work, then make one signed per-user helper the persistent host coordinator. Feed that helper allowlisted snapshots, alerts, operations, and settings through typed Swift contracts; keep provider credentials and arbitrary logs local. Build recommendations as an observe-only, auditable evidence pipeline and aggregate multiple independently paired hosts only on the iPhone.

**Tech Stack:** Swift 6, SwiftUI, Observation, Network.framework, CryptoKit, Security, ServiceManagement, UserNotifications, SQLite, Swift Testing, Xcode/iOS Simulator.

**Spec:** `docs/superpowers/specs/2026-09-25-ios-companion-design.md` and `docs/superpowers/specs/2026-09-27-cli-0910-companion-control-contract.md`

## Global Constraints

- Implement original native Swift code. Do not copy external project code, algorithms, schemas, UI text, or architecture.
- User-installed Tailscale supplies private remote reachability in this release; do not ship the experimental embedded transport.
- The helper and phone never receive provider credentials, private signing keys, arbitrary TOML, raw logs, prompts, responses, account identifiers, process environments, or caller-supplied executable paths.
- Provider and settings mutations remain typed, capability-scoped, revision-checked, serialized, signed, and reconciled through the existing Control services.
- Automatic model mutation remains disabled until the observe-only journal demonstrates the repository's evidence gate. This plan ships recommendations and the evidence pipeline, not an unproven optimizer.
- Preserve `.mimosa/`, `.zcodeignore`, unrelated worktrees, release artifacts, histories, and existing user data.
- Do not push, publish, deploy, enroll a real tailnet, or release the companion during this implementation.

## Review Focus

- A wrong host pin, replayed approval, expired invitation, revoked device, oversized frame, or stale settings revision must fail closed without dispatch.
- Helper or UI restart during an accepted drain must preserve or reconcile the durable operation without issuing it twice.
- Scheduled idle, initial cold start, stale telemetry, and manual refresh must not create duplicate or false alerts.
- Support packets and companion messages must remain free of secret canaries, paths, PIDs, account IDs, URLs, raw diagnostic prose, and model identifiers that were not explicitly allowlisted.
- Two paired hosts with the same display name, clock skew, stale snapshots, or independent connection failures must remain distinguishable and must not authorize cross-host commands.

---

### Task 1: Integrate the native companion foundation

**Files:**
- Create: `Sources/DarkbloomCompanionProtocol/*`
- Create: `Sources/DarkbloomCompanionTransport/*`
- Create: `Sources/DarkbloomCompanionHost/*`
- Create: `CompanionApp/*`
- Modify: `Package.swift`, `Package.resolved`
- Test: `Tests/DarkbloomCompanionProtocolTests/*`, `Tests/DarkbloomCompanionHostTests/*`

**Interfaces:**
- Produces: bounded `Envelope`, `CompanionSnapshot`, pairing, pinned TLS, paired-device registry, signed command preparation, host coordinator, and iOS client/store types.

- [ ] Integrate the repository's own protocol, transport, host, and iOS candidate commits without importing the experimental embedded transport or dated review documents.
- [ ] Reconcile `ProviderControlService` and `SourcePolicy` against the newer live-switch, fan-control, and freshness work on this branch.
- [ ] Add regression tests for authenticated idle sessions and current CLI command deadlines.
- [ ] Run protocol, host, telemetry, and iOS client tests; commit.

### Task 2: Add evidence-backed alerts and a bounded support packet

**Files:**
- Create: `Sources/DarkbloomTelemetry/OperationalAlerts.swift`
- Create: `Sources/DarkbloomTelemetry/AlertHistoryDatabase.swift`
- Create: `Sources/DarkbloomTelemetry/SupportPacketSnapshot.swift`
- Create: `Sources/DarkbloomMonitor/OperationalNotificationCenter.swift`
- Create: `Sources/DarkbloomMonitor/SupportPacketPreviewView.swift`
- Modify: `Sources/DarkbloomMonitor/MonitorStore.swift`, settings/dashboard navigation
- Test: new alert, database, privacy, cap, and export tests in `Tests/DarkbloomTelemetryTests`

**Interfaces:**
- Consumes: `TelemetrySnapshot`, fixed lifecycle/model failure enums, existing app support directory and export-preview patterns.
- Produces: `AlertRecord`, `AlertTransition`, `AlertHistoryRecording`, `SupportPacketSnapshot`, and a notification adapter that accepts only sanitized records.

- [ ] Add failing tests for sustained outage, deduplication, recovery, scheduled-idle suppression, restart persistence, retention, byte caps, and secret-canary exclusion.
- [ ] Implement a pure alert transition engine and capped SQLite history using fixed templates and bounded numeric facts.
- [ ] Add macOS notification delivery that preserves history when permission is denied and never requests permission merely to start monitoring.
- [ ] Add immutable preview/export for a deterministic allowlist-only support packet; commit.

### Task 3: Wire the signed persistent helper and live host adapters

**Files:**
- Create: `Sources/DarkbloomCompanionHelper/*`
- Create/modify: app helper registration, helper status, pairing approval, paired-device and revocation SwiftUI files
- Modify: packaging scripts/resources and `Package.swift`
- Test: helper ownership, approval, revocation, durable operation, crash reconciliation, and live snapshot adapter tests

**Interfaces:**
- Consumes: companion host interfaces, `TelemetryService`, `ProviderControlService`, settings store, alert history, verified application identity.
- Produces: one `SMAppService`-managed per-user helper, `LiveCompanionSnapshotProvider`, persistent audit/operation journals, and exact-bundle app lifecycle dispatch.

- [ ] Add failing tests for single ownership, helper restart, duplicate dispatch intent, uncertain reconciliation, local approval, revocation, unsaved-draft refusal, and exact app identity.
- [ ] Implement the helper executable and registration/status UI without enabling it automatically.
- [ ] Replace fixture telemetry and in-memory operation state with allowlisted live adapters and durable records.
- [ ] Route provider and app actions through existing services and close sessions immediately on revocation; commit.

### Task 4: Add an explainable recommendation journal

**Files:**
- Create: `Sources/DarkbloomTelemetry/RecommendationEvidence.swift`
- Create: `Sources/DarkbloomTelemetry/RecommendationJournal.swift`
- Modify: `Sources/DarkbloomTelemetry/DashboardPresentation.swift`
- Modify: `Sources/DarkbloomMonitor/Dashboard/OpportunityView.swift`, `MonitorStore.swift`
- Test: recommendation factor, stale/missing evidence, stay-decision, replay, and retention tests

**Interfaces:**
- Consumes: fresh network capacity, enabled/downloaded inventory, measured token rates, bounded earnings observations, current model, and readiness/memory evidence.
- Produces: `RecommendationDecision` with every factor, source timestamp, confidence class, blockers, selected action (`stay` or `consider(model)`), and a capped persistent journal.

- [ ] Add failing tests proving stale, duplicate, partial, cross-account, or incompatible evidence cannot create a stronger recommendation.
- [ ] Extend the existing ranker into an explainable decision without manufacturing an earnings forecast.
- [ ] Persist both `stay` and `consider` decisions idempotently and expose recent evidence in the Opportunity UI.
- [ ] Add journal summaries to the sanitized host snapshot and support packet; commit.

### Task 5: Add multi-host iPhone aggregation and alert history

**Files:**
- Modify: `CompanionApp/Sources/CompanionStore.swift`, `RootView.swift`, dashboard and settings views
- Create: `CompanionApp/Sources/HostRegistry.swift`, `FleetOverview.swift`, `AlertHistoryView.swift`
- Modify: companion protocol alert/history DTOs and host handlers
- Test: multi-host identity, stale/fresh merge, per-host command routing, duplicate names, and alert pagination tests

**Interfaces:**
- Consumes: independently paired host records and sanitized host alert/recommendation pages.
- Produces: persistent `[StoredHost]`, per-host sessions, combined read-only overview, host-specific commands, and bounded alert history.

- [ ] Add failing client tests for two hosts, duplicate display names, independent failures, clock skew, host removal, and command isolation.
- [ ] Replace the single-host store with an identity-keyed registry and one bounded session state per selected host.
- [ ] Add combined online/provider/model/jobs/earnings/temperature/alert presentation while preserving attribution and freshness.
- [ ] Add host-specific alert history and recommendation evidence views; commit.

### Task 6: Verify the complete native product and remove research references

**Files:**
- Modify: product README, architecture, companion operations runbook, implementation plan checkboxes
- Delete: `docs/research/2026-09-28-bloomkeeper-comparison.md`

**Interfaces:**
- Produces: reproducible build/test/render evidence and a project tree containing the implemented product design without the external comparison review.

- [ ] Run focused suites after each task, then the complete Swift test suite and macOS release build.
- [ ] Build and test the iOS app on Simulator; inspect Pairing, Hosts, Overview, Models, Operations, Alerts, and Settings at phone size.
- [ ] Run a local paired fixture smoke test for pairing, reconnect, read-only telemetry, stale state, command rejection/approval, revocation, and two-host aggregation.
- [ ] Search the project for the reviewed project's name and links, delete the comparison artifact, and rewrite any remaining implementation-facing text as standalone Darkbloom requirements.
- [ ] Run final privacy canaries, `git diff --check`, and a whole-branch review; commit.
