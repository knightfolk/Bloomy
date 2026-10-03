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

## Final verification

The exact repaired source passes **1,429 tests**, exit 0: 1,380 app/telemetry
tests in 182 suites (16.918s), 21 protocol tests (0.012s), and 28 companion-host
tests (11.796s). Full log:
`/tmp/bloomy-provider-keyboard-20261002-full-01.log`.
Final release compilation exits 0 in 42.11s; log:
`/tmp/bloomy-provider-keyboard-20261002-release-01.log`.

Actual VoiceOver, the full Provider/standalone settings key loop, rendered Leave
alert, other displays, real enrollment/restart, comparable production profiling
and signed updater/distribution gates remain open.
