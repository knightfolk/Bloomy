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

## Follow-up: compact keyboard reveal

The Native108 offscreen-control failure is repaired in the Fans settings Form.
`FanSettingsKeyboardReveal` reports only native focus entering a control to a
page-owned `ScrollViewReader`. Other settings pages and the popup install no
callback. No keys are consumed, focus is not assigned programmatically, and
there is no polling, animation or source-update scroll request.

The reader uses [Apple's minimum-scroll API](https://developer.apple.com/documentation/swiftui/scrollviewproxy/scrollto%28_%3Aanchor%3A%29).
A transparent background target extends six points beyond the control to
include its native focus ring, without changing layout or adding an AX element.
The helper action and draft gates are unchanged.

Native109 verified the initial centered-scroll pilot in compact light. Native110
changed only the reader anchor to minimum scrolling, but exposed a clipped
slider ring at the lower viewport boundary. Native111 adds the reveal margin;
the layout remains identical and the full ring is visible. An initial conditional
closure failed Swift type checking; explicit page branches repaired compilation
and keep the reader out of other settings routes. The failed log is retained at
`/tmp/bloomy-fan-reveal-focused-20261002.log`.

**Native111**, compact light and dark:

- Native sidebar entry and Tab reach header Refresh, readings Refresh, checkbox,
  policy disclosure, all presets, both sliders, Save, advanced disclosure,
  Disable, Uninstall and Discard. Space expands disclosures. No pointer
  scrolling is required to reveal these controls or their full focus rings.
- Right edits 80%/65 °C to 81%/66 °C. The speed slider keeps the same visible
  position and focus across updated readings at 8:08:32 and 8:09:10.
- Reverse navigation returns through the expanded policy to the upper controls.
  Refresh retains the draft. Appearance → Dark → Fans retains both edited values;
  the newly mounted disclosures can be expanded and traversed by keyboard again.
- Space on the checkbox opens the inert disable confirmation; Escape returns
  focus to the still-checked control. No command is submitted. Space on Discard
  restores 80%/65 °C and disables Save.

**Native112**, wide light and dark, preserves the native card layout and draft
through appearance changes. Light verifies slider entry and Right editing;
dark verifies the complete bounded forward/reverse control path, fully visible
Discard and Space discard. The disappearing Discard control does not expose an
AX focus identity immediately afterwards or after the first Tab; the surrounding
toolbar/full-window continuation remains unverified. This is not a claim of a
complete window key loop or VoiceOver proof.

The final source passed all **1,430 tests** (1,381 app/telemetry in 25.770s,
21 protocol in 0.022s, 28 companion-host in 11.810s). Release compilation exited
0 in 55.10s. Logs are `/tmp/bloomy-fan-reveal-full-20261002.log` and
`/tmp/bloomy-fan-reveal-release-20261002.log`. The initial centered candidate's
95 focused tests passed in 1.654s; the final full suite reruns that coverage.
Native before/after observations cover the scrolling regression directly;
no artificial test that merely mirrors the modifier was added.

All four bundles and manifests are retained in `.build/native-dashboard-fixture-20261002-109/`
through `-112/`. Native111/112 each match all **96** recorded source hashes.
Native109 predates the reader-anchor and margin refinements; Native110 predates
only the margin. All use the same three documented inert dependency substitutions
and linked telemetry hash recorded above. Executable SHA-256 values:

- Native111: `da0c29eb3ec2f27c50a7f28ab64c3ee70e727f405fc4646a0bf44c73c5134ef7`
- Native112: `c42206d532ce5849f4b38a1a33f4958329548add7a6c9ea36901ec0add353ecb`

All review apps were quit normally. Stale/error and standalone Settings paths,
actual VoiceOver, rendered helper confirmations, real helper actions, full-window
navigation and distribution remain open. The full polish goal is still active.
