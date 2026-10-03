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

## Reverse-keyboard follow-up — Native88

The reverse-traversal finding above is repaired in the subsequent source
checkpoint. A single `.focusSection()` on Metrics' eager content VStack groups
its native controls for sequential navigation. The existing reveal callback
could only scroll a control after it received focus; it could not correct a
reverse sequence that skipped the control entirely. The Activity selector is
outside that content as a sibling. Independent read-only hierarchy review
confirmed there was no lazy creation, hidden parallel page or competing nested
control behind this case. Apple's documented
[focus-section behavior](https://developer.apple.com/documentation/swiftui/view/focussection%28%29)
supports the native grouping; actual inspection establishes the result here.
No custom key handler, extra focusable wrapper, polling or focus trap was added.

**Native88**, session `4069A0CD-E952-478B-A0B4-41825D72A486`, uses the same final
Metrics source plus that one modifier. Actual compact dark Tab reaches period,
model, Refresh, visit filter, Show more and recording disclosure. Shift-Tab now
returns through those controls in reverse, moving the viewport to reveal each
focused section, then exits to the Activity selector from period. Repeating
after Space expands recording details still returns to Show more and filter.
Screenshots show complete centered filter/Show more focus rings.

After pausing synthetic publications, native Right/Space selects Without work,
removing Show more. Tab reaches recording details directly; Shift-Tab returns
to Without work with its complete focus ring visible. Wide light repeats the
filtered path and full All visits reverse sequence. Left/Space restores All
visits; Right/Space on the period picker selects seven days and produces the
correct seven-day coverage, then Tab reaches the model picker.

The initial streaming arrow/Space attempt did not change the visit selection;
the isolated repeat after pausing publications did. Full forward/reverse
traversal succeeded with publications running, but preserving an in-progress
segment choice across later publications remains a focused follow-up. This
does not claim sustained update/composition/VoiceOver coverage.

The opt-in read-only native focus trace saved 25 records for 12 real navigation
keys. It consumes or synthesizes no events. The final read counts are 11 starts,
11 completions, zero failures/cancellations/empty reads and no held read. Both
files are preserved beside `.build/native-dashboard-fixture-20261002-88/fixture-manifest.json`.
All **94** source hashes match. Executable SHA-256:
`eac9fb8dee8214ebdda0bafb915368421855761ab2dea124dc9169e343b753cc`.
The telemetry library hash is unchanged from Native87. The fixture was quit
normally; its process was absent afterward. Production/provider PIDs, launch
times and installed executable hash remain unchanged.

The final source passes **1,425 tests** again: 1,376/181 suites in 20.155s,
21/five suites in 0.013s and 28/nine suites in 11.718s, exit 0. Final release
compilation exits 0 in 38.68s. Logs:
`/tmp/bloomy-metrics-keyboard-20261002-full-01.log` and
`/tmp/bloomy-metrics-keyboard-20261002-release-01.log`.
This native regression is the meaningful proof for the one-line focus policy;
no unit test that merely checks presence of the modifier was added.

### Repeatable native regression

1. Build a fresh isolated fixture from the current source; choose Activity →
   Metrics, dark and 800 × 560. Keep the installed app untouched.
2. Tab from the Activity selector through period, model, Refresh, filter, Show
   more and disclosure. Each focused control must be wholly visible.
3. Shift-Tab through exactly the reverse sequence. Repeat with disclosure
   expanded. Period's previous control must be the Activity selector.
4. Pause synthetic publications. Select Without work with native Right/Space;
   Show more must disappear. Test filter ↔ disclosure in both directions.
5. Repeat in wide light; restore All visits with Left/Space. Verify period
   Right/Space and model Tab remain native and that no provider action occurs.
6. Save bounded diagnostics, quit normally and verify process absence without
   observing the closed app binding. Retain the exact source manifest.

## Streaming keyboard-choice follow-up — Native91

New measurements previously reset a pending native segment highlight before
Space confirmed it. Reopened Native88 baseline session
`D4B02E04-EB72-4B0F-BFC5-74CD9AEC9BAF` reproduced the visit reset when the sample
count advanced 361 → 362. A shorter eight-second publication hold preserved
it. With synthetic observations paused, a 35-second hold crossing the ordinary
30-second read cadence also preserved it. This distinguishes changed results
from unchanged reads or simple view invalidation; it does not establish a
universal macOS picker defect.

Both Metrics period and visit filter now use one Equatable native Picker leaf.
Its comparison uses an immutable selection snapshot and stable options, while
writes flow through the existing parent's Binding. Comparing two live bindings
would falsely compare both against the same new storage value. Two regression
tests cover this distinction and write-through ownership for Boolean and period
selections. The current callers retain stable state owners and unique option
IDs; changing binding ownership beneath an equal persistent view would require
revisiting that contract. No new state owner, key handler, timer, or view ID was
introduced. Read-only source review found no actionable defect in these callers.

Native89 was a rejected compile: actor-isolated Equatable conformance and a
callback conversion were repaired before any launch. Native90's visit-only
candidate preserved Without work through a 35-second changed-result hold but
its original period picker still reset pending 7 days to 24 hours. This is
intermediate evidence, not acceptance of the final source. Its session
`5988BFA3-00F0-429A-991B-659668F00A06` saved eight starts/eight completed reads.

**Native91**, session `A8713D47-E1EB-4894-9C77-0028BAD5020D`, verifies both final
controls with synthetic observations and the normal Metrics cadence running:

- Compact light Right highlights 7 days while 24 hours remains committed.
  After a real 35-second hold, samples increase 361 → 362 and latest observation
  advances 17:42:16 → 17:42:47; focus remains on uncommitted 7 days. Space then
  commits it and coverage describes seven days.
- Tab reaches model, Refresh and All visits. Right highlights uncommitted
  Without work. A second 35-second hold advances 363 → 364 and latest observation
  17:43:19 → 17:43:50 while preserving that highlight. Space commits Without work,
  removes Show more and retains the filtered visit.
- Tab reaches recording disclosure directly; Space expands it and Shift-Tab
  returns to the selected filter with its ring visible. Wide dark restores All
  visits and its rows/Show more, with aligned controls. Reverse traversal returns
  through Refresh, model and the selected period. Native88's separately recorded
  full Activity-selector boundary remains earlier evidence.

Final saved proof has seven starts/seven completions, zero failures,
cancellations or empty reads, and no held read. Native90 and Native91 proofs are
preserved in their corresponding `.build/native-dashboard-fixture-20261002-N/`
outputs. Both were quit normally and their processes were absent afterward.
Native91's manifest has **95** source hashes, all matching the checkout.
Executable SHA-256:
`f0945282b82700f1d7df9ef527671ae09f9172b605b16e567b821ff3cef5295d`.
Linked telemetry library SHA-256 remains
`0da0aed0eee0f3ace173ccbcbc1b413cc64f7d4f1ec2d78658e059fff593d102`.
The substitutions remain the documented inert dependencies; this is locally
signed review evidence, not distribution evidence.

The final full suite passes **1,427 tests**, exit 0: 1,378 app/telemetry tests in
182 suites (19.863s), 21 protocol tests (0.013s), and 28 companion-host tests
(11.603s). Log: `/tmp/bloomy-metrics-focus-update-20261002-full-01.log`.
Final release compilation exits 0 in 39.82s; log:
`/tmp/bloomy-metrics-focus-update-20261002-release-01.log`.
Production PID 61760 and provider/watchdog PIDs 67163/67169 retain their earlier
launch times, and the installed executable hash is unchanged. No real provider
mutation, inference, credentials, privacy or installed-app replacement occurred.
Mounted slow-analysis timing, other displays, actual VoiceOver, long production
history/profiling and the broader native/distribution gates remain open.

For repeatable streaming checks, keep synthetic observations running, establish
an uncommitted Right-arrow highlight, hold across a changed sample count and
latest timestamp, then confirm with Space. Test both pickers independently;
unchanged reads alone do not exercise the regression.
