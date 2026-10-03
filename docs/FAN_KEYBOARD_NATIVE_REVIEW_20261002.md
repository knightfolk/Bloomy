# Fan keyboard focus — October 2, 2026

The helper enable control now uses the standard macOS checkbox. Its existing
freshness, pending-confirmation, mutation and administrator-action gates are
unchanged. No custom key handling, focus restoration or polling was added.

## Native diagnosis and bounded proof

All observations use normal NSApplication fixtures, production views, inert
clients, isolated preferences and local review signatures. The review banner
was omitted. The fixture now offers Window → Toggle bounded focus diagnostics;
this only enables the existing passive trace, without changing the key loop.

- Native105 reproduced the switch losing keyboard focus between keys. The
  policy controls could be traversed when the switch was crossed quickly.
- Native106 records `PlatformSwitch` receiving focus at elapsed 36.692 seconds,
  then the window taking it at 36.932 seconds. The native stack includes
  `NSControl setEnabled:` and `NSSwitch setEnabled:` during a SwiftUI update.
  The trace does not identify which disabled-state predicate changed.
- Native107, wide light, retains the checkbox's same native `KeyViewProxy`
  from elapsed 18.591 through the next Space at 113.938 and next Tab at 203.032.
  Space opens the disable confirmation; Escape cancels and returns focus to the
  checked control. Cancellation is direct UI evidence, not a trace assertion.
  Tab/Shift-Tab traverses policy disclosure, all three presets, both sliders,
  Save, advanced disclosure, Disable, Uninstall and Discard. Right changes the
  draft to 81%/66 °C; Discard restores 80%/65 °C. No helper action was submitted.
- Native108, compact dark, verifies the same bounded forward and reverse
  control sequence and local edits through live fixture reads. Pointer scrolling
  reveals the lower controls and preserves focus. **Keyboard focus alone did
  not reveal the offscreen sliders or fully reveal Discard** after expanding
  the policy; compact keyboard scrolling therefore remains a product issue.

The native disable-confirmation capture was blank, although AX exposed the
warning and actions. Its appearance remains unaccepted. Actual VoiceOver,
standalone Settings, missing/stale states, real helper/admin actions and the
full window key loop remain open.

## Provenance and checks

Preserved bundles/manifests are `.build/native-dashboard-fixture-20261002-105/`
through `-108/`. Native107/108 each match all 95 recorded source hashes.
Native106 differs only in the subsequent checkbox line; Native105 additionally
predates the diagnostic menu. The three inert dependency substitutions are
recorded in each manifest.

Native106 session: `72EEE970-082B-4FFD-A788-48814306FCC4`.
Native107 session: `EAE8ECF0-B0EA-4C56-BCEC-1C5E6CA06F75`.
The saved traces are `fan-switch-baseline-focus-diagnostics.jsonl` in Native106
and `fan-checkbox-focus-diagnostics.jsonl` in Native107. Traces are bounded;
later reverse traversal is direct CUA evidence rather than captured trace.

Native107 executable SHA-256:
`3a5ec3596936bc582d2c663aec21b732cb1d325c0404f2713ba6d601e36ca89e`.
Native108 executable SHA-256:
`85807bdb23fb506dc5a8d5a2837a749ced24461a4dc3bce1e76056184a99b34e`.
Both linked telemetry libraries:
`0da0aed0eee0f3ace173ccbcbc1b413cc64f7d4f1ec2d78658e059fff593d102`.

Existing focused checks passed 95 tests in four suites. The final `swift test`
passed 1,430 tests (1,381 app/telemetry, 21 protocol, 28 companion-host), and
`swift build -c release` exited 0 in 46.33 seconds. Logs:
`/tmp/bloomy-fan-checkbox-focused-20261002.log`,
`/tmp/bloomy-fan-keyboard-full-20261002.log`, and
`/tmp/bloomy-fan-keyboard-release-20261002.log`.
No new test definitions were added for the one-line native style change;
the original failure and corrected responder behavior were inspected directly.

All review apps were quit normally. Production PID 61760 retains its
October 2 12:55:28 launch and executable hash
`5d692f240c9548f05350f2fb39d05eb15d00741ad7e9f317e3eeb8507e7c50c7`.
No installed release, provider settings, real inference, helper or privacy
permission was changed. Broader polish and distribution gates remain open.
