# Bloomkeeper comparison and product plan

Research date: 2026-09-28

Bloomkeeper revision reviewed: [`295e32d4605aed4de92401e4419e8cb933dcf1a1`](https://github.com/cookder/bloomkeeper/tree/295e32d4605aed4de92401e4419e8cb933dcf1a1)

Darkbloom Control baseline: `f0bba61` on `codex/models-window-grid`

## Decision

Bloomkeeper is the stronger reference for automatic provider operation, remote browser access, fleet aggregation, and notifications. Darkbloom Control should adopt the useful product patterns without copying Bloomkeeper's Python collector and local web-server architecture.

The next product sequence should be:

1. Ship the native iOS companion over user-installed Tailscale with QR-based device trust, read-only status, notifications, and narrowly scoped Start/Stop controls.
2. Add an observe-only model recommendation engine with evidence, confidence, and a decision journal.
3. Add multi-Mac read-only aggregation.
4. Add opt-in automatic switching only after the recommendation engine has accumulated and replayed enough direct paid-work evidence.

This preserves Darkbloom Control's simpler native trust boundary and explicit controls while closing the gaps users will notice first.

## Product comparison

| Capability | Bloomkeeper | Darkbloom Control | Assessment |
|---|---|---|---|
| Live provider, hardware, network, and earnings status | Yes | Yes | Comparable core scope; each presents different detail. |
| Confirmed earnings separated from forecasts and rewards | Yes | Yes | Both take data provenance seriously. |
| Manual Start, Stop, and model change | Yes, on Mac and phone | Yes on Mac; companion controls are planned | Bloomkeeper leads remotely. Its model changes run `darkbloom start --model …` and verify a new session; Darkbloom Control also has explicit graceful-drain UX and same-session Apply Live. |
| Model download, delete, enable, preload, concurrency, and residency | Limited to optimizer/manual selection scope | Yes | Darkbloom Control is the fuller provider administration tool. |
| Automatic model optimizer | Yes, observe-only by default, with guarded switching and trials | No | Largest Bloomkeeper advantage. Some newer prediction work remains in shadow evaluation rather than driving switches. |
| Prewarming | Authenticated one-token request through the provider's loopback endpoint | Catalog preload and same-session switching; no manual warm command | Bloomkeeper has a verified readiness flow. |
| Stall detection and recovery | Probe, same-model restart, escape, hold, and alert ladder | Diagnostics and lifecycle control, without an autonomous recovery ladder | Bloomkeeper leads. This is useful after alerts and evidence logging are established. |
| Phone access | Responsive web UI behind Tailscale Serve | Native companion protocol and plans, not shipped | Bloomkeeper is available now. Darkbloom Control's planned native device trust can be materially stronger. |
| Remote trust | Tailnet owner identity, HTTPS, random proxy path, strict request checks | Planned QR pairing, device key, capability grants, replay protection, and audit | Bloomkeeper authenticates a tailnet account. Darkbloom Control can authorize each paired device and command. |
| Push notifications | Encrypted Web Push through browser push services | Not shipped | High-value gap for offline, stalled, thermal, and earning-state alerts. |
| Multiple Macs | Read-only view of up to ten Macs through Tailscale | Not shipped | High-value gap after one-host companion status works. |
| Built-in local or paid-network chat | No advertised chat product | Yes, with explicit route provenance and fail-closed paid-route checks | Strong Darkbloom Control differentiator. |
| Fan controls | Explicitly out of scope | Official helper with bounded policy and admin authorization | Darkbloom Control differentiator. |
| Native app architecture | Swift shell hosting a React UI and bundled Python collector | SwiftUI/AppKit plus a Swift telemetry actor | Darkbloom Control currently has fewer runtimes and a narrower local interface surface. The companion helper will add one bounded listener. |
| Support workflow | Guided problem reports, optional automatic reports, help content | Diagnostics and log export | Bloomkeeper's user-facing support loop is more complete. |
| Updates | Signed/notarized app and Sparkle | Signed/notarized app and Sparkle, plus separate CLI update visibility and policy | Darkbloom Control has broader update controls. |

## What Bloomkeeper has that we should add

### 1. Alerts before automation

Add local and companion notifications for provider offline, stalled work after a healthy run, sustained thermal pressure, a completed drain, a failed switch, and a materially better model opportunity. Every notification should name the evidence time and open the relevant control or diagnostic screen.

This gives immediate value without granting the app autonomous mutation authority.

### 2. Explainable model recommendations

Start in observe-only mode. Rank eligible models using this Mac's own paid warm intervals, current demand, model readiness, memory fit, switching cost, and recent run history. Show:

- estimated earnings range rather than a single precise number;
- measured warm hours and last measurement;
- current demand and provider count;
- why the current model is being protected;
- why another model is recommended or blocked;
- the exact checks that would gate a switch.

Record every evaluated decision, including "stay," so the behavior can be replayed and audited before automatic switching exists.

### 3. Guarded automatic switching

Only enable this after shadow recommendations outperform a simple current-model baseline on replay and live scoring. Use minimum run time, minimum expected improvement, daily switch and downtime budgets, idle/drain state, fresh identity, memory, temperature, power, and endpoint readiness as hard gates. A manual selection should pin or pause automation. Failed verification should restore the protected model through a bounded recovery path rather than trying successive models indefinitely.

Bloomkeeper's current manager is a strong reference implementation: it protects a user-selected or evidence-backed home model, announces some automatic home changes, permits evidence-armed excursions, tracks switch costs and outcomes, and restores the home model after bounded failures. Its newer demand curve estimator still remains in shadow because it was weaker on newly switched models, the case that matters most for a switching decision.

### 4. Multi-Mac read-only view

After one paired host is stable, let the iOS app pair with several hosts and aggregate online state, active model, jobs, earnings, temperature, and alerts. Keep commands host-specific. A combined command such as "stop all" can come later with explicit confirmation and per-host results.

### 5. A user-facing support packet

Build a previewable, redacted diagnostic report with source freshness, versions, provider lifecycle state, recent command outcomes, and bounded logs. Keep credentials, account identifiers, prompts, and full process environments out of it. Add an explicit export action before any upload integration.

## What Darkbloom Control already has that is distinctive

### Native, typed control plane

The app uses SwiftUI/AppKit and a separate Swift telemetry module with bounded file, process, log, and network reads. It does not need a Python service, React dashboard, or localhost dashboard listener. Keep this architecture for the Mac helper and companion bridge.

### Deeper provider administration

Darkbloom Control manages downloads, deletion, enabled and preloaded models, concurrency, resident slots, idle-memory behavior, beta settings, native lifecycle commands, CLI update policy, and official fan controls. Bloomkeeper intentionally stays narrower and does not manage fans or power settings.

### Safer explicit switching UX

Darkbloom Control distinguishes saved configuration, currently advertised models, and actual loaded models. Apply Live uses the CLI's same-session switch only when fresh runtime evidence supports it. Bloomkeeper's manual and automatic model changes currently call `darkbloom start --model …`, wait for a new provider session, verify readiness, and prewarm it. Stop presents the exact accepted-request drain state. The companion and any future optimizer should keep the same-session path when the CLI supports it, while adopting Bloomkeeper's readiness verification and bounded recovery patterns.

### Local and paid-network chat

Built-in Chat has explicit per-conversation routing, local endpoint discovery, Keychain-backed consumer credentials, fresh model and price checks, balance checks, and an acknowledgement before paid network traffic. Bloomkeeper does not advertise a comparable capability.

### Per-device companion trust

The planned QR handshake can bind a phone public key to one host, issue scoped capabilities, rotate or revoke the pairing, reject replayed commands, and keep an audit trail. Tailscale should supply private reachability and encrypted transport in the first release; it should not replace application-level device authorization.

## Architecture lessons from Bloomkeeper

Bloomkeeper's remote implementation is careful for a browser-based design:

- Tailscale must be installed separately on the Mac and phone.
- Tailscale Serve exposes HTTPS on the tailnet and proxies to a loopback-only phone listener.
- It rejects Funnel/public exposure and will not take over an occupied Serve port.
- It checks the Tailscale login identity against the Mac node owner.
- A random secret path prevents another local process from spoofing Tailscale identity headers directly to the loopback listener.
- Local and phone listeners are separated, and phone access cannot change endpoint configuration.

Bloomkeeper's QR code is a convenient way to open its private phone URL; it is not cryptographic device enrollment. A reachable device presenting the Mac owner's Tailscale identity is accepted, with no app-specific device key, capability grant, or paired-device revocation. This validates Tailscale as the first-release transport while preserving the reason for Darkbloom Control's QR pairing and per-device capabilities above the tailnet.

Bloomkeeper also demonstrates the operational cost of its architecture: a native shell, WebKit, React/Vite bundle, Python runtime, two HTTP listeners, SQLite, browser session controls, Web Push dependencies, Tailscale Serve management, and optional privileged cache recovery. Darkbloom Control should avoid adding a local web dashboard or a `purge` authorization rule to match features that can be implemented within its existing native modules.

## Companion implementation priorities

### P0: useful and safe remote control

- Keep the Mac background helper online when the menu-bar app is quit.
- Discover hosts over the tailnet, then require QR pairing before exposing telemetry or commands.
- Ship read-only provider, model, jobs, hardware, earnings, and freshness views first.
- After that read-only surface is proven, add separately scoped commands for provider Start, graceful Stop, Restart, Apply Live, and Mac app open/quit.
- Require a fresh precondition token for every mutating command and return a durable command result.
- Add revoke, key rotation, local audit history, and a visible remote-control indicator.
- Add notifications for offline, drain completion, command failure, thermal pressure, and stalled work.

### P1: recommendations and fleet

- Add an observe-only recommendation engine and decision journal.
- Add multiple paired Macs with a combined read-only dashboard.
- Add support-packet export and an alert history shared between Mac and phone.

### P2: opt-in automation

- Evaluate the recommendation engine in shadow against historical and live outcomes.
- Add explicit optimizer policy, budgets, quiet hours, and manual override behavior.
- Add bounded stall recovery after the alert and command paths are proven.
- Keep the automatic controller in the persistent Mac helper, never in the phone app.

## Features to avoid or defer

- Do not replace the native dashboard with a web view or bundle a second backend runtime.
- Do not add privileged cache purging as a normal model-switch strategy.
- Do not infer future earnings from a small cross-user sample without hardware-specific calibration and honest uncertainty.
- Do not let the phone configure local endpoint authentication or broad provider security settings in the first release.
- Do not combine QR pairing, full remote mutation, fleet control, and automatic switching in one release. Each layer needs observable command results and failure recovery before the next one depends on it.

## Sources

- [Bloomkeeper README](https://github.com/cookder/bloomkeeper/blob/295e32d4605aed4de92401e4419e8cb933dcf1a1/README.md)
- [Bloomkeeper architecture](https://github.com/cookder/bloomkeeper/blob/295e32d4605aed4de92401e4419e8cb933dcf1a1/docs/ARCHITECTURE.md)
- [Bloomkeeper optimizer redesign](https://github.com/cookder/bloomkeeper/blob/295e32d4605aed4de92401e4419e8cb933dcf1a1/docs/OPTIMIZER_REDESIGN.md)
- [Bloomkeeper remote access implementation](https://github.com/cookder/bloomkeeper/blob/295e32d4605aed4de92401e4419e8cb933dcf1a1/native/remote.py)
- [Bloomkeeper manual model selection](https://github.com/cookder/bloomkeeper/blob/295e32d4605aed4de92401e4419e8cb933dcf1a1/native/manual_selection.py)
- [Bloomkeeper prewarm implementation](https://github.com/cookder/bloomkeeper/blob/295e32d4605aed4de92401e4419e8cb933dcf1a1/native/prewarm.py)
- [Bloomkeeper security policy](https://github.com/cookder/bloomkeeper/blob/295e32d4605aed4de92401e4419e8cb933dcf1a1/SECURITY.md)
