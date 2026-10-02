# Metrics refresh and background-cost review — October 2, 2026

This checkpoint advances the ongoing polish/efficiency goal. It does not prove
complete native accessibility, final whole-app performance, or release readiness.

## Correctness and scheduling change

Metrics previously keyed analysis by period, model, sample count, last sample ID
and the minute label clock. A successful manual read could replace a middle row
without changing the count or last ID, leaving the summary stale until that clock
advanced. The clock also launched full analysis independently of disk refresh.

A successful read now publishes its rows, ending time and generation together.
Every successful read, including explicit Refresh, causes analysis; failed or
cancelled reads preserve the preceding result. The minute clock updates freshness
labels without scheduling analysis. Rolling clipping uses the successful read's
endpoint at the existing 30-second visible refresh cadence. Model/period changes
and reopening still trigger work immediately; hidden views retain cancellation.
Value-driven review content advances to its latest observation without following
label-only time changes.

Six new regression tests exercise changed middle-row measurements with retained
IDs, unchanged successful reads, failed/cancelled reads, clock-only updates,
new value-driven observations, filter/visibility keys and rolling-window clipping.
They compare actual summary/chart/visit results, not just the task identifier.

## Installed-app observation

The existing installed Bloomy was left running at version 1.9.15/build 140,
source `6a6c583`, with Activity → Metrics → 24 hours visible and 1,365 samples.
The provider and watchdog stayed stopped. A 30-second process CPU-time delta
measured **5.132% of one CPU core**; RSS stayed at **227,152 KiB**. Instantaneous
CPU readings ranged from 0 to 31.6%, so the earlier 25.3% point reading was a
transient spike rather than a steady cost.

A three-second, ten-millisecond process sample showed the main thread waiting
for most samples. Active background stacks included uptime SQL, Metrics visit/
summary validation and legacy log parsing. Current source already includes the
uptime and log-parser improvements described in
`BACKGROUND_HISTORY_OPTIMIZATION_20261002.md`; the installed binary lacks them.
Neither this sample nor the isolated benchmarks establish current-source app
CPU improvement. The installed app, its windows and user state were preserved.

Raw evidence is retained in `/tmp/bloomy-efficiency-20261001/`:

- `stopped-provider-installed-sample-20261002.txt`
- `stopped-provider-installed-cpu-20261002.json` (instantaneous readings)
- `stopped-provider-installed-window-20261002.json` (CPU-time delta)

## Isolated history benchmark

`Tests/PerformanceBenchmarks/HistoryReadBenchmark.swift` uses synthetic rows and
the release-optimized telemetry library. It seeds SQLite in one transaction,
validates the production read results, then separates read, summary and visit
costs. The first read follows in-process seeding, so SQLite and filesystem
pages may already be warm; it is not a cold-cache measurement. It keeps
chronological model switches and stale/unavailable boundaries.
Three repeated reads must return every sample identically. Fifteen new inserts
also exercise the 100,000-row retention ceiling.

| Rows | First read after seed | Repeated-read median (3) | Read after 15 inserts | Summary | Visits |
| --- | ---: | ---: | ---: | ---: | ---: |
| 10,000 | 61.85 ms | 60.10 ms | 62.54 ms | 12.89 ms | 47.32 ms |
| 100,000 | 605.91 ms | 611.23 ms | 612.92 ms | 128.91 ms | 468.01 ms |

These are component timings, not full Metrics rendering or app CPU. The mixed
synthetic inputs differ from earlier visit benchmarks; do not compare them as
a before/after result. The benchmark retained baseline and updated arrays for
equality checks; its 131,006,464-byte peak RSS is not a database-cache estimate.
No decoded-row cache has been added. Such a cache needs demonstrated benefit,
bounded retained memory and authoritative invalidation for external changes,
out-of-order rows, tied timestamps, corruption and manual Refresh.

Reproduce after a release build, choosing a fresh output directory:

```sh
swiftc -O -I .build/out/Products/Release \
  Tests/PerformanceBenchmarks/HistoryReadBenchmark.swift \
  .build/out/Products/Release/libDarkbloomTelemetry.a -lsqlite3 \
  -o /tmp/bloomy-history-read-benchmark
/tmp/bloomy-history-read-benchmark /path/to/fresh/synthetic-output
```

This run used `/Volumes/Sol/BloomyReview/metrics-history-20261002-01` for disposable
SQLite outputs. Results are in `history-read-benchmark-20261002.json` beside the
process evidence. No real history, credentials, request contents or model files
were copied into the benchmark.

## Verification and next evidence

The focused Metrics/history suite passed 61 tests in five suites. The complete
suite passed **1,159 tests**: 1,110 app/telemetry, 21 companion and 28 host tests.
The release build completed in **37.49 seconds**. Logs are retained beside the
process evidence as `metrics-read-generation-focused-tests.log`,
`metrics-read-generation-full-tests.log` and
`metrics-read-generation-release-build.log`.

Root inspected the exact build-13 native synthetic app. All 76 source hashes,
the executable and linked debug telemetry library matched its saved manifest.
Native checks covered 24-hour/7-day/30-day periods, a single-model filter,
manual Refresh, the no-work visit filter and Earnings → Metrics reopening.
Refresh retained the chosen Gemma/30-day filters and updated the read status.
Gemma summaries marked provider-wide request/token totals Unknown; All models
restored the fixture's 115 requests and 103,800 tokens. The no-work filter
isolated Bonsai's completed 1m 30s visit. The compact 800 × 560 dark view fit
its period/model controls and consistent summary cards, and the visit row/chart
remained readable while scrolling. Reopening performed a fresh read and reset
the view's filters to their existing 24-hour/All-model defaults. This is bounded
fixture proof, not live traffic, every appearance/state or production performance.
Native minimize visibility forwarding is not provided by this fixture; hidden
read/analysis cancellation is covered by the focused tests and still needs
production-window observation. Quit exited the fixture; the installed app was
preserved and the provider/watchdog remained stopped with unchanged config.

The next comparable process measurement needs the current production source,
the same retained history and stopped-provider conditions. The production Sol
cache permission boundary still holds that launch/release gate; no permission
reset, installed-app replacement or provider activity was used for this review.
