# Native menu-ring window callbacks — October 6, 2026

Lost window observers do not explain the retained-target reopening failures
in this comparison. The detach target records observer removal/re-registration,
receives close, deferred reevaluation and visibility callbacks, and adds the
eligible rotation again. The original helper later observes no clock, without
a subsequent recorded synchronization stop. Fresh reopening targets retain
their clock and sustain actual compositor motion. The next investigation must
address cancellation/host context, not repair an absent observer failure.

This is bounded diagnostic evidence, not a production fix or release qualification.

## Instrumentation and controls

Source baseline: `298d7b1`. The opt-in `--motion-window-trace` requires an explicit
lifetime comparison. It stages guarded instrumentation in `MenuBarLabel.swift`
and the comparison report, preserving all original statements and the fifteen
case bodies. It adds no configure, animation, redraw, flush, timer or asynchronous
scheduling calls. Native events record identities, visibility, eligibility,
observer operations and animation keys before/after synchronization.

Each view retains at most 512 events and reports dropped events explicitly.
Thirteen direct cases append cumulative per-view histories on both success and
failure before progress/terminal reports are written. Parent cases bypass this
collection. Outgoing replacement-target close events and cleanup after the
terminal report are not captured. The registration field is instrumentation
bookkeeping, not introspection of NotificationCenter's internal registry;
actual delivered callbacks provide separate evidence.

Read-only review caught a stale registration diagnostic after dismantling. The
trace now clears that field after the original removals. The initial pair
compiled but was never executed; corrected builds used new output paths.
All four finite build jobs were joined at exit 0. Twelve staging checks pass,
including exact reverse restoration of the production label and comparison
source, fail-closed source anchors and rejected trace-without-comparison output.

The corrected optimized Release pair uses identical staged Swift and dependency
bytes, 119 original-source hashes and the same telemetry archive. Normalized
compiler commands differ only by target-lifetime definition. Both receive the
same trace and visibility preflight. Normal builds receive neither overlay.
Instrumentation adds allocation/serialization overhead, so the comparison
cannot establish production timing or resource use.

## Native findings

Run order: reset-before-detach, then fresh. Each completed motion → Models → Charts.

| Mode | Motion | Same-window reopen | Rapid reopen | Models / Charts |
| --- | --- | --- | --- | --- |
| Reset before detach | 12/15 | Fail | Fail | Pass / Pass |
| Fresh per case | 14/15 | Pass | Pass | Pass / Pass |

The pattern matches the earlier untraced comparisons. All thirty motion cases
are terminal, with no missing cases; twenty-six pass, four fail. Models complete
three cases and Charts two cases in each run. Genuine cover occlusion still
fails its visible-bit prerequisite in both apps; both aggregate reports fail.

No event is dropped. Maximum cumulative history is 87 events on the retained
target and 45 on fresh targets. Retained generation 1 receives one actual
will-close callback and one deferred callback in each reopening case. After
normal reopening it also receives the visibility callback. The final recorded
synchronization exits with `inferenceRotation`, active/non-dismantled evidence,
matching observed/registered window, and both visibility conditions true.
The helper subsequently fails waiting for a rotation key. The view's backing
layer and arc parent identities remain the same in the recorded transitions.

The fresh normal and rapid reopening targets retain one infinite 1.4-second
rotation through 1.652 and 1.706-second holds. Post-hold angle advances are
0.194 and 0.193 radians; no native display or flush is requested. Rapid reopening
also retains the later stationary active cue without rotation. The report
keeps native identities and all original clock/visibility predicates.

This rules out absent registration/callback delivery for the measured failures.
It does not identify which compositor/host operation removes the clock. Prior
[cancellation evidence](MENU_BAR_ANIMATION_CANCELLATION_REVIEW_20261003.md)
already records false-finished cancellations and rejects retry escalation and
root-layer ownership experiments. Do not repeat those fixes based on this trace.

## Evidence and preservation

Corrected outputs: `.build/menu-motion-window-trace-detach-final-20261006` and
`.build/menu-motion-window-trace-fresh-final-20261006`. Each retains immutable
staged inputs, manifest, binary and all terminal reports in `runtime-evidence/`.
Logs use `.build/menu-motion-window-trace-*-final-build-20261006.log`.
`.build/menu-motion-window-trace-summary-20261006.json` records result/report
hashes, callback summaries and confirmed-absent parent/cover PIDs.

Binary SHA-256:

- Detach: `54536dfb36817cdacc286944d041aabcff19725b585d03e57a2b6739d65c816e`
- Fresh: `1dcc2939c4e93c5f26f3bf65128405c287eae543dc891dd842b9df650954637e`

Original label SHA-256:
`a71ff6af64a20393f625f4655dae2fecda365a46091c39e87a477866822bb22f`.
Shared instrumented label:
`aed5df1795e7dc9f12568f5433f9832e36e4151b5f1ae2f98cfab46d782b1e38`.
The preserved original motion helper remains
`ca10cb20271d1bd5fafec801d0ed5fcb17377a0f8812132366aa2ece462db50d`.
Current original hashes and staged overlay bytes match their manifests.

Parent/cover PIDs 60525/60541 and 61444/61458 are absent after normal fixture quits.
Product source, the production app, provider settings, credentials, cache and
unrelated dirty work are preserved. The provider remains stopped. No fresh full
package suite is claimed for these test-only changes.

## Completion boundary

Exercise the actual production NSStatusItem/NSHostingView host in an inert
fixture next, retaining native identities through visibility/lifecycle changes.
The existing SwiftUI ordinary-window hosts pass reopening while the manual
native host fails after detach; neither proves the actual status-item route.
Keep the original fifteen-case gate, genuine occlusion and broader native
completion matrix open. The continuous polish goal remains active.
