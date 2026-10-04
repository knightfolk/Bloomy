# Metrics mounted read ownership

Goal: release obsolete large raw buffers when Metrics narrows or refreshes,
while preserving its displayed result, scope, failed-read recovery and hidden
release behavior. Keep the existing lightweight SwiftUI architecture.

Native evidence at d7dd5d7: after 30 days → 24 hours and several narrower
refreshes, heap still finds a 22,413,312-byte sample array. A no-content reverse
reference trace leads through SwiftUI.StoredLocation<PerformanceMetricsRead>
savedValues and a task capture. The journal owner reports only ~2,880 rows.

Test one factor first: read the successful result explicitly in the outer
view body, then pass that immutable value into TimelineView. This registers
the read dependency at its owner rather than only in the delayed timeline
content closure. Do not add a view model unless the native ownership evidence
requires a different owner. A candidate must eliminate the large typed buffer
after narrowing; an unchanged heap is a rejected candidate.

Local sequential review only. Preserve production/provider, unrelated motion
diagnostics, frozen libraries and rejected evidence. No worker, push, release
or installation.

- [x] Capture baseline typed allocation sizes, reverse references and actual
  read generations after narrowing.
- [x] Build the focused exact-source native candidate, verify real period and
  refresh actions, and inspect typed buffers without forcing extra view redraws.
- [x] If the candidate passes, check full/shorter/held-failed/empty/reopened
  semantics and run relevant plus full Release tests; otherwise diagnose and
  retain or remove only the task-owned experiment intentionally.
- [x] Record evidence, limits and process cleanup; commit a coherent verified
  improvement. Keep the broad polish goal open.

The explicit outer-body read candidate was rejected: its exact-source native
heap still had the same 22,413,312-byte buffer, with saved-state and task roots.
Its frozen bundle and traces remain preserved. The next single factor is a
StateObject owning only the current successful read. View/task copies share
that reference; period, filter, loading/error and loop ownership stay unchanged.

The reference-owned candidate passes four stable live ownership gates and
full/held-failed/empty/hidden/reopen/filter recovery checks. The obsolete
22,413,312-byte allocation disappears after narrowing. All 24 presentation
tests and 1,637 reported Release tests pass. Evidence, rejected candidate and
remaining broad gates: `docs/METRICS_READ_OWNERSHIP_REVIEW_20261004.md`.
