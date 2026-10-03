# Earnings model identity and profit aggregation — October 2, 2026

Selected-model stacked bars now consume the same resolved observations as Lines
and Area. A totals-only client retains the queried model's name and color; a
recorded model zero stays zero rather than becoming positive aggregate Work.
The color domain also includes a retained selected model absent from the current
period's model list. Aggregate-only history still uses Work and Base rewards:
this change does not invent model attribution.

Stacked rendering reuses already resolved chart values instead of repeating the
attribution transformation. Profit aggregation now visits each filtered hourly
record in original input order, locates ordered disjoint calendar buckets by
binary search, and stores a sum/count per model/bucket. Generic containment
remains for unordered, overlapping, duplicate or zero-length intervals. The
original finite filter, mean, signed/zero/missing values, sorted model output and
bucket-index gap runs remain unchanged. Production calendar logic does not
assume that a day is 86,400 seconds.

## Correctness and measurements

The selected-model regressions first failed for generic Work identity and for
positive fallback replacing an explicit zero. Their repaired focused pass runs
45 tests across Activity chart/style/view suites.

Profit tests compare exact output with a frozen copy of the old algorithm:
original-order floating-point means, duplicate weighting, selected/absent model,
full containment and crossings, gaps, signed and nonfinite data, overflow,
custom bucket shapes and actual 23/25-hour daylight-saving days. The six-test
Release run including the opt-in benchmark passes. A separate read-only native
worker reviewed the optimization and tests with no concrete findings; it did
not run tests or inspect visual behavior.

The isolated Release benchmark warms both implementations, alternates five
runs each and verifies exact output equality after every timed run. Medians:

| Synthetic history | Old reference | Optimized | Speed ratio |
| --- | ---: | ---: | ---: |
| 366 days, 1 model, 8,784 rows | 19.278 ms | 0.908 ms | 21.2× |
| 366 days, 8 models, 70,272 rows | 162.916 ms | 7.087 ms | 23.0× |
| 24 hours, 8 models, 192 rows | 0.066 ms | 0.040 ms | 1.7× |

The separate baseline run measured the unchanged production implementation at
19.967, 160.608 and 0.063 ms respectively, comparable to its old reference.
These are pure aggregation timings on this Mac, not whole-app CPU, allocation,
energy, storage-read or render measurements. No timing threshold is a test gate.
The 366-day synthetic benchmark uses fixed UTC-style day widths only to generate
its input; daylight-saving correctness has a separate actual-calendar test.

Logs:
- `/tmp/bloomy-earnings-model-identity-red-20261002.log`
- `/tmp/bloomy-earnings-model-identity-focused-20261002.log`
- `/tmp/bloomy-profit-aggregation-baseline-release-20261002.log`
- `/tmp/bloomy-profit-aggregation-optimized-release-20261002.log`

## Final and native verification

The full debug run passes: 1,418 app/telemetry tests in 187 suites, 21 protocol
and 28 host tests, totaling 1,467 reported tests with seven opt-in checks skipped.
Log: `/tmp/bloomy-activity-identity-profit-final-tests-20261002.log`.
The final Release compile passes in 61.67 seconds; log:
`/tmp/bloomy-activity-identity-profit-final-release-20261002.log`.

Native132 is an inert review-signed app at
`/Volumes/Sol/CodexReview/Bloomy/native-dashboard-fixture-20261002-132/Bloomy Dashboard Fixture.app`.
Sol was chosen because internal free space is below 100 GiB. CUA screenshots
and native state verify:

- Compact light selected-Qwen stacked bars are orange, with `1 Qwen 3.8 · 27B`
  in the legend and canonical `qwen3.8-27b` in the chart accessibility values.
  The former Native131 fallback used generic cyan Work for this same totals-only
  fixture path. Values still range from 0.15 to 0.33 USD; rewards are excluded.
- Wide dark Bars, Lines and Area keep that orange palette and model legend.
  The selected model chip matches the chart color.
- Wide dark All models still displays cyan Work and gold Base rewards for
  aggregate-only history, with the same 0.0200 USD reward table values.
- Wide dark zero/gap data displays eight recorded-zero markers separated by
  unknown intervals. The table distinguishes 0.0000 Recorded from — Unknown.
- The fixture quit normally; its process is absent. Production remains PID
  61760 with its original October 2 12:55:28 launch and executable hash
  `5d692f240c9548f05350f2fb39d05eb15d00741ad7e9f317e3eeb8507e7c50c7`.

The builder completed and wrote the manifest, using its existing three inert
substitutions and excluding production startup. **Post-build manifest hash
readback is unconfirmed:** two Python readers and a bounded `head` read stalled
opening the Sol manifest. A one-second process sample shows the first reader
blocked in `__open`; stat succeeds and no native permission prompt was visible.
The three task-owned readers were terminated and their tool sessions joined.
No privacy setting was reset. Preserve the review artifact; do not infer this
stall's cause or call source checksum equivalence verified.

Build log: `/tmp/bloomy-activity-identity-profit-native132-20261002.log`.
Diagnostic: `/tmp/bloomy-native132-manifest-read-sample.txt`.
This checkpoint is not a distributed app or complete whole-app polish proof.
Production, provider, cache, credentials and unrelated work remain protected.
