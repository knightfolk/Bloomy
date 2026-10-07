# Scoped credit presentation — October 7, 2026

This checkpoint connects financial query interfaces to authenticated, atomic
account reports. It does not finish session-aware publication or retained UI
clearing. No installed update or release is claimed.

## What changed

`AccountEarningsFetching` exposes session state, session changes, context-bound
fetches, context validation and report reads. Its defaults are unavailable;
implementing an older financial getter does not authenticate a client. The
default context-bearing fetch captures its context before suspension and checks
both success and error paths afterward. Production validation remains owned by
the shared authentication actor.

The SQLite report now derives per-model credit counts, token counts, signed
amounts and actual calendar earning-hour identities during its existing atomic
raw-record pass. Daily display buckets do not substitute for earning hours.
Repeated daylight-saving hours remain distinct. Query limits and checked
accumulators still apply; oversized reads fail rather than truncate money.

Pure projections provide activity buckets, selected-model buckets, model totals,
work-credit summaries, earning-hour averages and day/week subtotals. Selected
model reads filter in SQLite before consuming their row/model budget. Base
rewards remain separate. Another model's observed rows cannot prove the selected
model earned zero: absent rows become recorded zero only when reconciliation
establishes completeness through that interval. Future intervals remain unknown.
Calendar-dependent projections reject a different query calendar.

Legacy production earnings getters now delegate to scoped reports instead of
unattributed legacy database aggregates. The compatibility job-summary type
counts work credit records, not independently verified completed requests; its
labels still need the later UI integration. Signed corrections remain signed.
A partial day retains its observed subtotal with no fabricated day rate.

MonitorStore's activity query wrappers now read through one context-checked
report API. An explicitly expected context is rejected before reading if it is
obsolete. Successful and failed suspended reads revalidate; a mismatched returned
account scope is rejected. Compatibility view callers still make multiple reads,
so the complete view must capture one context and consume one immutable report.

## Review and verification

A bounded read-only review identified three repaired edge cases: SQLite-restored
Date precision falsely marking a complete day partial, unrelated models consuming
a selected-model read budget, and a failed suspended default fetch skipping its
final context check. The final source review confirms those repairs and reports
no further concrete defects within the report, projections and read wrappers.
It does not qualify summary publication or UI clearing.

The stable-source focused Release run passes 73 reported tests in seven suites.
The full Release suite passes 1,711 reported tests (1,662 telemetry/UI, 21
companion protocol and 28 companion host), with seven existing opt-in skips.
The production Release build passes in 43.68 seconds. All 32 native staging
checks and `git diff --check` pass. The focused compile retains the existing
unrelated redundant NSAppearance assertion warning; no changed-source warning
remains. The subsequent full run uses the stable compiled inputs.

The initial focused compile failure is retained separately; its test helper
token types and throwing macro expressions were repaired before rerunning.
No production credentials, databases, provider commands, downloads, inference
or installed application changes are involved. The provider remains stopped,
and its saved configuration and the unrelated motion-proof edits retain their
pre-checkpoint hashes.

Retained final logs are `.build/scoped-projection-{final-focused,release-tests,release-build,staging}-20261007.log`.
The source/terminal-log manifest is
`.build/scoped-projection-verification-20261007.json`. These are source and
bounded test/build evidence, not a signed distribution or native account-switch
rendering manifest.

## Remaining work

MonitorStore still needs session observation, generation-checked scalar and
coalesced publication, immediate financial clearing, and scoped profit/energy
caches. Activity and Overview must consume one explicitly scoped report and
suppress obsolete retained snapshots. Partial/signed summary presentation and
credit-count labels need matching UI changes. Native A/B/revocation/held-callback
proof is required. Local-provider identity, legacy disclosure and retention
remain separate work. Earlier native motion and distribution gates stay open.

See [authenticated sessions](AUTHENTICATED_FINANCIAL_SESSION_REVIEW_20261007.md),
[atomic reports](SCOPED_ACCOUNT_CREDIT_REPORT_REVIEW_20261007.md), and
[the comparison motivating the financial presentation work](BLOOMGAUGE_COMPARISON_20261006.md).
