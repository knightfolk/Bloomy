# Provider keyboard and draft review — October 2, 2026

This focused follow-up improves the native Provider page within the ongoing
[polish plan](APP_POLISH_OPTIMIZATION_PLAN.md). It does not complete the settings
key loop, real provider actions, accessibility or distribution gates.

## Reproduced problem and focused repair

In Native91 session `DEE3E3E8-48AB-4421-B94D-D963717DB164`, merely focusing the
unchanged idle-minutes field (30) changed the draft to dirty. Save and Discard
appeared, Enable Autopilot became disabled and its unsaved-settings warning
appeared. No text was typed or saved. Discard restored clean 30 and enabled
Autopilot; focusing the same field reproduced the problem before blur.

The native text field writes its existing text back through its Binding.
`ProviderSettingsDraftState.editIdle` previously marked every callback dirty and
advanced the save revision, even if the buffer was identical. It now ignores
only identical text. Actual text changes, including partial invalid input,
still mark the draft dirty and advance its revision. Already dirty duplicate
callbacks preserve that state and its submitted revision. Discard still always
invalidates earlier submitted saves; successful matching readback still clears
only the corresponding revision. No native key handling or new state was added.

Two regression tests failed before the repair: unchanged callbacks incorrectly
blocked the real app-update guard, and duplicates invalidated a matching save
revision. The Autopilot presentation regression also verifies that unchanged
callbacks leave a previously created action view eligible. After repair, the
31 focused tests in four suites pass in 7.208s, exit 0. Logs:
`/tmp/bloomy-provider-keyboard-20261002-red-01.log` and
`/tmp/bloomy-provider-keyboard-20261002-focused-01.log`.
Read-only review found no actionable regression in clean/dirty semantics,
invalid buffers, late saves or independent idle/fan ownership.

## Native92 final source

Session `8A74C725-8AB0-445C-B7DA-8D71A8E581AB` uses the actual production views in
an isolated native app, synthetic stores/preferences and inert dependencies.

- Compact light: clicking untouched 30 and pressing Tab retains 30, disabled
  Save, no Discard/unsaved warning, and available Enable Autopilot.
- Shift-Tab returns to the field. Actual Select All/type 45 immediately enables
  Save and Discard, shows the unsaved warning and disables Autopilot. Tab reaches
  Save with its full focus ring. Discard restores 30 and action eligibility.
- Wide dark repeats untouched-field focus/Tab with the same clean state.
- Baseline and candidate each save zero simulated enrollments and zero policy
  actions. No real provider, network, key or configuration mutation was invoked.

Both fixtures were quit normally; their processes were absent afterward.
Native91 baseline and Native92 candidate retain uniquely named diagnostics in
`.build/native-dashboard-fixture-20261002-91/` and `-92/`. Their Provider focus
traces each contain 49 records. These diagnostics do not consume or synthesize
key events and do not alter OS keyboard settings.

Native92 manifest: 95 source hashes all match the inspected checkout. Executable
SHA-256: `0f2f083f0cc6d9bc6770c7c23c187712bf01ebb993732ab6f30f4d2f449e146b`.
Telemetry library SHA-256:
`0da0aed0eee0f3ace173ccbcbc1b413cc64f7d4f1ec2d78658e059fff593d102`.
Its local review signature is not a distribution signature.

Installed Bloomy PID 61760 retains its October 2 12:55:28 launch and executable
SHA-256 `5d692f240c9548f05350f2fb39d05eb15d00741ad7e9f317e3eeb8507e7c50c7`.
The earlier provider PID 67163 is no longer present; watchdog PID 67169 retains
its 13:18:51 launch. This external process change was observed read-only; these
checks performed no provider start/stop/restart or installed-app replacement.

## Separate keyboard finding and remaining gates

Provider lower controls are reachable when entering via its field/beta area:
beta menu, profit switch/disclosure, four timing steppers, nudge switch/period,
console link and empty secure field. The console link was not opened and no key
was entered or saved. This is partial traversal evidence, not the full loop.

Compact Tab entry from the fixture banner skipped upper Refresh/Autopilot
controls before reaching the idle/beta/lower area. Another pass after pointer
interactions reached the upper controls but did not establish a reliable
through-page sequence. AX pressing Refresh does not itself move keyboard focus;
do not claim it supplies a deterministic key-loop starting point. The saved
native trace supports further diagnosis; cause and correction remain open.

Read-only trace review found the upper provider proxies present and eligible in
the native valid-key chain before event 13, but that event lands directly on the
field editor. Baseline91 also skips to the field, so this predates the draft
repair. The candidate field's viewport-relative y is -76 while the viewport
starts at 0; its immediate after-event frame remains offscreen. Between event
13 after and event 14 before, focus changes from field editor to window, so this
trace does not prove a direct field-to-banner Tab transition. Diagnostic node
IDs are offsets in each snapshot, not persistent identity; labels and key
modifiers are absent. These limits rule out claiming missing native links as
the root cause. The next controlled experiment should compare consecutive Tab
inputs with and without intermediate observation, starting from a verified
last-banner responder and inspecting before/after frames.

## Verification of the unchanged-text repair

The exact repaired source passes **1,429 tests**, exit 0: 1,380 app/telemetry
tests in 182 suites (16.918s), 21 protocol tests (0.012s), and 28 companion-host
tests (11.796s). Full log:
`/tmp/bloomy-provider-keyboard-20261002-full-01.log`.
Final release compilation exits 0 in 42.11s; log:
`/tmp/bloomy-provider-keyboard-20261002-release-01.log`.

