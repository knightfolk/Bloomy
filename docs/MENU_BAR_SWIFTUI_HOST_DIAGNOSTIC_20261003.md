# Actual SwiftUI menu host comparison

The separate native fixture hosts the production `MenuBarLabel` in an
`NSHostingController` with fixed synthetic active-model, GPU and fan values.
It makes no provider/API request and changes no preferences.

All four finite cases reached terminal success on October 3:

1. Active rotation advances in the actual compositor.
2. Closing/reopening the same window retains the native view and arc, and
   rotation still advances after a 1.6-second hold.
3. Rapid close/reopen retains the same objects and sustained motion.
4. SwiftUI root removal drives actual dismantle. The retained view is then
   reattached to an eligible visible window and stressed with configuration,
   hiding and reopening; its animation does not resurrect.

The observations retain real visibility/occlusion and Reduce Motion
prerequisites. No forced redraw or transaction flush establishes motion.
The first build caught a Swift 6 observer isolation error; copying the
notification name into a Sendable String before the main-actor closure fixed
compilation. The second builder completed, and actual native Run-button clicks
produced the terminal report.

This narrows the earlier standalone AppKit-host problem. It does not replace
or declare the separate 15-case check passing: Native186 still reports 12/15,
including an unestablished genuine-cover prerequisite and two standalone-host
reopen failures. Layer-backing its parent alone did not change those outcomes.
The failed checks and dirty layer-graph diagnostics remain preserved.

The ring production source is byte-identical to published 1.9.18. The focused
1.9.19 Uninstall release keeps that published menu-bar implementation and
excludes the later unfinished Settings preview. The development preview and
broader native matrix are still open.

Reproduce with
`python3 Tests/NativeUI/build-menu-host-lifecycle-fixture.py` after current Debug
products are available, then click **Run lifecycle diagnostic** in the emitted
isolated app. The retained second build is
`.build/menu-host-lifecycle-fixture-20261003-002`; its manifest records source,
dependency and binary hashes. Its report is
`BloomyMenuHostLifecycle-63933-49338C45-DC32-49A8-BBD1-DE6C4B642099/host-lifecycle-proof.json`
under this Mac's temporary directory. Review signing is not distribution proof.

## Resumed separate-app cover experiment

The October 3 resumed run adds a fifth finite case using a second independently
identified application, a normal-level opaque window, and the unchanged
production SwiftUI label. WindowServer evidence requires the cover's tracked
PID, front ordering, alpha 1 and full target-frame containment. The production
window must also actually lose its compositor-visible flag; bounding-box
coverage cannot substitute for this [Apple visibility contract](https://developer.apple.com/documentation/appkit/nswindow/occlusionstate-swift.property?language=objc).

The new run reached terminal **4/5**, with the original four cases passing
again. The cover readiness, independent bundle identity, actual front ordering
and full coverage passed. The target still reported `occlusionState = 8194`
(including `.visible`) through the four-second observation, so genuine
occlusion was not established. This is a failed prerequisite, not proof that
production ignores a delivered occlusion transition. Different app identity
alone does not explain the earlier standalone result.

The owned cover closed normally on its parent's EOF request and exited with
status 0. Both fixture processes were subsequently confirmed absent. No actual
app/provider lifecycle command or display-preference change was made. The
system's capture/occlusion interaction remains a hypothesis, not a diagnosed
cause. Do not weaken the predicate, force a rotation restart, or repeat the
same experiment without new evidence. A separate non-captured desktop
observation may help distinguish the environment; it has not been verified.

The retained build is `.build/menu-host-lifecycle-fixture-20261003-003`.
All 103 recorded source hashes matched the checkout at execution. The parent
binary SHA-256 is
`64dc98733b1210e4cb28b2dcc89a5cc848516e91295645c10012af2db677d174`;
the cover binary is
`8b405904b1ace565632012dfdbddd7c6be7cf2aefb9325621d25c364de947c98`.
The builder completed at exit 0; `build.log`, `fixture-manifest.json` and the
terminal `host-lifecycle-proof.json` are retained alongside those apps. This
standalone helper compilation and execution does not claim a new full app
suite, a repaired fifteen-case gate, or distribution readiness.
