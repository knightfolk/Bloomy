# Model-visit observation preparation

The visit analyzer now classifies each original observation once. Private
immutable facts retain validity, freshness, the selected resident, sole
residency, direct work, known inactivity and an explicitly empty slot. Traversal
holds only the current and previous facts; it adds no history-sized preparation
array or persistent cache. Existing visit-builder storage remains unchanged.

Repeated identical resident labels still mean one distinct resident. Concurrent
residency selects only a most-recently-used label present in the resident array.
Invalid/stale observations remain adjacency boundaries. Public result types,
counter arithmetic, clipping, floating-point accumulation, observation counts,
IDs and suffix limits are unchanged. Summary/chart normalization was not merged
with visit rules, because those consumers have different semantics.

## Measured component evidence

The optimized standalone comparison compiles production telemetry, a frozen
`6a46a89` reference and the benchmark in the same module with `-O`. The reference
history body is byte-identical after its type-name substitution. Every measured
result must match the complete expected visit array and summary. Three repeats
alternate reference/candidate ordering for each 100,000-observation fixture.

| Synthetic fixture | Reference median | Prepared median | Ratio |
| --- | ---: | ---: | ---: |
| Mixed quality/model history | 493.37 ms | 166.89 ms | 2.96× |
| Continuous idle | 492.06 ms | 161.10 ms | 3.05× |
| Continuous active | 506.56 ms | 168.00 ms | 3.02× |
| Frequent model switches | 547.62 ms | 187.85 ms | 2.92× |
| Long gaps | 474.19 ms | 164.13 ms | 2.89× |

The mixed input matches the history-read benchmark's observation values, but
these same-module timings have a distinct compilation setup. Do not compare
493.37 ms directly with the earlier library-linked 444.06 ms as a before/after
measurement. Neither run measures full Metrics rendering, database reads,
whole-app CPU, battery life or precise memory allocations. Normal provider
traffic continued independently. Cancellation responsiveness is unchanged.

Reproduce in a fresh task-owned scratch directory:

```sh
cp Tests/PerformanceBenchmarks/VisitFactsBenchmark.swift /tmp/visit-facts/main.swift
swiftc -O -swift-version 6 -D BLOOMY_VISIT_FACTS_SAME_MODULE \
  Sources/DarkbloomTelemetry/*.swift \
  Tests/DarkbloomTelemetryTests/ModelVisitHistoryFactsReference.swift \
  /tmp/visit-facts/main.swift -lsqlite3 -o /tmp/visit-facts/benchmark
/tmp/visit-facts/benchmark
```

Create `/tmp/visit-facts` first or choose another fresh path. The macro only
omits module imports for this same-module comparison; normal tests use
`@testable import DarkbloomTelemetry`. `BLOOMY_VISIT_FACTS_ROWS` optionally sets
1–100,000 rows. No live database, key, prompt, download or model inference is an
input. Results and compiled-source provenance remain locally under
`/tmp/bloomy-visit-facts-pilot-20261003/`.

## Correctness and native review

Six parity tests compare complete visits, summaries and no-work lists for
explicit duplicate/concurrent/MRU, invalid, capture/time tie, restart/reset,
missing counter, empty-slot and clipping cases, plus 24 seeded 256-row histories.
Each covers multiple windows and suffix limits. All 37 focused tests pass;
the existing opt-in scaling test is skipped. Independent read-only review found
no correctness regression. The final normal suite reports **1,543 tests** with
seven explicit opt-in skips, and Release compilation passes in 54.03 seconds.
Logs: `/tmp/bloomy-visit-facts-final-tests-20261003.log` and
`/tmp/bloomy-visit-facts-final-release-20261003.log`.

Native145 matches all 107 staged source hashes, its linked Debug telemetry
archive and actual binary. Executable SHA-256:
`e2d6a430ee5b522729c3dbad0ab7e31b861a0328aa0162f6efc7dfed89be4e12`.
Compact light Metrics shows the unchanged summary and aligned status pills.
Without work retains only the Bonsai visit with **1m 30s** observed without work.
Wide dark preserves that filter; All visits restores loaded-at-last-reading,
uncertain and work-observed rows with matching durations. The chart/history
content remains reachable. This fixture uses inert data and no provider actions;
it does not establish real request attribution or the full native matrix.
Normal Quit removed both task-owned review apps.

Installed Bloomy's process, binary and unsaved state remain protected. Provider
and watchdog continue running from the internal model cache. No app release or
installation is represented by this source checkpoint. Whole-app profiling,
bounded in-pass cancellation, wider native/accessibility and distribution proof
remain open.
