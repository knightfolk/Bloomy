# Aligned provider activity — October 7, 2026

## Product scope

Activity Metrics adds a Provider · all row on the same time axis as resident
model visits. Native bars and color-independent symbols distinguish active
readings, counter work between readings, observed idle and uncertain activity.
The provider row is explicitly independent of model and no-work visit filters.
This exposes work without assigning global counters to a resident/MRU model,
claiming continuous inference, or equating observed work with organic paid work.

The immutable completed Metrics snapshot now carries this activity history.
Existing retained-query and cancellation publication rules apply to both tracks.
No collector, persistence, inference, provider command or new refresh was added.
This advances the replay UI but does not join actions, credits or machine
attribution, and makes no measured resource-saving claim.

## Evidence and limits

The pure activity analyzer reuses PerformanceSummary's existing adjacent-pair
eligibility: valid current readings, a matching nonnil session, increasing
captures, positive observed separation at most 90 seconds, capture ages/gaps at
most 90 seconds and no counter reset. Invalid/stale rows remain in adjacency;
no interval crosses them, a restart or long gap. The last reading is not extended
to now. Active means active at both endpoints, not continuous inference.

Observed idle requires both endpoints inactive, both request/token counters known
and unchanged, and no positive active-request/token-rate reading. Increasing
counters can establish work somewhere between the complete readings, even if
both endpoints are inactive. A partially clipped counter-only bracket remains
uncertain because its work may be outside the selected range. Other mixed or
unknown activity remains uncertain.

Identical adjacent evidence is coalesced only within an uninterrupted session.
The chart retains the latest 600 segments and shows the original total when
reduced. Model visits retain their separate 500-row limit. Blank space remains
undisplayed evidence, not proven downtime. Provider-wide evidence remains global
even when a model has no matching residence visits.

## Review and tests

Read-only source review caught the partially clipped counter bracket; its fix
and regression are included. No further concrete source finding remained.
The first focused run failed that regression while compilation overlapped the
review edit. It is retained as preliminary evidence; a frozen-source rebuild
passes all 25 focused tests. No test expectation or production timing was relaxed.

Seven new tests cover activity classifications, missing/contradictory idle data,
stale/gap/session/capture/reset boundaries, coalescing across MRU model labels,
clipping, explicit retention and filter independence. Existing PerformanceSummary,
model-visit analysis and rendering checks pass. The final serial Release run
reports 1,781 tests (1,732 telemetry, 21 protocol and 28 host), with seven existing
opt-in skips. Thirty-two staging checks and the production Release build pass.
Logs are retained under .build/provider-activity-*20261007.log.

## Native proof

The optimized isolated artifact is .build/provider-activity-native-review-20261007.
All 127 view/fixture source hashes match; its frozen linked telemetry library
matches the qualified test build. Exact provenance:

- Manifest: `f839215ba9e168e495d5d2030df84e2fcf6e6a8538bff6c2f482df6f489e10fd`
- Executable: `12f1588bf4021f2371c0b5841bfa40e82952d130a502d1c90748fcef04bf9659`
- Telemetry library: `8b456b927bf67c46ecce1c370357796972efbb58e02ddebb34314f34a52e6b9e`

Computer use checks wide light/dark and compact light/dark layouts, aligned rows,
wrapped legends and color-independent shapes in fixture grayscale. The initial
fixture exposes 63 separate all-model activity accessibility rows and nine visit
rows. Subsequent recording adds a 64th activity segment. Without work shows one
Bonsai visit while the provider row remains global. Selecting Gemma with that
filter leaves zero visit rows and retains provider activity; All visits restores
four Gemma visits. The provider-only empty-visit layout is visually checked.
This is synthetic native layout/filter/accessibility proof, not whole-app
VoiceOver, chart audio traversal, larger-text or maximum-history performance proof.

The unchanged ordinary native proof reached terminal completion: Models and Charts
pass; motion remains 12/15 with opaque-cover and normal/rapid same-window reopening
failures. Results are retained in the artifact's native-proof directory. No motion
assertion or production animation was changed. The owned fixture quit normally;
PID 85274 was verified absent. All finite test/build/proof work is joined.

Provider and installed production app were not started or changed. The provider
configuration and protected pre-existing motion-proof changes retain their hashes.
No push, release or installed update is claimed. Joined work/action/credit replay,
historical local attribution, demand history, broad accessibility/performance,
existing motion failures and distribution qualification remain open.
