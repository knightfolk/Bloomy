# Earnings keyboard and value review — October 2, 2026

This checkpoint advances the ongoing polish plan. It does not complete the full
app, accessibility, performance, or distribution review.

## Changes

Earnings uses the existing native focus-reveal anchor and a focus section for
its period, date fields, filters, chart choices, disclosures and history table.
The model choices use an eager adaptive layout: equal widths, a 190-point cap,
and no historical-model limit. Hosting retains its existing uncapped behavior.
The filter group contains individually named accessible buttons. A small inset
keeps the About disclosure's native focus ring inside the detail viewport.

Empty results show native “No recorded activity” guidance. Unknown buckets remain
unknown. Recorded-zero chart intervals receive one aggregate marker and a legend
cue. Scalar Area runs use points rather than invisible AreaMarks; contiguous
zero endpoints remain in genuine multi-point areas. Micro-dollar table amounts
use Decimal formatting with four to six fractional digits, equal amount-column
widths, tabular digits and full-value hover help. No timer or provider action was
added.

## Rejected and intermediate observations

- Native123: Tab focuses the offscreen table without scrolling to it.
- Native124: anchors reveal the table, but reverse traversal skips its preceding
  controls. Empty history shows a blank chart with dollar axes.
- Native125: a focus section retains chart controls; the lazy grid still drops
  model choices from reverse traversal.
- Native126: eager choices restore both directions, but the group label overrides
  each model's accessible name. Tiny table values round to zero.
- Native127: individual labels and zero markers work; About's ring clips at the
  sidebar edge.
- Native128: the inset fixes that ring. The compact Work column truncates exact
  tiny values. Isolated zero Area readings pile numbered badges onto each other,
  and automatic chart descriptions span unknown gaps.

These retained candidates are comparisons, not final admission evidence.

## Native129 observations

The final isolated app matches all 100 source manifest hashes. CUA inspected the
production views with inert data and isolated preferences:

- Compact light empty history visibly shows its native empty state and explains
  that missing history is not zero earnings.
- Compact light recorded-zero Area shows eight separate gray markers, with no
  overlapping numbered badges. AX lists the eight recorded periods with zero
  amounts; the prior “entire time” descriptions across unknown gaps are absent.
- Wide dark tiny Area visibly separates four shaped, numbered series. The table
  shows `0.000003` work and `0.000001` rewards with unknown rows left as dashes.
- Compact dark shows those complete amounts without truncation. Selecting Qwen
  shows `0.000001` work, one job and unavailable throughput; base rewards are
  excluded.
- Actual compact dark Tab reaches period, Refresh, all five model/reward choices,
  Measure, Chart, Layout, About and table. Table focus reveals its viewport.
  Shift-Tab returns through every preceding choice to Refresh. About's complete
  native ring is visible. Native128 additionally records compact light traversal
  and the inset comparison before the final chart/column edits.

Tiny Area's automatic AX summary still groups point ranges. Individual spoken
point values and gap interpretation need actual VoiceOver review; the rendered
points alone do not establish that requirement.

## Verification and provenance

Final `swift test` passes: 1,400 app/telemetry tests in 185 suites, 21 protocol
tests and 28 host tests, or 1,449 reported tests including the intentionally
skipped opt-in focus regression. The shared focus helper was unchanged. Tests
cover eager mounting of 5 and 30 choices, adaptive width bounds, exact Decimal
amounts including Int64.max, zero/gap/signed-cancellation distinctions, scalar
Area exclusion and contiguous zero retention, plus existing rendering/data
checks. Log: `/tmp/bloomy-earnings-area-final-tests-20261002.log`.

Final Release compilation passes in 47.00 seconds. Log:
`/tmp/bloomy-earnings-area-final-release-20261002.log`.

Artifact: `.build/native-dashboard-fixture-20261002-129/Bloomy Dashboard Fixture.app`.
Binary SHA-256:
`6df6751c77a82379fe1fe4c0ad755166c895ca70a6129bb374923029b5a9fde6`.
Linked telemetry SHA-256:
`0da0aed0eee0f3ace173ccbcbc1b413cc64f7d4f1ec2d78658e059fff593d102`.
Only the builder's existing CLI-update, CPU-reader and network-cache inert
substitutions apply. This is a review-signed fixture, not distribution evidence.

Remaining proof includes conditional date/average controls, readonly table key
scrolling, larger native histories, all-unknown/negative states, sustained
publication and pending-read focus retention, VoiceOver, other displays and
comparable performance/energy measurements. `ActivityView.load` still clears
completed results on refresh; retaining a truthful completed scope through slow
or failed reads is the next priority. The installed production app and provider
were preserved. No new release was installed or published.
