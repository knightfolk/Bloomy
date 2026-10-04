# Metrics validated read reuse — October 4, 2026

Metrics now retains one opaque read snapshot in its off-main journal actor.
The snapshot shares its sample array with the visible consumer rather than
building another history-sized decoded cache. Hiding Metrics releases both
owners through the existing cleanup path. Recording cadence, conservative
analysis, unavailable/stale rows and the 100,000-row/30-day limits are unchanged.

## Integrity and bounds

Each read still queries SQLite's current indexed membership and chronological
insertion order. Validated payloads may reuse only within the same database
instance, with an unchanged outside-write version and a covered local insertion
journal. New local inserts always decode, including recycled rowids and expired
UUIDs with identical indexed fields. The journal is capped at 512 entries;
older tokens fall back to a full validated read. Replays, conflicting IDs and
rolled-back inserts never publish journal entries.

SQLite's [data_version](https://www.sqlite.org/pragma.html#pragma_data_version)
detects other connections' commits, not this connection's own writes; versions
are compared only on this same connection. A deferred read transaction pins
metadata and payload queries to one [consistent WAL snapshot](https://www.sqlite.org/isolation.html).
Version checks occur outside that transaction, after all SELECT statements have
been finalized. If an outside commit races an incremental read, that attempt is
discarded and every payload is read again. A raced full read can return its
consistent measurements, but its token cannot reuse on the next call.

Unmanaged triggers disable reuse: they could mutate old rows during our own
insert/prune without changing data_version. This preserves support for extended
databases through ordinary full validation. The schema probe is finalized before
the read transaction, so it cannot hold an implicit read snapshot across the
version fence.

The snapshot stores aligned rowids (about 0.8 MB at the maximum history size).
Its lookup dictionary and dirty-row set exist only during a read. The prior
general decoded-cache ceiling remains 32,768 entries/16 MiB; snapshot reads do
not create a second generation of that cache. Consumers should retain one
snapshot and release it when inactive. Process memory still includes analysis,
SwiftUI/Charts and allocator retention; releasing rows does not prove leak freedom.

## Verification

Fifteen focused regressions passed, covering complete sample fields, tied
timestamps, changing periods/model filters, gaps, local/outside insertions and
corrections, retention, rowid/UUID reuse, foreign tokens, journal overflow,
conflict/replay/rollback, triggers, corruption, cancellation and internally
consistent concurrent atomic outside corrections. Mixed histories compare every
sample and summary with the ordinary validated reader. The final full Release
suite passed: 1,587 telemetry/UI, 21 companion protocol and 28 companion host
tests, 1,636 reported total, with seven existing opt-in checks skipped. Log:
`.build/metrics-read-reuse-full-20261004.log`. The first focused build rejected
an implicit property capture in a lazy closure; that compile error was corrected.
The schema probe's lifetime was then tightened before the final full suite.

The optimized baseline component library is frozen under
`.build/metrics-read-reuse-baseline-20261004/`; SHA-256
`d9d01f826fdd9e8e90fd49b437ed7587147d41a3aa316872862c08812554a1f8`.
Both programs use the same closed synthetic seed. The candidate library is
frozen under `.build/metrics-read-reuse-candidate-20261004/`; SHA-256
`4b98f595192a10522b34bf6ccbf9269dbe50263415090bdb44b455f9afd4dc48`.

| Component read, 100,000 rows | Baseline, ms | Snapshot candidate, ms |
| --- | ---: | ---: |
| Initial | 1,508.46 | 1,483.57 |
| Median of three repeats | 925.32 | 74.87 |
| After 15 local inserts | 923.10 | 72.57 |

The candidate reuses all 100,000 rows on repeat and 99,985 after the inserts;
every complete sample and its order matched. The median repeated read is about
92% faster in this component benchmark. Cold reads still validate every payload;
no meaningful cold-read improvement is claimed. These are read timings, not
end-to-end UI latency, battery consumption or production whole-app savings.

The old native Metrics bundle is frozen at
`.build/metrics-summary-final-native-20261004/`; it predates the newer popup
checkpoint and is used only as the Metrics baseline. Its qualified visible
45-second window measured 8.6371% of one CPU core, median RSS 388.06 MiB and
median footprint 251.06 MiB. A full periodic read occurred within the window;
bounded read counts and visibility observations are preserved with the sample.
No compilation, test suite or other task-owned benchmark ran during it. Its
CPU series contains two refresh bursts, so it is retained as phase evidence and
is not compared directly with the candidate's one-refresh window.

The exact-source optimized native candidate is
`.build/metrics-read-reuse-native-20261004/Bloomy Dashboard Fixture.app`.
All 118 source hashes matched the inspected checkout. Binary SHA-256:
`06bddde2808c8c41c08bdcd8e11f5c2202f44c5cf6e707f5c0847877518c14a0`.
The linked telemetry and closed seed hashes match the component candidate and
the baseline seed. This is an inert, ad hoc signed review host.

Computer Use verified the 100,000-row summary, 158 visits without observed work
and 65h 50m in those visits. Qwen filtering keeps its 75 such visits/31h 15m
and correctly makes provider-wide counters unknown. A failed held read retains
the completed result and a usable Refresh control; retry reuses all rows.
A successful empty read displays zero samples and releases its snapshot; retry
validates the full history again. After minimization, the owner reports zero
retained snapshot rows and 100,000 released rows. Reopening with a held read
retains the completed summary; requesting Qwen displays “Showing All models”
until release supplies that scope. Switching to Unmeasured metrics without
Refresh replaces the 100,000-row source with 360 samples and unknown readings.

The verified minimized 30-second window starts/completes no reads, keeps zero
snapshot rows and measures 0.0125% of one CPU core. Two earlier attempts were
rejected before sampling because the UI observation reopened the window;
Minimize All followed by log-only observation produces an actual stable native
minimization. The visibility sampler's rejection remains intact. Native read
diagnostics bound the latest 12 timings/counts and never contain payloads.

## Qualified native comparison

The first two baseline 45-second windows each contained two refresh bursts;
their aggregate CPU percentages cannot be compared with the candidate's one.
For the accepted baseline, a bounded log-only wait starts sampling three
seconds after a periodic completion. Both accepted visible windows contain
exactly one subsequent completed read, verified by before/after counters.
All visibility samples remain unchanged, with no concurrent build/test or
task-owned benchmark. Candidate read 5 reuses all 100,000 rows in 106.84 ms.

| Native window | CPU, percent of one core | Median RSS, MiB | Median footprint, MiB |
| --- | ---: | ---: | ---: |
| Baseline visible, 45 s, one refresh | 4.4047 | 431.69 | 261.06 |
| Candidate visible, 45 s, one refresh | 2.5000 | 395.98 | 295.99 |
| Candidate minimized, 30 s, no reads | 0.0125 | 345.98 | 213.66 |

The observed visible CPU average is about 43% lower in this inert comparison.
The candidate's footprint is higher, while RSS is lower; no memory reduction
or leak-freedom claim follows. Allocation profiling and production traffic/
collector measurements remain open. Native counters, complete process series,
closed component databases, manifests and rejected phase observations remain
under the task-owned baseline/candidate `.build/` directories. Both measurement
processes quit normally, and no review process remained at measurement close.
The current candidate was then reopened separately for Kevin's inspection;
its icon-first popup and graphical earnings are visible. This handoff process
is intentionally left running and is not an additional resource sample.

Read-only checks retain installed Bloomy 1.9.18/build 143 and provider
configuration SHA-256
`fece43bb93691e7f702d83388428f5ef14dd83755f8e2f48bef140ec1a764eaf`.

This work is local source review. The installed application, provider, model
selection and network inference are untouched. Broader native accessibility,
production collector/traffic costs, menu motion and distribution gates remain
open; this milestone does not complete the whole-app polish goal.
