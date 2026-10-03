# Resource, visibility and privacy checkpoint

The log redactor now shares six immutable compiled expressions. The order,
patterns, normalization and fail-closed behavior remain unchanged. Frozen
`8db49ec` reference implementations compare all retained event fields, including
concurrent readers; there is no cache of unredacted incoming text.

The dashboard now derives display visibility from native window visibility,
application Hide, minimize and compositor exposure notifications. Close is
latched until explicit presentation. This controls display reads only;
monitoring, recording and provider actions retain their separate lifetimes.

## Checked evidence

Before subsequent GPU-protection feature work, the full suite passed with 1,482
reported tests (seven explicit opt-in skips), and Release compilation passed in
35.50 seconds. Logs: `/tmp/bloomy-resource-final-tests-20261003.log` and
`/tmp/bloomy-resource-final-release-20261003.log`. Focused privacy, visibility
and window checks passed with 23 tests. An independent read-only review found
no concrete defect in privacy parity or observer lifetime/notification ownership.

The Release log-tail benchmark replays 100 fictional events per read, 20 reads
per repetition, five repetitions, alternating reference/current timing order.
It checks exact full retained-array parity before and after every repetition.
It measures warm component processing, not whole-app CPU or energy.

| Tail | Reference median ms/read | Cached median ms/read | Ratio |
| --- | ---: | ---: | ---: |
| Ordinary | 11.446 | 2.041 | 5.61× |
| Warning/path/URL | 11.969 | 2.509 | 4.77× |
| Sensitive withheld text | 10.093 | 1.411 | 7.15× |

Raw result: `/tmp/bloomy-resource-20261003/event-privacy-benchmark.json`.

## Native behavior and bounded profiling

Native139 establishes the actual Hide bug: `applicationHidden=true` while
`displayEnabled=true`; four further Metrics reads completed over 126 seconds.
Native141 attaches the same observer as production. It was built before the
GPU-protection additions: all 102 staged source hashes and the telemetry archive
matched at build, and executable SHA256 was
`d9563f7b4db3c9d86366e6254a33154aa040ed623d9aa5aa900754ffc88a6e27`.

In Native141, Hide disabled display work within the native notification sequence.
Read counters stayed at three through a 114-second hold while synthetic history
continued growing to 367 rows. Restoration immediately read the latest rows.
Minimize similarly disabled display work; five reads stayed five for 216 seconds,
history grew to 376 rows, and restoration immediately completed read six.
The restored compact light Metrics screen was inspected. Normal Quit removed
the fixture process; installed Bloomy PID 61760, start time and executable hash
remained unchanged. Neither fixture starts the real provider or autonomous
CPU/GPU samplers.

The read-only process sampler calibrates Mach absolute CPU counters against
`getrusage`, following [Apple XNU's counter conversion](https://github.com/apple-oss-distributions/xnu/blob/main/tests/recount/recount_perf_tests.c).
On this Mac the timebase is 125/3; calibration produced 0.9989995 seconds versus
0.999008 seconds from `getrusage`. Earlier raw reports that assumed nanoseconds
were superseded by explicitly derived `*-calibrated.json` files.

| Inert Debug fixture / 30-second window | CPU percent of one core |
| --- | ---: |
| Native139 hidden, old visibility behavior | 1.131 |
| Native141 visible Metrics | 0.860 |
| Native141 hidden Metrics | 0.507 |
| Native141 minimized Metrics | 0.598 |

These short windows share Debug view/telemetry compilation and the synthetic
history scenario; differing row counts, normal system activity and allocator
state limit causal comparison. They do not establish production CPU, energy,
battery savings or a memory leak. Raw snapshots, visibility sequences and read
counters are in `/tmp/bloomy-resource-20261003/native141-*.json` and the retained
fixture temp directory. Native140 failed to compile because its optimized
telemetry module did not enable `@testable` fixture constructors; it was never
launched. Native141 retains the comparable Debug configuration.

## Reproduction and open scope

```sh
swiftc -O -swift-version 6 -I .build/out/Products/Release \
  Tests/PerformanceBenchmarks/EventPrivacyBenchmark.swift \
  Tests/PerformanceBenchmarks/EventBufferPrivacyReference.swift \
  Tests/DarkbloomTelemetryTests/EventPrivacyReference.swift \
  .build/out/Products/Release/libDarkbloomTelemetry.a -lsqlite3 \
  -o /tmp/event-privacy-benchmark
/tmp/event-privacy-benchmark
python3 Tests/PerformanceBenchmarks/mac-process-metrics.py --self-check \
  --output /tmp/fresh-timebase-calibration.json
python3 Tests/PerformanceBenchmarks/mac-process-metrics.py --pid PID --seconds 30 \
  --label visible-metrics --output /tmp/fresh-process-window.json
```

Keep fresh output paths and an unchanged process identity. Private provider
logs are never benchmark inputs. Actual fully covered-window compositor proof,
larger-history profiling, comparable production monitoring measurements,
VoiceOver, system motion propagation and distribution gates remain open. This
checkpoint does not complete the broader polish/optimization goal.