Actual VoiceOver, the full Provider/standalone settings key loop, rendered Leave
alert, other displays, real enrollment/restart, comparable production profiling
and signed updater/distribution gates remain open.

## Follow-up: editing across read-only control refreshes

Native93's whole-Form focus grouping and Native94's redundant-size guard did
not establish a correction. Native95 registered the idle field with local
`FocusState`; short forward/reverse checks retained focus, but upper entry and
sustained refresh behavior remained unproven. Native96 repeated grouping with
that registration and still skipped upper controls. Native98's explicit default
focus also failed to change entry. Both product experiments were removed.
No custom key routing or Form replacement remains.

Native97 adds bounded next-turn/50ms snapshots, monotonic timing and weak
persistent responder identities. Its first field editor remains identical
through settled sampling and the next key. Reverse traversal reaches Refresh
Autopilot, Enable and header Refresh. Native99 additionally observes AppKit
responder requests without altering their results. During initial entry SwiftUI's
FocusBridge requests the text field directly; the native proxy links alone do
not describe that decision.

More importantly, Native99 then loses editing without another key: at elapsed
21.657s, AppKit's `NSTextField setEnabled` / `NSControl abortEditing` path moves
focus to the window. The shared Provider host disabled all children whenever
the control store was non-idle, including its read-only `.refreshing` state.
The five-second inert control refresh reproduces that boundary. Field
registration alone does not prevent an enclosing disabled environment.

The Provider host now allows local editing during idle and read-only refreshing
when there is no pending confirmation or model draft. Mutations still block the
group. Idle Save and beta actions separately reflect provider operation
ownership, and the existing serialized write gate still requires idle. Autopilot
retains its own busy checks; Fans and Updates retain their previous refresh
policy. The fixture also avoids redundant native window resizes.

A held-read regression fails with the prior non-idle editing gate and passes
after the repair. It covers both clean and dirty model selections, late edits
and the exclusive settings-write gate. Focused verification passes 101 tests
in four suites. Logs: `/tmp/bloomy-provider-refresh-focus-20261002-red-held-read.log`
and `/tmp/bloomy-provider-refresh-focus-20261002-focused.log`.
The first red command selected only the write-gate test; the corrected held-read
command records the intended failure. Read-only review found no actionable
serialization or enabled-state regression; native focus remained a separate gate.

### Native100: sustained editing

Session `B2FBBADA-18BD-4571-8202-02EA653E110D` uses the final production source.
Compact light keeps the same field editor from elapsed 19.313s through the next
key at 65.260s, with the existing five-second read loop running. Tab reaches beta,
and Shift-Tab reveals the field. Actual typing 45 retains its draft and focus
through subsequent reads; Save/Discard are reachable, Autopilot immediately
blocks, and keyboard Discard restores clean 30. Wide dark retains the same editor
through another approximately 50-second interval and Tab reaches beta.
The saved `provider-read-edit-focus-diagnostics.jsonl` contains 47 records.

All 95 source hashes matched at inspection. Executable SHA-256:
`4226c5bbb53838478066708e53e4a1ebff5d1f33c356a29a87cd49bebbfbfdbd`.
Only the fixture subsequently changed to support the comparison below; all 87
production-view hashes still match both candidates.

### Native101: dashboard-only entry comparison

The review builder's explicit `--hide-review-banner --compact` options remove
only synthetic control rows. Inert data, collectors-off policy, native host and
synthetic window title remain. The manifest records those options. This avoids
making product changes to compensate for a focus boundary created by fixture
controls outside the production dashboard.

Session `9AD8593C-AF1D-482D-A06E-6FD08F84792C` shows compact light Provider with
the idle field visible. An actual sidebar pointer click followed by Tab reaches
Nudge, Settings, then header Refresh. Further Tab reaches Enable Autopilot,
Refresh Autopilot and idle minutes in order, with visible focus rings. The
banner-origin skip is therefore not established as a dashboard entry defect.

Forward Tab continues through beta disclosure/menu, profit switch/disclosure,
four timing steppers, automatic nudge/period, console link and the empty secure
field; native scrolling reveals each lower region. Fifteen Shift-Tab inputs
return through every page control to header Refresh. The next Shift-Tab reaches
the sidebar; another wraps to the secure field. This is bounded page traversal,
not a claim that all toolbar/window focus domains share one symmetric loop.
No link was opened, credential entered, setting saved or provider action issued.
Its executable SHA-256 is
`1270497bac90cae850641bfc48c4289ce5d2cef2135c4f8cf4925583c9117dbf`;
all 95 manifest source hashes match. Both candidates link telemetry SHA-256
`0da0aed0eee0f3ace173ccbcbc1b413cc64f7d4f1ec2d78658e059fff593d102`.

Native96–101 were quit normally; no owned app or compiler handle remains.
Installed Bloomy PID 61760 retains its earlier launch and executable hash.
No real provider, privacy, key or installed-app changes occurred.

### Integrated verification and remaining limits

The repaired production source passes all 1,429 tests: 1,380 app/telemetry in
182 suites (26.072s), 21 protocol (0.014s) and 28 companion-host (11.800s), exit 0.
Release compilation exits 0 in 41.62s. Logs:
`/tmp/bloomy-provider-refresh-focus-20261002-full.log` and
`/tmp/bloomy-provider-refresh-focus-20261002-release.log`.
The fixture builder separately compiles and opens both normal and dashboard-only
layouts. Local review signing is not notarized distribution.

Standalone Settings, expanded/error/paused control loops, actual VoiceOver,
rendered Leave confirmation, real enrollment/restart, production preservation,
whole-app profiling and updater/distribution remain open. The full polish goal
is not complete.
