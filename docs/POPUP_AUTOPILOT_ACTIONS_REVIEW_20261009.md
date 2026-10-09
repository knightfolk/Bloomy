# Popup Autopilot action review — October 9, 2026

The enrolled popup used long action labels that did not fit horizontally.
`ViewThatFits` selected the vertical fallback, pushing Refresh below the initial
popover viewport. Pause/Resume, Leave and Refresh now use shorter contextual
labels in the popup only. All three controls fit together in the first view.

## Scope and preserved behavior

`ProviderAutopilotSettingsView.compactActions` defaults to false. Only
`PopupAutopilotControl` enables it. Full accessibility labels and identifiers
remain explicit. Dashboard labels, consent text, Leave confirmation, busy/stale
and unsaved-draft guards, enrollment and policy mutation actions are unchanged.
The existing vertical fallback remains for widths where the row cannot fit.

The native baseline did not justify replacing the Autopilot popover or consent
sheet. Their existing platform presentation is retained.

## Native evidence

Evidence root: `.build/popup-autopilot-review-20261009/`.
Baseline is `83aeb53`. Matched dark, 360-point parent-popup budget captures show
Refresh below the baseline's initial shadow/paused view, while the candidate's
short action row shows Pause/Resume, Leave and Refresh together.

The optimized isolated fixture uses production SwiftUI views with private
preferences and inert provider/network/account actions. It does not enroll,
pause, restart, swap, download or infer through the real provider. Mac identity
and thermal state are actual; fan/temperature samples are synthetic and CPU/GPU
sampling is off, as its review banner states.

Fixture executable SHA-256:
`e1c63ac1e388004d9182da12bb1f54365c05f463fc784f8a012eb11c949eefc7`.
All **142** source-input hashes match the inspected checkout. Deep strict review
signature verification passes; this is not notarized distribution.

Computer-use inspection verifies:

- The unchanged consent sheet exposes Cancel and Enable. Its fresh inert Enable
  action changes to Observing · shadow mode without claiming live activation.
- A stale consent attempt correctly disables Enable and asks for Refresh.
  Cancel and Refresh restore eligibility before a fresh inert enrollment.
- Pause changes to Paused/Resume; Resume returns to shadow. Both enrolled rows
  show the three compact controls together with full accessible action names.
- Leave opens the existing confirmation. Cancel preserves enrollment; confirmed
  inert Leave returns to Off and Enable becomes available again. The diagnostic
  records **one enrollment and three policy actions** (Pause, Resume and Leave).
- Light active-mode presentation qualifies coordinator control, and the dashboard
  retains the full action labels.
- A failed synthetic read retains “Last known: Actively managing,” disables Pause
  and Leave, and keeps Refresh available. Refresh with the same unavailable
  source preserves those guards; missing data does not become an active claim.
- The review finishes in a dark synthetic shadow-mode popup, with its status,
  explanation, all three controls and enrollment feedback visible.

`native/` retains before/after PNGs and accessibility snapshots. The final usable
layout is `native/final-shadow-dark.png`; inert action counts are in
`fixture-autopilot-proof.json`.

## Confirmation capture limitation

Both baseline and candidate Leave-alert captures return blank pixels while their
accessibility text and actions remain available. A human visual check was asked
while the candidate dialog was open; no answer arrived during this checkpoint.
The dialog's rendered appearance remains **unaccepted**. Previous separate
AppKit/minimal-SwiftUI reproduction evidence is retained in the broader plan;
this label change does not bypass that unresolved visual boundary.

## Verification and delivery

- `swift test -c release --no-parallel`: exit 0; **1,862** reported app tests in
  234 suites plus **21 + 28** Companion tests. Seven existing opt-in tests skip.
- 49 staging checks pass.
- Regular `swift build -c release`: exit 0, 53.37 seconds.
- Independent read-only source review: no actionable findings.
- Protected concurrent `Tests/NativeUI/MenuBarMotionProof.swift` remains
  `ca10cb20271d1bd5fafec801d0ed5fcb17377a0f8812132366aa2ece462db50d`.
- Real provider configuration remains
  `e081909a3b2db8b1453e87efe30ca77322476b3d4ea16ff9ee8872447114093f`.
  Installed Bloomy PID 7234 and the existing real provider remain running.

This presentation change uses existing regression checks and native interaction
proof, not mirror tests of labels. Actual VoiceOver, large text, every constrained
path, normal-speed runtime/motion, sustained resource qualification, confirmation
pixels and distribution gates remain open. The previous review app was quit
normally; the isolated candidate remains open for inspection.

This is a local-only checkpoint. No real provider action, configuration write,
installed replacement, push or release occurred. The continuous polish goal
remains active.
