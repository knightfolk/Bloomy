# App-native Autopilot — October 2, 2026

Kevin requested optional Autopilot enrollment and on/off controls in Bloomy,
without running the interactive startup command. This is a focused feature
checkpoint within the ongoing polish plan, not completion of all native or
distribution gates.

## Behavior and contract

Settings → Provider offers experimental Enable, Pause/Resume, Leave, and Refresh
actions. Initial Enable opens native consent describing downloaded-model
reporting, shadow-first rollout, one graceful provider restart and preserved
startup/memory/schedule/hosting/slot preferences. Enrollment is consent; the
coordinator owns activation. Pause retains enrollment and residency ownership;
Leave removes enrollment. Accepted transitions remain visible while finishing.

The implementation uses the supported 0.9.17 CLI enrollment path with explicit
saved model IDs and existing hosting flags, not handwritten enrollment TOML or
the interactive model selector. Every saved enabled selector must resolve to a
downloaded, active, RAM-compatible, eligible model. Ordinary offline models can
qualify; capability-restricted builds need actual matching runtime evidence.
Alias preloads that would become invalid after the CLI normalizes enabled IDs
are refused before dispatch, with a Models repair instruction.

Every dispatched result is reconciled, including nonzero exit, cancellation and
timeout. Config comparisons account for materialized defaults and compare saved
selection/preload/capacity/idle/reserve/schedule semantics. Fresh bounded JSON,
supported protocol, consent, matching revision and independent same-config
daemon freshness are required for live confirmation. A saved-only result is
pending confirmation; failed reads retain visibly stale evidence. The upstream
CLI has no expected-revision argument: cross-process edits after preflight are
detected on readback rather than excluded by an atomic app guard.

Autopilot shares the existing background cadence. A status tick skips an
occupied visible-fan read and retries on the next tick, avoiding a joined-read
cycle or extra full/static refresh. Unsupported clients return unavailable
without implicit reads. Stale evidence disables changes. Completed policy
readback survives caller cancellation. History uses bounded Autopilot action
names and records observed enrollment completion rather than assuming that
caller cancellation prevented a dispatched change.

Bloomy's optional profit switching defers in active, paused, waiting,
waiting-inventory, transitioning, recovering, and unrecognized native phases,
including after its asynchronous pre-dispatch refresh. Unknown phase presence
is retained as a boolean, with arbitrary provider prose discarded. Off, shadow,
or genuinely absent legacy phase retains existing optional behavior. The saved
Bloomy preference and timing are preserved.

