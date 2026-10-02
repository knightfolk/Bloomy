# Background history checkpoint — October 2, 2026

The provider and recovery watchdog stayed stopped for this work. No real model, network nudge, download, credential, permission change or production configuration write was needed. The installed production app remains separate from the source checkpoint.

## Observed uptime

Previously, every source publication inserted an observation, pruned old rows twice, selected the rolling history and allocated/folded that complete array. State/models publish roughly every two seconds, logs every five seconds and status every thirty seconds. The October 2 read-only production count was 97,192 observations spanning 24 hours; it is a point-in-time count, not a fixed database limit.

The actor now bootstraps sorted observations and cumulative online/offline durations once. Chronological writes extend the tail; snapshots binary-search and clip the two rolling-window boundaries. It still persists each observation in the existing schema. It compacts expired entries and rebases duration totals. Duplicate latest timestamps update the tail; older timestamps or another connection's writes invalidate/rebuild the aggregate. SQLite step errors throw instead of returning a partial history.

The definition is unchanged: online/offline classified coverage, at most ten seconds carried forward from an observation, unknown and long gaps excluded, five classified minutes before publishing a percentage, rolling 24-hour window and persisted restart history.

Actual actor benchmark, same debug configuration, 50 chronological records after one bootstrap:

| Persisted rows | Before median / p95 | After median / p95 |
| ---: | ---: | ---: |
| 1,000 | 0.200 / 0.211 ms | 0.028 / 0.030 ms |
| 10,000 | 1.766 / 1.825 ms | 0.018 / 0.027 ms |
| 106,000 | 18.427 / 20.257 ms | 0.019 / 0.043 ms |

The 106,000-row bootstrap still takes about 15.5 ms. Cache entries occupy approximately 3.2 MiB plus spare array capacity. These are inert SQLite measurements, not total app CPU, resident-memory or energy measurements. The opt-in scaling test contains no speed assertion.

Evidence: `/tmp/bloomy-uptime-baseline.log`, `/tmp/bloomy-uptime-optimized.log`, `/tmp/bloomy-uptime-optimized-isolated.log`. Tests include a 1,000-step reference oracle with mixed records, snapshots and reopening, duplicate timestamps, clock rollback, external connections, storage failures and a 5,000-record bounded-cache check.

## Legacy log selection

Parsing now visits lines from the tail until it has the requested count of qualifying lifecycle/warning/error events, then restores file order. One per-call date formatter replaces one formatter per matching line. The lifecycle keyword set is immutable and shared; mutable date formatters are not shared between concurrent calls.

A standalone release-optimized benchmark compiled the original and updated production parser source with the same event definitions. It used a synthetic 129,789-byte warning-heavy tail, selected the latest 100 events, checked their first/last messages and took 25 samples:

| Parser | Median | p95 |
| --- | ---: | ---: |
| Original | 127.07 ms | 142.17 ms |
| Updated | 5.34 ms | 6.51 ms |

Evidence: `/tmp/bloomy-efficiency-20261001/log-selection-benchmark/results.json`. Quieter logs may show a smaller benefit. Selection tests cover intervening noise, invalid dates, file ordering, long tails and nonpositive limits; existing lifecycle/privacy/stream tests remain applicable.

## Verification and remaining work

The full Swift suite reported success in its three batches: 1,096 app/telemetry checks, 21 companion protocol checks and 28 host checks. Opt-in live network/adapter and benchmark checks remain skipped in the normal suite; the uptime benchmark was run separately with its opt-in flag. The release build passed in 41.51 seconds with two build jobs. No provider start was required.

This is a focused source checkpoint within the ongoing native polish and efficiency goal. It does not establish all-screen visual approval or comparable live-provider CPU/energy improvements. The broad native review and release's external-drive catalog gate remain separate.
