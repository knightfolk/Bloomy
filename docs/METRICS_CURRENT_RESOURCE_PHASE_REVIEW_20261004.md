# Current Metrics resource phases

The reference-owned Metrics build has fresh, bounded process measurements with
100,000 records. No further product optimization was made from these results.
They support quiet minimized behavior in this fixture and establish the cost
of visible periodic work under the named conditions.

## Conditions and results

Native bundle:
`.build/metrics-ownership-reference-native-20261004/Bloomy Dashboard Fixture.app`.
Source checkpoint: `45af0ab`; all 118 recorded source hashes and the binary hash
matched before measurement. Binary SHA-256:
`4f1400fd3e8d15caa664b1324769cfa02f195760fb52490812649ae1fc6b5326`.
The optimized, ad hoc signed fixture links testable telemetry, makes no API
calls and has CPU/GPU acquisition off. It is not a distribution build.

Same process, PID 39314, compact dark Activity → Metrics, 30 days, All models.
Synthetic source publications were paused before all windows. The history is
at its 100,000-record cap. Before pausing, the prior review resumed synthetic
publications into this fixture's own database, so it is not an unchanged copy
of the original seeder. No real history, provider or preferences were modified.

| Window | Seconds | Completed reads | CPU, percent of one core | Median RSS, MiB | Median footprint, MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| Visible A | 45 | 1 | 2.598 | 387.27 | 231.94 |
| Visible B | 45 | 1 | 2.672 | 390.64 | 236.13 |
| Minimized A | 30 | 0 | 0.0112 | 326.02 | 171.03 |
| Minimized B | 30 | 0 | 0.0051 | 271.27 | 115.64 |
| Restored visible C | 45 | 1 | 2.683 | 386.89 | 229.02 |

Every visible window has 46 process/visibility observations; minimized windows
have 31. Each retained the same native visibility event throughout. Native
Window → Minimize All affected only the review window. Evidence confirms
`miniaturized=true`, `windowVisible=false`, `displayEnabled=false`; this Mac
retains the compositor-visible bit while minimized, which is not used to infer
that state. Raw cached rows stayed zero while minimized and returned to 100,000
on restoration. The restored summary rendered 693h 59m covered and the expected
158 visits without observed work/65h 50m.

The first three windows have before/after read counters; Minimized B and visible
C also use the new per-observation read guard below. No build, Swift test,
calibration or UI observation ran during the windows. Other user processes
remained. These measure process CPU/footprint, not energy, battery life,
production collectors or leak-free allocation. Memory includes caches and
allocator effects; the lower later hidden footprint does not identify every
allocation. There is no comparable older shipping-build workload here, so
this table does not establish production-wide savings or close that gate.

## Phase-aware profiling

`Tests/PerformanceBenchmarks/mac-process-metrics.py` accepts optional
`--metrics-read-proof FILE --metrics-read-mode refresh|quiet` arguments.
They consume existing inert read proof, start no app/read and send no UI input.
The caller must supply the measured app's proof and hold the route/filter fixed.
Counters do not independently prove analysis completion or bind a file to a PID.

- Refresh needs a completed nonempty initial scope and at least one started and
  completed read. Quiet gaps and incomplete endpoints cannot qualify.
- Quiet rejects any started/completed read work.
- Each observation rejects counter reset, failed/cancelled/empty outcomes,
  cache releases, row-count or completed-period changes and held test reads.
  Normal in-flight reads may occur within a refresh window if they complete.
- Existing visibility/process guards remain independent. Rejection creates no
  accepted metrics JSON. Preserve evidence by using fresh output paths.

Eleven Python regressions pass: complete/pending/quiet phases, errors,
cancellation, empties, releases, changed scope, reset, invalid counters, held
reads and output ownership. Native CLI checks reject refresh against released
hidden rows and an unpaired proof argument, without accepted output. Integrated
native quiet/refresh modes pass in the last two windows. Mach conversion
calibration passes: 0.9956399 converted seconds versus 0.995646 getrusage seconds.

Evidence is `.build/metrics-current-profile-20261004/`: process samples, read
endpoints, negative checks, calibration, visibility events, hashes and summary.
Regression command:
`python3 -m unittest discover -s Tests/PerformanceBenchmarks -p test_metrics_read_phase.py`.
No Swift product code changed; its prior 1,637-test Release checkpoint remains
separate from these Python/native checks. All finite profiles/calibration ended.
Installed Bloomy, provider, recovery watcher, models and credentials were
preserved. No push, install or release occurred. The broader goal stays open.

## Next observed UI issue

This follow-up is now verified in
[the recorded-caption review](METRICS_RECORDED_CAPTION_REVIEW_20261004.md).

When recording ages, the main Metrics label correctly says “Waiting for fresh
measurements,” but its timestamp caption appends stored quality “current.” This
describes source quality when recorded, rather than current freshness. Clarify
that caption in a separately native-verified UI change without moving analysis
windows or adding a timer. The observation does not show that live recording or
the existing 90-second expiry calculation is wrong.
