# Action recording and compact History — October 3, 2026

Action History now keeps the Model column visible in the compact dashboard,
retains full timestamps, and brings short search results closer to their
details. Recording repeated earnings also avoids walking every retained row
just to enforce the journal limit. This checkpoint follows released build 142;
it does not establish completion of the broader native review matrix.

## Recording cost and retention

The pruning statement selects expired rowids and the oldest overflow rowids in
one atomic DELETE. Its overflow LIMIT is the actual SQLite COUNT minus the
configured history limit, clamped to zero. It preserves the previous age
boundary, newest-first retention, and rowid tie order. There is no cached count,
schema migration, skipped validation, or change to transactions and corrections.
The separate-connection regression inserts rows through another connection and
checks retention through the still-open journal.

`Tests/PerformanceBenchmarks/run-action-replay.py` builds an optimized standalone
comparison using the public `record` API and independent synthetic disk-backed
WAL databases. Each starts with 5,000 rows. Three serial repetitions rotate the
execution order. Every typed retained field and the complete event order are
compared after each repetition.

| Recording batch | Rows per repetition | Released build 142 median | Previous checkpoint median | Current median | Released/current |
| --- | ---: | ---: | ---: | ---: | ---: |
| Identical earnings replay | 1,000 | 3,253.44 ms | 667.44 ms | 67.76 ms | 48.01× |
| Corrected earnings | 200 | 662.02 ms | 134.60 ms | 14.50 ms | 45.66× |
| New rows at capacity | 200 | 667.89 ms | 140.78 ms | 18.65 ms | 35.81× |
| Expired earnings | 200 | 653.74 ms | 133.63 ms | 15.42 ms | 42.41× |

All comparisons matched. Replay keeps the earning identity and payload unchanged
while supplying a later observation timestamp; the existing API intentionally
does not rewrite an unchanged job. Correction changes the reported amount and
updated timestamp. The new-row and expired-row cases exercise actual insertion
and retention transactions.

Frozen sources:

- Released 142: `88181f89bcb21ae88dd385f888aa3faf142b189f`.
- Previous rowid/OFFSET checkpoint: `a8cbf63aa244c178dd30a7b8319af20b3b853675`.
- Current database source SHA-256:
  `3f304fc1a261630ba0ea5c7b8ba4c2d25344d68e11e210da71a6df56e9d16987`.
- Linked Release telemetry archive SHA-256:
  `c4a32d6b7a50079b95d5f86ed7123fc2b3a0fcbdd4b343f8d776471b3609bee2`.

Local raw results, generated comparison sources, binary and manifest:
`/tmp/bloomy-action-ingestion-20261003/public-api-final-01/`. The manifest records
every telemetry source hash, both original/generated reference hashes, compile
command and binary hash. Final UI-only changes left the telemetry inputs and
linked archive unchanged, so the database measurement remains applicable.

The supplementary system-SQLite query runner passed 144 exact parity cases.
Its quiet statement timing is narrower than the table above; do not interpret
either benchmark as a measured reduction in whole-app CPU, energy or memory.
Public-API timing includes validation, identity checks, correction, transactions
and retention. It excludes account parsing, ActionHistoryStore's wrapper, SwiftUI,
provider work and cold startup. No real account journal or provider was used.

Reproduce after a current Release build with a fresh evidence directory:

```sh
swift build -c release
python3 Tests/PerformanceBenchmarks/run-action-replay.py --output-dir /tmp/bloomy-action-replay-new
python3 Tests/PerformanceBenchmarks/action-retention-query.py --source Sources/DarkbloomTelemetry/ActionHistoryDatabase.swift --output /tmp/bloomy-action-retention-new.json
```

## Native layout and regression proof

Native165 reproduced the compact Model column entirely outside the visible
table. The AppKit geometry regression failed before the responsive columns and
passed afterward. Compact windows show Time, Action, Result and Model. Wide
windows also show Trigger; compact selected details retain Trigger. Separate
table builders preserve macOS 14.0 compatibility without using conditional
column APIs introduced in 14.4.

Native166 exposed truncation of an older timestamp's AM/PM ending. Native167
reallocated compact column widths and verified the complete older timestamp,
long model details, six-digit earnings, selection through resize and Refresh,
Jobs recovery and the Actions empty state. Its one-result table still consumed
300 points, so it was not the final candidate. The new geometry assertion
reproduced that excess at compact and wide sizes. Short results now reserve a
header and comfortable rows; large results remain bounded at 320 points.

The final candidate, native captures, hashes and complete test/build checks are
recorded in the accompanying evidence and the checkpoint below. All review
events are synthetic. The new **5,000 action records** fixture contains 1,000
swaps, 1,000 skipped nudges, 1,000 base rewards and 2,000 jobs. Read-only SQLite
inspection confirms the total; AX's exposed row count is not a full-history
count. Searching earning 10204 reaches an older record beyond the initially
visible rows. Earning 14998 carries a long model ID and exact `$0.000199` amount.

The fixture makes no live API calls, inference, provider changes or credential
writes. CPU/GPU sampling is disabled; Mac identity and thermal state remain
actual, while fan/temperature samples are synthetic. It is a review bundle,
not a notarized distribution artifact.

## Final checkpoint proof

Native168 is the accepted isolated candidate for this bounded History change.
Its executable SHA-256 is
`b5298a18643e9f85b7e1979540b1640068552e1b4916a730141ca848e48fa988`.
All 109 source hashes and the staged telemetry library match its manifest.
Captures and full accessibility snapshots are retained under
`/tmp/bloomy-action-ingestion-20261003/native168/`:

- `compact-light-all`: mixed actions, jobs and rewards, all four columns visible.
- `compact-light-old-timestamp`: full AM/PM ending and a short one-result table.
- `compact-dark-selected-short-result` and `compact-dark-precise-amount`:
  selected details immediately follow the table; scrolling reaches the full
  long identifier, token counts, exact micro-dollar amount and account scope.
- `wide-dark-selection-after-refresh`: the same earning remains selected through
  resize and Refresh; Trigger joins the visible columns.
- `wide-dark-no-matching-actions`: filtering removes the old selected details
  and presents the native empty state.
- `wide-light-jobs` and `wide-light-jobs-cleared-search`: recovery and full Jobs
  history, including base rewards, without stale selected details.
- `compact-dark-all`: restoring the mixed history and compact four-column layout.

The fixture was quit normally and process absence verified. Production PID
61760, provider PID 63387 and watchdog PID 63393 retained their start times and
executables. The final suite reported 1,530 app/telemetry tests plus 21 Companion
and 28 host tests: **1,579 reported, seven opt-in skips**, no failures. Final
Release compilation completed in 45.11 seconds; no warnings/errors appeared in
these logs. Geometry RED/GREEN, final build/test logs, benchmark manifests and
capture SHA-256 hashes are preserved in
`/tmp/bloomy-action-ingestion-20261003/final-evidence.json`.

## Scope still open

The installed Bloomy build 140 and running provider are preserved. Installed
replacement and comparable resource profiling await the outstanding saved-edit
response. Spoken VoiceOver, other locales/displays, real arrivals while selected
and the complete native route/state matrix remain open. This focused checkpoint
does not establish whole-app efficiency or final visual approval.
