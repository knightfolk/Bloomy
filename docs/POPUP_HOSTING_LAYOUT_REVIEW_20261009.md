# Compact popup Hosting review — October 9, 2026

The popup is a primary control surface. Hosting now shows selected-mode status
and Refresh below its fixed title, followed by a native segmented mode selector
and the selected explanation. The repeated dashboard heading and three tall
mode cards no longer consume its initial viewport. The full dashboard keeps
its original heading and explanatory mode cards.

## Scope and preserved behavior

- `HostingSettingsView` defaults to dashboard presentation; only
  `PopupControlPanel` requests popup presentation.
- The selector calls the existing `setMode` action and uses the existing CLI
  capability guard. Its badge remains labeled **Selected**, not a claim that
  the running provider has changed.
- Refresh, port/address drafts, token handling, exposure confirmation ownership,
  updater protection and Apply actions are unchanged.
- Local-only mode remains explicitly managed in Terminal. Bloomy does not claim
  to launch or stop that foreground CLI process.

## Native evidence

An optimized isolated synthetic fixture uses production SwiftUI views, private
preferences and inert provider/endpoint/account actions. No real inference,
restart, token save, network exposure or provider configuration change was made.
Mac identity and thermal state are actual; fan/temperature readings are
synthetic and CPU/GPU sampling is off, as its banner states.

Evidence root: `.build/popup-hosting-layout-review-20261009/`.
Fixture executable SHA-256:
`b7353d78d364741c42768775ea035aa67d1d34a86bf4e651274f43e2055221be`.
All **142** manifest source hashes match the inspected checkout; deep strict
review-signature verification passes. This is not notarized distribution.

Baseline `9f3a472` and final native images use Dark appearance, a 360-point
popup budget, Fleet only and valid port 8000. The baseline first screen exposes
only the first two large mode cards. The final first screen exposes all three
mode choices, the selected explanation and the Local endpoint heading.

Computer-use inspection verifies:

- Fleet only, Fleet + local API and Local only selection update the badge and
  explanation. Local only shows “Managed in Terminal,” retains the command
  controls, and omits app-owned Apply.
- Scrolling reaches endpoint/network controls and the connection/Apply area;
  the fixed Done control stays available.
- Invalid port `8x` retains its validation message and disabled Apply after
  Done, popup dismissal, reopening and Refresh. Discard input edits restores
  8000 and re-enables the existing Apply action.
- Light and dark rendering remain readable at the same 360-point budget.
- Dashboard Hosting retains its original heading and explanatory cards.
- The Offline fixture reports unavailable CLI version, keeps Refresh visible,
  and disables the segmented choices and Apply. The fixture is restored to
  Fresh, dark, Fleet only, port 8000 for review.

`native/` contains before/after PNGs and accessibility snapshots, including
`final-hosting-dark-360.png`, the unavailable-CLI state and retained-input state.
The review app remains open for inspection; installed Bloomy PID 7234 is intact.

## Verification

- `swift test -c release --no-parallel`: exit 0; **1,862** reported app tests in
  234 suites, plus **21 + 28** Companion tests. Seven existing opt-in tests skip.
- 49 staging checks pass.
- Regular `swift build -c release`: exit 0, 53.73 seconds.
- Independent read-only native source review: no actionable findings.
- Protected concurrent `Tests/NativeUI/MenuBarMotionProof.swift` hash remains
  `ca10cb20271d1bd5fafec801d0ed5fcb17377a0f8812132366aa2ece462db50d`.
- Real provider configuration hash remains
  `a559a8a109cb7ee6940cb9129cde2ce0305698ffe95148e126a803a69b0e495d`.

## Limits and delivery

This presentation change does not add mirror tests; existing meaningful
capability, draft and confirmation regressions pass alongside native mouse
interaction. Keyboard/VoiceOver, large text, every tiny-budget panel/footer,
accepted-work dialog pixels and whole-app resource qualification remain open.
No real Apply or security-sensitive action was exercised for visual evidence.

This checkpoint is local only. No installed replacement, provider mutation,
push or release occurred. The continuous polish goal remains active.
