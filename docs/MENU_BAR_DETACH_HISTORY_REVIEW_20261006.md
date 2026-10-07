# Native menu-ring detach history — October 6, 2026

Resetting the manual native target immediately before detach/reattach does not
remove either reopening failure. The contemporaneous reused control and this
one-reset treatment both complete 12 of 15 motion cases. This narrows the next
investigation toward detach/reattach and subsequent restoration on a retained
target. It does not identify the production cause or qualify the release gate.

## Controlled follow-up

Baseline: `3d6f957`, with the existing dirty `MenuBarMotionProof.swift` preserved.
The opt-in staging overlay now accepts `reset-before-detach`. It creates one
new target before `detach_and_restore` and retains that same target for the
remaining direct cases. Reused mode creates no replacement. Both optimized
Release builds use identical staged Swift, 119 recorded source hashes and the
same telemetry archive; the treatment compiler definition is the difference.
Normal fixture builds still stage the original helper without this overlay.

All fifteen original case bodies, predicates, compositor observations, holds
and cleanup remain unchanged. The modes use the same visibility preflight.
Parent-label cases bypass the wrapper. Runtime metadata explicitly declares
diagnostic-only scope and that these runs cannot replace the normal gate.
The read-only native reviewer found no blocking issue. Both finite builds were
joined at exit 0; seven staging regressions pass.

## Native result

Run order: reused control, then reset-before-detach. Each completed the full
motion → Models → Charts entry before normal quit.

| Mode | Motion | Detach | Same-window reopen | Rapid reopen | Models / Charts |
| --- | --- | --- | --- | --- | --- |
| Reused | 12/15 | Pass | Fail | Fail | Pass / Pass |
| Reset before detach | 12/15 | Pass | Fail | Fail | Pass / Pass |

The reset target is generation 1, window 28926; its view and arc identities
remain identical in detach and both reopening failure records. The control
retains generation 0, window 28867. All failures occur in the original case
bodies; there is no preparation failure. The reopening failures occur while
waiting for eligible activity to restore its rotation, before the sustained
compositor hold can run. They must not be reported as passing hold checks.

The earlier transitions still execute on the reset app's old target. This
isolates per-target history but does not rule out process-wide effects of
those transitions. Both genuine-cover cases still fail their prerequisite:
opaque front coverage does not establish loss of the target's visible bit.
Both covers report normal parent-request exit and closed windows.

Models complete all three cases and Charts both cases in each run. All thirty
motion cases are terminal, with no missing cases; twenty-four pass, six fail.
Both aggregate reports remain failed. This is bounded fixture evidence, not
full production or accessibility qualification.

## Retained evidence and preservation

Outputs are `.build/menu-motion-detach-control-20261006` and
`.build/menu-motion-detach-reset-20261006`. Each retains the immutable staged
sources, manifest, app and terminal reports in `runtime-evidence/`. Build logs
are `.build/menu-motion-detach-*-build-20261006.log`.
`.build/menu-motion-detach-summary-20261006.json` records report/binary hashes,
identities, outcomes and confirmed-absent parent/cover PIDs.

Binary SHA-256:

- Control: `2e36408f6e00cd898e8fdf3fe13b5d5ed165b1a5b78d119e904c0283d8659843`
- Reset: `5d916000eda1807effa00f8bc699f8d14ed04ee57f4dd4abbaff0d9a50e7d5e0`

Shared staged motion helper SHA-256:
`7669897071cd0b020862ade57df871f0f1676c4305940c97980d05fb52d7069a`.
The original helper remains
`ca10cb20271d1bd5fafec801d0ed5fcb17377a0f8812132366aa2ece462db50d`.
Current original-source hashes and staged overlay bytes match the manifests.

Parent/cover PIDs 56157/56168 and 56766/56779 are absent. A post-quit accessibility
lookup reopened the unused control app; it was quit again, and the final process
inventory confirms no DashboardFixture process remains. No extra proof run was
started in that instance. The production app, provider settings, credentials,
model cache and unrelated dirty work are preserved; the provider remains stopped.
No fresh full package suite is claimed for these test-builder-only changes.

## Next evidence

Inspect actual view/window callbacks and window-observer registration around
detach, reattach, close and reopen before changing animation recovery. Compare
against the previously successful fresh reopening case, keeping each case body
and compositor requirement intact. A diagnostic callback trace must not add
redraws, animation retries or another lifecycle controller.

The actual status-item host uses NSHostingView in NSStatusItem.button; this
manual window comparison does not prove that route. Genuine occlusion,
production status-item lifecycle and the original fifteen-case gate remain
open. The continuous native polish goal remains active.
