# Metrics scope, freshness and keyboard checkpoint — October 2, 2026

This is bounded progress within the active polish plan. The installed app and
real provider were preserved. The native review used production views with
isolated preferences, synthetic SQLite history and inert dependencies.

## Repairs

- Each successful history read retains its requested period. Loading or failing
  a seven-day read cannot relabel the retained 24-hour results.
- Calculated summaries, visits and charts publish together with their completed
  period/model query. While detached analysis is pending, chart axes, coverage
  denominators and counter explanations retain that completed scope.
- Coverage names its displayed period. Retained period/model results are
  qualified until their replacements are ready. Routine reads retain the
  existing 30-second cadence without a new progress/reflow cycle.
- The first pending read shows progress without zero summaries; a completed
  empty read shows the accumulating state. Open worked visits say
  “Last loaded · worked”, preserving historical residency rather than implying
  continued loading after recording becomes stale.
- Native focused Metrics controls scroll into view with centered margins. The
  optional callback applies only inside Metrics; standalone visit sections keep
  their existing behavior. No timer or global keyboard monitor was added.
- History accepts an optional inert read dependency. Production still defaults
  to its journal. Cancelled reads, including late ordinary failures, cannot
  publish a storage fault; successful recovery clears a preceding read fault.

## Native evidence and rejected candidates

Native84 established the compact dark baseline: Tab reached the visit filter
while the viewport stayed at its top, leaving that focus clipped. Native85 was
built but not launched after review found the additional pending-analysis scope
gap. Native86 revealed fabricated initial zero summaries and an invalid test
session identifier. Its attempted observation was correctly rejected with a
recording error. It is not evidence of successful arrival or freshness recovery.

Final **Native87**, session `F5196529-9E5C-4FAB-925B-2E094D4102A9`, verified:

- Held first read: reading progress, no zero-result summaries/visits/charts.
  Releasing it as empty shows the accumulating state and zero sample count.
- With synthetic publications paused, a valid observation at **17:09:06 local**
  followed by explicit Refresh displays “Recording locally”, 362 samples and
  the exact observation time. The open Qwen visit says “Last loaded · worked”.
  Later real elapsed time displays “Waiting for fresh measurements” while
  retaining the timestamp and 362 samples; no synthetic clock was advanced.
- Wide light seven-day selection with a held read retains the 24-hour notice,
  12.2% of 24 hours and the prior totals. Failure exposes the safe retry message
  beside those qualified results. Refresh removes the notice and changes
  coverage to 1.7% of seven days.
- Compact dark actual Tab traverses period, model, Refresh, visit filter, Show
  more visits and recording disclosure. The latter three move the actual
  viewport and show complete focus/control frames. Space opens recording
  details; ordinary scrolling reaches the full readable explanation.
- Gemma filtering exposes its canonical identifier in help and shows 5.9% of
  24 hours. Provider-wide request/token totals become Unknown with the All
  models instruction. Compact light and dark summaries remain aligned; wide
  light visit outcome pills retain consistent sizing.
- Leaving Metrics for Earnings cancels a held read. Returning performs a normal
  read without a false recording error. The saved final read proof reports
  **17 starts = 15 completions + 1 failure + 1 cancellation**, including one
  empty completion, normal next mode and no held continuation.

**Remaining keyboard finding:** actual Shift-Tab from either the expanded or
collapsed bottom recording disclosure skipped the offscreen preceding controls
and returned to the Activity Metrics selector. Forward reveal is verified;
complete reverse traversal is not accepted. This needs a focused follow-up,
not an assertion that the entire keyboard loop passed.

The fixture was quit normally; its process was absent afterward. No app binding
was observed after Quit, because that would reopen it. Its saved read proof is
`.build/native-dashboard-fixture-20261002-87/fixture-metrics-read-proof.json`.
All **94** manifest source hashes match the inspected checkout. The executable
SHA-256 is `76700e98b350a4774d8270a6b7cc3499dba35e8c848524e7f85ed4443eb19225`;
the linked telemetry library is
`0da0aed0eee0f3ace173ccbcbc1b413cc64f7d4f1ec2d78658e059fff593d102`.
Only the builder's three documented inert substitutions are staged.

## Automated checks and limits

The final full run exited 0: **1,425 tests** (1,376 app/telemetry in 181 suites,
21 protocol in five suites, 28 companion-host in nine suites). Their durations
were 19.515s, 0.013s and 11.627s. Final release compilation exited 0 in 38.16s.
Logs are `/tmp/bloomy-metrics-polish-20261002-full-03.log` and
`/tmp/bloomy-metrics-polish-20261002-release-03.log`.

The inert reader's independent finite harness passed ten starts: six successes,
one failure and three cancellations, including two empty reads, superseded
holds and no remaining continuation. Its log is
`/tmp/bloomy-metrics-reader-actor-proof-20261002.log`. Regression tests cover
scope pairing, failed/cancelled retained reads, historical worked wording and
late cancelled dependency failures. Read-only review found the second scope
gap before native acceptance; re-review found no additional actionable defects.
Mounted slow-analysis timing was not independently held; the query/snapshot
pairing is covered by unit checks and source review.

Production Bloomy PID 61760 and provider/watchdog PIDs 67163/67169 retain their
12:55:28 / 13:18:51 local launch times. The installed app executable hash remains
`5d692f240c9548f05350f2fb39d05eb15d00741ad7e9f317e3eeb8507e7c50c7`.
No real enrollment, policy change, inference, nudge, swap, download, credential,
privacy operation, installed-app replacement or release was performed.
Reverse keyboard traversal, actual VoiceOver, other displays, long production
history/performance and the broader native/distribution gates remain open.
