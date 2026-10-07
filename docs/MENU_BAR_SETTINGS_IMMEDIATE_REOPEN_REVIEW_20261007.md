# Immediate supported Settings reopening — October 7, 2026

The actual production Settings preview survives immediate navigation and
close/reopen in two fresh optimized review processes. All eleven diagnostic
cases pass in each, including three new immediate cycles per process. This
narrows the manual-host failure: the supported Settings path remains connected
before closing, unlike the failed manual fixture. It does not repair or replace
the ordinary motion gate, prove genuine occlusion or complete application polish.

## Supported sequence and assertions

The new case uses the existing production DashboardWindowController, unwrapped
RootView, DashboardNavigation and a separate never-started inert MonitorStore.
It navigates away to Appearance, waits for the departed preview to dismantle,
then returns to Menu Bar through the normal navigation owner. As soon as the
new native arc satisfies the existing eligibility checks, it synchronously
reads identity, geometry and model-layer attachment, closes and presents the
same production window. There is no presentation read, compositor hold or
yield between returned eligibility and close/reopen.

After reopening, the test requires the same returned view/layer, unchanged
geometry and a stopped departed clock. It uses the unchanged 1.7-second motion
hold, with advancing compositor angles before and after. Three cycles create
three distinct returned previews through supported navigation; none manually
detaches or reparents a SwiftUI-owned view. Attachment diagnostics read the
model hierarchy only and cap ancestry at 32 entries. They never mutate layers.

The pre-existing ten cases retain their bodies and assertions. The aggregate
now requires eleven cases, stopped retained clocks, no write errors and normal
production-controller closure. This remains a separately named diagnostic with
`replacesNormalNativeGate: false`.

## Native evidence

| Fresh process | Cases | Immediate cycles | Sustained motion holds | Hold range |
| --- | --- | --- | --- | --- |
| 24102 | 11/11 | 3/3 | 17/17 | 1.701–1.810 seconds |
| 24913 | 11/11 | 3/3 | 17/17 | 1.702–1.811 seconds |

All six immediate cycles have a non-nil backing-layer parent and the window's
content-view layer in the ancestry, both before close and after reopen. Each
chain has seventeen entries and is not truncated. The backing parent, view,
activity layer and window identities remain unchanged across each close/reopen.
The source assertions also require unchanged geometry and clock parameters.

CUA inspected the native Settings screen and terminal pass controls. The native
window appeared inactive in the captured Settings image; no foreground pixel-
motion recording is claimed. Normal Quit leaves both owned PIDs absent. Terminal
reports confirm completed cleanup and production-window closure in both runs.

This contrasts with the recent manual root-layer pair: root backing was observed
there, but the activity backing layer had a nil parent and no content-view
ancestor on failed reopening. The comparison supports investigating the manual
host's attachment contract rather than adding a production settling delay. It
does not yet establish the complete cause or retire the failing ordinary gate.
Next native evidence should cover genuine occlusion through a supported host and
system Reduce Motion delivery; broader layout, accessibility, performance and
feature-delivery work remains in the main plan.

## Source and artifact verification

All 42 staging checks pass, including three new supported-sequence guards. A
read-only reviewer found the initial test guarded only the span after attachment
capture; it now verifies the entire eligibility-to-reopen span exactly. Review
confirms that gap is resolved. The first optimized build completed but predates
the final geometry/timing guard, so it was not launched or qualified. The second
optimized build completed and matches all 128 original source hashes; its binary
also matches the manifest. No product source changed, and no fresh full package
test run or production build is claimed for this fixture-only checkpoint.

Qualified root: `.build/settings-immediate-reopen-qualified-20261007`.
Its `runtime-summary.json` indexes both retained reports, holds, attachment
checks and verified process absence. Reports are under `runtime-evidence/first`
and `runtime-evidence/second`.

- Manifest SHA-256: `4072c3816baf0063fbcdc3558543788cd753ef773de014ffa1d4a5262964b880`.
- Binary SHA-256: `633e7fbd0dcd9e7f0b658a7a2a77ce2999a422f6bf3e868863efd6d6fb8b14f3`.
- First report SHA-256: `a309461b89059eccabb0477afd2e43621652091b24e9505c2fe03ae00540d064`.
- Second report SHA-256: `0ffbc430e3545dd1f85c2bca5c0ecad35eaa8b6bc8c8c5d4956b68975aa4c660`.
- Telemetry library SHA-256: `8b456b927bf67c46ecce1c370357796972efbb58e02ddebb34314f34a52e6b9e`.
- Settings helper SHA-256: `9a715e2184db4f7ec9a68dad72b188645e18afc72a2566578e0da233b47c0f07`.

The protected dirty MenuBarMotionProof remains
`ca10cb20271d1bd5fafec801d0ed5fcb17377a0f8812132366aa2ece462db50d`;
provider configuration remains
`d144cd74f78414f18ae58692277993662c8eed4f6b6bfc0d0ea312f47ef4b7cc`.
Finite builds and native runs are terminal; the owned apps exited normally.
No provider commands, inference, installed-app update, global preference change,
push or release occurred. The broader improvement goal remains active.
