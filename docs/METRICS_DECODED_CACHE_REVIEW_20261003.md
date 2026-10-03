# Verified decoded Metrics reuse

Repeated Metrics reads now reuse a bounded set of recently decoded observations.
SQLite still selects every current row. Reuse requires a SHA-256 match against
that row's current BLOB, followed by validation of its indexed ID, timestamp and
model. Other rows decode and validate normally. No SQL result, raw BLOB, provider
state or request content is cached.

Reads scan newest first and reverse the completed interval result, preserving
chronological order and tied insertion order. A successful read publishes its
own generation; failed or cancelled scans retain the previous generation.
Replay/conflict/rollback writes do not publish derived read state. Metrics
releases this state when its page disappears or dashboard display becomes
inactive; recording remains independent.

Each generation has a 32,768-row ceiling and a conservative **16 MiB accounting
budget**. At most the old and staged generations coexist during a read. Their
combined estimated accounting is at most 32 MiB. This is estimated auxiliary
storage, not a hard resident-memory limit or a claim about returned arrays,
SQLite pages or Swift allocator retention.

## Release comparison

The unchanged benchmark source was compiled against a preserved pre-change
Release library and the final candidate Release library. Both use fresh
synthetic SQLite databases with deterministic IDs. Repeated arrays must match
exactly; 15 inserts also verify precise retained-array parity at the 100,000-row
ceiling. No private history or model inference is an input.

| Rows | First read before / after | Repeat median before / after | After 15 inserts before / after |
| --- | ---: | ---: | ---: |
| 10,000 | 58.03 / 68.56 ms | 56.24 / 13.37 ms | 55.01 / 14.05 ms |
| 100,000 | 596.16 / 612.25 ms | 595.39 / 531.73 ms | 604.95 / 538.14 ms |

Warm read improvements are approximately 4.21 times and 10.7 percent,
respectively. The first read pays admission overhead. Seeding already warmed
filesystem/SQLite pages, so “first” is not a cold-storage measurement. Raw BLOB
copy scans were 1.76 / 1.92 ms and 14.39 / 14.17 ms. These isolate database read
work; summary, visits, SwiftUI rendering and whole-app CPU/energy remain separate.
The live provider continued ordinary serving during these serial comparisons;
normal system activity limits fine-grained timing conclusions.

The first pilot hashed and staged every row, then evicted old staged entries.
Its 100,000-row repeat median rose to 611.53 ms. That approach was rejected.
The accepted iteration hashes only potential reuse or admission and avoids
staged eviction. Older unretained misses remain fully decoded and validated.

An isolated memory mode discards returned arrays between four reads. At
100,000 rows, final resident sizes were 89,079,808 bytes before and 102,088,704
bytes after, a **12.4 MiB** difference. Both processes began at 10,780,672 bytes.
Those figures include allocator reuse and SQLite pages. They do not establish
precise cache allocations, a memory leak, or immediate OS reclamation on clear.

Preserved baseline archive SHA-256:
`a5a592a27d0e35fa60eb4c93478bb9429d687bdc66ec71acbc92534efcc80890`.
Local evidence is under `/tmp/bloomy-history-cache-pilot-20261003/`:
`baseline-timing-serial.json`, `baseline-memory-serial.json`,
`candidate-v2-timing.json`, `candidate-v2-memory.json`, the rejected pilot outputs,
separate executables and baseline library. These task-owned outputs remain
available for review. No external backup or unrelated files were removed.

## Verification

The full suite passed with **1,537 reported tests**, including seven explicit
opt-in skips; Release compilation passed in 48.04 seconds. Logs:
`/tmp/bloomy-history-cache-final-tests-20261003.log` and
`/tmp/bloomy-history-cache-final-release-20261003.log`.
Fourteen cache tests and three store-release tests add external middle-row
replacement, unretained older replacement, malformed indexed text, corruption,
ordering/filters, pruning, rollback, partial scan failure, release and capacity
coverage. The long-scan cancellation test uses a started signal and a 5 ms delay;
it is a timed fixture, not a deterministic per-row gate. Concurrent external
commits during an open SELECT were not separately exercised.

An independent read-only review found no concrete correctness regression in
the final iteration. Actual byte accounting remains estimated as stated above.

## Native review

Native144 is an isolated Debug dashboard fixture; 107 staged source hashes,
its linked telemetry archive and actual executable matched after building.
Executable SHA-256:
`9d5b4b4c9d8374df786c44885958e3175b02047580b19baaad9b3a8d6fc4e77b`.
The fixture starts no real provider, network client or CPU/GPU sampler.
Compact light and wide dark Metrics were rendered and inspected. Reopening
retained the measured totals, 30-day selection updated coverage, and manual
Refresh completed. Leaving Metrics evicted 361 decoded rows without deleting
observations. Hide evicted 363 rows; started/completed counts remained five
through a 136.35-second hidden interval. Recording grew from 363 to 367 samples,
and restoration immediately completed read six with the newer observations.
A quick Earnings/Metrics exit/reopen evicted the older 367-row generation and
completed read seven with 369 samples; no delayed clear of the newly warmed
generation was observed in that sequence.

Minimize evicted 370 rows and disabled display work. The automation observation
restored the window after about one second, so this is brief transition proof,
not a sustained minimized hold. Longer minimize suspension was previously
checked in Native141; that evidence is not relabeled as current-build proof.
Normal Quit removed Native144. Final counters are retained under the local
benchmark evidence directory, including `native144-final-*.json`.

Installed Bloomy remained PID 61760 with its original start time and binary
SHA-256 `5d692f240c9548f05350f2fb39d05eb15d00741ad7e9f317e3eeb8507e7c50c7`.
Provider/watchdog PIDs 63387/63393 remained running. No real provider stop,
restart, download, swap or nudge was performed for this optimization proof.

This is component and inert native proof. Installed Bloomy, its unsaved state
and the serving provider remain separate. Distribution, long-duration behavior,
whole-app energy and broader polish completion remain open.
