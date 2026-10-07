# Scoped financial reads and chart integration

**Goal:** Use correction-aware account records for financial presentation while preventing cross-account retained data and false completeness.

**Architecture:** Build one atomic scoped SQLite report from exact records, with authoritative account observation and reconciliation metadata. Then introduce an actor-owned authenticated session with opaque scope plus generation, credential replacement observation and generation-checked publication. Bind all constituent chart reads to one context; clear retained charts and financial/profit caches on scope changes. Preserve legacy data as separately labeled unattributed history.

**Tech stack:** Swift actors, CryptoKit, SQLite3, SwiftUI/Charts and synthetic native fixtures.

**Spec:** `docs/superpowers/plans/2026-10-07-account-credit-ledger.md`, research attribution review and BloomGauge comparison.

**Constraints:** No production data/config changes, inference or provider restart. No raw account ID or credential persistence. Signed subtotals are not automatically a lower bound. Balance/ledger comparison is account-wide, even when a report filters provider/model. Incomplete or mismatched history must not become complete history or invented zero credits. Do not wire views until session/retention rules can be verified.

**Review focus:** Overflow, correction/removal between work and rewards, exact time boundaries, bounded memory/cancellation, account isolation, stale observations and full-page reconciliation; then A→B→A generations, auth replacement, held callbacks, chart clearing and native proof.

## Data prerequisites

- [x] Persist current authoritative observations and first/latest hourly balance samples per account within the existing ingestion transaction.
- [x] Reject contradictory equal-time observations and ignore stale updates; do not let rejected pages advance scoped state.
- [x] Return one atomic account/provider/model report with exact-time buckets, signed totals, model contributions, observed counts and account-wide reconciliation.
- [x] Preserve unknown intervals; only fill zero intervals when a full reported page reconciles with count and lifetime amount through its capture time.
- [x] Bound bucket/model/read work and check cancellation/overflow without returning truncated totals.
- [x] Prove corrections, A/B isolation, partial/duplicate history, current balance mismatch, signed totals, exact non-UTC boundaries, rollback/reopen and query bounds using fixtures.

Data prerequisite proof is recorded in [scoped account report review](../../SCOPED_ACCOUNT_CREDIT_REPORT_REVIEW_20261007.md).
Lifetime reconciliation above its row budget is deferred explicitly; long-term
rollups and disk retention are not complete.

## Auth and presentation integration

- [ ] Add context-bearing authentication/read APIs with actor-owned in-memory identity and generation.
- [ ] Observe credential file/directory replacement; revoke/clear on missing, changed or unauthorized credentials, with no extra network polling.
- [ ] Bind each complete chart read to one immutable context; check after suspension and reject obsolete A callbacks after B or a later A session.
- [ ] Clear retained financial charts, balances, rates, energy/profit caches on switch/revocation; preserve same-scope transient failures as explicitly stale only.
- [ ] Show scoped/reconciled/partial evidence and separately disclosed legacy aggregates. Never blend legacy data into scoped totals.
- [ ] Adapt synthetic clients and native fixtures; render A→B→A, revoked scope, failed B ingestion/refresh and held A completion with no A evidence visible in B.

## Verification and delivery

- [x] Run focused and full Release tests, production build and relevant staging checks; collect bounded read-only review for the data prerequisite. Repeat relevant checks for subsequent authentication/UI changes.
- [ ] Verify native financial presentation before claiming chart integration. Existing motion gates remain independently required for release.
- [ ] Commit/push coherent verified milestones and keep the full integration goal open until native proof passes.
