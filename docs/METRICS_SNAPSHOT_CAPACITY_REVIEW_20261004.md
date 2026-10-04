# Metrics snapshot capacity and native heap investigation

The immutable Metrics snapshot now reserves its sample and row-ID arrays for
the current query membership. Previously, a smaller period or model filter
reserved the prior snapshot's row count. A 24-hour query could therefore keep
space for 100,000 samples after viewing 30 days. Cold reads also grew their
buffers geometrically.

An indexed count shares the row query's predicate and pinned SQLite transaction.
Reservation is capped at the configured history limit, but the row loop still
returns all valid rows. The reuse version fence, field validation, chronological
order, cancellation, recording cadence and visible UI remain unchanged.

This is local optimization work. Installed Bloomy, its provider, models and
credentials were preserved. The popup's committed icon-first common bar and
graphical earnings layout remain in the review source.

## Root-cause evidence

Evidence directory: `.build/metrics-allocation-audit-20261004/`.

- Instruments Allocations attach to the inert baseline stalled before recording.
  After bounded investigation, the exact task-owned xctrace process was stopped
  intentionally. Its incomplete trace is rejected; no privacy change was made.
- Native `heap -s -H --noContent` and `vmmap -summary` succeeded. A visible
  100,000-row baseline had three typed sample arrays totaling about 42 MiB.
  This does not by itself prove three copies of the full history.
- Actual Window → Minimize All was verified from the fixture's native visibility
  diagnostic, without observing/reopening its UI before the heap capture.
  Its snapshot owner released all 100,000 rows. The typed sample-array allocation
  fell to one 256-byte object; repeated model/string-array allocations also
  disappeared. Footprint fell from 278.0 to 149.8 MiB in this particular session.
  Those samples are not comparable production resource windows or leak proof.
- A Release component probe isolated excess capacity: shrinking 100,000 rows
  to 3,457 retained capacity for 100,059 samples before this change.
- An initial regression used a broad interval too short for its test rows; it
  was corrected before production changes. The corrected test failed only its
  five capacity expectations, then passed with this fix.
- An initial probe compared periods using Swift Date filtering and hit a
  one-row boundary difference from timestamp rounding. Final parity uses the
  ordinary validated SQLite reader with the same actual interval and predicate.
  Rejected probes are retained and excluded from the results below.

## Verification and component measurements

All 16 snapshot regressions passed, including field/order parity, narrower
periods, model filtering, empty results, reuse, outside writes, correction,
corruption, cancellation and concurrent atomic corrections.

Full `swift test -c release` passed: 1,588 telemetry/UI, 21 companion protocol,
28 companion host tests; 1,637 reported total, seven existing opt-in skips.
Logs: `.build/metrics-capacity-focused-20261004.log` and
`.build/metrics-capacity-full-20261004.log`.

Three paired optimized runs used one closed synthetic 100,000-row seed and
frozen libraries. Each compares complete samples/order with the ordinary
validated reader. No task-owned build or test ran during these paired runs.
The opt-in program is `Tests/PerformanceBenchmarks/MetricsSnapshotCapacityBenchmark.swift`.

| Read | Rows | Old capacity | New capacity | Old median ms | New median ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Cold 24 hours | 3,457 | 4,681 | 3,510 | 55.46 | 56.97 |
| Expand to 30 days | 100,000 | 112,347 | 100,059 | 1,617.47 | 1,579.06 |
| Repeat 30 days | 100,000 | 100,059 | 100,059 | 80.66 | 80.81 |
| Cold 30 days | 100,000 | 112,347 | 100,059 | 1,187.04 | 1,102.66 |
| Shrink to 24 hours | 3,457 | 100,059 | 3,510 | 4.43 | 4.26 |

With a 224-byte sample stride, shrinking reserves about 21.375 → 0.750 MiB
for the sample array, 96.5% less storage. Cold 30-day sample capacity falls
24.000 → 21.375 MiB. This excludes per-sample strings/arrays, row IDs, lookup
dictionaries, SwiftUI/Charts and allocator retention. The small timing
differences do not establish a speed improvement or regression.

Provenance and raw results are in `capacity-provenance.json` and
`capacity-paired-summary.json` under the evidence directory. Baseline library
SHA-256: `4b98f595192a10522b34bf6ccbf9269dbe50263415090bdb44b455f9afd4dc48`.
Candidate: `abdb41aa22e6d950896cf7ff4b4b2a6695ad001b9eff252b252f9969152d364e`.

## Native candidate gate

The optimized inert bundle is
`.build/metrics-capacity-native-20261004/Bloomy Dashboard Fixture.app`.
All 118 manifest source hashes matched the checkout. Its frozen telemetry
library matches the component candidate. Binary SHA-256:
`8f6626d90c9fecd1b754ca36a325f7d9f874cd38dc34082d19f191933756909d`.

Computer Use verified 100,000 samples, 693h 59m covered, 312h 25m active and
158 visits without observed work totaling 65h 50m. The first switch to 24
hours displayed 2,904 rows; native read diagnostics confirm every row reused.
Manual Refresh then read/reused 2,901 rows. The difference is the moving window
endpoint while synthetic observations were paused, not lost data.

Native heap captures showed about 22 MiB of typed sample arrays both before
and shortly after narrowing. A former large buffer remains temporarily owned
by the mounted SwiftUI graph, so the smaller snapshot capacity is **not** a
claim that all previous buffers disappear immediately on a period change.
The full/narrow footprint readings were 390.4/288.3 MiB in this candidate
session; they are not phase-matched comparisons with the baseline, and no
whole-process improvement is claimed. Remaining graph ownership merits review.

Window → Minimize All was verified as miniaturized, not visible and display
work disabled, using the native diagnostic without a reopening observation.
The snapshot owner released all 2,901 rows and reported zero retained rows.
The heap again had just one 256-byte typed sample array; footprint was
142.4 MiB. Reopening displayed 2,899 rows, with zero reused rows on that first
read, confirming fresh validation after release. The completed summary remained
usable and no false successful-empty state appeared.

Final Computer Use also inspected graphical Activity Earnings in light
appearance and the dense common popup bar/Earnings tiles in dark appearance.
The review app was left open on that synthetic popup for inspection; the
baseline review exited normally. All finite jobs completed. Production resource
profiling, menu-bar motion, VoiceOver and the broader native completion matrix
remain open. No push, release or installation is part of this checkpoint.

The installed Bloomy, provider and recovery watcher PIDs remained running.
Provider configuration SHA-256 remains
`fece43bb93691e7f702d83388428f5ef14dd83755f8e2f48bef140ec1a764eaf`.
