# Large Metrics history and hidden-row release — October 4, 2026

Activity Metrics now releases its raw display sample array when hidden or
removed, alongside the existing decoded database cache release. The last
completed summary, visits, chart points and their period/model scope remain.
A released buffer is explicitly unavailable for analysis: reopening or changing
a filter cannot turn it into a false empty result. A successful read, including
an actual empty read, supplies the next analysis generation. Failures and
cancellation preserve the preceding result and its scope. Recording is unchanged.

## Reproducible large-history fixture

`Tests/PerformanceBenchmarks/SeedMetricsHistory.swift` writes a new, explicitly
supplied synthetic database through the production `PerformanceHistoryDatabase`
API. It refuses to overwrite existing evidence. The 100,000-record production
retention cap covers about 28.94 days, with 25-second samples, four models,
25-minute single-resident visits, periodic idle visits, stale/unavailable gaps
and counters held flat at switch boundaries. No provider or network is used.

The builder's optional `--metrics-seed` checks integrity and row bounds, rejects
a WAL sidecar, and copies the completed database into the Fresh fixture only.
The fixture copies it into its own temporary directory without opening or
replacing real history. Other scenarios retain the ordinary small seed.
Bounded read diagnostics retain the last 12 completed read timings and counts,
without row payloads or raw errors.

The final immutable seed has 100,000 rows, integrity `ok`, DELETE journal mode,
74,256,384 bytes, and SHA-256
`f26ec99e2ba5b98bb631b76ac236bdcc027aa8b6e260426ab6daf598cde7da07`.
Seeding plus the two validation reads took 12.423 seconds. The finite optimized
seeder's cold/repeat reads took 938.76/847.09 ms. The initial seed with an empty
WAL sidecar was rejected before the builder created an output directory; the
seeder now closes and finalizes its database before copying. The reviewed
seeder source also compiles after a whitespace-only indentation cleanup.

## Baseline before the row-release change

Optimized baseline fixture:
`.build/metrics-100k-profile-native-final-20261004/`; executable SHA-256
`cd2a0688b222a0d8daf37c966c1563351fcdb4fb75cb3060f5b0e21d0c1b7f35`.
Its 114 source hashes matched the checkout at the baseline checkpoint, before
the subsequent production Metrics edit. Synthetic observations were paused
after preparation. A few initial fixture observations replace the oldest seed
rows at the retention cap; displayed data is not byte-identical to the seed.

The native 30-day view rendered 100,000 samples, 158 visits without observed
work and 65h 50m in those visits. Qwen filtering reported 75 such visits and
31h 15m; provider-wide counters correctly became unknown for the model filter.
The native first full read took 1,506.33 ms; later reads were about 0.91–0.95 s.
These are disk-read timings, not end-to-end UI latency measurements.

| Qualified 30-second window | CPU, percent of one core | Median RSS, MiB | Median footprint, MiB |
| --- | ---: | ---: | ---: |
| Minimized A | 0.0101 | 299.42 | 155.22 |
| Displayed A | 6.1860 | 473.64 | 329.39 |
| Minimized B | 0.0200 | 402.91 | 216.44 |
| Displayed C | 6.2978 | 484.42 | 274.38 |

Each accepted window has 31 observations and an unchanged native visibility
event record. No compilation or test suite ran during these accepted windows.
Displayed B is excluded because focused native-hosting tests ran concurrently
for part of its window; the result is preserved as rejected comparison evidence.
The old minimized path released 9,152 decoded database rows per cache clear,
but source inspection showed that view state still retained all raw samples.
The growing process footprint alone does not establish a leak or its cause.

## Final native behavior and resource observations

The final view restored the 30-day summary after actual native minimization.
An in-flight held read cancelled without recording a storage failure. A later
held reopening read displayed the spinner alongside the retained 100,000-sample
summary, 158 no-work visits and unchanged totals. Selecting Qwen during this
hold showed “Showing All models until results for Qwen 3.8 · 27B are ready.”
Failing that held read kept the same summary and scope, with an explicit error
and available Refresh control. Retry produced Qwen's 75 no-work visits and
unknown provider-wide counters. An actual successful empty read displayed
zero samples and “Metrics are accumulating”; subsequent Refresh restored the
history. Returning to All models restored its original totals and visit counts.

| Final qualified window | CPU, percent of one core | Median RSS, MiB | Median footprint, MiB |
| --- | ---: | ---: | ---: |
| Minimized A, 30 s | 0.0075 | 258.34 | 148.33 |
| Minimized B, 30 s | 0.0090 | 286.84 | 159.03 |
| Displayed B, 45 s | 8.4879 | 422.62 | 253.77 |

The two minimized windows each have 31 unchanged visibility observations;
before/after diagnostic counts confirm no reads start or complete during either
window. The displayed 45-second window has 46 unchanged visibility observations
and includes periodic work. An earlier 30-second displayed sample measured
0.0085% CPU between reads; it is retained as an idle-phase observation, not a
displayed refresh-cost baseline. The loop waits 30 seconds after a read finishes,
so 30-second windows can miss a refresh entirely. Phase and read counts affect
the displayed CPU average; no visible CPU reduction is claimed from this fix.

The repeat hidden footprint remains above its first sample. Raw view-row release
is verified by the state regressions, and native retention/recovery is verified
visually, but these process observations do not assign every retained byte to a
specific owner. Further incremental read/analysis work remains open.

## Verification and limits

- Three new regressions cover released versus empty buffers, retained totals
  and scope, filters/reopening, failure, cancellation and successful recovery.
  All 23 focused presentation tests pass.
- Full `swift test -c release` reports 1,569 telemetry/UI, 21 companion protocol
  and 28 companion host tests passing: 1,618 total with seven existing opt-in
  skips. Log: `.build/metrics-hidden-buffer-full-tests-20261004.log`.
- Final optimized fixture: `.build/metrics-hidden-buffer-native-20261004/`.
  All 114 source hashes match; binary SHA-256
  `b5a9e06d41d8f2f8552fb9434d0d1fcb3978084795334953bbc151dc9a836759`.
  It uses the existing three inert dependency substitutions, testable Release
  telemetry and ad hoc signing. It is not a distribution release.
- The immutable seed, process samples, native visibility events, bounded read
  counts and manifests remain in task-owned `.build/` evidence. Python syntax,
  Swift seeder compilation, production Release compilation and diff checks pass.
- The final native popup still shows the two-row icon-led common bar and
  Today/Week earnings comparison. Its known amount values and missing GPU/power
  qualifications remain intact. Both task-owned baseline/final review apps
  quit normally after proof; no DashboardFixture process remains.
- Read-only production verification retains installed 1.9.18/build 143,
  provider PID 47646, exactly Qwen 3.8 and Gemma 4 advertised, and Autopilot
  shadow. Configuration SHA-256 remains
  `fece43bb93691e7f702d83388428f5ef14dd83755f8e2f48bef140ec1a764eaf`.
  No provider mutation, inference, installed replacement, push or release occurred.

The short synthetic resource windows do not prove production collector costs,
battery use, leak freedom, or an installed-app memory improvement. Allocator
high-water marks and different navigation/read sequences limit direct process
comparisons. The broader native, VoiceOver, motion, real integration and delivery
matrix remains open. Unrelated menu-motion diagnostics remain unstaged.
