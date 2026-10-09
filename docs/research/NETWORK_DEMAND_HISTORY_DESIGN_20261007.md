# Bounded model-demand history

Implementation follows the BloomGauge comparison and `5658487` demand ruler.
The local journal, accepted-snapshot recording, shared visible-screen read loop
and native card sparklines are implemented. See the accompanying native review
for verification and remaining qualification limits.

## Authority and acquisition

`NetworkCapacitySnapshot` supplies a fresh current observation, not authoritative
completed-request history. Its timestamp is the capture time assigned by the
existing fetch. The separate `NetworkSeries` endpoint supplies whole-network
aggregates and cannot stand in for per-model history.

Record only snapshots accepted by `MonitorStore.refreshNetworkCapacity()` after
its cancellation, shutdown, generation, freshness and monotonic-time guards.
Publish live facts and complete existing decision work before awaiting bounded
recording; do not republish capacity after that suspension. An immutable accepted
payload avoids reentrancy changing what gets recorded. Recording participates in
the store's existing joined shutdown, with no additional network acquisition.

## Implemented storage contract

Use a separate lazily opened, actor-owned SQLite journal. Retain capture time,
canonical model ID, active/queued requests and loaded-provider denominator.
An accepted snapshot writes atomically across its models. Exact replay is
idempotent; conflicting replay fails. Missing models, draining observations and
zero denominators never become zero demand.

Five-minute local buckets and a 72-hour retention ceiling bound the database to
864 atomic snapshot rows, containing at most 110,592 model values. Each row stores
one validated JSON payload of at most 100,000 bytes. A newer capture replaces the
whole occupied bucket; identical replay is ignored, conflicting timestamp replay
fails, and older captures cannot replace newer captures. This is sampled pressure while
Bloomy is collecting, not a continuous network history. Longer retention needs
explicit rollups and measured storage/query costs.

The journal uses transactional retention, indexed capture-time queries,
private DB/WAL/SHM permissions and corrupt-read failure behavior. Follow
`PerformanceHistoryStore`'s lazy opening, bounded retry queue, separate read/write
faults and cancellation handling. Do not run synchronous SQLite on MainActor.

## Shared report and presentation

Return one immutable bounded report containing its completed query/range, actual
read time, histories indexed by canonical ID, common pressure scale and storage
status. Read all series in one transaction. Derive scale before search/filtering,
including the current snapshot consistently if used. Distinguish first successful
empty reads from pending/failed reads; retain an older report only with its
original range and freshness.

Models and Opportunity receive one screen report and prepared points. The popup
currently does not pass demand to `CompactModelCard`; adding it needs explicit
plumbing and proof within the fixed popup card budget. No card owns a database
query or timer. Use a visibility/revision task; hiding or changing scope cancels publication.
Read after accepted captures and on one five-minute visible-screen cadence, which
advances the rolling 24-hour window even when acquisition is unavailable. Search,
body updates and individual cards do not initiate queries. Preparation runs
outside MainActor, checks cancellation, and is joined before publication.

Extend the shared ruler with a small native sparkline. Keep live/stale demand
separate from recorded history. Preserve gaps, actual zeros, one-point readings
and unknown zero-denominator points. Do not join lines across long missing
intervals or label a demand ratio as earnings. A typical marker requires explicit
coverage and a defined sample statistic: the dashed median is withheld until
twelve valid recorded samples exist. All cards use the full report's historical
scale, separately from the current snapshot's scale. Pay-colored zones require attributable
financial evidence beyond this journal.

## Required proof

- Acceptance tests: only fresh latest accepted snapshots record; cancellation,
  supersession, future/stale responses and errors do not. Storage failure cannot
  clear current capacity.
- Database tests: reopen/replay, conflict, atomic rollback, retention/row caps,
  corruption, private files and concurrent writes.
- Report tests: bounded output, filter-independent shared scale, unknown versus
  empty, one point/zero/gaps, query changes, failed reads and hidden cancellation.
- Cache tests: one read per shared scope, no per-card work, canonical ID handling,
  no grade rebuild merely because historical points changed.
- Native proof: mixed histories, compact/wide, light/dark, source/freshness help,
  accessibility, popup height and Available collapse/reopen.
- Release measurements: query latency, database growth, CPU, memory and wakeups
  visible/hidden with matched history. Architecture does not establish savings.

The bounded native read-only reviewer inspected these seams and made no edits,
provider calls or external requests. Main owns implementation and final proof.
