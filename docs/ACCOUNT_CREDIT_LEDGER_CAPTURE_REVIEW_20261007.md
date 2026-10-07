# Account credit ledger capture — October 7, 2026

Bloomy now captures exact observed credits alongside its preserved hourly history.
The new ledger retains late lower-ID arrivals and same-ID amount, provider, model,
token and timestamp corrections. This is durable capture, not a replacement of
current financial chart queries or proof that a particular missing reward was paid.

## Data contract

`EarningsDatabase.ingest` normalizes each page and captures the ledger, legacy
hourly work/rewards, balance sample, coverage and maximum-ID state in one SQLite
transaction. An invalid page, conflicting duplicate or overflow rolls back all
writes. Exact duplicate IDs collapse before legacy aggregation. Signed integer
micro-USD and zero amounts are retained; tokens must be nonnegative. Neither empty
nor partial pages delete earlier records or imply complete history.

Records use `(account_scope, earning_id)` identity. Account scope is the full,
domain-separated SHA-256 digest of the account ID, separate from the friendly
account pseudonym. The enclosing raw account ID and credential-bearing
`providerKey` field are never persisted. Provider IDs and models are retained.
An empty provider ID remains explicitly unattributed. Hashing is pseudonymization,
not encryption or a claim that a known account ID cannot be guessed. The main
database and existing sidecars are made private (0600) before WAL creation,
matching the Action History store; reopened permissive sidecars are repaired.

Created time is the source credit timestamp, not proof of the serving interval.
First-observed and changed times use the caller's capture time. A per-account
observation boundary permits an older page to add unseen records while preventing
it from overwriting previously observed records. Contradictory changes at the
same capture time fail explicitly. This orders local observations; the API does
not supply a separate source revision number. Unchanged pages do not rewrite raw
credit rows; a newer page updates only the account observation boundary. Timestamp
equality uses SQLite's Unix-epoch representation so fractional replays do not
appear to be corrections.

`accountCreditRecords` requires an account ID, optionally filters provider and
half-open credit-time range, and returns 1–5,000 rows newest first with earning-ID
ties resolved deterministically. Missing accounts return no rows. Invalid bounds
and terminal SQLite read errors throw instead of returning partial success.
No caller is permitted to treat a limited query as complete history.

Schema creation and the existing base-reward migration share a transaction.
Integer-type triggers protect old hourly tables from SQLite's integer-to-REAL
promotion on additive overflow. Swift page bucket sums use checked arithmetic.
`earningsByModel` now checks its terminal SQLite result, so a failed SUM cannot
silently return an incomplete list. Old aggregate rows are not reconstructed,
assigned to an account or rewritten into ledger records.

## Verification

The complete Release suite passes: 1,665 reported tests (1,616 telemetry/UI,
21 companion protocol and 28 companion host), with seven existing opt-in skips.
The focused database run passed all 28 tests, including 13 new ledger regressions.
All 32 native staging checks and `git diff --check` pass. A bounded native reviewer
found the fractional timestamp comparison issue; it was repaired and the final
read-only review found no remaining concrete stage-1 defects. The sidecar privacy
addition also passed a separate bounded review. The final 13-test ledger run passes after the privacy and connection-lifetime
assertions; the final production build passes. Source and terminal-log hashes are
recorded in `.build/account-credit-ledger-verification-20261007.json`.

Fixtures cover late IDs, same-ID signed/model/provider/time/token corrections,
partial and empty pages, overlapping account IDs, raw no-op writes, key rotation,
credential canaries, private sidecars and reopen repair, stale/equal-time conflicts,
duplicate collapse, positive/negative/token overflow, transaction rollback,
legacy reward collision/reopen/migration overflow, bounded half-open reads,
invalid inputs, unknown providers and terminal aggregate SUM errors.

All fixtures use disposable synthetic databases. No production ledger, network
inference, provider command, model download, installed app update or privacy/global
settings change was made. SQLite fixture file-permission changes are local to the
synthetic databases.

## Remaining boundaries

Current charts, balance history and coverage still read the old globally scoped,
maximum-ID aggregates. They remain correction-unaware and can blend account
observations. The new capture path does not repair old missing data, recalculate
those charts, establish this Mac's provider identity or reconcile ledger records
with authoritative totals. Stage 2 must deliver explicit scoped queries, balance
observations, coverage and a disclosed legacy-history presentation before claiming
those financial surfaces repaired.

Raw records are retained, with bounded reads rather than silent pruning. A storage
retention/archive policy needs scoped rollups and coverage semantics first; no
bounded disk-growth claim is made. The earlier ordinary native gate's three
cover/reopening failures remain unresolved. This telemetry-only scope changes no
UI and makes no new native rendering or release-readiness claim.

Plan: [account credit ledger](superpowers/plans/2026-10-07-account-credit-ledger.md).
Research basis: [BloomGauge comparison](research/BLOOMGAUGE_COMPARISON_20261007.md).

## Provenance and preserved state

Retained logs are `.build/account-credit-ledger-{focused,final-focused,final-release-tests,final-release-build,staging}-20261007.log`. The pre-implementation compile failure for the absent API and initial focused run are retained separately. The verification manifest records exact source and final log hashes; this is source/build evidence, not a signed distribution manifest.

The unrelated dirty `Tests/NativeUI/MenuBarMotionProof.swift` remains SHA-256
`ca10cb20271d1bd5fafec801d0ed5fcb17377a0f8812132366aa2ece462db50d`.
Provider configuration remains SHA-256
`d144cd74f78414f18ae58692277993662c8eed4f6b6bfc0d0ea312f47ef4b7cc`.
`.mimosa/` and `.zcodeignore` remain outside this scope.
