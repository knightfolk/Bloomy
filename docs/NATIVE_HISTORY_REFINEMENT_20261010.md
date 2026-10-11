# Native UI refinement — October 10, 2026

This pass inspected the installed Bloomy 1.9.19/build 144 and an isolated native
SwiftUI review app. Production provider settings, model residency and inference
were not changed. The installed application was not replaced.

## Refinements

- Popup Action History uses compact native buttons with the complete action,
  model, trigger, date and visible outcome. Selecting an entry expands its
  details directly beneath that entry; selecting it again collapses them.
- Embedded entries, recording notes and details share one vertical scroll.
- Compact dashboard tables reserve more width for the action and use a shorter
  numeric date; complete timestamps and model identifiers remain in hover help.
- The synthetic review controller now uses the same readiness/live observation
  as telemetry. Idle, active and stale review modes can no longer conflict
  simply because the two fake sources regenerated different observations.
- A finite, fixture-only Window menu diagnostic records window ownership and
  native enablement without reading text values or credentials.

## Native observations

The original compact table visibly clipped Save Settings. The refined popup
shows that name completely. Failed Swap details expand inline, collapse again,
and remain reachable by the single scroll at a 360-point dark popup height.
Search presents No matching entries distinctly. Available on this Mac expands
and collapses. A synthetic idle observation reports Ready / no active work,
Idle / no current rate, and In memory model residency consistently.

Evidence and finite logs are retained in `.build/ui-pass-20261010`; isolated
apps and source manifests are under
`/Volumes/Sol/BloomyReview/ui-pass-20261010`.

## Navigation diagnosis

Fresh dashboard sidebar navigation works. After a popup sheet is dismissed and
the parent popup closes, this computer-use session leaves the review app
inactive. Accessibility and pointer clicks then fail to change List selection,
although ordinary buttons still respond. The finite before/after diagnostic
shows `isActive` changing from true to false and key/main window references
becoming null. Native tables remain enabled; window key/main eligibility and
mouse handling remain normal. There is no app modal window, attached sheet or
remaining sheet parent.

Opening the already running review bundle through Finder restores foreground
activation, key/main window ownership and sidebar navigation to Models, Action
History and Hosting. This isolates the observed failure to inactive-app review
interaction; no production navigation change or global modal cancellation was
made. Foreground before/after records are retained alongside the screenshots.

## Verification

The full nonparallel run passes 1,881 application checks and 49 companion
checks. All 49 native staging checks pass. Final compact timestamp changes have
an additional six-test Action History rendering pass. Final Release compilation
passes. The final fixture's 144 source-input hashes match the working source;
strict deep signature verification passes. Its binary SHA-256 is
`f53c9bc0241e85772c98a790adecc691eaf102ef63b3c01f03eb6cd035f402c6`.
Final native rendering confirms complete actions and separated numeric dates,
light inline details, short dark details, navigation after normal foreground
activation, distinct idle/stale readings, empty History and explicit storage
failure feedback. Debug fixture rendering is not
distribution or performance qualification; broader motion, spoken accessibility
and release gates remain.
