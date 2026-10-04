# Common popup bar: cooling posture

This follows the visual Earnings and shared popup header checkpoint in
[Earnings and command bar review](EARNINGS_POPUP_COMMAND_BAR_REVIEW_20261003.md).
The earlier compact Cooling entry always preferred measured RPM. Native review
of the exact previous fixture reproduced a disabled helper displaying only
54°C and 2200 RPM, although its accessibility description said Helper off.

The compact entry now prioritizes helper posture when disabled, in error or
unknown. A confirmed healthy helper keeps the short temperature/RPM treatment.
Errors use an orange warning symbol and Needs attention. Numeric sensor values
remain in accessibility output, with independent freshness qualifiers. Retained
helper temperature is shown as Last 54°C; current diagnostic temperature can
remain 42°C while the helper's retained fan reading is qualified separately.
Missing data stays unavailable rather than becoming zero. This reuses the
existing thermal freshness presentation and adds no polling or provider calls.

## Verification

- Focused first check: 29 tests in four suites passed. The final full run reports
  1,554 telemetry/UI tests, 21 companion protocol tests and 28 companion host
  tests passing (1,603 total reported), with seven existing opt-in skips.
- The first fixture compilation exposed an actor-isolation warning. The
  presentation is now explicitly on the main actor; the final fixture and test
  logs have no new warning. Final Release compilation passed.
- Exact fixture: `.build/popup-cooling-posture-native-final-20261003/`.
  All 113 manifest source hashes match the checkout; its executable SHA-256 is
  `cc0a1819eb9e647305ee60f251a4339d2f59feb51756c0a6dbbfa95a4ffbcb72`.
- Native CUA screenshots and accessibility inspection confirm Helper off in
  light and dark; orange Needs attention despite numeric RPM; Last 54°C and
  Check helper for expired helper evidence; current 42°C with retained fan
  evidence in partial cooling; Cooling — / Unavailable for missing settings;
  and normal 54°C / 2200 RPM for healthy evidence. No text clipped in these
  normal-height popup states.
- The error entry opens Cooling. Refresh readings remains reachable and updates
  its synthetic read timestamp; Done returns to the popup. All changes to
  scenarios and reads are inert. No fan configuration, inference, restart,
  enrollment or real provider policy action was made.
- The healthy dark review popup is left open. Installed Bloomy remains
  1.9.18/build 143, PID 54773. Real provider PID 47646 still advertises exactly
  Qwen 3.8 and Gemma 4; fresh daemon evidence reports Autopilot shadow mode.
  Provider configuration SHA-256 remains
  `fece43bb93691e7f702d83388428f5ef14dd83755f8e2f48bef140ec1a764eaf`.

Earlier fixture output is retained as compiler provenance. Unrelated menu-ring
diagnostics and user files are preserved. This is a local checkpoint, with no
push, release or installed-app replacement. Spoken VoiceOver, wider display and
large-text states, live account integration, menu-ring motion and the broader
polish/efficiency matrix remain open.
