# Account credit ledger implementation plan

**Goal:** Preserve exact account/provider credit records, including late arrivals and corrections, before replacing legacy aggregate queries.

**Architecture:** Add account-scoped records to the existing SQLite database. Account scope is a domain-separated full SHA-256 digest; provider keys and raw account IDs are never stored. Capture records in the existing ingestion transaction alongside legacy hourly buckets, balance samples and coverage. A bounded query explicitly requires account identity and optionally filters provider and time. Existing charts continue to use legacy aggregates until a separate scoped presentation change is verified.

**Tech stack:** Swift actor isolation, CryptoKit, SQLite3, Swift Testing; synthetic fixtures only.

**Spec:** `docs/research/BLOOMGAUGE_COMPARISON_20261007.md` and `docs/research/STAT_ATTRIBUTION_REVIEW.md`.

**Constraints:** Preserve existing aggregates and credentials. No inference, downloads, provider restart or live database changes during testing. Do not attribute old buckets to an account, reconstruct unknown IDs, claim full history from a partial page, or claim the current charts are correction-aware. A local digest is pseudonymization, not encryption. Raw-credit retention policy and scoped chart delivery remain open.

**Review focus:** Atomic rollback, checked integer sums, credential exclusion, duplicate conflicts, account/provider isolation, stale observations, migration/reopen safety and bounded deterministic reads.

## Stage 1: durable capture

- [x] Write regression fixtures for late lower IDs, same-ID signed/model/provider/time/token corrections, account changes and repeat pages.
- [x] Add `AccountCreditRecord` and synchronous `CreditLedgerPersistence`, owned by `EarningsDatabase`'s connection. Schema uses `(account_scope, earning_id)` and scope/time/provider query indexes.
- [x] Validate timestamps, identifiers, counts and tokens; collapse exact duplicate IDs ignoring provider-key rotation, reject contradictory duplicates without including input values in errors.
- [x] Preserve records across empty/partial pages. Older observations may add unseen records but cannot overwrite already-observed records. Equal-time contradictory corrections fail explicitly.
- [x] Capture ledger and legacy data in one transaction. Guard both Swift bucket sums and SQLite additive updates against overflow, including legacy reward migration.
- [x] Expose a bounded account-scoped record query (1–5,000 rows, half-open time range, deterministic newest-first ordering). Check terminal SQLite errors.
- [x] Verify synthetic privacy, overflow/invalid-input rollback, no-op raw writes, reopen/migration and query bounds. Run the required Release suite and source/staging checks, then bounded read-only review.
- [x] Prepare the verified checkpoint and record exact checks and unresolved boundaries. Commit/push identity and remote verification are reported at handoff.

## Stage 2: scoped presentation and reconciliation (not part of stage 1)

The report/observation data prerequisite is now implemented and verified; see
[scoped financial reads](2026-10-07-scoped-financial-reads.md). Authentication,
chart publication, legacy disclosure and native proof below remain open.

- [ ] Derive checked account/provider/model rollups from the ledger and persist scoped authoritative balance observations/coverage.
- [ ] Present old aggregates as explicitly unattributed legacy evidence, without double-counting overlap or claiming complete history.
- [ ] Wire explicit account scope through authenticated reads and financial charts, with account A → B → A and partial-history regressions.
- [ ] Reconcile ledger observations with authoritative totals; surface missing history and corrections without treating observation time as serving time.
- [ ] Verify financial presentation in the native app before claiming charts or this Mac's earnings attribution repaired.