Official contract sources:
[enrollment](https://github.com/Layr-Labs/d-inference/blob/v0.9.17/provider-swift/Sources/darkbloom/Autopilot/AutopilotEnrollmentCommands.swift),
[policy](https://github.com/Layr-Labs/d-inference/blob/v0.9.17/provider-swift/Sources/darkbloom/Autopilot/AutopilotPolicyCommands.swift),
[rollout](https://github.com/Layr-Labs/d-inference/blob/v0.9.17/docs/operations/model-autopilot.md),
[eligibility](https://github.com/Layr-Labs/d-inference/blob/v0.9.17/provider-swift/Sources/ProviderCore/Models/ModelRuntimeRequirements.swift).

## Verification boundaries

One worker owned backend/stores and regression tests; root owned native UI,
profit integration and final verification. Two read-only reviewers assessed
contract and UI separately. Review identified and repaired alias preload
corruption risk, cancellation readback/history, leaving-during-recovery wording,
policy explanation, stale enrollment feedback and automatic-selection overlap.

Initial focused checks passed 17 tests; later focused checks passed 72 tests in
9 suites. A combined run exposed a held-fan/background joined-read cycle and
implicit full reads in the unsupported protocol fallback; it was stopped
intentionally and repaired. A full run then exposed a 500ms test-watchdog race
under concurrent native rendering. The bounded test watchdog now allows 30s;
production cadence was unchanged. The next full run passed 1,412 tests. A final
parser hardening change adds explicit malformed-phase coverage and is verified
again in the final results below.

A sanitized read-only probe of the real running provider returned available,
enrolled, live-confirmed, unpaused **shadow**, with activelyManaging=false.
No root provider restart, enrollment, pause/resume/leave, download, swap, nudge,
inference or privacy change was performed to obtain that evidence.

## Final integrated verification

The final source passed **1,417 tests**: 1,368 app/telemetry tests in 180 suites,
21 protocol tests and 28 companion-host tests. `swift test` exited 0; the three
runs took 21.921s, 0.014s and 11.825s respectively. The final release compile
exited 0 in 49.07s. Logs are retained in
`/tmp/bloomy-autopilot-20261002/full-05.log` and `release-03.log`.

Native77 was a consent pilot. Native78 exercised enrollment and policy actions,
but revealed that a captured dirty-settings Boolean did not invalidate Enable
immediately after an idle edit. The final view observes the retained draft
directly. Its regression constructs the view once, changes/discards idle and
changes fan edits, verifying that its action gate reads each new state.

**Native79** inspected the final source using normal NSApplication, production
views, inert provider/account/network/key clients and isolated preferences:

- Wide light Provider shows optional Enable and Refresh. Its native consent
  explains reporting, shadow rollout, preserved choices and one provider restart;
  the full text and both fixed footer buttons are readable.
- Editing idle 30 → 45 immediately disables Enable and exposes the draft warning;
  Discard immediately restores 30 and enables the action, before a periodic read.
- Consent Escape leaves Off. Reopening and Tab/Space confirms exactly one
  simulated enrollment, showing Observing · shadow mode.
- Compact dark Pause changes to Paused/Resume; Resume returns to shadow.
  Leave's native alert exposes its warning and both actions to accessibility;
  confirming returns to Off with Enable available.
- An invalid preload enrollment fails before dispatch, retains Off and displays
  the safe Models repair instruction beside the action. The error is visible in
  the compact dark window; it does not require a terminal command.
- A failed status read retains Last known: Off, disables Enable and leaves
  Refresh usable. A saved/revision-mismatched enrollment reads Enrolled · awaiting
  confirmation; matching active evidence reads Actively managing.

The saved inert proof reports `enrollmentCount=1`, `policyCount=3`. Consent Cancel
and rejected preload enrollment add no action. Native78 independently saved the
same counts. Both apps were closed normally, and their processes were absent
afterward. These are simulated mutations, not real provider action evidence.

Native79 session: `62F1D3C0-BC66-466F-B756-47EB009A7403`.
Its preserved output is `.build/native-dashboard-fixture-20261002-79/`, with
`fixture-manifest.json`; all 90 source hashes still match the checkout after
inspection. The exact linked telemetry library hash is
`0da0aed0eee0f3ace173ccbcbc1b413cc64f7d4f1ec2d78658e059fff593d102`;
the executable hash is
`da2412673c5f31656b9454b85594a8f57ae2a72618e0041cff45469ff4c1d913`.
Only the documented three inert dependency substitutions are staged. The
isolated signature is local review evidence, not distribution signing.

At the final read-only probe, the real provider still reports fresh confirmed,
unpaused shadow enrollment, not active model control. Production Bloomy PID
61760, provider PID 67163 and watchdog PID 67169 retain their earlier launch
times. The installed executable hash remains
`5d692f240c9548f05350f2fb39d05eb15d00741ad7e9f317e3eeb8507e7c50c7`.

## Remaining limits

The native Leave alert's screenshot capture returned a blank image in both
Native78 and Native79 despite functional accessibility/actions. Its rendered
appearance is **unaccepted**; do not treat the action proof as visual acceptance.
Actual VoiceOver, a real enrollment/restart, production replacement with
protected drafts, the broader native matrix and signed updater/distribution
checks remain open. No installed release was changed or published here.
