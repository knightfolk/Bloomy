# Native dashboard review — October 2, 2026

This is bounded native layout and interaction evidence within the ongoing polish
goal. The provider and recovery watcher remained stopped. The installed Bloomy
1.9.15/build 140 stayed running and was not replaced. Review data, preferences,
configuration drafts, histories, tokens and chat responses were synthetic.

## Host and provenance

`Tests/NativeUI/DashboardFixture.swift` hosts the production dashboard views in
an AppKit window matching the production window style. The fixture disables
live CPU/GPU sampling, CLI update queries and network-cache polling through
three exact staged constructor substitutions. Thermal state is the actual
host value and is identified in the review banner. It never starts the monitor
service or a real provider. Each process has isolated preferences and temporary
histories. Its builder records source, telemetry-library and binary hashes.

The initial SwiftUI WindowGroup fixture made dashboard headings and Activity
tabs appear blurred under the native scroll edge. A controlled comparison with
the production AppKit window policy removed the blur. Production headings were
not changed in response to that fixture artifact.

The pre-correction native inspection used
`.build/native-dashboard-fixture-20261002-03/fixture-manifest.json`. This artifact
remains a comparison baseline. Its source hashes predate the card-status, Chat
wrapping and settings-copy changes below. It is ad hoc signed for local review,
has no update feed, and is not a distribution build.

## Inspected paths

The following results came from rendered screens and native accessibility/input
actions, rather than compilation alone. Compact means 800 × 560 content size;
wide means 1280 × 900, both including the fixture banner.

| Surface | Native evidence on the baseline fixture |
| --- | --- |
| Overview | Wide fresh/light and compact offline/light. Metric cards have consistent dimensions; missing earnings remain unavailable. |
| Activity — Earnings | Compact light; model chips wrap with a common height, and the chart/segmented controls remain readable. |
| Activity — Metrics | Compact dark; summary grid, history, speed and phase charts including `waiting_inventory`. The initial seed had no no-work visits, so that populated case required a revised fixture. |
| Models | Compact fresh/dark, stale/light; demand refresh updates its age, Available collapses and reopens, and Capacity expands. Save/Apply guards remain visible. |
| Opportunity | Compact dark; two-column model cards remain readable. |
| Network activity | Compact dark; metric selectors, chart and expanded infrastructure status. Cache results are synthetic. |
| Chat | Compact dark; New Chat, local route, typed prompt, synthetic reply and cleared composer. Route descriptions were clipped and needed correction. |
| Hosting | Compact dark; mode cards, selected fleet and token controls. No real hosting/security setting was changed. |
| Action History | Wide dark; table and selected-row details. Coordinate selection was used after duplicate synthetic accessibility identities rejected a row click. |
| Health & Logs | Wide health/dark and compact logs/dark; source status, diagnostics, filters and event table. No file was exported. |
| Appearance | Compact; switching Dark to Light changed the isolated fixture immediately. |
| Menu Bar | Compact; three-circle explanation and configurable idle-alert timing. The actual menu-bar animation was not proved by this dashboard host. |
| Electricity | Compact; disabled tracking and price controls. No power sampling was started. |
| Updates | Compact; fixture app updating unavailable, synthetic CLI 0.9.17 status. This is not updater integration proof. |
| Provider | Compact, including lower content; idle-memory settings, experimental controls, configurable switch timings and 15-minute auto-nudge setup. No key was entered or action enabled. |
| Fans | Compact; Refresh readings advanced the synthetic reading time. The visible Fan policy chevron expanded the controls. No actual fan setting was changed. |
| iPhone Companion | Compact; Coming soon, with pairing and remote control unavailable. Implementation details in the copy needed simplification. |
| Support | Compact; preview entry point and copy. The initial inspection did not save or share a report. |

## Corrections prompted by review

The initial stale fixture incorrectly retained daemon and loaded-model values
inside its control snapshot. Production omits those values when their sources
are stale. That fixture mismatch is corrected separately from the real card
issue: Model Manager previously presented the resulting unverified empty
residency as “Not loaded.” Cards must distinguish unknown live status from a
verified unloaded state, including their detailed badges and accessibility.

The obsolete CLI 0.9.7 concurrency explanation is replaced with a version-neutral
description of the provider's default cap and model/profile restrictions. Chat
route descriptions wrap vertically. Companion and Support pages use user-facing
availability/report language while retaining the existing review-before-save
gate and report filtering.

## Remaining proof

The updated production source passed the full Swift suite: 1,102 app/telemetry,
21 companion protocol and 28 host checks, with opt-in checks skipped in the
normal run. The release build passed in 42.01 seconds with two jobs. The focused
residency/presentation/rendering run passed 41 checks across five suites.
Evidence: `/tmp/bloomy-efficiency-20261001/dashboard-residency-full-suite.log`
and `dashboard-residency-release-build.log` in the same directory.

Revised native inspection used
`.build/native-dashboard-fixture-20261002-05/fixture-manifest.json`:

- Compact dark fresh cards showed Serving now, Ready in memory and Not loaded.
  Stale runtime readings instead showed neutral Status unavailable cards and
  an Unknown detailed badge/accessibility value; deletion stayed blocked.
- Stale catalog with fresh runtime kept accurate live labels while blocking
  settings changes. Catalog freshness and residency freshness are independent.
- Compact light Metrics showed one bounded Bonsai no-work visit lasting 90
  seconds. Selecting Without work removed other rows and preserved its time,
  outcome and uncertainty explanation; the complete row was visually checked.
- New Chat descriptions wrapped fully in light and dark appearances. Paid-route
  confirmation remained readable and Escape dismissed the sheet.
- Compact dark Companion and Support copy rendered clearly. The synthetic
  Support preview showed its JSON, disabled Save before acknowledgement and
  enabled it afterward. Closing saved no report.

One Support notice initially overstated the absence of alert history as
“current status only,” despite included recommendation information. The final
copy states that saved alerts are omitted. Five focused Support tests passed
after this caption correction; the exact final source release build passed in
41.91 seconds. Evidence is `dashboard-support-final-tests.log` and
`dashboard-residency-final-release-build.log` in the same temporary directory.

The final native artifact is
`.build/native-dashboard-fixture-20261002-06/fixture-manifest.json`. All 76
recorded source hashes, linked telemetry and binary matched the checkout. Its
Offline scenario now includes a current synthetic official-CLI stopped-status
read, matching the lifecycle contract, rather than relying on daemon data alone.
Rendered wide/light inspection verified all downloaded cards as Not loaded and
the separate not-downloaded state. The corrected capacity help was read on
screen; a one-slot/Gemma startup draft survived navigation and five-second
control refreshes. Synthetic Save cleared edits and showed Saved, retaining the
existing explanation that applying capacity requires a restart. No real
configuration or provider action occurred. Final Support preview/cancellation
and the corrected missing-alert notice were checked in wide/light appearance.

The complete light/dark × narrow/wide × fresh/stale/offline matrix, retained
drafts, keyboard navigation, Reduce Motion and sustained update stability have
not all been verified. Dashboard fixtures cannot establish real GPU/fan
collection, live provider/configuration actions, credential access, distribution
updating, external-drive permission behavior or comparable process-energy
improvements. The production external-drive catalog gate still holds release
publication; no privacy permission was reset for this review.

Two further visual considerations are recorded for the next pass: active-first
model sorting moves cards when residency changes (an existing intentional/tested
behavior), and the iPhone Companion sidebar label truncates at the standard
sidebar width. Neither was silently changed during this checkpoint.
