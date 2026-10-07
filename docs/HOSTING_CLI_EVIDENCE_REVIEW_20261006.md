# Hosting CLI evidence review — October 6, 2026

Hosting now distinguishes a confirmed old CLI from a missing or malformed
version reading. Unknown evidence shows “CLI version unavailable” with a
question-mark icon and Refresh guidance. A confirmed version below 0.9.7
retains the update warning. Supported versions have no capability notice.
Unknown and old versions still block provider Apply and Terminal-command Copy.
The minimum version, acquisition cadence and dispatch rules are unchanged.

## Verification

- The new unknown-version regression failed before the fix. The red run's
  nine assertions covered misleading update guidance, missing capitalized
  Refresh guidance and exposing the malformed version canary.
- An intermediate focused run reported two failures because a new test
  incorrectly expected the pure command preview to be absent. The existing
  action gate, not the preview property, blocks copying. The test now checks
  that gate; product command-preview behavior was preserved.
- Final `swift test -c release` passed: 1,599 telemetry/UI tests, 21 protocol
  tests and 28 host tests (1,648 reported total), with seven existing opt-in
  skips. Log: `.build/hosting-cli-evidence-full-20261006.log`.
- The final optimized native fixture compiled and was ad-hoc signed. All 119
  source hashes match the reviewed checkout; executable SHA-256 is
  `266fe1167b149009039ccdf8de9b330d812247206abb044459860cdc368a068d`.
  Manifest and immutable sources are in
  `.build/hosting-cli-evidence-native-20261006/`; verification is in
  `.build/hosting-cli-evidence-proof-20261006/source-verification.json`.

## Computer Use observations

The prior October 4 exact-source native fixture reproduced the incorrect
“Update Darkbloom CLI” warning in the Offline scenario. The final fixture's
actual SwiftUI Hosting page was then inspected at the same compact size:

- Offline/light and dark show neutral missing-version guidance.
- Staging a synthetic 0.9.6 response leaves the display unchanged; clicking
  Hosting's actual Refresh changes the notice to the old-version warning.
- Staging 0.9.17 and clicking Refresh removes the notice and enables mode
  selection and Apply. No Apply was used.
- Selecting Local only, then refreshing with malformed evidence, preserves
  the selected mode while disabling it. The Terminal section replaces its
  copyable command with Refresh guidance. The canary is absent from the
  production page's visible text and accessibility output.
- Fresh Overview, Activity/Earnings and Opportunity were also inspected for
  the accompanying product comparison. These are rendered synthetic data,
  not live revenue or routing evidence.

Both task-owned review apps were closed after inspection. The production
provider was not started, stopped, reconfigured or invoked for inference.
The provider configuration hash remains unchanged from the start of the turn;
the PID in the existing daemon-state file is absent. This is bounded review
proof, not completed VoiceOver, production endpoint or distribution proof.
