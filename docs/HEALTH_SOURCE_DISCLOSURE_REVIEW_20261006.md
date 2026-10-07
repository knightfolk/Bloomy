# Health source disclosure review — October 6, 2026

Source freshness now groups four concise source/status rows. Stale and
unavailable rows use native disclosures for their complete diagnostic reasons;
stale details also show the last capture time. Successful reads retain their
qualified capture timestamp. Color is limited to status labels rather than
entire diagnostic paragraphs. Expanded details remain selectable.

The change adds no acquisition, timer, provider operation or preference write.
Existing source availability and warning rules are unchanged.

## Evidence

- Before-state: the October 6 Hosting fixture displayed four lengthy red
  diagnostics in the missing-source scenario. Expanded missing verification
  and daemon sections remained reachable in compact light and dark.
- A hosted regression checks constrained 300- and 540-point row widths:
  collapsed long diagnostics stay compact, while expanded content gains its
  required height without horizontal overflow. Existing Health rendering
  tests still confirm that views neither acquire CLI data nor alter the
  supplied snapshot.
- The first sizing test mistakenly measured unconstrained intrinsic text
  width. Its four failed assertions were corrected by imposing the actual
  test viewport; no product size or acceptance bound was relaxed.
- The first native candidate looked correct, but its explicit accessibility
  value caused the successful-read output to omit source names. That candidate
  was rejected. Removing the redundant value restored the named status text;
  full reasons remain in accessibility help and expanded text.
- Final full Release verification passed: 1,600 telemetry/UI tests, 21 protocol
  tests and 28 host tests, **1,649 reported total**, with seven existing opt-in
  skips. Log: `.build/health-disclosure-full-final-20261006.log`.

## Final native inspection

Computer Use inspected the exact-source optimized `r2` fixture:

- Fresh compact/light accessibility output includes all four source names and
  their capture timestamps.
- Mixed compact/light and dark distinguish captured, stale and unavailable
  rows. Stale expansion exposes both the last capture and full two-paragraph
  reason; scroll reaches the complete content.
- Wide/light displays the full hierarchy. A second unavailable row expands
  independently without collapsing the stale row or inventing a capture time.
- Open details survive appearance and size changes and subsequent synthetic
  source updates. This is bounded observed behavior, not comprehensive motion
  or spoken VoiceOver proof.

Final bundle: `.build/health-disclosure-native-r2-20261006/Bloomy Dashboard Fixture.app`.
All 119 manifest source hashes match the checkout. Executable SHA-256:
`bbcece1a54727715d3544f536a7f123c406d66e92d70843a1fd25312761949cb`.
Verification: `.build/health-disclosure-proof-20261006/source-verification.json`.

All task-owned review apps were closed. The provider configuration hash is
unchanged, and its previously absent daemon PID remains absent. No provider
start, swap, nudge, download or credential change occurred.

The overall Health route and application remain partial. Actual VoiceOver,
broader source transitions, large-text/display settings and production resource
and distribution proof remain open.
