# Overview hourly credits — October 7, 2026

Overview now places an hourly native earnings chart between its existing four
money/work summaries and model cards. Detailed hardware/cooling sits behind a
persisted disclosure, initially closed. GPU protection and slowdown notices
remain outside that disclosure while closed and move into resources when open.
The resources view is conditionally mounted, so collapse runs its existing CPU
sampler cleanup. Activity and local Refresh controls remain available in the
chart header. This is a bounded native UI checkpoint, not completed accounting,
a release or completion of the ongoing polish goal.

## Data and lifecycle

The chart uses the existing local account-history API, ActivityReadState tickets,
calendar query identity, signed stacking, exact amount accessibility, zero
markers and adaptive axes. It adds no network acquisition or independent provider
controller. Its minute display schedule is visibility-gated; local reads happen
on query/revision changes or explicit Refresh, not on telemetry ticks. Hidden
reads cancel and later callbacks cannot overwrite a newer ticket.

Amounts are retained gross account credits, including signed corrections, with
coverage and missing hours explicitly described. They cannot establish this
Mac's attributable income or complete account history. The correction/late-ID
persistence finding in [the competitor review](research/BLOOMGAUGE_COMPARISON_20261007.md)
remains unresolved. Existing summary metrics retain their separate coverage;
this change does not replace their values with a sum of chart samples.

Initial pending history shows progress; first failures say unavailable. A
successful zero is a plotted dot, not a missing interval. Empty and unknown
reports retain the captured calendar date/timezone and read status. Failed reads
retain the previous completed report, explicitly identified as such. The captured
date belongs to the header; it never silently changes to a rolling Today label.

## Verification

The actual mounted Overview regression verifies no hidden read, one visible
aggregate read, no reread after a telemetry update, cancellation on hiding,
revision changes without hidden reads, and a fresh read on restoration. It also
requires no model-list/per-model reads. The complete final Release suite exits 0
with 1,652 reported tests (1,603 + 21 + 28), including seven existing opt-in skips.
All 32 fixture staging checks and git diff --check pass. Shared Activity state,
calendar, signed stacking and tiny-axis regressions remain part of that suite.

Native computer use inspected populated layouts in compact/wide light/dark
conditions, hourly accessibility amounts, signed corrections, sparse micro-dollar
bars, recorded-zero markers and unknown gaps. Native interactions verified
Activity navigation, expand/collapse, retained hardware source labels, and a
warning visible while hardware is collapsed. The final exact-source build
rechecked empty/unknown dates, compact light/dark empty states, signed and zero
charts, recovery, Activity navigation, disclosure and the collapsed warning.
Changing only the inert source to Offline and pressing Refresh retained the
preceding unknown report and captured date, with “Showing the last completed
read” visible. This is not a live API, inference, sensor or midnight-rollover test.

Rendered review found a wasted negative half-axis for positive-only earnings;
the chart now uses the positive axis unless actual negative segments exist.
Interval-bounded RectangleMarks follow Activity's implementation instead of an
automatically sized BarMark, preserving unknown gaps. A standalone date caption
was not visibly reliable alongside the flexible empty view. Caption-only vertical
fixedSize did not settle the observation; grouping the date with the heading
produced the verified compact empty/unknown layout. Earlier artifacts remain
separate. A retained CUA helper accidentally reopened the earlier caption build;
that task-owned process was stopped before rebinding the exact final process and
repeating the final observations. Those mixed-process observations are not final
artifact proof.

The original native gate remains terminal at 12/15, with no missing cases:
opaque-cover occlusion, normal retained-window reopening and rapid reopening
still fail. Models and Charts pass. The assertions and dirty diagnostic helper
were not changed by this scope. Actual system Reduce Motion, physical motion,
live data and broader application proof remain open.

## Provenance and handoff

Final optimized artifact: `.build/overview-earnings-header-review-20261007`.
All 124 current source hashes match its manifest; the production menu label is
unmodified by staging. This is an isolated ad-hoc signed review app, not a
notarized distribution or installed update.

- Binary SHA-256: `1b4f96589a9ef591e405a73de6e7f82e165819b540098a1afe745f6d8b603eee`.
- Manifest SHA-256: `ab5b2b88c6c2b7d46688a60672e201fad58594943e1d59f46ec1aeabb17e7d27`.
- Motion report: `runtime-evidence/BloomyDashboardFixture-1863E7AE-8C72-4F54-9078-4E09ACA8A4E8/motion-lifecycle-proof.json`.
  SHA-256: `107f8b15f9b7931749b71e96693fc1ae57128839554b037294d358efcb84b4b1`.
- `runtime-summary.json` indexes all terminal reports, source checks and verified
  process absence. Final parent 67092, cover 67843 and earlier review processes
  63309/67110 are absent; no Overview review process remains running.
- Final test/build logs: `.build/overview-earnings-header-{release-tests,review}-20261007*.log`.
  Staging log: `.build/overview-earnings-staging-20261007.log`.

Provider configuration remains SHA-256
`d144cd74f78414f18ae58692277993662c8eed4f6b6bfc0d0ea312f47ef4b7cc`;
the unrelated dirty MenuBarMotionProof remains SHA-256
`ca10cb20271d1bd5fafec801d0ed5fcb17377a0f8812132366aa2ece462db50d`.
No provider commands, inference, installation or global settings changes were
made. `.mimosa/` and `.zcodeignore` are preserved and outside this checkpoint.
Next priorities remain the correction-aware credit ledger, joined day/switch
timeline and evidence-backed readiness explanation; retain the native stack.
