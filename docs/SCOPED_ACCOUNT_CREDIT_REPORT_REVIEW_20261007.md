# Scoped account credit reports — October 7, 2026

Bloomy now has correction-aware financial report reads backed by its exact credit
ledger. Each report explicitly selects an account, optionally a provider/model,
and returns exact-time buckets, signed work/reward totals, model contributions,
authoritative balance observations and reconciliation status in one SQLite read
transaction. The existing authenticated client and charts are not wired to these
reads yet; this milestone is their data prerequisite.

## Evidence and completeness

Ingestion stores the latest authoritative observation and first/latest hourly
balance samples per account within the existing transaction. Stale observations
cannot advance this state. Contradictory balances/counts at an equal capture time
fail and roll back; consistent pages can strengthen page evidence without
treating a union of partial pages as a complete page. Future-created records
prevent a page from proving completeness.

Reconciliation compares the entire account ledger's count and signed amount with
a full reported page's lifetime count and amount, even for a provider/model-filtered
report. Partial and mismatched history remain explicit. Missing intervals receive
zero only after that comparison matches and the interval ends no later than the
observation. Credits use exact half-open source-time ranges, including local
half-hour boundaries. A credit timestamp is not a serving-start timestamp.

Counts describe credit rows, not confirmed completed requests. Signed observed
subtotals are not necessarily a lower bound. Lifetime balance changes compare
captured endpoints; they are not an earned-income rate and do not reconstruct
omitted intermediate points. Provider IDs are caller-selected filters, not proof
of this Mac's provider identity. Raw account IDs and credentials are not persisted
in the new tables; account scope is the existing opaque SHA-256 pseudonym.

## Bounded and consistent reads

Reports allow at most 744 calendar buckets, 128 work models and 250,000 credit
records. Exceeding the selected report's row budget throws instead of returning
truncated money totals. Lifetime reconciliation separately checks a bounded
250,001-row probe, then sums at most 250,000 records; larger account histories
return `readLimitExceeded` rather than a truncated lifetime total. Balance reads
use account/hour bounds. Scoped rollups and a disk retention policy remain open.

Swift aggregation checks signed integer overflow and cancellation. A SQLite
progress handler also interrupts cancelled scans. Errors/cancellation remove
the handler and roll back the read transaction before later reads or writes.
Observation, reconciliation, credits and balances share one snapshot, including
when another SQLite connection commits during the read.

## Verification

The full Release run passes with 1,682 reported tests: 1,633 telemetry/UI,
21 companion protocol and 28 companion host, with seven existing opt-in skips.
The final focused run passes 45 tests, including 17 new scoped-report regressions,
13 ledger regressions and 15 existing database tests. All 32 native staging checks
and `git diff --check` pass. The production `swift build -c release` completes
successfully (44.99 seconds).

Synthetic fixtures cover corrections moving between model/provider/hour and
work/rewards, late IDs, A/B/A isolation and reopen, partial/duplicate/empty pages,
mismatch, verified zeros versus future/unknown intervals, fractional and non-UTC
boundaries, stale/equal-time observations, signed balance changes and overflow
rollback. A 250,001-record fixture checks row limits and deferred reconciliation.
The cancellation test waits for the actual SQLite progress callback, cancels the
task, verifies immediate interruption and then verifies subsequent writes/reads.
The concurrent-commit test holds a report inside SQLite, commits corrections from
a second connection, and verifies the held report sees one old snapshot while
the following report sees the new one. Fixture runtimes are not production or
competitor performance benchmarks.

A bounded read-only native reviewer identified unbounded lifetime scans and
insufficient in-flight cancellation proof. Both were repaired and tested; final
review found no remaining concrete defects in this data scope. No live account
database, credentials, provider command, inference, model download, production
app or system privacy settings were changed.

## Remaining delivery

Authentication must supply one immutable account context plus session generation
to a complete chart read. Credential replacement/revocation must clear retained
financial data and reject obsolete callbacks, including A → B → A. Existing
global aggregate charts/balances remain unchanged until that integration and
native proof pass. Legacy history needs separate disclosure. This Mac's provider
mapping, long-term scoped rollups and storage retention also remain open.

This change has no UI rendering claim. The earlier native gate still has three
unresolved cover/reopening failures; no release or installed update is claimed.
See the [integration plan](superpowers/plans/2026-10-07-scoped-financial-reads.md)
and [BloomGauge comparison](research/BLOOMGAUGE_COMPARISON_20261007.md).

Retained terminal logs are `.build/scoped-credit-reports-{verified-focused,release-tests,release-build,staging}-20261007.log`.
Source/log hashes are recorded in `.build/scoped-credit-reports-verification-20261007.json`;
this is source/build evidence, not a signed distribution manifest.
The unrelated menu-motion file, `.mimosa/`, `.zcodeignore` and provider configuration
remain preserved outside this scope.
