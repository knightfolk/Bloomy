# Metrics recorded-quality caption

Metrics no longer appends an unqualified “current” quality word to an old
observation. The timestamp now reads “Observed … · current when recorded,”
with corresponding stale/unavailable wording. The main recording label still
uses its existing 90-second live-freshness check. The shorter timestamp prefix
keeps the qualification compact. No timer, read, analysis or persistence changed.

## Native verification

The isolated optimized review app is
`.build/metrics-recorded-caption-native-20261004/Bloomy Dashboard Fixture.app`.
All 118 manifest source hashes and its executable matched the checkout.
Binary SHA-256:
`0417f9c559a9343f56cb5e52d9a55499633f00ce59f82df447d6ba5955c81c7c`.
It uses synthetic services and the existing inert dependency substitutions,
with acquisition off; ad hoc signing is not distribution proof.

Computer Use checked the 800 × 560 view:

- Fresh, light: “Recording locally” and “current when recorded,” on one line.
- Real expiry with synthetic publications paused: the same stored current
  observation ages beyond 90 seconds. A read-only database check records an
  age of 109 seconds before the UI inspection. The main label changes to
  “Waiting for fresh measurements” while the caption remains qualified.
  The aged state fits in both light and dark without timestamp clipping.
- Dark stale: the normal fake source publications record stale samples, and
  the rendered caption says “stale when recorded.”
- Dark unavailable: the caption says “unavailable when recorded.” Actual
  Refresh advances the captured timestamp/sample count and keeps that qualifier.
  The longest caption fits beside the separate sample-count/Refresh row.

The last two cases use Health long mixed/missing, whose normal fake publications
record those qualities. The plain Stale selector seeds fresh historical samples
and suppresses new publications; its initial current row does not exercise
the stale-record branch. That preliminary inspection is not a product failure
or accepted stale-caption proof.

Read-only quality/time evidence and source hashes are retained under
`.build/metrics-recorded-caption-proof-20261004/`. Raw source text and credentials
were not collected. The native tool observations are in this task's UI history.

## Checks and handoff

All 24 PerformanceMetricsViewTests pass. Full `swift test -c release` passes:
1,588 telemetry/UI + 21 protocol + 28 host reported tests, 1,637 total;
seven existing opt-in checks skip. Logs:
`.build/metrics-recorded-caption-focused-20261004.log` and
`.build/metrics-recorded-caption-full-20261004.log`.
Native compilation and `git diff --check` pass. No mirror test was added for
this wording-only change; the existing freshness/scope tests remain intact.

All finite checks ended. The old owned review process quit normally; the new
review host remains available for inspection. Installed Bloomy, provider,
recovery watcher, models and credentials were preserved. No push, installation
or release occurred. This bounded fix does not complete the broader native,
production, accessibility or motion matrix.
