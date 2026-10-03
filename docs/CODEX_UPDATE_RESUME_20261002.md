# Bloomy app-update hold — 20261002-181645 America/Phoenix

Resumed: the user-controlled goal returned to active after the update. The hold
instructions below describe the earlier checkpoint and no longer pause current
work. Native96–101 follow-up, the read-only refresh repair and remaining gates
are recorded in [Provider keyboard review](PROVIDER_KEYBOARD_DRAFT_NATIVE_REVIEW_20261002.md).

Status: READY for Codex app update. Hold new implementation, generation,
tests, builds and workers until Kevin confirms the update is done and explicitly
authorizes resume. This is a safe checkpoint, not completion of the active polish
goal. Use the supported native Goal pause; conversational hold alone is insufficient.

## Authorization and owner

Kevin approved preparing the three active owners for update with “Yes” in
`Monitor Codex task progress`, thread `01a0f3a1-9807-71f1-94e2-a236533c203c`,
turn `01a0ff4d-5d37-7094-abd8-c91054d452a5`. The preceding question was whether
to ask the three active threads for safe checkpoints; its tool handoff explicitly
includes supported pause-for-update authority. The coordinating thread forwarded
that request. Direct evidence was inspected, not inferred from its message alone.
Kevin also directed no new Sol Ultra threads; preserve existing owner/model choices.

Main integration owner remains this Bloomy task
`01a0eb34-3317-7821-8c46-73723894fd79`. The full original goal remains a polished
native SwiftUI app conforming to Apple design language with minimal background
cost. `APP_POLISH_OPTIMIZATION_PLAN.md` and the native completion matrix remain
open. Standing verified local commit and prudent authorized GitHub checkpoint
workflow remains in AGENTS.md; native/distribution gates still apply.

## Exact checkout and saved work

- Checkout/worktree: `/Users/kevink/Projects/DarkbloomCLIMenuBarMonitor`; branch `main`.
- HEAD/source base: `9df744e15f4def927390bade14209b0fb5bf6aa2` (false idle draft fix).
  GitHub main was verified live at that SHA at this hold checkpoint; recheck before any push.
- Current uncommitted owned files: `Sources/DarkbloomMonitor/ProviderExtrasViews.swift` and `Tests/NativeUI/DashboardFixture.swift`.
- `Sources/DarkbloomMonitor/ProviderExtrasViews.swift` adds local `@FocusState idleFieldFocused` and `.focused` to idle
  minutes. Native95 improves focus retention, but is NOT fully verified/releasable.
- `Tests/NativeUI/DashboardFixture.swift` skips redundant `setContentSize` when the content size already
  matches. Compact/wide resizing works in Native94. It did NOT fix the focus bug.
- This resume note is newly untracked. Unrelated `.mimosa/` and `.zcodeignore`
  are untouched and must remain outside staging/cleanup.
- Backup of exact owned diff and both files: `/Users/kevink/Projects/DarkbloomCLIMenuBarMonitor/.build/codex-update-checkpoint-20261002-181645`.
  No incomplete product source was committed or pushed for the update.

## Current diagnosis and exact next step

Provider grouped Form keyboard entry skips header Refresh/Autopilot and enters
idle minutes while offscreen; without explicit registration the field loses focus
between events. Native key-view links exist, so missing links are not proven.

- Native92 immediate pair, session `B68CDC1B-86CF-4160-BD35-DBBDA2AF9C77`:
  consecutive Tab calls with NO intermediate AX observation still lose focus.
  Saved `provider-immediate-focus-diagnostics.jsonl` (35 records) beside its manifest.
- Native93 provider-only whole-Form `.focusSection` experiment, session
  `685B5424-DE53-4430-99E4-39A0330D27F3`: skip and loss persist. REJECTED;
  its staged source/manifest/five-record trace remain, product modifier was removed.
- Native94 stable-sizing-only comparison, session
  `38B164E0-702E-4EC3-BA20-6D21A47D9BD3`: skip/loss persist; compact→wide still
  resizes. Five-record `provider-resize-control-focus-diagnostics.jsonl` retained.
- Native95 adds explicit field registration, session
  `737E44D5-D7AF-4EE8-AC6F-D38391173572`: from verified last banner responder,
  Tab still enters offscreen idle; next Tab now reaches beta disclosure instead
  of returning to the banner. Shift-Tab returns to visible selected 30 with full
  ring. Upper entry and initial reveal remain OPEN. Saved registration trace.

After explicit resume: first revalidate checkout/dirty diff and app state. The
next planned one-factor experiment was provider-only whole-Form `.focusSection`
with the now-registered field, compared against Native95. It was NOT started;
do not assume it will fix entry/reveal. Capture both independently and reject
changes lacking evidence. Keep native Form; no custom global key routing.
If focus still fails, improve bounded timing/stable-identity evidence before
further structural guesses. Actual VoiceOver approval remains unanswered;
do not enable it. Mounted slow Metrics analysis, broader route/appearance/motion,
whole-app profiling, protected production launch and distribution remain open.

## Checks and artifacts

- Last fully verified product commit `9df744e`: 1,429 tests and release compile
  passed; previous turn's native unchanged/real input checks are in
  `PROVIDER_KEYBOARD_DRAFT_NATIVE_REVIEW_20261002.md`.
- New dirty focus registration: Native95 build exits 0, native partial proof only.
  No new full tests/release compile/reviewer acceptance yet. Run relevant regressions
  and required full checks only AFTER resume and final native source is selected.
- Builder handles 49471 (Native93), 96734 (Native94), 41362 (Native95) all joined
  exit 0. No active owned compiler/test session remains. Native92–95 apps quit
  normally; process absence confirmed at checkpoint.
- `.build/native-dashboard-fixture-20261002-92/` through `-95/` preserve staged
  source, manifests, binaries and uniquely named diagnostics. Keep them for
  review/provenance; do not equate local review signing with distribution.
- Native95 has 95 source hashes; all match dirty checkout at checkpoint.
  Binary: `4ce11cad1ab7cd26442de4fddea10d5f541f6ee078afc6d481080a1f1f9d84a3`.
  Telemetry library: `0da0aed0eee0f3ace173ccbcbc1b413cc64f7d4f1ec2d78658e059fff593d102`.
- Build logs: `/tmp/bloomy-settings-focus-20261002-native-93.log`, `-94.log`,
  `-95.log`. Apple focus-section reference inspected:
  https://developer.apple.com/documentation/swiftui/view/focussection%28%29
  It specifies sequential descendant grouping; Native93 proves the modifier
  alone was insufficient here. No broad success follows from that API contract.
- Source-review worker `/root/metrics_focus_review` completed; no active worker
  or pending delegated operation remains. Do not create new expensive/Ultra workers.

## Resources and protected external state

No GPU/model-inference reservation and no owned external generation/server/watcher.
Free storage last observed about 62 GiB; reuse established build outputs and
avoid large disposable batches/worktrees. Preserve unrelated tasks/resources.
Installed Bloomy PID 61760 retains launch 12:55:28; executable SHA-256
`5d692f240c9548f05350f2fb39d05eb15d00741ad7e9f317e3eeb8507e7c50c7`.
Watchdog PID 67169 retains launch 13:18:51; original provider PID 67163 is absent.
No provider, installed app, credentials or privacy state was changed by this pass.
Do not replace/quit production over possible unsaved edits. Do not restart Codex
or resume this goal automatically. Pending update/resume confirmation belongs to Kevin.
