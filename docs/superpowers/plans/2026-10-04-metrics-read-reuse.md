# Metrics read reuse implementation plan

**Goal:** Reduce repeated large-history decoding while preserving every recorded
row, uncertainty boundary, correction and selected-period semantic.

**Architecture:** Add an opaque, immutable read snapshot to the SQLite API.
Reuse its samples only for the same database instance, a stable external-write
version and a covered local insertion journal. Current indexed membership/order
is always queried. New or reused rowids that were inserted locally are decoded.
Outside writes, expired insertion history and foreign snapshots trigger full
validated reads. An external-write fence surrounds each read transaction; a
raced incremental attempt is discarded and fully reread. The journal actor
holds one snapshot sharing its array with the visible consumer and releases it
when Metrics hides. The existing general-purpose decoded-cache ceiling remains.

**Tech stack:** Swift 6, Foundation, SQLite, existing SwiftUI Metrics view.

**Spec:** `docs/APP_POLISH_OPTIMIZATION_PLAN.md`, Remaining optimization review;
`docs/LARGE_METRICS_HISTORY_REVIEW_20261004.md`, full-read baseline and limits.

Execution is local and sequential with Codex as integration owner. No new
workers, model routes, provider work, installed replacement, push or release.
Preserve unrelated motion diagnostics and all rejected evidence.

- [x] Capture an optimized component baseline and qualified native 100,000-row
  refresh window before source changes. Freeze the linked library and manifests.
- [x] Add snapshot API and regressions for immutable ownership, same-time order,
  moving periods/model filters, append, out-of-order insertion, retention,
  rowid reuse, replay/conflict/rollback, local journal overflow, outside writes,
  corruption, cancellation and all gap/model fields. Compare complete results
  with ordinary validated reads. Do not trust caller-supplied sample arrays.
- [x] Integrate one snapshot into the off-main journal actor and release it
  with existing hidden-read cleanup. Keep failed/empty/cancelled scopes and
  capture cadence unchanged. Adapt only inert fixture diagnostics as needed.
- [x] Run focused and full Release tests. Compile an exact-source optimized
  fixture and verify full-history values, filter/recovery/hidden behavior and
  read reuse/release evidence. Join every finite job.
- [x] Run the same optimized component benchmark and qualified native window
  without concurrent compilation/tests. Record read counts and phases; do not
  claim whole-app savings from a component timing or a window missing refresh.
- [x] Document actual results, bounds and remaining gates; commit only verified
  owned scope. Keep the full polish goal open unless the broad audit passes.

Results and phase/rejection limits:
`docs/METRICS_READ_REUSE_REVIEW_20261004.md`. Component repeat median 925.32 →
74.87 ms; matched native one-refresh windows 4.4047 → 2.5000% of one core.
Memory readings are mixed; allocation and production profiling remain open.
