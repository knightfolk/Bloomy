# Metrics snapshot capacity

Goal: bound snapshot array capacity to current query membership, especially
when a 30-day history shrinks to 24 hours or one model. Preserve every row,
ordering, reuse fence and cancellation behavior.

Evidence: native heap snapshots confirm hidden rows release. A frozen Release
probe shows a 3,457-row read retaining capacity for 100,059 samples after a
100,000-row read. Cold/expanded arrays also have excess growth capacity.

Use an indexed COUNT in the same pinned read transaction to reserve current
membership for the sample and row-ID arrays. Cap speculative reservation to
the configured history limit; do not drop rows if an external writer exceeds
that limit. No new cache, telemetry, provider or UI behavior.

Local sequential work only. Preserve unrelated motion diagnostics, production
Bloomy and its provider. No worker, push, installation or release.

- [x] Add a regression showing narrower/empty/filter reads preserve all fields
  and reuse, without retaining the old larger array capacity. Confirm it fails
  against the current implementation.
- [x] Implement transactional membership reservation and run focused snapshot
  regressions, including outside writers, corruption and cancellation.
- [x] Compare frozen optimized probes for capacity, fields/order and timings.
- [x] Run full Release checks and exact-source native large-history navigation,
  refresh and minimized release checks. Wait for every finite job.
- [x] Record measured scope and limits; make a coherent local checkpoint.

Evidence and remaining native ownership limits:
`docs/METRICS_SNAPSHOT_CAPACITY_REVIEW_20261004.md`. Shorter-query sample capacity
falls 21.375 → 0.750 MiB in the paired component probe; no whole-app memory
improvement is claimed. Full Release checks report 1,637 passing tests.
