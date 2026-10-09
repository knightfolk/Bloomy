# Compact Nudge controls review — October 9, 2026

The automatic Nudge panel previously filled the first 360-point popup viewport
with two long explanatory paragraphs. Setup was hidden below them. A concise
icon-led summary now keeps the warm-model scope, eight-output-token cap and lack
of guaranteed work visible. A native **How nudges work** disclosure exposes both
original paragraphs verbatim. Setup and saved-key controls are outside it.

No store, timer, request, credential, updater-protection or lifecycle code changes.
The shared view also improves the dashboard's Provider settings presentation.

## Native evidence

Evidence root: `.build/popup-nudge-layout-review-20261009/`.
Baseline is `20709e8`; the native before/after comparison uses Dark appearance,
360-point popup budget, automatic Nudge off, 15-minute timing and a missing key.
The final first screen exposes controls, the essential summary, disclosure and
Set up Nudge heading. The baseline did not expose that setup heading.

The optimized isolated fixture uses production SwiftUI views, private preferences
and inert provider/network/account actions. Its consumer key store is in memory;
the dummy setup value never reaches real Keychain or an API. Production wording
still says Keychain, so these screenshots prove the presentation and navigation,
not actual Keychain storage. Mac identity and thermal state are actual;
fan/temperature readings are synthetic and CPU/GPU sampling is off.

Fixture binary SHA-256:
`677f28d420368da2599cea778d2d6f1f22082283c68949c71492f586b586564a`.
All **142** source-input manifest hashes match the inspected checkout. Deep strict
review-signature verification passes; this is not notarized distribution.

Computer-use inspection verifies:

- The native arrow expands and collapses the full original behavior explanation.
  Clicking the disclosure's label through CUA's element-center action did not
  expand it; clicking the visible native arrow did. Whole-row hit behavior and
  spoken accessibility are not claimed.
- Scroll reaches all setup steps, masked input, Save/Discard and the fixed Done
  control remains available.
- A masked dummy setup draft survives explanation collapse; Save and
  Discard remain available. Inert Save changes to the existing saved-key UI.
- The same expansion/collapse preserves a masked replacement draft; Cancel
  returns to the saved-key presentation. No replacement was submitted.
- The timing picker changes to 30 minutes. The fixture-only toggle enables the
  watcher with guarded status; the fixture cannot act or send a request. Timing
  returns to 15 minutes and automatic Nudge returns to off.
- Light/dark 360-point popup rendering and the wider light Provider settings
  layout fit. Reload removes the dummy in-memory key. The final review is Fresh,
  dark, 360 points, 15 minutes, automatic Nudge off and missing-key setup.

`native/` contains PNGs and accessibility snapshots for the baseline, compact
first screen, expanded explanation, retained setup/replacement drafts, inert
saved-key/toggle states, light appearance and wide dashboard Provider settings.
The final image is `native/final-nudge-dark-360.png`.

## Verification and preserved state

- `swift test -c release --no-parallel`: exit 0; **1,862** reported app tests in
  234 suites plus **21 + 28** Companion tests. Seven existing opt-in tests skip.
- 49 staging checks pass.
- Regular `swift build -c release`: exit 0, 59.97 seconds.
- Independent read-only source review: no actionable findings.
- Protected concurrent `Tests/NativeUI/MenuBarMotionProof.swift` remains
  `ca10cb20271d1bd5fafec801d0ed5fcb17377a0f8812132366aa2ece462db50d`.
- Installed Bloomy PID 7234 remains running. The previous isolated Hosting review
  was quit normally before the new Nudge review was opened.
- Real provider configuration was observed to change at 05:29:29, with hash
  `e081909a3b2db8b1453e87efe30ca77322476b3d4ea16ff9ee8872447114093f`,
  and live provider processes appeared during this turn. This work performed no
  real provider action or config write and did not restore older settings.

## Limits and delivery

This is a presentation change with existing regression coverage and actual native
mouse/scroll/draft evidence, not mirror tests of the layout. Keyboard/VoiceOver,
large text, normal-speed publication/motion, every tiny-budget path, sustained
resource profiling and broader delivery gates remain open.

The checkpoint is local only. No real credential, nudge, configuration write,
installed replacement, push or release occurred. The isolated review stays open
for inspection and the continuous polish goal remains active.
